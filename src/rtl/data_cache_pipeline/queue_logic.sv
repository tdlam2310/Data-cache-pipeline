import param_pkg::*;
module queue_logic(
    input logic clk,
    input logic incoming_hit_miss,
    input logic [INSTR_ADDR_WIDTH-1:0] incoming_instr_addr,
    input logic [DATA_ADDR_WIDTH-1:0] incoming_data_addr,
    input logic incoming_wr_rd,
    input logic [DATA_WIDTH-1:0] incoming_data,
    input logic incoming_valid,
    input logic [TAG_WIDTH-1:0] incoming_evicted_tag,
    input logic [CACHE_LINE_WIDTH-1:0] incoming_evicted_line
);
    typedef struct {
        logic hit_miss; // 1 if hit, 0 if miss
        logic [INSTR_ADDR_WIDTH-1:0] instr_addr;
        logic [DATA_ADDR_WIDTH-1:0] data_addr;
        logic wr_rd; // 1 if write, 0 if read
        logic [DATA_WIDTH-1:0] data;
        logic valid;
        logic complete; // always 0 if not at front of queue
        logic [TAG_WIDTH-1:0] evicted_tag; // not care if hit
        logic [CACHE_LINE_WIDTH-1:0] evicted_line; // not care if hit
    } queue_entry_t;

    queue_entry_t queue[QUEUE_LENGTH];
    queue_entry_t queue_next[QUEUE_LENGTH];

    logic [$clog2(QUEUE_LENGTH)-1:0] last_entry_idx;
    logic [$clog2(QUEUE_LENGTH)-1:0] last_entry_idx_next;

    always_ff @(posedge clk) begin
        for (int i = 0; i <= last_entry_idx; i += 1) begin
            queue[i].hit_miss <= queue_next[i].hit_miss;
            queue[i].instr_addr <= queue_next[i].instr_addr;
            queue[i].data_addr <= queue_next[i].data_addr;
            queue[i].wr_rd <= queue_next[i].wr_rd;
            queue[i].data <= queue_next[i].data;
            queue[i].valid <= queue_next[i].valid;
            queue[i].complete <= queue_next[i].complete;
            queue[i].evicted_tag <= queue_next[i].evicted_tag;
            queue[i].evicted_line <= queue_next[i].evicted_line;
        end
        last_entry_idx <= last_entry_idx_next;
    end

    always_comb begin
        // Only if move up
        for (int i = 0; i <= last_entry_idx; i += 1) begin
            queue_next[i].hit_miss = queue[i + 1].hit_miss;
            queue_next[i].instr_addr = queue[i + 1].instr_addr;
            queue_next[i].data_addr = queue[i + 1].data_addr;
            queue_next[i].wr_rd = queue[i + 1].wr_rd;
            queue_next[i].data = queue[i + 1].data;
            queue_next[i].valid = queue[i + 1].valid;
            queue_next[i].complete = queue[i + 1].complete;
            queue_next[i].evicted_tag = queue[i + 1].evicted_tag;
            queue_next[i].evicted_line = queue[i + 1].evicted_line;
        end

        // Only if add new entry
        last_entry_idx_next = last_entry_idx + 1;
        queue_next[last_entry_idx_next].hit_miss = incoming_hit_miss;
        queue_next[last_entry_idx_next].instr_addr = incoming_instr_addr;
        queue_next[last_entry_idx_next].data_addr = incoming_data_addr;
        queue_next[last_entry_idx_next].wr_rd = incoming_wr_rd;
        queue_next[last_entry_idx_next].data = incoming_data;
        queue_next[last_entry_idx_next].valid = incoming_valid;
        queue_next[last_entry_idx_next].complete = 0;
        queue_next[last_entry_idx_next].evicted_tag = incoming_evicted_tag;
        queue_next[last_entry_idx_next].evicted_line = incoming_evicted_line;
    end
endmodule