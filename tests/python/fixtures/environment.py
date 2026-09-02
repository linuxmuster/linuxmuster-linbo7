# environment.py (test fixture)
#
# Minimal stand-in for linuxmuster-common's real /usr/lib/linuxmuster/environment.py
# (not installed in the test environment) - just the constants
# linbo_remote_cli.py actually reads. See conftest.py, which puts this
# directory on sys.path ahead of anything else named `environment`.
#
# thomas@linuxmuster.net
# 20260902

LINBODIR = '/srv/linbo'
LINBOLOGDIR = '/var/log/linuxmuster/linbo'
