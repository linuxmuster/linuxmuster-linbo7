#!/bin/sh
#
# extract_function.sh
# thomas@linuxmuster.net
# 20260722
#
# Usage: extract_function <script> <function_name> [<function_name> ...]
#
# Cuts out only complete "name(){ ... }" definitions (convention in this
# repo: the closing brace stands alone on its own line - no character-level
# brace counting needed, which would get "${var}" expansions wrong anyway).
# Works regardless of whether the function sits inside a
# "#### functions begin/end ####" marker block, and ignores any top-level
# statements in that block (e.g. "source /usr/share/linbo/shell_functions"
# in linbo_mountcache), since only the named function itself is captured.

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
