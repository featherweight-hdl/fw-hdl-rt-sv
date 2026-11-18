// fw_rt_protocol.svh: rt-sv's bodies for the protocol API (fw-hdl-spec
// fw_protocol*.svh, endpoints, sockets, configuration). Included inside
// fw_hdl_pkg. The registry is __fw_rt_proto (fw_rt_proto.svh).

// ---- families, APIs and specializations ----
function string fw_protocol_family::name();
    __fw_rt_family f;
    if ($cast(f, this)) return f.n;
    return "";
endfunction
function string fw_protocol_family::prefix();
    __fw_rt_family f;
    if ($cast(f, this)) return f.pfx;
    return "";
endfunction
function string fw_api_type::name();
    return __fw_rt_proto::api_names.exists(this) ? __fw_rt_proto::api_names[this] : "";
endfunction
function string fw_api_type::family();
    return __fw_rt_proto::family_of(name());
endfunction
function fw_protocol_type_q fw_api_type::protocols();
    return __fw_rt_proto::api_protocols(this);
endfunction
function string fw_protocol_type::name();
    __fw_rt_proto_rec r = __fw_rt_proto::rec(this);
    return r == null ? "" : r.n;
endfunction
function fw_protocol_family fw_protocol_type::family();
    __fw_rt_proto_rec r = __fw_rt_proto::rec(this);
    return r == null ? null : r.fam;
endfunction
function string fw_protocol_type::params();
    return __fw_rt_proto::params_of(name());
endfunction
function fw_api_type fw_protocol_type::api(fw_proto_dir_e dir);
    __fw_rt_proto_rec r = __fw_rt_proto::rec(this);
    if (r == null) return null;
    return dir == FW_PROTO_REQ ? r.req : r.rsp;
endfunction
function fw_api_type_q fw_protocol_type::apis();
    fw_api_type_q q;
    __fw_rt_proto_rec r = __fw_rt_proto::rec(this);
    if (r != null && r.req != null) q.push_back(r.req);
    if (r != null && r.rsp != null) q.push_back(r.rsp);
    return q;
endfunction
function fw_string_q fw_protocol_type::bundles();
    __fw_rt_proto_rec r = __fw_rt_proto::rec(this);
    fw_string_q q;
    if (r != null) q = r.bundles;
    return q;
endfunction
function fw_component_ctor_q fw_protocol_type::abstractors();
    return __fw_rt_proto::abstractors(this);
endfunction

// ---- declaration ----
function void fw_protocol_decl::api(fw_api_type h, fw_proto_dir_e dir);
    __fw_rt_proto::decl_api(h, dir);
endfunction
function void fw_protocol_decl::prefix(string s);
    __fw_rt_proto::decl_prefix(s);
endfunction
function void fw_protocol::declare(fw_protocol_decl d);
endfunction

// ---- queries ----
function fw_protocol_type fw_protocol::of(fw_object x);
    return __fw_rt_proto::of(x);
endfunction
function fw_proto_role_e fw_protocol::role_of(fw_object b);
    return __fw_rt_proto::role_of(b);
endfunction
function fw_ctor #(fw_component) fw_protocol::abstractor_for(fw_protocol_type from, fw_protocol_type to);
    return __fw_rt_proto::abstractor_for(from, to);
endfunction

// ---- handles ----
function fw_api_type_of::this_t fw_api_type_of::get();
    static this_t __fw_inst;
    if (__fw_inst == null) begin
        __fw_inst = new;
        __fw_rt_proto::add_api(__fw_inst, $typename(API));
    end
    return __fw_inst;
endfunction
// The first call makes the record and runs P::declare().
function fw_protocol_type_of::this_t fw_protocol_type_of::get(string family);
    static this_t __fw_inst;
    if (__fw_inst == null) begin
        fw_protocol_decl __fw_d = new;
        __fw_rt_proto_rec __fw_prev;
        __fw_inst = new;
        __fw_prev = __fw_rt_proto::begin_decl(__fw_inst, family, $typename(P));
        P::declare(__fw_d);
        __fw_rt_proto::end_decl(__fw_prev);
    end
    return __fw_inst;
endfunction

// ---- endpoints and sockets ----
function fw_port::this_t fw_port::create(string name, fw_object parent);
    this_t o = new();
    void'(__fw_rt_api::create(o, name, parent, $typename(this_t), 1, 0));
    return o;
endfunction
function void fw_port::connect(fw_export #(API) exp);
    void'(__fw_rt_api::link(this, exp, 0));
endfunction
function void fw_port::connect_up(fw_port #(API) outer);
    void'(__fw_rt_api::link(this, outer, 1));
endfunction
function API fw_port::get_if();
    return __fw_rt_imp #(API)::resolve(__fw_rt::impl(this));
endfunction
// The implementation is derived: the parent, when it implements API.
function fw_export::this_t fw_export::create(string name, fw_object parent);
    this_t o = new();
    API imp;
    __fw_rt_obj r = __fw_rt_api::create(o, name, parent, $typename(this_t), 0, 0);
    if ($cast(imp, parent)) __fw_rt_imp #(API)::imp[r] = imp;
    return o;
endfunction
function void fw_export::set_imp(API imp);
    __fw_rt_obj r = __fw_rt::impl(this);
    if (r != null) __fw_rt_imp #(API)::imp[r] = imp;
endfunction
function void fw_export::connect_up(fw_export #(API) outer);
    void'(__fw_rt_api::link(this, outer, 1));
endfunction
// The IN implementation is derived as an export's: the parent, when it
// implements IN.
function fw_socket::this_t fw_socket::create(string name, fw_object parent);
    this_t o = new();
    IN imp;
    __fw_rt_obj r = __fw_rt_api::create(o, name, parent, $typename(this_t), 1, 1);
    if ($cast(imp, parent)) __fw_rt_imp #(IN)::imp[r] = imp;
    return o;
endfunction
function void fw_socket::connect(fw_socket #(IN, OUT) peer);
    void'(__fw_rt_api::link(this, peer, 0));
endfunction
function void fw_socket::connect_up(fw_socket #(OUT, IN) outer);
    void'(__fw_rt_api::link(this, outer, 1));
endfunction
function void fw_socket::set_imp(IN imp);
    __fw_rt_obj r = __fw_rt::impl(this);
    if (r != null) __fw_rt_imp #(IN)::imp[r] = imp;
endfunction
function OUT fw_socket::get_if();
    return __fw_rt_imp #(OUT)::resolve(__fw_rt::impl(this));
endfunction

// ---- configuration ----
function fw_cfg_src::this_t fw_cfg_src::create(string name, fw_object parent);
    this_t o = new();
    __fw_rt_cfg::publisher(o, name, parent, $typename(this_t));
    return o;
endfunction
// The commit point: store, then push to every bound sink.
function void fw_cfg_src::set(T v);
    __fw_rt_cfg_t #(T)::set(this, v);
endfunction
function fw_cfg_src::T fw_cfg_src::get();
    return __fw_rt_cfg_t #(T)::get(this);
endfunction
function void fw_cfg_src::connect_up(fw_cfg_src #(T) outer);
    __fw_rt_cfg::link(this, outer, 1);
endfunction
function fw_cfg_sink::this_t fw_cfg_sink::create(string name, fw_object parent);
    this_t o = new();
    __fw_rt_cfg_h #(this_t, T) c = new;
    c.h = o;
    __fw_rt_cfg::consumer(o, name, parent, $typename(this_t), c);
    return o;
endfunction
function void fw_cfg_sink::connect(fw_cfg_src #(T) s);
    __fw_rt_cfg::link(this, s, 0);
endfunction
function void fw_cfg_sink::connect_up(fw_cfg_sink #(T) outer);
    __fw_rt_cfg::link(this, outer, 1);
endfunction
function void fw_cfg_sink::add_listener(fw_cfg_listener_if #(T) l);
    __fw_rt_cfg_t #(T)::listen(this, l);
endfunction

// ---- configured endpoints: an endpoint that is also a source or a sink ----
function fw_port_cfg_src::this_t fw_port_cfg_src::create(string name, fw_object parent);
    this_t o = new();
    __fw_rt_obj r = __fw_rt_api::create(o, name, parent, $typename(this_t), 1, 0);
    __fw_rt_cfg::source(r);
    return o;
endfunction
function void fw_port_cfg_src::connect(fw_export_cfg_sink #(API, CFG) exp);
    if (__fw_rt_api::link(this, exp, 0)) __fw_rt_cfg::bind_cfg(__fw_rt::impl(this), __fw_rt::impl(exp), 0);
endfunction
function void fw_port_cfg_src::connect_up(fw_port_cfg_src #(API, CFG) outer);
    if (__fw_rt_api::link(this, outer, 1)) __fw_rt_cfg::bind_cfg(__fw_rt::impl(this), __fw_rt::impl(outer), 1);
endfunction
function API fw_port_cfg_src::get_if();
    return __fw_rt_imp #(API)::resolve(__fw_rt::impl(this));
endfunction
function void fw_port_cfg_src::set(CFG v);
    __fw_rt_cfg_t #(CFG)::set(this, v);
endfunction
function fw_port_cfg_src::CFG fw_port_cfg_src::get();
    return __fw_rt_cfg_t #(CFG)::get(this);
endfunction
function fw_port_cfg_sink::this_t fw_port_cfg_sink::create(string name, fw_object parent);
    this_t o = new();
    __fw_rt_cfg_h #(this_t, CFG) c = new;
    __fw_rt_obj r = __fw_rt_api::create(o, name, parent, $typename(this_t), 1, 0);
    c.h = o;
    __fw_rt_cfg::sink(r, c);
    return o;
endfunction
function void fw_port_cfg_sink::connect(fw_export_cfg_src #(API, CFG) exp);
    if (__fw_rt_api::link(this, exp, 0)) __fw_rt_cfg::bind_cfg(__fw_rt::impl(this), __fw_rt::impl(exp), 0);
endfunction
function void fw_port_cfg_sink::connect_up(fw_port_cfg_sink #(API, CFG) outer);
    if (__fw_rt_api::link(this, outer, 1)) __fw_rt_cfg::bind_cfg(__fw_rt::impl(this), __fw_rt::impl(outer), 1);
endfunction
function API fw_port_cfg_sink::get_if();
    return __fw_rt_imp #(API)::resolve(__fw_rt::impl(this));
endfunction
function void fw_port_cfg_sink::add_listener(fw_cfg_listener_if #(CFG) l);
    __fw_rt_cfg_t #(CFG)::listen(this, l);
endfunction
function fw_export_cfg_src::this_t fw_export_cfg_src::create(string name, fw_object parent);
    this_t o = new();
    API imp;
    __fw_rt_obj r = __fw_rt_api::create(o, name, parent, $typename(this_t), 0, 0);
    if ($cast(imp, parent)) __fw_rt_imp #(API)::imp[r] = imp;
    __fw_rt_cfg::source(r);
    return o;
endfunction
function void fw_export_cfg_src::connect_up(fw_export_cfg_src #(API, CFG) outer);
    if (__fw_rt_api::link(this, outer, 1)) __fw_rt_cfg::bind_cfg(__fw_rt::impl(this), __fw_rt::impl(outer), 1);
endfunction
function void fw_export_cfg_src::set_imp(API imp);
    __fw_rt_obj r = __fw_rt::impl(this);
    if (r != null) __fw_rt_imp #(API)::imp[r] = imp;
endfunction
function void fw_export_cfg_src::set(CFG v);
    __fw_rt_cfg_t #(CFG)::set(this, v);
endfunction
function fw_export_cfg_src::CFG fw_export_cfg_src::get();
    return __fw_rt_cfg_t #(CFG)::get(this);
endfunction
function fw_export_cfg_sink::this_t fw_export_cfg_sink::create(string name, fw_object parent);
    this_t o = new();
    API imp;
    __fw_rt_cfg_h #(this_t, CFG) c = new;
    __fw_rt_obj r = __fw_rt_api::create(o, name, parent, $typename(this_t), 0, 0);
    if ($cast(imp, parent)) __fw_rt_imp #(API)::imp[r] = imp;
    c.h = o;
    __fw_rt_cfg::sink(r, c);
    return o;
endfunction
function void fw_export_cfg_sink::connect_up(fw_export_cfg_sink #(API, CFG) outer);
    if (__fw_rt_api::link(this, outer, 1)) __fw_rt_cfg::bind_cfg(__fw_rt::impl(this), __fw_rt::impl(outer), 1);
endfunction
function void fw_export_cfg_sink::set_imp(API imp);
    __fw_rt_obj r = __fw_rt::impl(this);
    if (r != null) __fw_rt_imp #(API)::imp[r] = imp;
endfunction
function void fw_export_cfg_sink::add_listener(fw_cfg_listener_if #(CFG) l);
    __fw_rt_cfg_t #(CFG)::listen(this, l);
endfunction
function fw_socket_cfg_src::this_t fw_socket_cfg_src::create(string name, fw_object parent);
    this_t o = new();
    IN imp;
    __fw_rt_obj r = __fw_rt_api::create(o, name, parent, $typename(this_t), 1, 1);
    if ($cast(imp, parent)) __fw_rt_imp #(IN)::imp[r] = imp;
    __fw_rt_cfg::source(r);
    return o;
endfunction
function void fw_socket_cfg_src::connect(fw_socket_cfg_sink #(IN, OUT, CFG) peer);
    if (__fw_rt_api::link(this, peer, 0)) __fw_rt_cfg::bind_cfg(__fw_rt::impl(this), __fw_rt::impl(peer), 0);
endfunction
function void fw_socket_cfg_src::connect_up(fw_socket_cfg_src #(OUT, IN, CFG) outer);
    if (__fw_rt_api::link(this, outer, 1)) __fw_rt_cfg::bind_cfg(__fw_rt::impl(this), __fw_rt::impl(outer), 1);
endfunction
function void fw_socket_cfg_src::set_imp(IN imp);
    __fw_rt_obj r = __fw_rt::impl(this);
    if (r != null) __fw_rt_imp #(IN)::imp[r] = imp;
endfunction
function OUT fw_socket_cfg_src::get_if();
    return __fw_rt_imp #(OUT)::resolve(__fw_rt::impl(this));
endfunction
function void fw_socket_cfg_src::set(CFG v);
    __fw_rt_cfg_t #(CFG)::set(this, v);
endfunction
function fw_socket_cfg_src::CFG fw_socket_cfg_src::get();
    return __fw_rt_cfg_t #(CFG)::get(this);
endfunction
function fw_socket_cfg_sink::this_t fw_socket_cfg_sink::create(string name, fw_object parent);
    this_t o = new();
    IN imp;
    __fw_rt_cfg_h #(this_t, CFG) c = new;
    __fw_rt_obj r = __fw_rt_api::create(o, name, parent, $typename(this_t), 1, 1);
    if ($cast(imp, parent)) __fw_rt_imp #(IN)::imp[r] = imp;
    c.h = o;
    __fw_rt_cfg::sink(r, c);
    return o;
endfunction
function void fw_socket_cfg_sink::connect(fw_socket_cfg_src #(IN, OUT, CFG) peer);
    if (__fw_rt_api::link(this, peer, 0)) __fw_rt_cfg::bind_cfg(__fw_rt::impl(this), __fw_rt::impl(peer), 0);
endfunction
function void fw_socket_cfg_sink::connect_up(fw_socket_cfg_sink #(OUT, IN, CFG) outer);
    if (__fw_rt_api::link(this, outer, 1)) __fw_rt_cfg::bind_cfg(__fw_rt::impl(this), __fw_rt::impl(outer), 1);
endfunction
function void fw_socket_cfg_sink::set_imp(IN imp);
    __fw_rt_obj r = __fw_rt::impl(this);
    if (r != null) __fw_rt_imp #(IN)::imp[r] = imp;
endfunction
function OUT fw_socket_cfg_sink::get_if();
    return __fw_rt_imp #(OUT)::resolve(__fw_rt::impl(this));
endfunction
function void fw_socket_cfg_sink::add_listener(fw_cfg_listener_if #(CFG) l);
    __fw_rt_cfg_t #(CFG)::listen(this, l);
endfunction
