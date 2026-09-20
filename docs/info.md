## How it works

Digital dual-phase (I/Q) lock-in amplifier / demodulator with programmable block averaging:

1. **`reference_generator`**: a 16-bit phase accumulator drives a 32-entry sine lookup table
   (8-bit signed), producing quadrature reference signals `ref_i` (cosine) and `ref_q` (negative sine).
   The phase only advances when the core actually accepts a new sample (`advance`), so the
   reference frequency is expressed as phase-per-sample, not phase-per-clock.
2. **`lockin_core`**: for every accepted sample, a single reused multiplier computes
   `sample * ref_i` then `sample * ref_q` over two internal states (`MIX_I`, `MIX_Q`), and
   accumulates both products into 26-bit running sums. After the configured block size
   (16 / 64 / 256 / 1024 samples, selected by `window_sel`), the accumulated sums are
   right-shifted (block-average) and latched as the signed 16-bit result `result_i`/`result_q`,
   raising `result_valid` for one cycle.
3. **`register_interface`**: a synchronous, strobe-based register file (addresses 0-7) exposes
   configuration (phase step, window size), a snapshot mechanism to atomically read back the
   latest I/Q result without tearing, and status flags (`busy`, `new_result`, `overrun`).

## How to test

All access is through the 8-bit `DATA_IN`/`READ_DATA` bus plus dedicated strobes on the
bidirectional pins, sampled synchronously to `clk` (one strobe edge recognized per clock, not an
SPI/I2C protocol):

- **Configure**: write `phase_step` (registers `4`/`5`, low/high byte) and `window_sel`
  (register `6`, 0-3) using `WRITE_STROBE` with `ADDR` set to the target register and `DATA_IN`
  holding the byte.
- **Feed samples**: drive `DATA_IN` with a signed 8-bit sample and pulse `SAMPLE_STROBE` for one
  cycle. `BUSY` goes high while the sample is being mixed (a few clocks) and must be low before
  the next sample is accepted.
- **Read a result**: once a full block has been averaged, `NEW_RESULT` goes high. Pulse
  `SNAPSHOT_STROBE` to atomically latch the current `result_i`/`result_q` into the read-back
  registers (this also clears `NEW_RESULT`), then read the four bytes at addresses `0`-`3`
  (`snapshot_i[7:0]`, `snapshot_i[15:8]`, `snapshot_q[7:0]`, `snapshot_q[15:8]`).
- **Status**: register `7` reports `{5'b0, overrun, new_result, busy}`.
  Writing `1` to register `7` clears the flags, snapshots, results,
  accumulators and reference phase, aborting any ongoing measurement.
  The configured phase step and window size are preserved.

`test/test.py` cross-checks the RTL against an independent Python integer reference model across
all four window sizes and several reference frequencies (including phase wrap-around), exercises
the register protocol and edge cases (reset mid-block, reconfiguration while busy, sample
overruns, `ena` gating), and validates amplitude/phase recovery against a noisy synthetic input
signal with third-harmonic interference.

## External hardware

Simulation uses digitally generated samples and requires no external hardware.
Physical testing requires a controller that supplies signed 8-bit samples
and reads the results through the synchronous GPIO interface.
Measuring a real analog signal additionally requires an external ADC
and suitable signal conditioning. No ADC is integrated in this design.