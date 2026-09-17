#!/bin/bash
#
# Filename     : linbo-scp.sh
# Description  : rsync wrapper for LINBO log/status uploads over linbo-ssh.
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20260917
#

RSYNC_SKIP_COMPRESS="/7z/arc/arj/bz2/cab/cloop/deb/gz/gpg/iso/jar/jp2/jpg/jpeg/lz/lz4/lzma/lzo/png/qcow2/qdiff/qt/rar/rzip/s7z/sfx/svgz/tbz/tgz/tlz/txz/xz/z/zip/zst"
rsync --skip-compress="${RSYNC_SKIP_COMPRESS}" -e linbo-ssh "$@" ; RC="$?"

exit "$RC"
