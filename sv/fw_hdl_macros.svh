// fw_hdl_macros.svh: rt-sv's expansions of the fw_hdl_pkg macros.
//
// The names, arguments and declared members are the spec's
// (fw-hdl-spec bindings/sv/fw_hdl_macros.svh). An expansion declares only
// the members the API lists plus names beginning __fw_.
//
// - `fw_component_utils: create() pushes the creator's params value and a
//   creation record, constructs the object, then attaches the record.
// - `fw_component_params[_init]: params is initialized at the start of the
//   declaring class's constructor by __fw_params_resolve(), which applies
//   defaults, the creator's value, overrides and the init function.
`ifndef FW_HDL_MACROS_SVH
`define FW_HDL_MACROS_SVH

`define fw_component_utils(T) \
    typedef T __fw_self_t; \
    static function T create(string name, fw_component parent, \
                             params_t p = mk_params()); \
        T __fw_obj; \
        fw_hdl_pkg::__fw_rt_box #(params_t)::push(p); \
        fw_hdl_pkg::__fw_rt::begin_comp(name, parent, $typename(T)); \
        __fw_obj = new(); \
        fw_hdl_pkg::__fw_rt::end_comp(__fw_obj); \
        fw_hdl_pkg::__fw_rt_box #(params_t)::pop(); \
        return __fw_obj; \
    endfunction

`define fw_extern_utils(T, MODULE) \
    `fw_component_utils(T) \
    virtual function string extern_module(); \
        return MODULE; \
    endfunction

`define fw_component_params \
    params_t params = __fw_params_resolve(); \
    static function params_t __fw_params_resolve(); \
        params_t __fw_p = fw_hdl_pkg::__fw_rt_params #(params_t)::resolve(mk_params()); \
        fw_hdl_pkg::__fw_rt_params #(params_t)::finish(__fw_p); \
        return __fw_p; \
    endfunction

`define fw_component_params_init(FN) \
    params_t params = __fw_params_resolve(); \
    static function params_t __fw_params_resolve(); \
        params_t __fw_p = fw_hdl_pkg::__fw_rt_params #(params_t)::resolve(mk_params()); \
        FN(__fw_p); \
        fw_hdl_pkg::__fw_rt_params #(params_t)::finish(__fw_p); \
        return __fw_p; \
    endfunction

// As the spec's: the kind's handle.
`define fw_domain_kind_utils(T) \
    static function fw_domain_kind_type get_type(); \
        return fw_domain_kind_type_of #(T)::get(); \
    endfunction

`define fw_component_param_utils(C) \
    `fw_component_utils(this_t)

// As the spec's: get_type() returns the specialization's handle; its first
// call registers the protocol (fw_rt_proto.svh).
`define fw_protocol_utils(C) \
    static function fw_protocol_type get_type(); \
        return fw_protocol_type_of #(C)::get(`"C`"); \
    endfunction

`define fw_protocol_param_utils(C) \
    static function fw_protocol_type get_type(); \
        return fw_protocol_type_of #(this_t)::get(`"C`"); \
    endfunction

// As the spec's, plus __fw_conv_reg, whose static initializer registers
// the class as a converter. The pin mixin that decides its role
// (fw_mirror -> target, fw_monitor -> monitor, fw_bundle -> initiator) is
// an instance field, not knowable at this static registration time, so
// FW_ROLE_INITIATOR here is only a placeholder: __fw_rt_proto::xtor_role
// (fw_rt_proto.svh) derives the real role from a built instance's pins
// when the netlist is written.
`define fw_xtor_utils(C, PROTO) \
    `fw_component_utils(C) \
    static function fw_protocol_type __fw_xtor_protocol(); \
        return PROTO::get_type(); \
    endfunction \
    static bit __fw_conv_reg = fw_hdl_pkg::__fw_rt_proto::add_conv($typename(C), \
        PROTO::get_type(), PROTO::get_type(), FW_ROLE_INITIATOR, 1, fw_ctor_of #(fw_component, C)::get());

`define fw_xtor_param_utils(C, PROTO) \
    `fw_xtor_utils(this_t, PROTO)

`define fw_abstractor_utils(C, FROM, TO) \
    `fw_component_utils(C) \
    static function fw_protocol_type __fw_abs_from(); \
        return FROM::get_type(); \
    endfunction \
    static function fw_protocol_type __fw_abs_to(); \
        return TO::get_type(); \
    endfunction \
    static bit __fw_conv_reg = fw_hdl_pkg::__fw_rt_proto::add_conv($typename(C), \
        FROM::get_type(), TO::get_type(), FW_ROLE_INITIATOR, 0, fw_ctor_of #(fw_component, C)::get());

`define fw_abstractor_param_utils(C, FROM, TO) \
    `fw_abstractor_utils(this_t, FROM, TO)

// As the spec's, plus __fw_bundle_reg, whose initializer registers each
// instance with the protocol (fw_protocol::of answers from it).
`define fw_bundle_protocol(PROTO) \
    static function fw_protocol_type __fw_bundle_protocol(); \
        return PROTO::get_type(); \
    endfunction \
    bit __fw_bundle_reg = fw_hdl_pkg::__fw_rt_proto::bundle_inst(this, PROTO::get_type());

// As the spec's; the constructor registers the block with rt-sv
// (fw_rt_proc.svh), which finds its component after elaboration.
`define fw_comb(name) \
    class __fw_comb_``name implements fw_comb_if; \
        __fw_self_t __fw_p; \
        function new(__fw_self_t p); \
            __fw_p = p; \
            fw_hdl_pkg::__fw_rt_procs::add(p, this, null, `"name`"); \
        endfunction \
        virtual function void comb(); __fw_p.name(); endfunction \
    endclass \
    __fw_comb_``name __fw_comb_``name``_i = new(this);

`define fw_step(name) \
    class __fw_step_``name implements fw_step_if; \
        __fw_self_t __fw_p; \
        function new(__fw_self_t p); \
            __fw_p = p; \
            fw_hdl_pkg::__fw_rt_procs::add(p, null, this, `"name`"); \
        endfunction \
        virtual function void step(); __fw_p.name(); endfunction \
    endclass \
    __fw_step_``name __fw_step_``name``_i = new(this);

`endif // FW_HDL_MACROS_SVH
