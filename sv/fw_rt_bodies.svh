// fw_rt_bodies.svh: rt-sv's out-of-block bodies for every extern method of
// the spec's fw_hdl_api.svh. Included inside fw_hdl_pkg.

// ---- fw_component ----
function fw_component::params_t fw_component::mk_params();
    params_t p;
    return p;
endfunction
function void fw_component::build(); endfunction
function void fw_component::connect(); endfunction
function void fw_component::connect_all(fw_pair_t pairs[]);
    foreach (pairs[i]) __fw_rt::connect(pairs[i][0], pairs[i][1]);
endfunction

// ---- constructor factories ----
function fw_ctor_of::ctor_t fw_ctor_of::get();
    static fw_ctor_of #(B, D) __fw_inst;
    if (__fw_inst == null) begin
        struct { ctor_t h; } __fw_s;
        __fw_inst = new;
        __fw_s.h = __fw_inst;
        __fw_rt::reg_ctor($sformatf("%p", __fw_s), $typename(D));
    end
    return __fw_inst;
endfunction
function fw_ctor_of::base_t fw_ctor_of::create(string name, fw_component parent, B::params_t p);
    D d = D::create(name, parent, p);
    return d;
endfunction

// ---- overrides ----
function void fw_param_override::set(fw_component scope, string glob, P value);
    __fw_rt_ov_t #(P) ov = new;
    ov.value = value;
    __fw_rt_ov_t #(P)::q.push_back(ov);
    __fw_rt::add_ov(ov, scope, glob, $typename(P));
endfunction
function void fw_param_override::edit(fw_component scope, string glob, fw_param_edit #(P) e);
    __fw_rt_ov_t #(P) ov = new;
    ov.e = e;
    __fw_rt_ov_t #(P)::q.push_back(ov);
    __fw_rt::add_ov(ov, scope, glob, $typename(P));
endfunction

// ---- signals and ports ----
function fw_signal::this_t fw_signal::create(string name, fw_object parent);
    this_t o = new();
    __fw_rt::attach(o, __fw_rt::new_obj(name, parent, __FW_K_SIGNAL, $typename(T), __FW_D_NONE, $bits(T)));
    return o;
endfunction
function void fw_signal::connect(fw_signal #(T) other);
    __fw_rt::connect(this, other);
endfunction
function void fw_signal::tie(T value);
    __fw_rt::tie(this, $sformatf("'h%0h", value));
endfunction
function fw_signal::T fw_signal::read();
    __fw_rt_cell_t #(T) c = __fw_rt_cell_t #(T)::of(this);
    T __r;
    if (c != null) __r = c.cur;
    return __r;
endfunction
function void fw_signal::write(T v);
    __fw_rt_cell_t #(T) c = __fw_rt_cell_t #(T)::of(this);
    if (c == null || !__fw_rt_val::may_write(this)) return;
    if (!__fw_rt_procs::wrote(this)) return;
    c.nxt = v;
    __fw_rt_procs::request(this, c);
endfunction
function fw_input::this_t fw_input::create(string name, fw_object parent);
    this_t o = new();
    __fw_rt::attach(o, __fw_rt::new_obj(name, parent, __FW_K_PORT, $typename(T), __FW_D_IN, $bits(T)));
    return o;
endfunction
function fw_output::this_t fw_output::create(string name, fw_object parent);
    this_t o = new();
    __fw_rt::attach(o, __fw_rt::new_obj(name, parent, __FW_K_PORT, $typename(T), __FW_D_OUT, $bits(T)));
    return o;
endfunction
function fw_inout::this_t fw_inout::create(string name, fw_object parent);
    this_t o = new();
    __fw_rt::attach(o, __fw_rt::new_obj(name, parent, __FW_K_PORT, $typename(T), __FW_D_INOUT, $bits(T)));
    return o;
endfunction

// ---- bundles ----
function void fw_bundle_base::build(); endfunction
function fw_bundle::this_t fw_bundle::create(string name, fw_object parent);
    this_t o = new();
    __fw_rt::attach(o, __fw_rt::new_obj(name, parent, __FW_K_BUNDLE, $typename(B), __FW_D_NONE, 0));
    __fw_rt_proto::bundle_created(o, $typename(B));
    o.build();
    return o;
endfunction
function void fw_bundle::connect(fw_mirror #(B) other);
    __fw_rt::connect(this, other);
endfunction
function void fw_bundle::connect_up(fw_bundle #(B) outer);
    __fw_rt::connect(this, outer);
endfunction
function fw_mirror::this_t fw_mirror::create(string name, fw_object parent);
    this_t o = new();
    __fw_rt::attach(o, __fw_rt::new_obj(name, parent, __FW_K_MIRROR, $typename(B), __FW_D_NONE, 0));
    __fw_rt_proto::bundle_created(o, $typename(B));
    o.build();
    return o;
endfunction
function void fw_mirror::connect(fw_bundle #(B) other);
    __fw_rt::connect(this, other);
endfunction
function void fw_mirror::connect_up(fw_mirror #(B) outer);
    __fw_rt::connect(this, outer);
endfunction
function fw_monitor::this_t fw_monitor::create(string name, fw_object parent);
    this_t o = new();
    __fw_rt::attach(o, __fw_rt::new_obj(name, parent, __FW_K_MONITOR, $typename(B), __FW_D_NONE, 0));
    __fw_rt_proto::bundle_created(o, $typename(B));
    o.build();
    return o;
endfunction
function void fw_monitor::connect(B other);
    __fw_rt::connect(this, other);
endfunction

// ---- extern maps ----
function void fw_extern_map::param(string name, fw_param_arg value);
    __fw_rt::xm_param(name, value);
endfunction
function fw_value::this_t fw_value::of(T value);
    __fw_rt_value #(T) o = new;
    o.ty = __fw_rt_str::tn($typename(T));
    o.val = __fw_rt_str::pval($sformatf("%p", value), $typename(__fw_rt_shape #(T)));
    return o;
endfunction
function fw_type::this_t fw_type::get();
    static __fw_rt_type #(T) __fw_inst;
    if (__fw_inst == null) begin
        __fw_inst = new;
        __fw_inst.val = __fw_rt_str::tn($typename(T));
    end
    return __fw_inst;
endfunction
function void fw_extern_map::pin(string name, fw_signal_base s);
    __fw_rt::xm_pin(name, s);
endfunction
function fw_pin_rule fw_extern_map::prefix(fw_object b, string pre);
    fw_pin_rule r = new;
    __fw_rt::xm_rule(r, b, pre);
    return r;
endfunction
function void fw_extern_map::tie(string name, logic [1023:0] value);
    __fw_rt::xm_tie(name, $sformatf("'h%0h", value));
endfunction
function void fw_extern_map::open(string name);
    __fw_rt::xm_open(name);
endfunction
function void fw_extern_map::unused(fw_object o);
    __fw_rt::xm_unused(o);
endfunction
function fw_pin_rule fw_pin_rule::rename(string member, string pin_part);
    __fw_rt::xm_rename(this, member, pin_part);
    return this;
endfunction

// ---- time (processes.md "Time") ----
function time fw_time::now();
    return $time;
endfunction
task fw_time::delay(time d);
    #d;
endtask
