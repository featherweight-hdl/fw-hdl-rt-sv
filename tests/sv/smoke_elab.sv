// Elaborates the spec's smoke example (fw-hdl-spec tests/sv/smoke) with
// rt-sv through fw_elab #(T).
module smoke_elab;
    fw_elab #(smoke_pkg::soc) e();
endmodule
