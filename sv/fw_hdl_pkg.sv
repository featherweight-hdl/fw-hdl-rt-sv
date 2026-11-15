// fw_hdl_pkg.sv: rt-sv's fw_hdl_pkg, the reference SV runtime of fw-hdl
// layer 1 (elaboration only).
//
// The spec's declarations (fw-hdl-spec bindings/sv/fw_hdl_api.svh), included
// unchanged, plus rt-sv's classes and its bodies for every extern method.
// Compile with this directory before the spec's bindings/sv on the include
// path, so `include "fw_hdl_macros.svh" finds rt-sv's macros.

`include "fw_hdl_macros.svh"

package fw_hdl_pkg;
    `include "fw_hdl_api.svh"       // the spec's, unchanged
    `include "fw_rt_util.svh"
    `include "fw_rt.svh"
    `include "fw_rt_bodies.svh"
endpackage
