# 8-Point NTT Accelerator — Verilog Implementation

Hardware implementation of the Number Theoretic Transform (NTT).

## Parameters

| Parameter | Value |
|-----------|-------|
| Transform size (n) | 8 |
| Modulus (q) | 17 |
| Root of unity (ω) | 9 |
| Data width | 5 bits (covers 0..16) |

## Repository Structure

```
ntt_accelerator/
├── butterfly.v        # Butterfly arithmetic unit (combinational)
├── twiddle_rom.v      # Precomputed twiddle factor ROM (async read)
├── ntt_top.v          # Top-level NTT with FSM control and data RAM
├── tb_ntt.v           # Self-checking testbench (4 test vectors)
├── input_0.hex        # Test vector 0 input  [1,2,3,4,5,6,7,8]
├── expected_0.hex     # Test vector 0 expected output
├── input_1.hex        # Test vector 1 input  [3,1,4,1,5,9,2,6]
├── expected_1.hex     # Test vector 1 expected output
├── input_2.hex        # Test vector 2 input (impulse at end)
├── expected_2.hex     # Test vector 2 expected output
├── input_3.hex        # Test vector 3 input (DC impulse)
├── expected_3.hex     # Test vector 3 expected output
└── README.md
```

## Architecture

### Algorithm

Cooley-Tukey **Decimation-in-Time (DIT)** NTT with in-place butterfly operations.

1. Input coefficients are written into data RAM in **bit-reversed** order.
2. The FSM iterates through **log₂(n) = 3 stages**, each with **n/2 = 4** butterfly operations.
3. A **single butterfly unit** is reused across all stages (iterative architecture).


### FSM States

```
IDLE (start)>>> LOAD (8 cycles) >>> COMPUTE (12 cycles)>>> DONE>>> IDLE
```

- **IDLE**: Wait for `start` pulse.
- **LOAD** (8 cycles): Copy `coeff_in[0..7]` into RAM at bit-reversed addresses.
- **COMPUTE** (4 butterflies × 3 stages = 12 cycles): Iterative butterfly processing.
- **DONE** (1 cycle): Assert `done`, results readable on `coeff_out`.

Total latency: **21 clock cycles** from `start` to `done`.

### Modules

#### `butterfly.v`
Combinational butterfly unit. Performs:
- `bw = (b × w) mod q` - modular multiply using integer division by constant q
- `u  = (a + bw) mod q` - modular add
- `v  = (a - bw) mod q` - modular subtract

For q=17, all intermediate values fit in ≤9 bits. Division by the constant 17 is optimised away by synthesis to a small LUT or shift-add tree.

#### `twiddle_rom.v`
Asynchronous ROM storing the 4 precomputed twiddle factors:

| Index | Value | Meaning |
|-------|-------|---------|
| 0 | 1  | ω⁰ mod 17 |
| 1 | 9  | ω¹ mod 17 |
| 2 | 13 | ω² mod 17 |
| 3 | 15 | ω³ mod 17 |

#### `ntt_top.v`
Top-level integrating FSM, data RAM (8-entry register file), butterfly unit, and twiddle ROM.

Address generation logic per stage:

| Stage | stride | half | addr_a | addr_b | twiddle index |
|-------|--------|------|--------|--------|---------------|
| 1 | 2 | 1 | cnt×2 | cnt×2+1 | 0 |
| 2 | 4 | 2 | group×4+k | group×4+k+2 | k×2 |
| 3 | 8 | 4 | cnt | cnt+4 | cnt |

where `cnt` ∈ {0,1,2,3} indexes the butterfly within each stage.

## Simulation

### Prerequisites

- [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog`, `vvp`)

```bash
# Ubuntu/Debian
sudo apt install iverilog

# macOS
brew install icarus-verilog
```

### Run

```bash
iverilog -o ntt_sim tb_ntt.v ntt_top.v butterfly.v twiddle_rom.v
vvp ntt_sim
```

Expected output:
```
=================================================
  8-point NTT Accelerator — Simulation Results
  n=8  q=17  omega=9
=================================================

Test 0 | in:  [ 1, 2, 3, 4, 5, 6, 7, 8]
        | exp: [ 2, 1,12, 3,13, 6,14, 8]
        | got: [ 2, 1,12, 3,13, 6,14, 8]  PASS

Test 1 | in:  [ 3, 1, 4, 1, 5, 9, 2, 6]
        | exp: [14,13, 7,11,14, 1,14, 1]
        | got: [14,13, 7,11,14, 1,14, 1]  PASS

Test 2 | in:  [ 0, 0, 0, 0, 0, 0, 0, 1]
        | exp: [ 1, 2, 4, 8,16,15,13, 9]
        | got: [ 1, 2, 4, 8,16,15,13, 9]  PASS

Test 3 | in:  [ 1, 0, 0, 0, 0, 0, 0, 0]
        | exp: [ 1, 1, 1, 1, 1, 1, 1, 1]
        | got: [ 1, 1, 1, 1, 1, 1, 1, 1]  PASS

=================================================
  4 PASSED  |  0 FAILED  (of 4 tests)
=================================================
  ALL TESTS PASSED
```

### Waveform (optional)

```bash
# View the VCD dump generated automatically
gtkwave ntt_sim.vcd
```

## Extending to Larger / Production NTTs

| Feature | Change required |
|---------|-----------------|
| **Inverse NTT (INTT)** | Reverse butterfly order, use ω⁻¹ = modular inverse of ω, multiply output by n⁻¹ mod q |
| **Larger n (16, 32, …)** | Increase LOG2N, extend address generators, add twiddle ROM entries |
| **Pipelining** | Register butterfly inputs/outputs; add pipeline stages to FSM counter |
| **Large prime (e.g., Kyber q=3329)** | Replace modular multiply with Barrett reduction; widen data path to 12 bits |
| **Parallel butterflies** | Instantiate n/2 butterfly units; remove stage loop; reduce to log₂n cycles |
