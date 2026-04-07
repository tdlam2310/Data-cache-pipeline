package param
    parameter int ADDR_WIDTH = 32;
    parameter int INSTR_ADDR_WIDTH = 32;
     //length data that register file store
    parameter int DATA_WIDTH = 32;

    //CACHE and MEMORY
    parameter int OFFSET_WIDTH = $clog2(CACHE_LINE_WIDTH/DATA_WIDTH);
    parameter int TAG_WIDTH = ADDR_WIDTH - OFFSET_WIDTH - INDEX_WIDTH;
    parameter int INDEX_WIDTH = 8;
    parameter int CACHE_LINE_WIDTH = 128;

    struct {
        
    } queue_data;
    

endpackage
