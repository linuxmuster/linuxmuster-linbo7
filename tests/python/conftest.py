#
# Filename     : conftest.py
# Description  : pytest fixture setup for tests/python/ - makes
#                src/serverfs/usr/share/linuxmuster/linbo/ importable as
#                plain module names (e.g. `import linbo_remote_lib`),
#                matching how these files are laid out on a real server, not
#                as an installable Python package.
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20260914
#

import pathlib
import sys

_REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
_MODULE_DIR = _REPO_ROOT / 'src' / 'serverfs' / 'usr' / 'share' / 'linuxmuster' / 'linbo'
_FIXTURES_DIR = pathlib.Path(__file__).resolve().parent / 'fixtures'

# _FIXTURES_DIR first: it provides a stand-in `environment` module (the real
# one ships in linuxmuster-common, not installed in the test environment).
sys.path.insert(0, str(_FIXTURES_DIR))
sys.path.insert(0, str(_MODULE_DIR))
