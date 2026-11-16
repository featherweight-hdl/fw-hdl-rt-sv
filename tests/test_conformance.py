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


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
@pytest.mark.parametrize("opt,want", [
    # dom_cross_reset: a related crossing (warning) and an unrelated one (error).
    ("fw_reset_kind.unrelated=warning", [("FW-W-DOM-CROSS", "top.a0.o"),
                                         ("FW-W-DOM-CROSS", "top.a1.o")]),
    ("fw_reset_kind.related=none,fw_reset_kind.unrelated=info", [("FW-I-DOM-CROSS", "top.a1.o")]),
    ("fw_reset_kind.close=none", [("FW-E-RT-OPT", ""), ("FW-W-DOM-CROSS", "top.a0.o"),
                                  ("FW-E-DOM-CROSS", "top.a1.o")]),
])
def test_severity_option(tmp_path, opt, want):
    """+fw_dom_sev overrides the kinds' crossing severities (core-domains-plan
    §3.9); a malformed option is an error."""
    spec = _spec()
    d = os.path.join(spec, "conformance", "dom_cross_reset")
    expect = {"diagnostics": [{"id": i, "path": p} for i, p in want]}
    status, detail = conformance.run_one("dom_cross_reset", d, spec, str(tmp_path),
                                         plusargs=["fw_dom_sev=" + opt], expect=expect)
    assert status == "PASS", "\n".join(detail)
