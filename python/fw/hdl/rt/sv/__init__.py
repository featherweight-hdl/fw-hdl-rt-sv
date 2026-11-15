"""fw-hdl-rt-sv: the reference SV runtime of fw-hdl, and its conformance-runner
glue.

The runtime itself is SystemVerilog (the repo's ``sv/`` directory): its own
``fw_hdl_pkg`` (the spec's declarations plus rt-sv bodies) and ``fw_elab``.
This package locates those sources and runs the spec's conformance scenarios
against them (:mod:`fw.hdl.rt.sv.conformance`).
"""
import os

def sv_dir() -> str:
    """The directory holding rt-sv's fw_hdl_pkg.sv, fw_elab.sv and includes."""
    here = os.path.dirname(os.path.abspath(__file__))
    # python/fw/hdl/rt/sv -> repo root
    return os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.dirname(here))))), "sv")
