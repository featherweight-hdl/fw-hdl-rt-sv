# fw-hdl-rt-sv

The reference SystemVerilog runtime of fw-hdl, layer 1 and domains:
elaboration in a stock simulator. It implements the API of
[fw-hdl-spec](https://github.com/featherweight-hdl/fw-hdl-spec) and is one of
the two conformance implementations (the other is fw-hdl-fe-sv). The design
is in the fw-hdl repo's `docs/design/core-layer1.md` (section 5) and
`docs/design/core-domains-plan.md` (section 5).

## Layout

| Path | Contents |
|---|---|
| `sv/fw_hdl_pkg.sv` | rt-sv's `fw_hdl_pkg`: the spec's `fw_hdl_api.svh`, unchanged, plus rt-sv's classes and bodies |
| `sv/fw_hdl_macros.svh` | rt-sv's expansions of the API macros |
| `sv/fw_rt.svh`, `sv/fw_rt_util.svh` | the runtime: object records behind `fw_impl_if`, params resolution, phase walker, per-scope net resolution (union-find), checks, extern-map recording, netlist writer |
| `sv/fw_rt_bodies.svh` | a body for every `extern` method of the layer-1 API |
| `sv/fw_rt_dom.svh` | the domain runtime: domain records, association and lookup, relation, drivers and domain pins, the crossing check, the end-of-elaboration checks, the domain members of the netlist |
| `sv/fw_rt_domain.svh` | the bodies of `fw_domain #(K)` and the kind handles |
| `sv/fw_elab.sv` | `fw_elab #(type T)`: creates `T` as `top`, elaborates, writes the netlist to `+fw_netlist=<path>`, exits non-zero on error |
| `python/fw/hdl/rt/sv/` | conformance-runner glue (`python -m fw.hdl.rt.sv.conformance`) |
| `tests/` | pytest (conformance), and the spec's smoke example through `fw_elab` |

Compile `sv/fw_hdl_pkg.sv` and `sv/fw_elab.sv` with `sv/` *before* the
spec's `bindings/sv` on the include path, then your own sources. The dfm
package `fw.hdl.rt.sv` exports this as the fileset `fw_hdl_pkg`.

## Running

With the IVPM environment loaded (fw-hdl-spec under `$IVPM_PACKAGES`):

    dfm run tests            # api-check, conformance, smoke-elab
    dfm run conformance      # the spec's scenarios under Verilator
    python -m fw.hdl.rt.sv.conformance --spec $IVPM_PACKAGES/fw-hdl-spec -k params

### Plusargs

| Plusarg | Effect |
|---|---|
| `+fw_netlist=<path>` | write the elaborated netlist |
| `+fw_dom_sev=<kind>.<relation>=<severity>[,...]` | override the kinds' crossing severities: `+fw_dom_sev=fw_reset_kind.unrelated=warning`. A relation is `same`, `related` or `unrelated`; a severity `none`, `info`, `warning` or `error` (`none` silences). A malformed option is `FW-E-RT-OPT`. fe-sv's equivalent is the `Elaborate` parameter `domain_severity`. |

In a flow, pass them with `hdlsim.vlt.SimRun`'s `plusargs`.

Scenarios marked `static-only` (extern header checks, `FW-E-PARAM-WRITE`,
`FW-E-PARAM-NULL`) are skipped: they need a static implementation.

## Notes

- Params values are read with `%p` and type names with `$typename`, both
  normalized to the netlist format; this is written against Verilator's
  output.
- Verilator 5.055 has an internal error when a class whose params struct
  holds a constructor factory is reached through a module type parameter and
  its params type is also named outside the class (see `sv/fw_elab.sv`). The
  conformance runner therefore elaborates through a non-parameterized
  wrapper that calls `fw_hdl_pkg::__fw_rt::main`.
- A domain handle inside a kind's params is written in the netlist as a
  path for `from` (every kind) and `fw_reset_kind`'s `clock`. A user kind
  with a handle in another params field gets the handle's class name there,
  because Verilator's `%p` prints a nested handle that way. fe-sv has no
  such limit. Closing it needs a kind hook that lists a params value's
  handles; none of the library kinds needs one.
