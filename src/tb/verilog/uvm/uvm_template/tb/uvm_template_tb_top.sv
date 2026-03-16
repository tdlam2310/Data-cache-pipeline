module uvm_template_tb_top;

    timeunit 1ns;
    timeprecision 100ps;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import uvm_template_test_pkg::*;
    import uvm_template_seq_pkg::*;
    import uvm_template_agent_pkg::*;
    import uvm_template_env_pkg::*;

endmodule : uvm_template_tb_top
