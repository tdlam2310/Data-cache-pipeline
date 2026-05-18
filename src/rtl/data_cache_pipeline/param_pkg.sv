<<<<<<< HEAD:src/rtl/data_cache_pipeline/param_pkg.sv
package param_pkg;
    parameter int DATA_ADDR_WIDTH = 32;
    parameter int INSTR_ADDR_WIDTH = 32;
    parameter int DATA_WIDTH = 32;
    parameter int QUEUE_LENGTH = 4;

    // CACHE and MEMORY
    parameter int CACHE_LINE_WIDTH = 128;
    parameter int OFFSET_WIDTH = $clog2(CACHE_LINE_WIDTH/DATA_WIDTH);
    parameter int INDEX_WIDTH = 8;
    parameter int TAG_WIDTH = ADDR_WIDTH - OFFSET_WIDTH - INDEX_WIDTH;
    parameter int INDEX_BASE = OFFSET_WIDTH;
    parameter int TAG_BASE = OFFSET_WIDTH + INDEX_WIDTH;
endpackage
=======
package cache_pkg;

    parameter int ADDR_WIDTH       = 32;
    parameter int INSTR_ADDR_WIDTH = 32;
    parameter int DATA_WIDTH       = 32;     // word size to register file
    parameter int CACHE_LINE_WIDTH = 128;    // 16 bytes, 4 x 32-bit words
    parameter int INDEX_WIDTH      = 8;      // 256 sets, direct-mapped
    parameter int TAG_SRAM_WIDTH   = 32;     // matches the sky130 tag macro
    parameter int BYTE_OFFSET_WIDTH = $clog2(DATA_WIDTH/8);                   // 2
    parameter int WORD_OFFSET_WIDTH = $clog2(CACHE_LINE_WIDTH/DATA_WIDTH);    // 2
    parameter int OFFSET_WIDTH      = BYTE_OFFSET_WIDTH + WORD_OFFSET_WIDTH;  // 4
    parameter int TAG_WIDTH         = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH;// 20
    parameter int DATA_WMASK_WIDTH  = CACHE_LINE_WIDTH / 8;                   // 16
    parameter int TAG_WMASK_WIDTH   = TAG_SRAM_WIDTH   / 8;                   // 4
    parameter int BYTES_PER_WORD    = DATA_WIDTH / 8;                         // 4
    parameter int NUM_SETS          = 1 << INDEX_WIDTH;                       // 256
    parameter logic OP_READ  = 1'b0;
    parameter logic OP_WRITE = 1'b1;

    // ---- tag SRAM word layout ----
    //   [31 : TAG_WIDTH+1]  pad   (11 bits unused: room for LRU/ECC/2nd way)
    //   [TAG_WIDTH]         dirty (1 bit)
    //   [TAG_WIDTH-1 : 0]   tag   (20 bits)
    //
    typedef struct packed {
        logic [TAG_SRAM_WIDTH - TAG_WIDTH - 1 - 1:0] pad;    // 11 bits
        logic                                         dirty; // 1 bit
        logic [TAG_WIDTH-1:0]                         tag;   // 20 bits
    } tag_entry_t;

endpackage
>>>>>>> 4054474 (code):src/rtl/data_cache_pipeline/param.sv
