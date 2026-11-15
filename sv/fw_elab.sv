// fw_elab #(type T): elaborates component class T as the top, named "top".
// Writes the netlist to the path given by +fw_netlist=<path>, and ends with a
// non-zero exit status if elaboration reported an error.
//
// Under Verilator 5.055 there is an internal error (V3Param, "ClassRefDType
// still has paramsp in paramValueString") when a class reached through this
// module's type parameter uses a params struct holding a constructor factory
// that is also named from outside its class (fw_param_override #(c::params_t)).
// The equivalent non-parameterized form avoids it:
//     module elab_top;
//         initial fw_hdl_pkg::__fw_rt::main(my_pkg::top_c::create("top", null));
//     endmodule
module fw_elab #(type T);
    initial fw_hdl_pkg::__fw_rt::main(T::create("top", null));
endmodule
