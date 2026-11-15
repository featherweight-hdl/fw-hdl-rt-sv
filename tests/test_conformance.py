"""rt-sv conformance: every non-static-only fw-hdl-spec scenario passes under
Verilator. Needs verilator on PATH and fw-hdl-spec under IVPM_PACKAGES (or
FW_HDL_SPEC)."""
import os
import shutil

import pytest

from fw.hdl.rt.sv import conformance, sv_dir


def _spec():
    p = os.environ.get("FW_HDL_SPEC") or os.path.join(os.environ.get("IVPM_PACKAGES", ""), "fw-hdl-spec")
    return p if os.path.isdir(os.path.join(p, "conformance")) else None


def test_sv_dir():
    assert os.path.isfile(os.path.join(sv_dir(), "fw_hdl_pkg.sv"))


def test_compare_diagnostics_only():
    exp = {"diagnostics": [{"id": "FW-E-IN-OPEN", "path": "top.c.i"}]}
    got = {"top": "top", "objects": [], "nets": [], "diagnostics": exp["diagnostics"]}
    assert conformance.compare(exp, got) == []
    got["diagnostics"] = []
    assert conformance.compare(exp, got) != []


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
def test_conformance(tmp_path):
    rc = conformance.main(["--spec", _spec(), "--work", str(tmp_path)])
    assert rc == 0
