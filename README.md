# Data Cache Pipeline

2-stage blocking data cache in SystemVerilog. Direct-mapped, write-back + write-allocate, Sky130 SRAM macros. Part of the SiliconJackets Tapeout 3 project at Georgia Tech.

## Specs

- **4 KB** data, **256 sets**, **128-bit lines** (4 × 32-bit words), direct-mapped
- 32-bit byte address: `tag[19:0] | index[7:0] | word_offset[1:0] | byte[1:0]`
- Write-back + write-allocate, depth-2 write buffer, write-buffer forwarding

## Pipeline

**Stage 1** decodes the address and drives the index onto SRAM port 1 (read). PRF1 captures request metadata at the clock edge.

**Stage 2** receives the SRAM read, compares tags, and either completes a hit or kicks off the miss FSM. Splitting across PRF1 keeps the per-cycle critical path short — steady-state throughput is one request per cycle.

## FSM (6 states)

| State | Purpose |
|---|---|
| `S_IDLE` | Hit handling, request acceptance, opportunistic WB drain |
| `S_WH_COMMIT` | Commit a write hit to SRAM port 0 (1-cycle bubble for port-0/port-1 hazard) |
| `S_FORWARD` | Install a line forwarded from the write buffer |
| `S_FETCH` | Issue a memory read |
| `S_WAIT_FILL` | Wait for `main_mem_to_cache_valid` |
| `S_REFILL` | Install the refilled line; complete the request |

The FSM governs stage 2. Stage 1 advances only when stage 2 is in `S_IDLE` and ready to accept.

## Write buffer

Dirty evictions push into a 2-entry buffer instead of stalling for a serial writeback — the fetch issues immediately, the writeback drains in background. Bitmap-indexed (no FIFO order; drain order doesn't matter for single-threaded correctness). Three priority encoders pick slots for push (lowest invalid), drain (lowest valid), and forward (address match).

**Memory port arbiter:** pipeline fetches in `S_FETCH` win; the WB drains in any other state where the bus is free (`S_IDLE`, `S_WH_COMMIT`, `S_REFILL`). This means the writeback completes in parallel with `S_REFILL` — SRAM port 0 installs the new line while the WB drives the old line out the memory port.

## Forwarding

When a miss's line address matches a pending WB entry, the cache forwards the line directly out of the buffer rather than going to memory. `S_FORWARD` installs the line via port 0, marks it dirty (it was dirty when it left, still dirty relative to memory), and cleans up the WB slot. If the cache slot being filled holds a dirty line, that line slots into the just-vacated WB entry — same-slot reuse, no extra bookkeeping.

A worst-case "re-access an evicted line" pattern goes from `2 + M` cycles to `3` cycles.

## Timing

| Operation | Cycles | LSU stall |
|---|---|---|
| Read hit | 2 | 0 |
| Write hit | 3 | 2 |
| Read/write miss | 2 + M | M (writeback hidden) |
| Forwarded miss | 3 | 1 |

`M` = memory read latency (`S_FETCH + S_WAIT_FILL + S_REFILL`).

## Storage layout

- **Data SRAM** (`sky130_sram_4kbytes_1rw1r_128x256_8`): port 1 reads, port 0 writes (refill / forward / write-hit commit). `dout0` unused.
- **Tag SRAM** (`sky130_sram_2kbyte_1rw1r_32x512_8`): 32-bit entries holding `{pad, dirty, tag}`. `wmask0` hardcoded to `4'hF` — tag entries always rewritten whole.
- **Valid bits**: 256 flops outside the SRAM. SRAMs power up to garbage, no global reset, so a flop array is the only safe reset target.
- **Refill latch** (`refill_line_q`): captures `main_mem_to_cache` at the handshake so `S_REFILL` doesn't depend on memory holding the bus past the valid pulse.

## Design choices

- **Blocking, not non-blocking.** One in-flight miss at a time; LSU stalls during miss handling. `NON_BLOCKING_HOOK` comments mark where the request queue (Complete / Dependency columns, hit/miss-flip comparator on refill) plugs in.
- **Write hits cost 2 stall cycles** to dodge SRAM port-0/port-1 same-row hazard. A store-bypass buffer would close this; left as future work.
- **Memory writes assumed accepted in 1 cycle.** Add a `main_mem_wb_ack` input and gate `wb_pop` if your memory needs a handshake.

## Files

- `cache_pkg.sv` — parameters, `tag_entry_t` struct, R/W constants
- `data_cache_pipeline.sv` — full pipeline: stage 1, PRF1, stage 2, FSM, WB, forwarding, SRAM instantiations

## Status

Blocking version with write buffer and forwarding — complete, simulatable. Non-blocking queue is under separate development and plugs in at `NON_BLOCKING_HOOK` points.

