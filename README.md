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

## Team

SiliconJackets Tapeout 3: pipeline + write buffer (me), miss / memory access (Hongyun), stall logic (Trung), queue + comparator (Lilian, Tu).
Trimmed to roughly half the length but kept the technical details that matter — FSM table, timing table, what's in each SRAM, the actual design decisions and why. Cut the parameter table (numbers are in the prose), full interface listing, and verbose acknowledgments — those are the kind of thing readers can find in the code itself.
Fix the team names if I got them wrong, and double-check you're allowed to publish this on a personal repo (academic tapeout projects sometimes have restrictions).You said: humanizehumanize17:38Claude responded: The voice now reads like someone explaining their own work — first person where natural, judgment calls called out as such ("the part I'm happiest with," "didn…markdown# Data Cache Pipeline

A 2-stage data cache I built in SystemVerilog as part of Georgia Tech's SiliconJackets Tapeout 3 project. Direct-mapped, write-back + write-allocate, backed by Sky130 SRAM macros.

## What it is

A 4 KB cache: 256 sets, 128-bit lines (four 32-bit words each), direct-mapped. The address splits into a 20-bit tag, 8-bit index, 2-bit word offset, and 2-bit byte offset. Standard textbook layout — nothing fancy in the geometry, but the pieces around it are where the interesting work is.

The cache is blocking: one miss in flight at a time, LSU stalls during the miss. I built it as the foundation for a non-blocking design that the rest of the team is layering on top.

## How the pipeline works

There are two pipeline stages with a register (PRF1) between them.

Stage 1 takes the incoming address, splits it into tag/index/offset, and hands the index to both SRAMs on their read ports. That's it — stage 1 just asks the question.

Stage 2 gets the SRAM answer back the next cycle, compares tags, decides hit or miss, and either drives the load result back to the regfile or kicks off the miss-handling FSM. In the common case (hits), one request retires per cycle.

The reason it's two stages and not one is the SRAMs themselves — they need a full cycle between "here's the address" and "here's the data," so you can't do everything combinationally. Splitting across PRF1 keeps the per-cycle critical path manageable.

## The FSM

Six states control what stage 2 is doing on any given cycle:

| State | What it's doing |
|---|---|
| `S_IDLE` | Normal mode — checking hits, taking new requests, opportunistically draining the write buffer |
| `S_WH_COMMIT` | Committing a write hit to the SRAMs (1-cycle bubble — port 0 writes can't share a row with port 1 reads) |
| `S_FORWARD` | Pulling a line straight out of the write buffer back into the cache |
| `S_FETCH` | Issuing a read request to main memory |
| `S_WAIT_FILL` | Waiting for memory to respond |
| `S_REFILL` | Installing the line memory just gave us |

Stage 1 only makes progress while we're in `S_IDLE` and ready for the next request. Everything else stalls the LSU.

## The write buffer

The straightforward way to handle a dirty miss is: write the old line back to memory, then fetch the new one. That's two serial trips across a slow memory bus, and the LSU is stuck waiting for both.

Instead, dirty evictions go into a 2-entry write buffer in the cache. The fetch starts *immediately*; the writeback drains to memory in the background, opportunistically, whenever the memory bus isn't being used for something more urgent. Most of the time the writeback completes during `S_REFILL` — the SRAM is busy installing the new line via port 0 while the memory bus is busy sending the old line out. Different hardware, same cycle, no conflict.

I ended up using a bitmap-indexed buffer rather than a strict FIFO. Strict ordering didn't matter for correctness (writes to different addresses don't depend on each other in a single-threaded design), and dropping the head/tail pointers made the forwarding logic cleaner. Three small priority encoders pick the slot to push into, the slot to drain, and the slot to forward from.

## Forwarding

This is the part I'm happiest with. If the line the CPU is asking for happens to be sitting in the write buffer (because we just evicted it and the writeback hasn't drained yet), there's no reason to go to memory — the line is *right there*.

`S_FORWARD` handles this case in one cycle. It pulls the line out of the WB, installs it back in the cache (marked dirty, since the WB never actually wrote it to memory), and cleans up the buffer slot. If the cache slot being filled happens to hold another dirty line, that line takes the WB slot the forwarded line just vacated — same slot, swapped contents, no extra bookkeeping.

The worst-case "evict a line, then immediately need it back" pattern (which would otherwise be a full memory round-trip) collapses into a 3-cycle operation, almost as fast as a hit.

## Timing

| Operation | Cycles end-to-end | LSU stall |
|---|---|---|
| Read hit | 2 | 0 |
| Write hit | 3 | 2 |
| Read/write miss | 2 + M | M (writeback is hidden) |
| Forwarded miss | 3 | 1 |

`M` is the memory read latency — `S_FETCH + S_WAIT_FILL + S_REFILL`, mostly the wait.

## Small details worth mentioning

- **Valid bits live in flops, not the SRAM.** The SRAM macros have no global reset and power up to garbage. A flop-backed valid array is the only way to guarantee correct behavior after `rst` without a flush sequence.
- **The refill data is latched** the moment `main_mem_to_cache_valid` pulses. Memory might drop the bus right after the handshake, so we can't rely on it being there in `S_REFILL`.
- **Tag SRAM `wmask` is hardcoded to `4'hF`.** Tag entries are always rewritten as a whole word — there's no scenario where you'd want to update only part of a tag — so partial masking is pointless.
- **The data and tag SRAMs are accessed in parallel** every cycle, which means stage 1 reads both before stage 2 even knows whether it's a hit. Slightly wasteful on misses, but it keeps the critical path short and is the standard tradeoff.

## What's not in here yet

The cache is blocking — one miss at a time. The non-blocking version from our team's design has a request queue with Complete and Dependency columns and a comparator that flips hit/miss bits when refills land. That's a separate module my teammates are building. Every spot in my code where it would plug in is marked with a `NON_BLOCKING_HOOK` comment.

Write hits also cost an extra stall cycle that a small store-bypass buffer could eliminate. Didn't end up implementing that — it would complicate the SRAM port arbitration and the win is modest.

## Files

- `cache_pkg.sv` — parameters, the `tag_entry_t` struct, R/W constants
- `data_cache_pipeline.sv` — the actual pipeline module: stage 1, PRF1, stage 2, FSM, write buffer, forwarding, SRAM instantiations
