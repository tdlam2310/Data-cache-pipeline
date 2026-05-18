# Data Cache Pipeline

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

## Files

- `cache_pkg.sv` — parameters, the `tag_entry_t` struct, R/W constants
- `data_cache_pipeline.sv` — the actual pipeline module: stage 1, PRF1, stage 2, FSM, write buffer, forwarding, SRAM instantiations
