"""rt-sv signal values at run time (layer 2, processes.md "Signal values"),
driven directly, before the edge loop exists. Needs verilator on PATH and
fw-hdl-spec under IVPM_PACKAGES (or FW_HDL_SPEC)."""
import shutil

import pytest

from test_protocols import _run, _spec


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
def test_values_runtime(tmp_path):
    assert _run(tmp_path, "values_runtime") == [
        "R elab 0",
        "R pending 00 00 1",            # writes wait for the update; one pending net
        "R update 1",
        "R net ab ab ab",               # last write wins; one value per net
        "R again 0",                    # nothing pending, nothing changes
        "R tie 5a3",                    # a tied net reads as its constant
        "R in ab",                      # the write to the input is ignored
        "D FW-E-WRITE-IN top.c.i",
    ]
