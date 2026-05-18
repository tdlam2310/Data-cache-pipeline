module data_cache_pipeline(

    input logic clk, rst,
    input logic [ADDR_WIDTH-1:0] requested_addr,
    input logic read_write,
    input logic [INSTR_ADDR_WIDTH-1:0] instr_addr,
    input logic [DATA_WIDTH-1:0] lsu_data,  

    //read output to register file
    output logic [DATA_WIDTH-1:0] output_tp_regster_file,

    
    //INTERACTION WITH MEMROY
    output logic read_write_mem,
    //receive from mem
    input logic [CACHE_LINE_WIDTH-1:0] main_mem_to_cache,
    input logic [ADDR_WIDTH-1:0] main_mem_to_cache_addr,
    //not sure if we need this but yeah lets just put it here
    input logic  main_mem_to_cache_valid,

    //send to mem
    output logic [CACHE_LINE_WIDTH-1:0] cache_to_main_mem,
    output logic [CACHE_LINE_WIDTH-1:0] cache_to_main_mem_addr,
    output logic mem_enable;


); 
    


//================================================
   //  tag [31:10] |    index [9:2]      | 0ffset [1:0]                
   //================================================                                                 =
    logic [INDEX_WIDTH-1:0] index;
    logic [TAG_WIDTH-1:0] tag;
    logic [OFFSET_WIDTH-1:0] offset;
    assign offset = requested_addr[OFFSET_WIDTH-1:0];
    assign index = requested_addr[OFFSET_WIDTH+INDEX_WIDTH-1 :OFFSET_WIDTH];
    assign tag = requested_addr[ADDR_WIDTH-1:OFFSET_WIDTH+INDEX_WIDTH];

    logic [CACHE_LINE_WIDTH-1:0] cache_line_from_data_array;
     logic [TAG_WIDTH-1:0] cache_line_from_tag_array;

    
    sky130_sram_4kbytes_1rw1r_128x256_8 data_array(
        .clk0(clk),
        .csb0(),
        .web0(),
        .wmask0(),
        .addr0(index),
        .din0(),
        .dout0(),

        .clk1(clk),
        .csb1(),
        .addr1(),
        .dout1(cache_line_from_data_array)
    );

     sky130_sram_2kbyte_1rw1r_32x512_8 tag_array (
        .clk0   (clk),  
        .csb0   (), //write
        .web0   (), 
        .wmask0 (), 
        .addr0  (index), 
        .din0   (),
        .dout0  (), 
        .clk1   (clk), 
        .csb1   (), //read
        .addr1  (), 
        .dout1  ({10'd0,TAG_WIDTH}) 
    );

endmodule
