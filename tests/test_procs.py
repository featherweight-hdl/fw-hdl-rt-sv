"""rt-sv processes (layer 2, processes.md "Register or wire", "Domain of a
process"): discovery, writer learning and step-block clocks, with blocks
called directly, before the edge loop exists. Needs verilator on PATH and
fw-hdl-spec under IVPM_PACKAGES (or FW_HDL_SPEC)."""
import shutil

import pytest

from test_protocols import _run, _spec


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
def test_procs_runtime(tmp_path):
    assert _run(tmp_path, "procs_runtime") == [
        "R proc top.i __FW_PK_COMB - 0",           # by $cast
        "R proc top.t.s0 __FW_PK_STEP top.clk 0",  # macro blocks; two clocks: tentative
        "R proc top.t.s1 __FW_PK_STEP top.clk 0",
        "R proc top.t.s2 __FW_PK_STEP top.clk 0",
        "R proc top.b __FW_PK_STEP top.clk 0",
        "R proc top.b __FW_PK_RESET - 0",
        "R proc top.m.st __FW_PK_STEP top.clk 1",  # one clock: final
        "R proc top.m.cb __FW_PK_COMB - 0",
        "R s0 1",
        "R o 00 0",                                 # clk_b's commit leaves o pending
        "R o 00 1",                                 # clk's commits it
        "R comb 1",
        "R y 00 1",                                 # a wire waits for the settle's update
        "R y 12",                                   # and reads o's committed 11
        "R s2 top.clk 0 top.clk_b",                 # learns clk_b; the write is dropped
        "R q 00 0",
        "R s2 1 1",
        "R q 22",
        "R s1 1 top.clk 1",                         # field only: the component's clock
        "R both 0 0",                               # two clocks: dropped
        "R rst 01",                                 # reset_state: clk_b's part only
        "R x 1 0",                                  # the step's write; the comb's dropped
        "R x 1",
        "D FW-E-STEP-DOMAINS top.b",
        "D FW-E-WRITE-MULTI top.m.x",
    ]
