// fw_rt_domain.svh: rt-sv's bodies for the domain API (fw_domain and the
// kind handles). Included inside fw_hdl_pkg. The runtime is __fw_rt_dom
// (fw_rt_dom.svh).
//
// Defaults are repeated because Verilator takes them from the body.

function fw_domain_kind_type fw_domain_base::kind();
    __fw_rt_obj o = __fw_rt_acc::get(this);
    return o == null ? null : o.dkind;
endfunction

function fw_domain_kind_type_of::this_t fw_domain_kind_type_of::get();
    static this_t __fw_inst;
    if (__fw_inst == null) __fw_inst = new;
    return __fw_inst;
endfunction
function string fw_domain_kind_type_of::name();
    return __fw_rt_str::tn($typename(T));
endfunction

function fw_domain::this_t fw_domain::create(string name, fw_component parent,
                                             params_t p = K::root());
    this_t d = new();
    __fw_rt_held #(params_t) h = new;
    h.v = p;
    __fw_rt_dom::create(d, name, parent, fw_domain_kind_type_of #(K)::get(), $typename(this_t),
                        h, p.from, $sformatf("%p", p));
    return d;
endfunction
function void fw_domain::set(fw_object obj, this_t dom, string name = "");
    __fw_rt_dom::set(obj, dom, name, fw_domain_kind_type_of #(K)::get());
endfunction
function fw_domain::this_t fw_domain::get(fw_object obj, string name = "");
    __fw_rt_obj o = __fw_rt_dom::get_h(obj, name, fw_domain_kind_type_of #(K)::get());
    this_t d;
    if (o != null) void'($cast(d, o.h));
    return d;
endfunction
function fw_domain_rel_e fw_domain::relate(this_t a, this_t b);
    return __fw_rt_dom::relate_h(a, b);
endfunction
function void fw_domain::pin(fw_extern_map m, string name, this_t dom = null,
                             pin_attr_t attr = K::pin_default());
    __fw_rt_dom::pin(name, fw_domain_kind_type_of #(K)::get(), dom, 0, $sformatf("%p", attr));
endfunction
function void fw_domain::pin_out(fw_extern_map m, string name, this_t dom,
                                 pin_attr_t attr = K::pin_default());
    __fw_rt_dom::pin(name, fw_domain_kind_type_of #(K)::get(), dom, 1, $sformatf("%p", attr));
endfunction
function void fw_domain::waive(fw_object a, fw_object b, string reason);
    __fw_rt_dom::waive(fw_domain_kind_type_of #(K)::get(), a, b, reason);
endfunction
function void fw_domain::port_name(fw_component comp, string assoc, string port);
    __fw_rt_dom::port_name(comp, fw_domain_kind_type_of #(K)::get(), assoc, port);
endfunction
function void fw_domain::provides(fw_component comp, string assoc, params_t p);
    __fw_rt_held #(params_t) h = new;
    h.v = p;
    __fw_rt_dom::provides(comp, fw_domain_kind_type_of #(K)::get(), assoc, h, p.from,
                          $sformatf("%p", p));
endfunction
function void fw_domain::drive(fw_signal_base sig, pin_attr_t attr = K::pin_default());
    __fw_rt_dom::drive(this, fw_domain_kind_type_of #(K)::get(), sig, $sformatf("%p", attr));
endfunction
function fw_domain::params_t fw_domain::params();
    __fw_rt_obj o = __fw_rt_acc::get(this);
    __fw_rt_held #(params_t) h;
    params_t p;
    if (o != null && $cast(h, o.dheld)) return h.v;
    return p;
endfunction
