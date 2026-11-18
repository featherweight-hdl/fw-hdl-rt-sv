"""rt-sv protocol cases a conformance scenario can't express (run-time
behavior after elaboration). Needs verilator on PATH and fw-hdl-spec under
IVPM_PACKAGES (or FW_HDL_SPEC)."""
import os
import shutil
import subprocess

import pytest

from fw.hdl.rt.sv import sv_dir


def _spec():
    p = os.environ.get("FW_HDL_SPEC") or os.path.join(os.environ.get("IVPM_PACKAGES", ""), "fw-hdl-spec")
    return p if os.path.isdir(os.path.join(p, "bindings", "sv")) else None


def _run(tmp_path, top, extra=(), std=False, args=()):
    rt = sv_dir()
    src = os.path.join(os.path.dirname(__file__), "sv", top + ".sv")
    sd = os.path.join(_spec(), "std")
    cmd = ["verilator", "--binary", "-Wno-fatal", "-Wno-lint", "-Wno-style",
           "--top-module", top, "-Mdir", str(tmp_path / "obj"), "-o", "V" + top,
           "-I" + rt, "-I" + os.path.join(_spec(), "bindings", "sv"), "-I" + sd,
           "-I" + os.path.join(_spec(), "conformance", "_lib"),
           os.path.join(rt, "fw_hdl_pkg.sv")]
    if std:
        cmd.append(os.path.join(sd, "fw_hdl_std_pkg.sv"))
    cmd += [os.path.join(rt, x) for x in extra] + [src]
    r = subprocess.run(cmd, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    return _exec(tmp_path, top, args)


def _exec(tmp_path, top, args=()):
    """Runs the binary _run built again, with other plusargs."""
    r = subprocess.run([str(tmp_path / "obj" / ("V" + top))] + list(args), capture_output=True,
                       text=True)
    return [l for l in r.stdout.splitlines() if l.startswith(("R ", "D "))]


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
def test_cfg_runtime(tmp_path):
    assert _run(tmp_path, "cfg_runtime") == [
        "R bind 0 9600",                # set() in build reaches the consumer on bind
        "R set 19200 2 19200",          # set() after bind is pushed; get() returns it
        "R ndiag 0",
        "R write 38400",                # the push still lands
        "D FW-E-CFG-WRITE top.r.c",     # the client write is reported on the consumer
    ]


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
def test_cfg_ep_runtime(tmp_path):
    assert _run(tmp_path, "cfg_ep_runtime") == [
        "R bind 0 9600 1",              # bind pushes through connect_up; the listener runs once
        "R set 19200 2 19200",          # set() after bind is pushed; the listener runs again
    ]


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
def test_cfg_ep_bad(tmp_path):
    # connect() takes only the opposite role: source to source must not compile.
    with pytest.raises(AssertionError, match="fw_export_cfg_src"):
        _run(tmp_path, "cfg_ep_bad")


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
def test_sock_runtime(tmp_path):
    assert _run(tmp_path, "sock_runtime") == [
        "R req 10 got 105",             # host OUT reaches dev IN; dev OUT reaches host IN
        "D FW-E-SOCK-UNBOUND top.lone.s",
    ]


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
def test_rv_b2b(tmp_path):
    # Class-only initiator -> pins -> target with a monitor tap; the root
    # clock's period drives the run.
    assert _run(tmp_path, "rv_b2b", std=True, args=["+fw_edges=16"]) == [
        "R done 8 got 8",
        "R sink 1@1 2@2 3@3 4@4 5@7 6@8 7@9 8@10",   # one put per cycle; beat 4 blocks 2
        "R log pre 1 post 1 pre 2 post 2 pre 3 post 3 pre 4 post 4"
        " pre 5 post 5 pre 6 post 6 pre 7 post 7 pre 8 post 8",
        "R txns 1@1-1 2@2-2 3@3-3 4@4-4 5@5-7 6@8-8 7@9-9 8@10-10",  # beat 5 offered at 5
    ]


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
def test_timed_channel(tmp_path):
    # A hand-built fw_timed_channel: 10 bit times per byte by the sender's
    # configuration; '!' is frame_err from the sinking mismatch rule.
    assert _run(tmp_path, "timed_channel", std=True, args=["+fw_edges=200"]) == [
        # 1, 2: 10ns bits both sides. 3: a at 20ns, b at 10ns -> mismatch.
        # 4: both 20ns; a's change back at 450 does not shorten it.
        # 5: forwarding, a at 10ns, b at 20ns -> no mismatch applied.
        "R got 1@100 2@200 3!@400 4@600 5@700",
    ]


@pytest.mark.skipif(_spec() is None or shutil.which("verilator") is None,
                    reason="needs fw-hdl-spec and verilator")
def test_two_uart(tmp_path):
    # Two UART models, each socket configured from the model's registers,
    # joined by the kit's sinking uart_txrx_chan: 10 bits at 10 Mbaud is
    # 1000 ns a byte, by the sender's configuration.
    assert _run(tmp_path, "two_uart", std=True, args=["+fw_edges=600"]) == [
        "R b got 41@1000 42@2000 43@3000",
        "R a got 61@1000 62@2000",
    ]
    # ub's baud register at 5 Mbaud: its bytes take 2000 ns, and every
    # byte either way arrives with frame_err ('!').
    assert _exec(tmp_path, "two_uart", ["+fw_edges=600", "+baud_b=5000000"]) == [
        "R b got 41!@1000 42!@2000 43!@3000",
        "R a got 61!@2000 62!@4000",
    ]
