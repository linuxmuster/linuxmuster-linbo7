#!/bin/bash
#
# Filename     : kernel-sync.sh
# Description  : sync prebuilt kernels in kernel/ with the orphan git branch kernels-<major.minor>
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261003
#
# Usage: build/bin/kernel-sync.sh <push|pull> [remote]
#
# push: commit the content of kernel/ as single commit without history and
#       force-push it to the kernels branch, if it differs from the remote one.
#       Refuses to replace a newer remote kernel version with an older one.
# pull: replace the content of kernel/ with the remote kernels branch.
#
# The kernels branch is named after the package version, e.g. kernels-4.3
# for 4.3.39-0, so that the release workflow can find it for tag builds too.
#

set -o pipefail

ACTION="$1"
REMOTE="${2:-origin}"

cd "$(git rev-parse --show-toplevel)" || exit 1

KERNELDIR="kernel"
KBRANCH="kernels-$(head -1 debian/changelog | sed -n 's|^[^(]*(\([0-9]*\.[0-9]*\)\..*|\1|p')"
KREF="refs/heads/$KBRANCH"
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

case "$ACTION" in

    push)
        if [ ! -d "$KERNELDIR" ]; then
            echo "No $KERNELDIR directory, nothing to push."
            exit 0
        fi

        # create tree object from kernel/ using a temporary index
        index="$(mktemp)"
        trap 'rm -f "$index"' EXIT
        rm -f "$index"
        # leftovers of interrupted builds (<version>.tmp) are not synced
        GIT_INDEX_FILE="$index" git -C "$KERNELDIR" --git-dir="$GITDIR" --work-tree=. \
            add -A -f -- . ':(exclude,glob)**/*.tmp/**' || exit 1
        tree="$(GIT_INDEX_FILE="$index" git --git-dir="$GITDIR" write-tree)" || exit 1
        if [ "$tree" = "$EMPTY_TREE" ]; then
            echo "$KERNELDIR is empty, nothing to push."
            exit 0
        fi

        rcommit="$(remoteCommit)" || { echo "Cannot query $REMOTE/$KBRANCH!"; exit 1; }
        if [ -n "$rcommit" ]; then
            if [ "$(git rev-parse "$rcommit^{tree}")" = "$tree" ]; then
                echo "$REMOTE/$KBRANCH is up to date."
                exit 0
            fi
            # never replace a newer remote kernel with an older local one
            for kname in stable longterm legacy; do
                lvers="$(ls -1 "$KERNELDIR/$kname" 2> /dev/null | latestVersion)"
                rvers="$(treeVersions "$rcommit" | grep "^$kname/" | sed "s|^$kname/||" | latestVersion)"
                [ -z "$rvers" -o -z "$lvers" ] && continue
                if [ "$lvers" != "$rvers" ] \
                    && [ "$(printf '%s\n%s\n' "$lvers" "$rvers" | sort -V | tail -1)" = "$rvers" ]; then
                    echo "$REMOTE/$KBRANCH has newer $kname kernel $rvers than local $lvers."
                    echo "Run '$0 pull $REMOTE' first."
                    exit 1
                fi
            done
        fi

        message="LINBO kernels: $(treeVersions "$tree" | tr '\n' ' ')"
        commit="$(git commit-tree "$tree" -m "$message")" || exit 1
        echo "Pushing prebuilt kernels to $REMOTE/$KBRANCH ..."
        git push --no-verify -f "$REMOTE" "$commit:$KREF" || exit 1
        ;;

    pull)
        rcommit="$(remoteCommit)" || { echo "Cannot query $REMOTE/$KBRANCH!"; exit 1; }
        if [ -z "$rcommit" ]; then
            echo "$REMOTE/$KBRANCH does not exist, nothing to pull."
            exit 0
        fi
        echo "Pulling prebuilt kernels from $REMOTE/$KBRANCH ..."
        rm -rf "$KERNELDIR.new"
        mkdir -p "$KERNELDIR.new"
        git archive "$rcommit" | tar -x -C "$KERNELDIR.new" || { rm -rf "$KERNELDIR.new"; exit 1; }
        rm -rf "$KERNELDIR"
        mv "$KERNELDIR.new" "$KERNELDIR" || exit 1
        treeVersions "$rcommit"
        ;;

    *)
        echo "Usage: $0 <push|pull> [remote]"
        exit 1
        ;;

esac
