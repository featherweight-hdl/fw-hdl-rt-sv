"""fw_pin_bridge (core-layer2.md §8): an RTL ready/valid source against a
class comb ready, zero latency. Needs verilator on PATH and fw-hdl-spec
under IVPM_PACKAGES (or FW_HDL_SPEC)."""
import shutil

import pytest

from test_protocols import _run, _spec


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
def test_pin_bridge_runtime(tmp_path):
    assert _run(tmp_path, "pin_bridge_runtime", extra=["fw_pin_bridge.sv"]) == [
        "R xfers 23 bad 0",             # ready and dout follow this cycle's inputs
        "D FW-E-PIN-PATH top.nope",
    ]


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
def test_pin_bridge_clock(tmp_path):
    assert _run(tmp_path, "pin_bridge_clock", extra=["fw_pin_bridge.sv"]) == [
        "R cyc 30 cnt 29 seen 84 rq 28 bad 0",  # same values as the all-RTL model
    ]


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
def test_pin_bridge_rv(tmp_path):
    assert _run(tmp_path, "pin_bridge_rv", extra=["fw_pin_bridge.sv"], std=True) == [
        "R got 20 span 26 stall 6 drops 0 bad 0",  # one cycle per put plus stalls
        "R done 20 mon 20 20 bad 0",                # monitor: one pre, one post each
    ]


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
def test_pin_bridge_rv_tgt(tmp_path):
    assert _run(tmp_path, "pin_bridge_rv_tgt", extra=["fw_pin_bridge.sv"], std=True) == [
        "R sent 30 got 30 bad 0",
        "R ready low 12 stall 9",   # low only while the sink blocks: 6 x 2 cycles
    ]
