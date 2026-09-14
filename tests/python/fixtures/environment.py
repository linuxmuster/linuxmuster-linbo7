#
# Filename     : environment.py (test fixture)
# Description  : Minimal stand-in for linuxmuster-common's real
#                /usr/lib/linuxmuster/environment.py (not installed in the
#                test environment) - just the constants linbo_remote_cli.py
#                actually reads. See conftest.py, which puts this directory
#                on sys.path ahead of anything else named `environment`.
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20260914
#

LINBODIR = '/srv/linbo'
LINBOLOGDIR = '/var/log/linuxmuster/linbo'
