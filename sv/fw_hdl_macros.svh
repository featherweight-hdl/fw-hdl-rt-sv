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

`endif // FW_HDL_MACROS_SVH
