#
# Filename     : test_linbo_mkgrubimg.py
# Description  : pytest tests for linbo_mkgrubimg.py's pure helpers - the
#                school lookup from the workstations file path and the school
#                qualified host name (issue #178).
# Signed-off by: tom.lehmann@netzint.de
# Assisted by  : Claude
# Date         : 20261001
#

import importlib
import sys
import types

import pytest


@pytest.fixture
def mkgrubimg(monkeypatch):
    """
    linbo_mkgrubimg imports linuxmuster-base7 at module level, which isn't
    installed in the test environment - stub the names it imports (none of
    which the helpers under test call), scoped to the test so the stub doesn't
    leak into tests that rely on base7 being absent.
    """
    base7 = types.ModuleType('linuxmuster_base7')
    functions = types.ModuleType('linuxmuster_base7.functions')
    for name in ('getHostname', 'getStartconfOption', 'readTextfile', 'writeTextfile'):
        setattr(functions, name, None)
    base7.functions = functions
    monkeypatch.setitem(sys.modules, 'linuxmuster_base7', base7)
    monkeypatch.setitem(sys.modules, 'linuxmuster_base7.functions', functions)
    monkeypatch.delitem(sys.modules, 'linbo_mkgrubimg', raising=False)
    return importlib.import_module('linbo_mkgrubimg')


def test_default_school_devices_file(mkgrubimg):
    assert mkgrubimg.getSchoolFromDevicesFile('/etc/linuxmuster/sophomorix/default-school/devices.csv') == 'default-school'


def test_non_default_school_devices_file(mkgrubimg):
    assert mkgrubimg.getSchoolFromDevicesFile('/etc/linuxmuster/sophomorix/abc/abc.devices.csv') == 'abc'


def test_school_name_with_hyphen(mkgrubimg):
    assert mkgrubimg.getSchoolFromDevicesFile('/etc/linuxmuster/sophomorix/gs-nord/gs-nord.devices.csv') == 'gs-nord'


def test_relative_path(mkgrubimg):
    assert mkgrubimg.getSchoolFromDevicesFile('abc.devices.csv') == 'abc'
    assert mkgrubimg.getSchoolFromDevicesFile('devices.csv') == 'default-school'


def test_default_school_host_name_is_unchanged(mkgrubimg):
    assert mkgrubimg.getQualifiedHostname('default-school', 'pc01', 'PC01') == 'pc01'


def test_non_default_school_host_name_keeps_the_case_of_the_devices_row(mkgrubimg):
    assert mkgrubimg.getQualifiedHostname('agy', 'pc02', 'PC02') == 'agy-PC02'


def test_non_default_school_host_name_with_lowercase_row(mkgrubimg):
    assert mkgrubimg.getQualifiedHostname('gs-nord', 'pc02', 'pc02') == 'gs-nord-pc02'
