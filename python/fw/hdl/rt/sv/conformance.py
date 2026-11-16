"""Runs fw-hdl-spec conformance scenarios on rt-sv under Verilator.

For each scenario directory (``top.sv``, ``expect.json``, ``meta.json``) it
builds ``fw_elab #(scenario::top)`` with rt-sv's ``fw_hdl_pkg``, runs it with
``+fw_netlist=<path>``, and compares the result with ``expect.json``:

- an expectation with ``objects`` is a full netlist, compared whole after
  canonicalization (:func:`canonical`);
- otherwise only ``diagnostics`` is compared.

The exit status must be non-zero exactly when an ``FW-E-`` diagnostic is
expected. Scenarios marked ``"static-only": true`` are skipped, as are
scenarios that need a feature rt-sv does not implement yet (``features`` in
``meta.json``, not in :data:`FEATURES`).

Usage::

    python -m fw.hdl.rt.sv.conformance --spec <fw-hdl-spec dir> [--work DIR]
        [-j N] [-k SUBSTR ...]
"""
import argparse
import concurrent.futures
import difflib
import json
import os
import shutil
import subprocess
import sys

from . import sv_dir

# Not fw_elab #(scenario::top): see the Verilator note in fw_elab.sv.
WRAPPER = ("module fw_elab_top;\n"
           "    initial fw_hdl_pkg::__fw_rt::main(scenario::top::create(\"top\", null));\n"
           "endmodule\n")

# The optional features of the spec that rt-sv implements (meta.json
# "features"). "domains" arrives with core-domains-plan.md D2.
FEATURES = {"domains"}


def canonical(nl) -> str:
    """The canonical text of a netlist: keys sorted, two-space indent."""
    return json.dumps(nl, indent=2, sort_keys=True) + "\n"


def scenarios(conf_dir, filters=()):
    out = []
    for name in sorted(os.listdir(conf_dir)):
        d = os.path.join(conf_dir, name)
        if not os.path.isfile(os.path.join(d, "top.sv")):
            continue
        if filters and not any(f in name for f in filters):
            continue
        meta = {}
        mp = os.path.join(d, "meta.json")
        if os.path.isfile(mp):
            with open(mp) as fp:
                meta = json.load(fp)
        out.append((name, d, meta))
    return out


def compare(expect, got):
    """Returns a list of difference lines; empty when they match."""
    if "objects" in expect:
        a, b = canonical(expect), canonical(got)
    else:
        a = canonical(expect.get("diagnostics", []))
        b = canonical(got.get("diagnostics", []))
    if a == b:
        return []
    return list(difflib.unified_diff(a.splitlines(), b.splitlines(),
                                     "expect", "rt-sv", lineterm="", n=1))


def run_one(name, d, spec_dir, work, verilator="verilator", plusargs=(), expect=None):
    """Builds and runs one scenario. Returns (status, detail lines).
    ``plusargs`` are passed to the run (``fw_dom_sev=...``); ``expect``
    replaces the scenario's expect.json."""
    wd = os.path.join(work, name)
    if os.path.isdir(wd):
        shutil.rmtree(wd)
    os.makedirs(wd)
    rt = sv_dir()
    with open(os.path.join(wd, "fw_elab_top.sv"), "w") as fp:
        fp.write(WRAPPER)
    cmd = [verilator, "--binary", "-Wno-fatal", "-Wno-lint", "-Wno-style",
           "--top-module", "fw_elab_top", "-Mdir", os.path.join(wd, "obj"),
           "-o", "Vfw_elab",
           "-I" + rt, "-I" + os.path.join(spec_dir, "bindings", "sv"),
           "-I" + d,                       # the scenario's own includes
           os.path.join(rt, "fw_hdl_pkg.sv"), os.path.join(rt, "fw_elab.sv"),
           os.path.join(d, "top.sv"), os.path.join(wd, "fw_elab_top.sv")]
    with open(os.path.join(wd, "build.log"), "w") as log:
        r = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, cwd=wd)
    if r.returncode != 0:
        return "FAIL", ["build failed: %s" % os.path.join(wd, "build.log")]
    nl_path = os.path.join(wd, "netlist.json")
    with open(os.path.join(wd, "run.log"), "w") as log:
        r = subprocess.run([os.path.join(wd, "obj", "Vfw_elab"), "+fw_netlist=" + nl_path]
                           + ["+" + a for a in plusargs],
                           stdout=log, stderr=subprocess.STDOUT, cwd=wd)
    try:
        with open(nl_path) as fp:
            got = json.load(fp)
    except (OSError, ValueError) as e:
        return "FAIL", ["no netlist (%s): %s" % (e, os.path.join(wd, "run.log"))]
    with open(os.path.join(wd, "netlist.canon.json"), "w") as fp:
        fp.write(canonical(got))
    if expect is None:
        with open(os.path.join(d, "expect.json")) as fp:
            expect = json.load(fp)
    detail = compare(expect, got)
    want_err = any(x["id"].startswith("FW-E-") for x in expect.get("diagnostics", []))
    if want_err != (r.returncode != 0):
        detail.append("exit status %d, but errors were %sexpected" % (r.returncode, "" if want_err else "not "))
    return ("PASS" if not detail else "FAIL"), detail


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--spec", required=True, help="the fw-hdl-spec directory")
    ap.add_argument("--work", default="rt-sv-conformance", help="work directory")
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("-k", action="append", default=[], help="run scenarios whose name contains this")
    ap.add_argument("--results", help="write a JSON summary here")
    args = ap.parse_args(argv)

    work = os.path.abspath(args.work)
    os.makedirs(work, exist_ok=True)
    args.spec = os.path.abspath(args.spec)
    conf = os.path.join(args.spec, "conformance")
    todo, results = [], {}
    for name, d, meta in scenarios(conf, args.k):
        missing = sorted(set(meta.get("features", [])) - FEATURES)
        if meta.get("static-only"):
            results[name] = ("SKIP", ["static-only"])
        elif missing:
            results[name] = ("SKIP", ["needs " + ", ".join(missing)])
        else:
            todo.append((name, d))
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = {ex.submit(run_one, n, d, os.path.abspath(args.spec), work): n for n, d in todo}
        for f in concurrent.futures.as_completed(futs):
            results[futs[f]] = f.result()
    nfail = 0
    for name in sorted(results):
        status, detail = results[name]
        print("%-4s %s" % (status, name))
        if status == "FAIL":
            nfail += 1
            for line in detail[:40]:
                print("     " + line)
    counts = {s: sum(1 for v in results.values() if v[0] == s) for s in ("PASS", "FAIL", "SKIP")}
    print("conformance: %(PASS)d passed, %(FAIL)d failed, %(SKIP)d skipped (static-only or a feature not implemented)" % counts)
    if args.results:
        with open(args.results, "w") as fp:
            json.dump({n: {"status": s, "detail": d} for n, (s, d) in results.items()}, fp, indent=2)
    return 1 if nfail else 0


if __name__ == "__main__":
    sys.exit(main())
