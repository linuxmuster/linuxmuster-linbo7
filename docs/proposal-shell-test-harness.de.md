# Vorschlag: Leichtgewichtiger Shell-Test-Harness für linbofs-Skripte

- Status: Skizze / Diskussionsgrundlage, keine Implementierung
- Anlass: PR #157 (`docs/linbofs-windows-driver-profiles.md`, Abschnitt "Decisions required before
  upstream release", Punkt 2 — "this repository currently has no general shell-test harness"
- **Reihenfolge (bewusst so gewählt):** Der Harness wird zunächst unabhängig von PR #157 anhand
  bereits bestehender, gemergter `linbofs`-Skripte konzipiert, umgesetzt und dokumentiert. Erst
  wenn das steht, ergänzt der PR-#157-Autor Tests für `linbo_driverpostsync` in seinem eigenen PR
  gegen den dann etablierten Harness. So wird der Harness nicht an einen einzelnen, noch offenen
  PR gekoppelt, und der Contributor bekommt eine stabile Zielvorgabe statt eines beweglichen Ziels.

## Ausgangslage

`src/linbofs/usr/bin/` enthält ~50 POSIX-`ash`-Skripte (busybox, kein Bash). Viele folgen einer
Konvention, die sich für Tests ausnutzen lässt: Sie markieren ihren Funktionsblock explizit:

```sh
#### functions begin ####
...
#### functions end ####
```

Bestätigt u. a. in `linbo_sync`, `linbo_partition`, `linbo_download_image`, `linbo_start`,
`linbo_label`, `linbo_create_image`, `linbo_wrapper`, `linbo_mountcache`. Wichtig für das
Extraktionsdesign: **der Marker allein reicht nicht.** Manche Blöcke enthalten neben reinen
Funktionsdefinitionen auch Top-Level-Anweisungen, z. B. `linbo_mountcache`:

```sh
#### functions begin ####

# read common shell functions
source /usr/share/linbo/shell_functions
echo "### $timestamp $(basename "$0") ###"

usage(){ ... }
findcache(){ ... }

#### functions end ####
```

Ein naives `sed`-Cut zwischen den Markern würde hier `source /usr/share/linbo/shell_functions`
mitziehen — ein Pfad, der außerhalb eines echten LINBO-Clients nicht existiert und den Test sofort
zum Absturz bringt. Der Extraktor muss deshalb **einzelne benannte Funktionen** herausschneiden,
nicht den gesamten Blockinhalt.

## Framework-Wahl: shunit2, nicht bats-core

| Kriterium | shunit2 | bats-core |
|---|---|---|
| Läuft unter `ash`/`dash` (kein Bash nötig) | ja | nein, Runner braucht Bash |
| Assertions/Setup/Teardown | `assertEquals`, `setUp`/`tearDown`, xUnit-Stil | ähnlich, aber TAP-Output |
| Passt zur Zielumgebung (busybox) | sehr gut | nur der Runner wäre Bash, getestete Skripte bleiben `ash` |

Empfehlung: **shunit2**, als einzelne Datei in `tests/shell/shunit2` vendored (kein externes
Paket, keine zusätzliche Abhängigkeit für Contributor, die lokal ohne Docker/`lmndev-runner`
testen wollen).

## Verzeichnisstruktur

```text
tests/
└── shell/
    ├── shunit2                       # vendored, einzelne Datei
    ├── lib/
    │   └── extract_function.sh       # awk-Helper: schneidet genau eine benannte Funktion aus
    │                                  # einem linbofs-Skript, ignoriert alles davor/danach/dazwischen
    ├── test_linbo_partition.sh       # erster Pilot: convert_size()
    └── run.sh                        # Runner: einmal mit dash, einmal mit busybox ash
```

### Der Extraktor: benannte Funktion statt ganzer Block

```sh
# tests/shell/lib/extract_function.sh
# Usage: extract_function <script> <function_name> [<function_name> ...]
# Schneidet nur vollständige "name(){ ... }"-Definitionen heraus (Konvention in diesem Repo:
# die schließende Klammer steht allein auf einer Zeile — kein Zeichen-Brace-Counting nötig,
# das bei "${var}"-Expansions ohnehin falsch läge).
extract_function() {
  script="$1"; shift
  for name in "$@"; do
    awk -v fn="$name" '
      $0 ~ "^" fn "\\(\\)[[:space:]]*\\{$" { capture=1 }
      capture { print }
      capture && /^}$/ { capture=0 }
    ' "$script"
  done
}
```

Das ist robust gegenüber Stör-Statements im Block (wie oben bei `linbo_mountcache`) und
funktioniert unabhängig davon, ob der Marker überhaupt vorhanden ist — der Marker bleibt aber ein
nützliches menschenlesbares Signal "hier stehen die testkandidaten-verdächtigen Funktionen".

## Beispieltest: `convert_size()` aus `linbo_partition` (bereits im Repo, gemerged)

```sh
# src/linbofs/usr/bin/linbo_partition (Ausschnitt)
# convert all units to MiB and ensure partability by 2048
convert_size(){
  local unit="$(echo $1 | sed 's|[^a-zA-Z]*||g')"
  local size="$(echo ${1/$unit} | awk -F\[,.] '{ print $1 }')"
  local unit="$(echo $unit | tr A-Z a-z | head -c1)"
  case "$unit" in
    k) size=$(( $size / 2048 * 2 )) ;;
    m) size=$(( $size / 2 * 2 )) ;;
    g) size=$(( $size * 1024 )) ;;
    t) size=$(( $size * 1024 * 1024 )) ;;
    *) return 1 ;;
  esac
  echo $size
}
```

Gute erste Wahl, weil rein und deterministisch: keine Dateisystem-, Geräte- oder
Netzwerkzugriffe, nur String-/Arithmetik-Verarbeitung — aber mit echten, wissenswerten
Rundungs-Eigenheiten (Ganzzahldivision, `head -c1` auf die Einheit), die es wert sind, gegen
Regressionen abgesichert zu werden.

```sh
# tests/shell/test_linbo_partition.sh
SCRIPT="$(dirname "$0")/../../src/linbofs/usr/bin/linbo_partition"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" convert_size > "$SHUNIT_TMPDIR/convert_size.sh"
  . "$SHUNIT_TMPDIR/convert_size.sh"
}

test_convert_size_megabyte_passthrough() {
  assertEquals "512" "$(convert_size 512M)"
}

test_convert_size_gigabyte_to_mib() {
  assertEquals "10240" "$(convert_size 10G)"
}

test_convert_size_terabyte_to_mib() {
  assertEquals "1048576" "$(convert_size 1T)"
}

test_convert_size_kilobyte_rounds_down_to_even() {
  # 5000 KiB / 2048 = 2 (Ganzzahldivision), * 2 = 4
  assertEquals "4" "$(convert_size 5000K)"
}

test_convert_size_unit_is_case_insensitive() {
  assertEquals "10240" "$(convert_size 10g)"
}

test_convert_size_rejects_unknown_unit() {
  convert_size 10X
  assertEquals 1 $?
}

. "$(dirname "$0")/shunit2"
```

## Zweite Welle: Funktionen, die noch nicht ohne Stubs testbar sind

Nicht jede Funktion in einem `#### functions begin/end ####`-Block ist ein guter erster
Kandidat. Zwei Gegenbeispiele aus dem bestehenden Code, damit das nicht erst beim Ausprobieren
auffällt:

- **`mk_label()` (`linbo_label`)** ruft `fstype_startconf`/`partlabel_startconf` auf — Funktionen
  aus `/usr/share/linbo/shell_functions`, die selbst wieder reale `start.conf`-Dateien und
  teils Blockgeräte lesen. Testbar erst, wenn diese Helfer entweder gestubbt oder `shell_functions`
  in einer Fixture-Variante bereitgestellt wird.
- **`findcache()` (`linbo_mountcache`)** iteriert über `/dev/disk/by-id/*part*` und mountet reale
  Partitionen. Ohne eine Abstraktion der Geräte-Enumeration (z. B. über eine überschreibbare
  Variable statt eines hartkodierten Pfads) nicht sinnvoll unit-testbar, nur als
  Integrationstest auf einer echten oder virtuellen Maschine.

Empfehlung: Harness und erste Tests bewusst auf das beschränken, was *heute schon* rein ist
(wie `convert_size`), und Funktionen mit externen Abhängigkeiten offen als "braucht Stubs, Wave 2"
in einer kurzen Liste im `tests/shell/README.md` führen — statt sie zu erzwingen oder den Code
vorab zu refaktorieren.

## CI-Integration (lmndev-runner als Ausführungsumgebung)

`lmndev-runner` installiert bereits `busybox` (verlinkt als `/bin/ash`); Ubuntu bringt `dash` als
`/bin/sh` mit. Beide für den Harness relevanten Shells sind also ohne Dockerfile-Änderung
vorhanden — der Runner muss dafür nicht angepasst werden, er wird nur als Container-Image
wiederverwendet (dieselbe Umgebung, in der auch das Paket gebaut wird).

Ein Workflow, drei Auslöser, keine Duplizierung:

```yaml
# .github/workflows/shell-tests.yml (linuxmuster-linbo7)
on: [push, pull_request, workflow_dispatch, workflow_call]

jobs:
  test:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/linuxmuster/lmndev-runner:latest
    strategy:
      matrix:
        shell: [sh, busybox_ash]
    steps:
      - uses: actions/checkout@v4
      - name: Run shell tests
        run: |
          if [ "${{ matrix.shell }}" = "busybox_ash" ]; then
            busybox ash tests/shell/run.sh
          else
            sh tests/shell/run.sh
          fi
```

```yaml
# .github/workflows/release.yml (Ergänzung, Auszug)
jobs:
  test:
    uses: ./.github/workflows/shell-tests.yml

  build:
    needs: test
    ...
```

- Automatisch bei jedem Push/PR (schnelles Feedback, ohne den teuren Kernel/Busybox-Paketbau).
- Automatisch als Gate vor `build` im Release-Workflow, per `workflow_call` ohne doppelte Logik.
- Jederzeit manuell separat startbar über `workflow_dispatch`, unabhängig vom Release-Zyklus.
- **Vorerst rein informativ:** kein Required-Status-Check in der Branch-Protection. PRs können
  auch bei fehlschlagendem `shell-tests`-Job gemerged werden, solange Wave 1 noch klein ist und
  sich der Harness selbst noch einspielt. Das Umschalten auf einen blockierenden Check ist eine
  spätere, separate Entscheidung, sobald mehr Funktionen abgedeckt sind.

## Umfang und Reihenfolge

**Phase 1 (dieser Vorschlag):**

- `tests/shell/`-Grundgerüst, `extract_function`-Helper, `shunit2` vendored, `run.sh`.
- Pilot-Tests für `convert_size()` (`linbo_partition`) als Existenzbeweis.
- `shell-tests.yml` + Release-Gate wie oben, in `linuxmuster-linbo7` gemerged und dokumentiert
  (`tests/shell/README.md`: wie man einen weiteren Test hinzufügt, was "Wave 2" bedeutet).

**Phase 2 (durch den PR-#157-Autor, in dessen eigenem PR):**

- Tests für `valid_image_name`/`valid_profile_name`/Matching-Logik in `linbo_driverpostsync`,
  gegen den dann etablierten Harness, nach demselben Muster wie `test_linbo_partition.sh`.
- Der Contributor entscheidet in seinem PR, ob der `match.conf`-Parser dafür in eine eigene
  Funktion extrahiert wird (siehe Diskussion im Review) oder zunächst als Wave-2-Fall
  dokumentiert bleibt.

**Nicht Teil von Phase 1:** rückwirkende Testabdeckung für den gesamten Bestand an
`linbofs`-Skripten. Ziel ist ein benutzbarer, dokumentierter Harness plus ein überzeugender
erster Test, nicht Vollabdeckung.

## Entscheidungen (Maintainer, 2026-07-21)

1. **Pilot:** `convert_size()` ist als erster Testkandidat akzeptiert.
2. **CI-Strenge:** `shell-tests.yml` läuft zunächst rein informativ, kein
   Required-Status-Check/Branch-Protection. Siehe Hinweis im CI-Abschnitt oben.
3. **Dokumentation der Testreife:** ein einfaches `tests/shell/README.md` mit der
   "Wave 1 / Wave 2"-Unterscheidung genügt vorerst; keine strengere Durchsetzung (z. B. Lint-Regel)
   in Phase 1.
