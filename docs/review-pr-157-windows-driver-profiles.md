# Review: PR #157 — Add native Windows driver profile support

## Status update (2026-07-23)

Since the notes below were first written, the PR has moved forward:

- **Tests landed.** `tests/shell/test_linbo_driverpostsync.sh` now covers `valid_image_name()`/`valid_profile_name()` (Wave 1) — accept/reject cases including traversal attempts, length limits, and all Windows-reserved device names. CI (`Shell tests`, both `dash` and BusyBox `ash`) is green on the current head (`719231a`).
- **Rebased onto current `7.4`**, including the `--user root` container fix for `shell-tests.yml` (an unrelated CI infra bug, not something this PR introduced).
- **Cross-repo coupling checked, not just asserted.** `linuxmuster-tools` already released **v7.4.10** (2026-07-22, published to the real apt repo) containing the server-side dispatcher renderer this PR's runtime is meant to pair with — i.e. the "linuxmuster-tools7" side shipped *before* this PR merged, ahead of the sequence the design doc itself describes. Checked the actual generated code (`drivers.py:render_driverpostsync`): it guards with `command -v linbo_driverpostsync || { echo ... ; return 1; }` before invoking it, so a client without this PR's executable gets a visible warning and skips driver install rather than crashing. That's the fail-visibly behavior the design doc asks for, so the early tools-side release is lower-risk than it first looked — but it's still not the package-level "release guard" the doc promised, and it means this PR is now the blocking piece for an already-shipped, currently-nonfunctional tools feature.
- Argument contract cross-checked line-for-line against `render_driverpostsync()`'s output: order, quoting, and the zero-profile tombstone case all match. Profile-name validation on the tools side (`^[a-zA-Z0-9_.-]+$`) is at least as strict as this script's own, so no shell-injection path through a rendered dispatcher.

The findings below (from the pre-rebase script content, byte-identical to the current head) still stand as the substantive code review.

## Overview

Adds one new file to `linbofs`: `src/linbofs/usr/bin/linbo_driverpostsync` (639 lines, POSIX/busybox `ash`), plus a very thorough design document (`docs/linbofs-windows-driver-profiles.md`, 588 lines). No existing files are touched — `linbo_sync` and `linbo_download_image` already have the download/source hooks this relies on (confirmed at `linbo_sync:541-542` and `linbo_download_image:148`), so the PR is additive and backward compatible by construction.

The feature: a per-image `.driverpostsync` companion (today a big generated hook, eventually a tiny dispatcher rendered by `linuxmuster-tools7`) sources into `linbo_sync`, then invokes this new executable with `<image> [<profile>...]`. The script reads client DMI (`sys_vendor`/`product_name`), downloads only the small `match.conf` for each assigned profile, matches locally, pulls full payloads only for matches, stages them into `/mnt/Drivers/LINBO`, generates a `pnputil-install.cmd`, and arms either a SYSTEM-task-ready path or an administrative `RunOnce` fallback via `linbo_patch_registry`.

Notably, the author explicitly frames this as a workbench/RFC PR — the doc lists 6 open "Decisions required before upstream release" (contract naming, test location, failure-semantics for `linbo_sync`, release guard mechanism, fleet-readiness gate, SYSTEM-task packaging). This is not presented as a final, mergeable state.

## Code quality and style

- Matches existing conventions well: shebang/header/author/date block, `usage()` pattern, `source /usr/share/linbo/shell_functions`, `echo "### $timestamp ..."` banner, `local` usage — all consistent with `linbo_patch_registry` and siblings.
- Defensive by default: strict whitelisting of image/profile names (`valid_image_name`, `valid_profile_name`) blocks path traversal (`..`, `/`, glob metacharacters) before any value touches an rsync path or filesystem path. Windows reserved device names (`aux`, `con`, `nul`, `com1-9`, `lpt1-9`) and the literal `pnputil-install.cmd` are also rejected as profile names.
- `match.conf` parsing is fail-closed: single `[match]` section required, exactly one `vendor`, at least one non-empty `product`, unknown keys/values invalidate the whole file.
- Staging + atomic swap pattern (`.staging-*` → `mv` → active, with `.previous-*` last-known-good) is used consistently for both metadata and payload syncs, with crash recovery on next run.
- One deviation from repo convention worth flagging: other rsync-using scripts (`linbo_download`, `linbo_update`, `linbo_upload`) wrap calls in `interruptible` and pass `--skip-compress="$RSYNC_SKIP_COMPRESS"`; this script uses plain `rsync --timeout=120`. The doc acknowledges this explicitly as preserved-but-deferred behavior ("preserve for the extraction; evaluate `interruptible` separately"), so it's a documented tradeoff, not an oversight — but it does mean a client can't cleanly Ctrl-C out of a driver sync the way it can for image syncs.

## Potential issues / risks

- **Known cache leak (self-documented):** the "retain only current matches" cleanup loops (`for CACHED_DIR in "$DRIVERPOSTSYNC_CACHE"/*` and the equivalent for `.match`) use a bare `*` glob, which does not match dotfiles in POSIX shell. Hidden `.staging-*` / `.previous-*` directories left behind for profiles that become unassigned or stop matching will never be swept by that generic cleanup — only a full tombstone (`cleanup_managed_state`, via `rm -rf` on the whole cache dir) clears them. This is explicitly called out in the doc as an accepted, deferred hardening item, but it's a real and slightly unusual leak pattern worth double-checking isn't hiding a bigger issue than described (e.g. do these leaked dirs ever get counted toward `FILE_COUNT`/copied into `/mnt/Drivers/LINBO`? They shouldn't, since the copy loop only iterates `$MATCHED_FOLDERS`, so the blast radius is disk space only, not incorrect driver installation).
- **Partial test coverage (was: none).** `tests/shell/test_linbo_driverpostsync.sh` now covers `valid_image_name()`/`valid_profile_name()` in-repo, passing under both `dash` and BusyBox `ash` in CI. The 91-assertion workbench matrix covering the rest of the script (match.conf parsing, crash recovery, batch/registry generation) is still author-side only, documented as a deferred Wave 2 (needs rsync/filesystem/DMI stubs) — an accepted scoping call, not an oversight, but worth tracking as a follow-up rather than closing the book on test coverage here.
- **Cross-repo coupling risk — confirmed to have already materialized, but with a working safety net.** `linuxmuster-tools` v7.4.10 (released 2026-07-22) already ships the server-side dispatcher renderer, ahead of this PR merging. The rendered dispatcher does guard against a missing `linbo_driverpostsync` (visible stderr warning + clean `return 1`), so old clients degrade safely rather than breaking — but no package-level "release guard" exists yet, and the feature is currently live-but-nonfunctional for any school that tries it. This makes merging and releasing this PR the actual blocking step for an already-shipped tools feature, which raises the urgency without changing the code-quality verdict.
- **`usage()` doesn't handle a `help` argument** the way `linbo_patch_registry` does (`[ -z "$1" -o "$1" = "help" ] && usage 0`). Minor, but `linbo_driverpostsync help` would currently be interpreted as image name `"help"` rather than printing usage, since `valid_image_name` happily accepts it.

## Security considerations

- Argument handling is fail-closed and traversal-safe (see whitelisting above) — this is the most important property given the script writes into a mounted Windows partition and can arm `RunOnce`/SYSTEM-task registry values.
- `match.conf` payloads and driver payloads are pulled from the same trusted internal LINBO rsync server as every other LINBO asset (`$LINBOSERVER::linbo/drivers/...`) — no new trust boundary is introduced, so this doesn't materially expand the attack surface beyond what already exists for image distribution.
- Registry patching uses a quoted heredoc (`<<'REG'`) with a hardcoded fallback command string, avoiding injection via `$FOLDER`/`$DRIVERPOSTSYNC_IMAGE` into the `.reg` payload.
- `pnputil-install.cmd` generation correctly maps `pnputil` exit codes `0/1641/3010` (success) and `259` (no-op) to self-deletion, while other codes retain the batch for retry — verified by tracing the generated batch's control flow, matches the documented behavior.

## Recommendation

**Approved.** Solid, carefully-reasoned extraction with strong input validation and honest, extensive self-documentation of what's deferred. Items (1) and (2) from the original recommendation are resolved or de-risked: Wave 1 tests landed and CI is green; the cross-repo coupling was checked against the actually-released tools code rather than left as a paper risk, and the dispatcher fails visibly rather than silently. Non-blocking follow-ups, best tracked as issues rather than held against this PR:

- Confirm the hidden-dotfile cache leak (`.staging-*`/`.previous-*` surviving the bare-`*` cleanup glob) is truly cosmetic and land a fix — disk space only per the trace above, but worth closing out.
- Land the remaining Wave 2 behavior tests (match.conf parsing, crash recovery, batch/registry generation) once the necessary rsync/filesystem/DMI stubs exist.
- Get an actual package-level release guard implemented on the `linuxmuster-tools` side — it shipped without one, relying solely on the runtime `command -v` check.
- `usage()` doesn't special-case `help` the way `linbo_patch_registry` does — minor, low-priority polish.
