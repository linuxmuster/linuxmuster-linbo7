#!/bin/bash
#
# Filename     : kernel-sync.sh
# Description  : sync prebuilt kernels in kernel/ with the orphan git branch kernels-<major.minor>
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261003
#
# Usage: build/bin/kernel-sync.sh push [remote]
#        build/bin/kernel-sync.sh pull [-f] [remote]
#        build/bin/kernel-sync.sh build [-w]
#
# push:  commit the content of kernel/ as single commit without history and
#        force-push it to the kernels branch, if it differs from the remote one.
#        Refuses to replace a newer remote kernel version with an older one.
# pull:  update kernel/ per kernel branch from the remote kernels branch:
#        a newer remote version replaces the local one, which is moved to the
#        kernel archive in cache/kernel; a newer or differing local version is
#        kept. -f takes the remote version even if the local one is newer or
#        differs.
# build: start the GitHub workflow kernels.yml, which builds newer kernel.org
#        versions and pushes them to the kernels branch. -w waits for the
#        workflow run and pulls the result afterwards. Needs the gh cli.
#
# The kernels branch is named after the package version, e.g. kernels-4.3
# for 4.3.39-0, so that the release workflow can find it for tag builds too.
#

set -o pipefail

ACTION="$1"
shift
FORCE=""
WAIT=""
while getopts "fw" opt; do
    case "$opt" in
        f) FORCE="yes" ;;
        w) WAIT="yes" ;;
        *) ACTION="" ;;
    esac
done
shift $((OPTIND - 1))
REMOTE="${1:-origin}"

cd "$(git rev-parse --show-toplevel)" || exit 1

# provides KERNELDIR, KERNELARCHIVE and KERNELARCHIVE_KEEP
source build/conf.d/0_general || exit 1
source build/bin/kernel-archive.sh || exit 1

KBRANCH="kernels-$(head -1 debian/changelog | sed -n 's|^[^(]*(\([0-9]*\.[0-9]*\)\..*|\1|p')"
KREF="refs/heads/$KBRANCH"
KWORKFLOW="kernels.yml"
KNAMES_ALL="stable longterm legacy"
GITDIR="$(git rev-parse --absolute-git-dir)"
EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"

if [ "$KBRANCH" = "kernels-" ]; then
    echo "Cannot determine kernels branch from debian/changelog!"
    exit 1
fi

# print the commit of the remote kernels branch, fetch it if not available locally
remoteCommit() {
    local commit
    commit="$(git ls-remote "$REMOTE" "$KREF" | awk '{print $1}')" || return 1
    [ -z "$commit" ] && return 0
    if ! git cat-file -e "$commit" 2> /dev/null; then
        git fetch -q "$REMOTE" "$KREF" || return 1
    fi
    echo "$commit"
}

# print "<branch>/<version>" for every kernel of the given tree-ish
treeVersions() {
    git ls-tree -d --name-only "$1" stable/ longterm/ legacy/ 2> /dev/null \
        | grep -E '^[a-z]+/[0-9]+\.[0-9]+\.[0-9]+$'
}

# print the latest version of a list of versions
latestVersion() {
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
}

# print the latest version of kernel branch <kname> in directory <dir>
dirVersion() {
    ls -1 "$1/$2" 2> /dev/null | latestVersion
}

# true if version $1 is newer than version $2
isNewer() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

doPush() {
    if [ ! -d "$KERNELDIR" ]; then
        echo "No $KERNELDIR directory, nothing to push."
        return 0
    fi

    # create tree object from kernel/ using a temporary index
    local index
    index="$(mktemp "$GITDIR/kernel-sync-index.XXXXXX")" || return 1
    rm -f "$index"
    # leftovers of interrupted builds (<version>.tmp) are not synced
    GIT_INDEX_FILE="$index" git -C "$KERNELDIR" --git-dir="$GITDIR" --work-tree=. \
        add -A -f -- . ':(exclude,glob)**/*.tmp/**' || { rm -f "$index"; return 1; }
    local tree
    tree="$(GIT_INDEX_FILE="$index" git --git-dir="$GITDIR" write-tree)"
    rm -f "$index"
    [ -z "$tree" ] && return 1
    if [ "$tree" = "$EMPTY_TREE" ]; then
        echo "$KERNELDIR is empty, nothing to push."
        return 0
    fi

    local rcommit kname lvers rvers
    rcommit="$(remoteCommit)" || { echo "Cannot query $REMOTE/$KBRANCH!"; return 1; }
    if [ -n "$rcommit" ]; then
        if [ "$(git rev-parse "$rcommit^{tree}")" = "$tree" ]; then
            echo "$REMOTE/$KBRANCH is up to date."
            return 0
        fi
        # never replace a newer remote kernel with an older local one
        for kname in $KNAMES_ALL; do
            lvers="$(dirVersion "$KERNELDIR" "$kname")"
            rvers="$(treeVersions "$rcommit" | grep "^$kname/" | sed "s|^$kname/||" | latestVersion)"
            [ -z "$rvers" -o -z "$lvers" ] && continue
            if isNewer "$rvers" "$lvers"; then
                echo "$REMOTE/$KBRANCH has newer $kname kernel $rvers than local $lvers."
                echo "Run '$0 pull $REMOTE' first."
                return 1
            fi
        done
    fi

    local message commit
    message="LINBO kernels: $(treeVersions "$tree" | tr '\n' ' ')"
    commit="$(git commit-tree "$tree" -m "$message")" || return 1
    echo "Pushing prebuilt kernels to $REMOTE/$KBRANCH ..."
    git push --no-verify -f "$REMOTE" "$commit:$KREF" || return 1
}

doPull() {
    local rcommit
    rcommit="$(remoteCommit)" || { echo "Cannot query $REMOTE/$KBRANCH!"; return 1; }
    if [ -z "$rcommit" ]; then
        echo "$REMOTE/$KBRANCH does not exist, nothing to pull."
        return 0
    fi

    # extract the remote content to a temporary directory
    local knew="$KERNELDIR.new"
    rm -rf "$knew"
    mkdir -p "$knew" "$KERNELDIR"
    git archive "$rcommit" | tar -x -C "$knew" || { rm -rf "$knew"; return 1; }

    local kname lvers rvers
    for kname in $KNAMES_ALL; do
        rvers="$(dirVersion "$knew" "$kname")"
        lvers="$(dirVersion "$KERNELDIR" "$kname")"
        [ -z "$rvers" ] && continue
        if [ -z "$FORCE" -a -n "$lvers" ]; then
            if [ "$lvers" = "$rvers" ]; then
                if diff -rq "$KERNELDIR/$kname/$lvers" "$knew/$kname/$rvers" > /dev/null; then
                    echo "$kname kernel $lvers is up to date."
                else
                    echo "Local $kname kernel $lvers differs from $REMOTE/$KBRANCH, keeping it (pull -f replaces it)."
                fi
                continue
            fi
            if isNewer "$lvers" "$rvers"; then
                echo "Local $kname kernel $lvers is newer than $rvers on $REMOTE/$KBRANCH, keeping it (push it)."
                continue
            fi
        fi
        echo "Pulling $kname kernel $rvers from $REMOTE/$KBRANCH ..."
        mkdir -p "$KERNELDIR/$kname"
        rm -rf "$KERNELDIR/$kname/$rvers"
        mv "$knew/$kname/$rvers" "$KERNELDIR/$kname/" || { rm -rf "$knew"; return 1; }
        archiveKernels "$kname" "$rvers" || { rm -rf "$knew"; return 1; }
    done
    rm -rf "$knew"
}

doBuild() {
    if ! command -v gh > /dev/null; then
        echo "The gh cli is needed to start the workflow."
        return 1
    fi

    # the workflow builds with the configs of the remote branch
    local branch lhead rhead
    branch="$(git rev-parse --abbrev-ref HEAD)"
    lhead="$(git rev-parse HEAD)"
    rhead="$(git ls-remote "$REMOTE" "refs/heads/$branch" | awk '{print $1}')"
    if [ -z "$rhead" ]; then
        echo "Branch $branch does not exist on $REMOTE!"
        return 1
    fi
    if [ "$lhead" != "$rhead" ]; then
        echo "WARNING: local $branch differs from $REMOTE/$branch, the workflow uses the remote state."
    fi

    echo "Starting workflow $KWORKFLOW on $branch ..."
    local output runid
    output="$(gh workflow run "$KWORKFLOW" --ref "$branch" 2>&1)" || { echo "$output"; return 1; }
    echo "$output"
    [ -z "$WAIT" ] && return 0

    runid="$(echo "$output" | grep -oE '/actions/runs/[0-9]+' | tail -1 | sed 's|.*/||')"
    if [ -z "$runid" ]; then
        # older gh versions do not print the run url
        sleep 5
        runid="$(gh run list --workflow "$KWORKFLOW" --branch "$branch" --event workflow_dispatch \
            --limit 1 --json databaseId --jq '.[0].databaseId')"
    fi
    if [ -z "$runid" ]; then
        echo "Cannot determine the workflow run!"
        return 1
    fi
    echo "Waiting for workflow run $runid ..."
    gh run watch "$runid" --interval 60 --exit-status > /dev/null || {
        echo "Workflow run $runid failed, see: gh run view $runid --log-failed"
        return 1
    }
    echo "Workflow run $runid finished."
    doPull
}

case "$ACTION" in
    push) doPush ;;
    pull) doPull ;;
    build) doBuild ;;
    *)
        echo "Usage: $0 push [remote]"
        echo "       $0 pull [-f] [remote]"
        echo "       $0 build [-w]"
        exit 1
        ;;
esac
