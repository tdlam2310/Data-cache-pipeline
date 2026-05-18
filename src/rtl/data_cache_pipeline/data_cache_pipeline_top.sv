// ============================================================================
// data_cache_pipeline.sv
// Trung Lam, Tu Pham
// 2-stage blocking data cache pipeline with a write buffer AND write-buffer
// forwarding. Sky130 1RW+1R SRAM macros.
//
//   STAGE 1   address decode -> drive index onto SRAM read port (port 1).
//             PRF1 latches request metadata for stage 2.
//
//   STAGE 2   tag + valid compare -> hit/miss.
//                 read hit  : mux the right 32-bit word out of the line.
//                 write hit : commit store via SRAM port 0 (S_WH_COMMIT).
//                 miss      : if a pending write-buffer entry holds the line
//                             we're looking for, forward it directly out of
//                             the Write Buffer into the cache (S_FORWARD). Otherwise normal miss
//                             FSM: writeback was already decoupled into
//                             the WB, so we just fetch and refill.
//
// Write buffer:
//   - On a dirty eviction the line + address are pushed; the fetch issues
//     in the SAME cycle (no separate S_WB state).
//   - Drains 1 entry per cycle whenever the main FSM isn't using the
//     memory bus (so: S_IDLE, S_WH_COMMIT, S_REFILL).
//   - If the WB is full when a new dirty eviction shows up AND no
//     forwarding is possible, we stall in S_IDLE until the background
//     drain clears a slot.
//
// Write-buffer forwarding (S_FORWARD):
//   - If a miss's line address matches any pending WB entry, the line is
//     literally in our hand. Skip S_FETCH/S_WAIT_FILL entirely, install
//     directly from the WB.
//   - The forwarded line is installed with dirty=1 (it was dirty when it
//     left, so it's still dirty relative to memory; the WB never
//     reached memory).
//   - The matching WB slot is invalidated (the line is now back in the
//     cache, no longer pending to memory).
//   - If the cache slot we're installing into currently holds a dirty
//     line, we push THAT line into the WB slot we just freed
//     (same-cycle invalidate + push to the same slot, net WB count
//     unchanged). Memory port stays idle the whole forward cycle.
//   - For write misses, the store data is spliced in just like a refill.
//   - Saves ~M cycles of memory latency on every forward hit, where M is
//     the memory read latency.
// ============================================================================
import cache_pkg::*;
module data_cache_pipeline (
    input  logic                          clk,
    input  logic                          rst,

    // ---- request from LSU ----
    input  logic                          req_valid,
    input  logic [ADDR_WIDTH-1:0]         requested_addr,
    input  logic                          read_write,
    input  logic [INSTR_ADDR_WIDTH-1:0]   instr_addr,
    input  logic [DATA_WIDTH-1:0]         lsu_data,
    output logic                          stall,

    // ---- response to register file ----
    output logic                          resp_valid,
    output logic [INSTR_ADDR_WIDTH-1:0]   resp_instr_addr,
    output logic [DATA_WIDTH-1:0]         output_to_register_file,

    // ---- main memory interface ----
    output logic                          mem_enable,
    output logic                          read_write_mem,
    output logic [ADDR_WIDTH-1:0]         cache_to_main_mem_addr,
    output logic [CACHE_LINE_WIDTH-1:0]   cache_to_main_mem,
    input  logic [CACHE_LINE_WIDTH-1:0]   main_mem_to_cache,
    input  logic [ADDR_WIDTH-1:0]         main_mem_to_cache_addr,
    input  logic                          main_mem_to_cache_valid
);
    // -------------------------------------------------------------------------
    // Local constants
    // -------------------------------------------------------------------------
    localparam int TAG_SRAM_DEPTH = 1 << (INDEX_WIDTH + 1);
    localparam int TAG_ADDR_W     = $clog2(TAG_SRAM_DEPTH);
    localparam int WB_DEPTH       = 2;
    localparam int WB_PTR_W       = $clog2(WB_DEPTH);
    // =========================================================================
    // FSM
    // =========================================================================
    typedef enum logic [2:0] {
        S_IDLE,         // hit handling, accept new requests, opportunistic WB drain
        S_WH_COMMIT,    // 1-cycle bubble committing a write hit to the SRAMs
        S_FORWARD,      // installing a line forwarded out of the write buffer
        S_FETCH,        // issuing the read request to memory
        S_WAIT_FILL,    // waiting for main_mem_to_cache_valid
        S_REFILL        // installing the refilled line; completing the request
    } cache_state_t;

    cache_state_t state, next_state;
    // =========================================================================
    // Stage 1: address decode
    // =========================================================================
    logic [TAG_WIDTH-1:0]         s1_tag;
    logic [INDEX_WIDTH-1:0]       s1_index;
    logic [WORD_OFFSET_WIDTH-1:0] s1_word_offset;


    assign s1_tag         = requested_addr[ADDR_WIDTH-1               : INDEX_WIDTH+OFFSET_WIDTH];
    assign s1_index       = requested_addr[INDEX_WIDTH+OFFSET_WIDTH-1 : OFFSET_WIDTH];
    assign s1_word_offset = requested_addr[OFFSET_WIDTH-1             : BYTE_OFFSET_WIDTH];


    // =========================================================================
    // PRF1
    // =========================================================================
    logic                          s2_valid_q;
    logic [ADDR_WIDTH-1:0]         s2_addr_q;
    logic                          s2_rw_q;
    logic [INSTR_ADDR_WIDTH-1:0]   s2_instr_addr_q;
    logic [DATA_WIDTH-1:0]         s2_lsu_data_q;
    logic accept_new_req;
    logic clear_prf1;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s2_valid_q      <= 1'b0;
            s2_addr_q       <= '0;
            s2_rw_q         <= OP_READ;
            s2_instr_addr_q <= '0;
            s2_lsu_data_q   <= '0;
        end else if (accept_new_req) begin
            s2_valid_q      <= req_valid;
            s2_addr_q       <= requested_addr;
            s2_rw_q         <= read_write;
            s2_instr_addr_q <= instr_addr;
            s2_lsu_data_q   <= lsu_data;
        end else if (clear_prf1) begin
            s2_valid_q      <= 1'b0;
        end
    end

    logic [TAG_WIDTH-1:0]         s2_tag;
    logic [INDEX_WIDTH-1:0]       s2_index;
    logic [WORD_OFFSET_WIDTH-1:0] s2_word_offset;
    assign s2_tag         = s2_addr_q[ADDR_WIDTH-1               : INDEX_WIDTH+OFFSET_WIDTH];
    assign s2_index       = s2_addr_q[INDEX_WIDTH+OFFSET_WIDTH-1 : OFFSET_WIDTH];
    assign s2_word_offset = s2_addr_q[OFFSET_WIDTH-1             : BYTE_OFFSET_WIDTH];

    // =========================================================================
    // Valid-bit array (flops, reset to 0)
    // =========================================================================
    logic [NUM_SETS-1:0] valid_bits;

    // =========================================================================
    // SRAM port wires
    // =========================================================================
    logic                            data_csb0, data_web0;
    logic [DATA_WMASK_WIDTH-1:0]     data_wmask0;
    logic [INDEX_WIDTH-1:0]          data_addr0;
    logic [CACHE_LINE_WIDTH-1:0]     data_din0;
    logic [CACHE_LINE_WIDTH-1:0]     data_dout0_unused;

    logic                            tag_csb0, tag_web0;
    logic [TAG_ADDR_W-1:0]           tag_addr0;
    logic [TAG_SRAM_WIDTH-1:0]       tag_din0;
    logic [TAG_SRAM_WIDTH-1:0]       tag_dout0_unused;

    logic                            data_csb1;
    logic [INDEX_WIDTH-1:0]          data_addr1;
    logic [CACHE_LINE_WIDTH-1:0]     data_sram_dout1;

    logic                            tag_csb1;
    logic [TAG_ADDR_W-1:0]           tag_addr1;
    logic [TAG_SRAM_WIDTH-1:0]       tag_sram_dout1;

    // =========================================================================
    // Stage 2 hit detection
    // =========================================================================
    tag_entry_t tag_entry;
    assign tag_entry = tag_sram_dout1;

    logic victim_valid, victim_dirty, hit;
    assign victim_valid = valid_bits[s2_index];
    assign victim_dirty = victim_valid && tag_entry.dirty;
    assign hit          = s2_valid_q
                       && (state == S_IDLE)
                       && victim_valid
                       && (tag_entry.tag == s2_tag);

    logic [DATA_WIDTH-1:0] hit_word;
    logic [DATA_WIDTH-1:0] refill_word;
    logic [DATA_WIDTH-1:0] forward_word;

    // =========================================================================
    // WRITE BUFFER (bitmap-indexed; no head/tail FIFO order)
    //
    // Each slot has its own valid bit. We need three operations on the WB:
    //   push    : on a dirty eviction (or in S_FORWARD if the cache slot
    //             being filled holds a dirty line)
    //   drain   : background, sends an entry to main memory
    //   forward : pulls an entry that matches the current fetch address
    //             directly back into the cache, skipping memory entirely.
    //
    // Drain order doesn't matter (different addresses can be written in any
    // order in a single-threaded design), so we use three small priority
    // encoders instead of FIFO head/tail pointers.
    // =========================================================================
    logic [CACHE_LINE_WIDTH-1:0]   wb_line  [WB_DEPTH];
    logic [ADDR_WIDTH-1:0]         wb_addr  [WB_DEPTH];
    logic [WB_DEPTH-1:0]           wb_valid;


    logic wb_full, wb_empty;
    assign wb_full  = &wb_valid;
    assign wb_empty = ~|wb_valid;


    // Line-aligned address for current PRF1 request -- target of the fetch
    // and key for the WB hazard / forwarding check.
    logic [ADDR_WIDTH-1:0] fetch_addr;
    assign fetch_addr = {s2_tag, s2_index, {OFFSET_WIDTH{1'b0}}};


    // Address of the line we're about to evict from the cache.
    logic [ADDR_WIDTH-1:0] evicted_addr_now;
    assign evicted_addr_now = {tag_entry.tag, s2_index, {OFFSET_WIDTH{1'b0}}};


    // Priority encoder: lowest-index INVALID slot (where push goes)
    logic [WB_PTR_W-1:0] wb_push_slot;
    always_comb begin
        wb_push_slot = '0;
        for (int i = WB_DEPTH-1; i >= 0; i--) begin
            if (!wb_valid[i]) wb_push_slot = i[WB_PTR_W-1:0];
        end
    end


    // Priority encoder: lowest-index VALID slot (drain candidate)
    logic [WB_PTR_W-1:0] wb_drain_slot;
    always_comb begin
        wb_drain_slot = '0;
        for (int i = WB_DEPTH-1; i >= 0; i--) begin
            if (wb_valid[i]) wb_drain_slot = i[WB_PTR_W-1:0];
        end
    end


    // Priority encoder: VALID slot whose address matches fetch_addr (the
    // forwarding hit slot). wb_addr_hazard goes high if any slot matches.
    logic [WB_PTR_W-1:0] wb_fwd_slot;
    logic                wb_addr_hazard;
    always_comb begin
        wb_addr_hazard = 1'b0;
        wb_fwd_slot    = '0;
        for (int i = WB_DEPTH-1; i >= 0; i--) begin
            if (wb_valid[i] && (wb_addr[i] == fetch_addr)) begin
                wb_addr_hazard = 1'b1;
                wb_fwd_slot    = i[WB_PTR_W-1:0];
            end
        end
    end


    // =========================================================================
    // Miss / forward routing
    //
    //   wb_addr_hazard : line we want is in WB    -> S_FORWARD (skip memory)
    //   !wb_addr_hazard, clean miss                -> S_FETCH
    //   !wb_addr_hazard, dirty miss + WB has room  -> S_FETCH (push evicted)
    //   !wb_addr_hazard, dirty miss + WB full      -> stay in S_IDLE
    //                                                 (background drain)
    // =========================================================================
    logic miss_ready_to_fetch;
    assign miss_ready_to_fetch =
        (s2_valid_q && !hit) &&
        !wb_addr_hazard &&
        (!victim_dirty || !wb_full);


    logic miss_ready_to_forward;
    assign miss_ready_to_forward =
        (s2_valid_q && !hit) && wb_addr_hazard;


    // =========================================================================
    // Next-state logic
    // =========================================================================
    always_comb begin
        next_state = state;
        unique case (state)
            S_IDLE: begin
                if (miss_ready_to_forward) begin
                    next_state = S_FORWARD;
                end else if (miss_ready_to_fetch) begin
                    next_state = S_FETCH;
                end else if (s2_valid_q && hit && (s2_rw_q == OP_WRITE)) begin
                    next_state = S_WH_COMMIT;
                end
                // else: stay in S_IDLE (either no work, or WB-full stall)
            end
            S_WH_COMMIT: next_state = S_IDLE;
            S_FORWARD:   next_state = S_IDLE;
            S_FETCH:     next_state = S_WAIT_FILL;
            S_WAIT_FILL: if (main_mem_to_cache_valid) next_state = S_REFILL;
            S_REFILL:    next_state = S_IDLE;
            default:     next_state = S_IDLE;
        endcase
    end


    always_ff @(posedge clk or posedge rst) begin
        if (rst) state <= S_IDLE;
        else     state <= next_state;
    end

    // =========================================================================
    // PRF1 control
    // =========================================================================
    logic read_hit_complete;
    assign read_hit_complete = (state == S_IDLE)
                            && s2_valid_q && hit
                            && (s2_rw_q == OP_READ);
    assign accept_new_req = (state == S_IDLE) && (!s2_valid_q || read_hit_complete);
    assign clear_prf1     = (state == S_WH_COMMIT)
                         || (state == S_REFILL)
                         || (state == S_FORWARD);
    assign stall = !accept_new_req;

    // =========================================================================
    // Refill line latch
    // =========================================================================
    logic [CACHE_LINE_WIDTH-1:0] refill_line_q;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            refill_line_q <= '0;
        end else if ((state == S_WAIT_FILL) && main_mem_to_cache_valid) begin
            refill_line_q <= main_mem_to_cache;
        end
    end
    assign hit_word     = data_sram_dout1     [s2_word_offset*DATA_WIDTH +: DATA_WIDTH];
    assign refill_word  = refill_line_q       [s2_word_offset*DATA_WIDTH +: DATA_WIDTH];
    assign forward_word = wb_line[wb_fwd_slot][s2_word_offset*DATA_WIDTH +: DATA_WIDTH];
    // =========================================================================
    // Write buffer push / pop / forward control
    //
    //   push          : S_IDLE dirty miss going to S_FETCH (normal path)
    //   pop  (drain)  : background memory write
    //   forward       : cycle in S_FORWARD; either invalidate the source
    //                   slot (clean cache victim) or REPLACE it with a new
    //                   eviction (dirty cache victim, same slot reuse).
    // =========================================================================
    logic wb_push;
    logic wb_pop;
    logic wb_forward_active;
    logic wb_forward_with_replace;   // dirty victim during forward -> push B into freed slot
    assign wb_push           = (state == S_IDLE) && (s2_valid_q && !hit && victim_dirty)
                             && miss_ready_to_fetch;
    assign wb_forward_active = (state == S_FORWARD);
    assign wb_forward_with_replace = wb_forward_active && victim_dirty;
    // =========================================================================
    // Memory port arbiter
    //   priority 1 : pipeline fetch (S_FETCH)
    //   priority 2 : WB drain, in S_IDLE / S_WH_COMMIT / S_REFILL only.
    //                Suppressed in S_FORWARD (memory port idle), in
    //                S_WAIT_FILL (read response in flight), and in S_IDLE
    //                when we're about to forward (so the matching slot
    //                doesn't get drained out from under us).
    // =========================================================================
    logic main_fsm_drives_mem;
    logic wb_drain_now;
    assign main_fsm_drives_mem = (state == S_FETCH);
    assign wb_drain_now        = !wb_empty
                              && ((state == S_IDLE)
                                  || (state == S_WH_COMMIT)
                                  || (state == S_REFILL))
                              && !miss_ready_to_forward;
    assign wb_pop = wb_drain_now;
    always_comb begin
        mem_enable             = 1'b0;
        read_write_mem         = OP_READ;
        cache_to_main_mem_addr = '0;
        cache_to_main_mem      = '0;
        if (main_fsm_drives_mem) begin
            mem_enable             = 1'b1;
            read_write_mem         = OP_READ;
            cache_to_main_mem_addr = fetch_addr;
        end else if (wb_drain_now) begin
            mem_enable             = 1'b1;
            read_write_mem         = OP_WRITE;
            cache_to_main_mem_addr = wb_addr[wb_drain_slot];
            cache_to_main_mem      = wb_line[wb_drain_slot];
        end
    end
    // =========================================================================
    // Write buffer (sequential)
    //
    // Operations and what they touch:
    //   wb_push                : write slot wb_push_slot, set valid
    //   wb_pop                 : clear valid on wb_drain_slot
    //   wb_forward + clean     : clear valid on wb_fwd_slot
    //   wb_forward + dirty     : OVERWRITE wb_fwd_slot (slot stays valid;
    //                            X is replaced by B). One write, no
    //                            ordering hazard.
    //
    // Slot disjointness:
    //   push   slot != drain  slot (push needs invalid, drain needs valid)
    //   push   and forward    never co-fire (different states)
    //   drain  and forward    never co-fire (forward state, drain inhibited)
    // =========================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wb_valid <= '0;
            for (int i = 0; i < WB_DEPTH; i++) begin
                wb_line[i] <= '0;
                wb_addr[i] <= '0;
            end
        end else begin
            if (wb_push) begin
                wb_line [wb_push_slot] <= data_sram_dout1;
                wb_addr [wb_push_slot] <= evicted_addr_now;
                wb_valid[wb_push_slot] <= 1'b1;
            end
            if (wb_pop) begin
                wb_valid[wb_drain_slot] <= 1'b0;
            end
            if (wb_forward_active) begin
                if (wb_forward_with_replace) begin
                    // Replace X with B in the forwarded slot; valid stays 1.
                    wb_line[wb_fwd_slot] <= data_sram_dout1;
                    wb_addr[wb_fwd_slot] <= evicted_addr_now;
                end else begin
                    wb_valid[wb_fwd_slot] <= 1'b0;
                end
            end
        end
    end

    // =========================================================================
    // Valid bit updates
    // =========================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_bits <= '0;
        end else if ((state == S_REFILL) || (state == S_FORWARD)) begin
            valid_bits[s2_index] <= 1'b1;
        end
    end

    // =========================================================================
    // SRAM port 1 (read) drivers
    // =========================================================================
    logic port1_enable;
    assign port1_enable = req_valid && accept_new_req;
    assign data_csb1  = ~port1_enable;
    assign data_addr1 = s1_index;
    assign tag_csb1   = ~port1_enable;
    assign tag_addr1  = {1'b0, s1_index};
    // =========================================================================
    // SRAM port 0 (read/write) drivers
    // =========================================================================
    logic [DATA_WMASK_WIDTH-1:0] data_wmask_wh;
    logic [CACHE_LINE_WIDTH-1:0] data_din_wh;
    logic [CACHE_LINE_WIDTH-1:0] data_din_refill;
    logic [CACHE_LINE_WIDTH-1:0] data_din_forward;
    always_comb begin
        // write-hit: partial mask (one word's bytes), store data spliced
        data_wmask_wh = '0;
        data_wmask_wh[s2_word_offset*BYTES_PER_WORD +: BYTES_PER_WORD] = '1;
        data_din_wh   = '0;
        data_din_wh[s2_word_offset*DATA_WIDTH +: DATA_WIDTH] = s2_lsu_data_q;
        // refill: full line, optional write-allocate splice
        data_din_refill = refill_line_q;
        if (s2_rw_q == OP_WRITE) begin
            data_din_refill[s2_word_offset*DATA_WIDTH +: DATA_WIDTH] = s2_lsu_data_q;
        end
        // forward: full line from WB, optional write-allocate splice
        data_din_forward = wb_line[wb_fwd_slot];
        if (s2_rw_q == OP_WRITE) begin
            data_din_forward[s2_word_offset*DATA_WIDTH +: DATA_WIDTH] = s2_lsu_data_q;
        end
    end
    tag_entry_t tag_din_wh, tag_din_refill, tag_din_forward;
    assign tag_din_wh      = '{pad: '0, dirty: 1'b1,                  tag: s2_tag};
    assign tag_din_refill  = '{pad: '0, dirty: (s2_rw_q == OP_WRITE), tag: s2_tag};
    // Forwarded line was already dirty when it went into WB (that's why it
    // was there). It stays dirty in cache -- memory still doesn't have it.
    assign tag_din_forward = '{pad: '0, dirty: 1'b1,                  tag: s2_tag};


    always_comb begin
        // defaults: both port-0 ports idle
        data_csb0   = 1'b1;
        data_web0   = 1'b1;
        data_wmask0 = '0;
        data_addr0  = s2_index;
        data_din0   = '0;
        tag_csb0    = 1'b1;
        tag_web0    = 1'b1;
        tag_addr0   = {1'b0, s2_index};
        tag_din0    = '0;
        case (state)
            S_WH_COMMIT: begin
                data_csb0   = 1'b0;
                data_web0   = 1'b0;
                data_wmask0 = data_wmask_wh;
                data_din0   = data_din_wh;
                tag_csb0    = 1'b0;
                tag_web0    = 1'b0;
                tag_din0    = tag_din_wh;
            end
            S_REFILL: begin
                data_csb0   = 1'b0;
                data_web0   = 1'b0;
                data_wmask0 = {DATA_WMASK_WIDTH{1'b1}};
                data_din0   = data_din_refill;
                tag_csb0    = 1'b0;
                tag_web0    = 1'b0;
                tag_din0    = tag_din_refill;
            end
            S_FORWARD: begin
                data_csb0   = 1'b0;
                data_web0   = 1'b0;
                data_wmask0 = {DATA_WMASK_WIDTH{1'b1}};
                data_din0   = data_din_forward;
                tag_csb0    = 1'b0;
                tag_web0    = 1'b0;
                tag_din0    = tag_din_forward;
            end
            default: ;
        endcase
    end

    // =========================================================================
    // Response to register file
    // =========================================================================
    always_comb begin
        resp_valid              = 1'b0;
        output_to_register_file = '0;
        resp_instr_addr         = s2_instr_addr_q;
        if (read_hit_complete) begin
            resp_valid              = 1'b1;
            output_to_register_file = hit_word;
        end else if ((state == S_REFILL) && (s2_rw_q == OP_READ)) begin
            resp_valid              = 1'b1;
            output_to_register_file = refill_word;
        end else if ((state == S_FORWARD) && (s2_rw_q == OP_READ)) begin
            resp_valid              = 1'b1;
            output_to_register_file = forward_word;
        end
    end

    // =========================================================================
    // SRAM instantiations
    // =========================================================================
    sky130_sram_2kbyte_1rw1r_32x512_8 SRAM_A (
        .clk0   (clk),
        .csb0   (tag_csb0),
        .web0   (tag_web0),
        .wmask0 (4'hF),
        .addr0  (tag_addr0),
        .din0   (tag_din0),
        .dout0  (tag_dout0_unused),
        .clk1   (clk),
        .csb1   (tag_csb1),
        .addr1  (tag_addr1),
        .dout1  (tag_sram_dout1)
    );
    sky130_sram_4kbytes_1rw1r_128x256_8 SRAM_B (
        .clk0   (clk),
        .csb0   (data_csb0),
        .web0   (data_web0),
        .wmask0 (data_wmask0),
        .addr0  (data_addr0),
        .din0   (data_din0),
        .dout0  (data_dout0_unused),
        .clk1   (clk),
        .csb1   (data_csb1),
        .addr1  (data_addr1),
        .dout1  (data_sram_dout1)
    );
endmodule



