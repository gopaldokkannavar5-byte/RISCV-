# BFloat16 ALU — Basys 3 FPGA Project

## Project Overview

This project implements a **BFloat16 (Brain Floating Point) Arithmetic Logic Unit (ALU)** on the Digilent **Basys 3** FPGA board (Xilinx Artix-7). It supports three floating-point operations:

- **Addition** (mode `00`)
- **Subtraction** (mode `01`)
- **Multiplication** (mode `10`)

The result is displayed on the **4-digit 7-segment display** as a 4-digit hexadecimal number, and the raw result bits appear on the **16 LEDs**. Three additional LEDs flag **Overflow**, **Underflow**, and **NaN/Invalid** conditions.

---

## What is BFloat16?

BFloat16 is a 16-bit floating-point format used in machine learning hardware (Google TPUs, Intel/AMD CPUs). It shares the same exponent range as 32-bit IEEE 754 float but uses fewer mantissa bits.

```
Bit layout:
 15      14    7   6       0
 ┌──────┬────────┬──────────┐
 │ Sign │  Exp  │ Mantissa  │
 │  1b  │  8b   │   7b      │
 └──────┴────────┴──────────┘

Value = (-1)^sign × 2^(exp-127) × 1.mantissa
```

| Field    | Bits   | Description                       |
|----------|--------|-----------------------------------|
| Sign     | 1 bit  | 0 = positive, 1 = negative        |
| Exponent | 8 bits | Biased by 127 (range 1–254)       |
| Mantissa | 7 bits | Fractional part (implicit 1 in front) |

### Special Values
| Pattern       | Meaning     |
|---------------|-------------|
| exp=0, frac=0 | Zero (±0)   |
| exp=255, frac=0 | Infinity (±∞) |
| exp=255, frac≠0 | NaN         |

---

## Project File Structure

```
bfloat16_alu/
├── src/
│   ├── bf16_alu_top.v          ← Top-level module (main integration)
│   ├── bf16_decoder.v          ← Decodes sign/exp/mantissa from bf16 bits
│   ├── bf16_align.v            ← Aligns mantissas for add/sub
│   ├── bf16_addsub.v           ← Performs addition or subtraction
│   ├── bf16_mul.v              ← Performs multiplication
│   ├── bf16_normalize.v        ← Normalizes the result mantissa/exponent
│   ├── bf16_round_encode.v     ← Rounds and re-encodes to bf16 format
│   ├── bf16_exception.v        ← Handles NaN, Inf, Zero special cases
│   ├── input_reg.v             ← Input registers + button debouncer
│   └── seg7_display.v          ← 7-segment display controller
├── sim/
│   └── tb_bf16_alu.v           ← Testbench for simulation
├── constraints/
│   └── basys3_bfloat16_alu.xdc ← Basys 3 pin assignment constraints
└── README.md                   ← This file
```

---

## Module-by-Module Explanation

### 1. `bf16_decoder.v` — BFloat16 Decoder
**What it does:** Breaks a 16-bit bfloat16 number into its three parts: sign, exponent, and mantissa.

**How it works:**
- Sign = bit 15
- Exponent = bits 14 down to 7
- Mantissa = `{1, bits[6:0]}` for normal numbers (adds the implicit leading 1)
- Also flags if the value is Zero, Infinity, or NaN

---

### 2. `bf16_align.v` — Alignment Unit
**What it does:** Before adding or subtracting two numbers, their exponents must match. The number with the smaller exponent has its mantissa shifted right until both exponents are equal.

**Example:**
```
A = 1.5 × 2^3,  B = 1.0 × 2^1
To align: B becomes 0.25 × 2^3 (shifted right by 2)
Now both have exponent 3 and can be added.
```

---

### 3. `bf16_addsub.v` — Add/Subtract Unit
**What it does:** Adds or subtracts the aligned mantissas. Handles the sign logic:
- Same signs → add magnitudes, keep sign
- Different signs → subtract smaller from larger, sign follows the larger magnitude

---

### 4. `bf16_mul.v` — Multiplier Unit
**What it does:** Multiplies two bfloat16 numbers.

**Steps:**
1. **Result sign** = A sign XOR B sign
2. **Result exponent** = exp_A + exp_B − 127 (remove one bias)
3. **Result mantissa** = mant_A × mant_B (8 × 8 = 16-bit product)

---

### 5. `bf16_normalize.v` — Normalization Unit
**What it does:** After arithmetic, the result mantissa may not be in normal form. This module shifts it left or right until the leading 1 is in the correct position, adjusting the exponent accordingly.

**Cases handled:**
- Carry-out from addition → shift right 1, increment exponent
- Leading zeros from subtraction → shift left N times, decrement exponent by N

---

### 6. `bf16_round_encode.v` — Rounding and Encoding
**What it does:** Two sub-modules:
- **`bf16_round`**: Applies round-to-nearest (IEEE default). If the guard bit is 1 and sticky/LSB conditions are met, rounds the mantissa up.
- **`bf16_encoder`**: Packs sign + exponent + mantissa back into the 16-bit bfloat16 format. Also handles force-zero, force-Inf, force-NaN overrides from the exception handler.

---

### 7. `bf16_exception.v` — Exception Handler
**What it does:** Checks for IEEE-defined special cases before computation:

| Case              | Result  |
|-------------------|---------|
| Any input is NaN  | NaN     |
| Inf + Inf (same)  | Inf     |
| Inf − Inf         | NaN     |
| Inf × 0           | NaN     |
| 0 × anything      | 0       |
| Inf + normal      | Inf     |

---

### 8. `input_reg.v` — Input Register + Debouncer
**What it does:**
- **`input_reg`**: Captures switch values into registers for operand A and B.
- **`btn_debounce`**: Eliminates button bounce by waiting ~20ms of stable signal before generating a clean pulse.

---

### 9. `seg7_display.v` — 7-Segment Display Driver
**What it does:** Drives all four digits of the Basys 3's 7-segment display.

**How TDM works:** Only one digit can be lit at a time. The module cycles through all 4 digits at ~250Hz (fast enough to appear steady). For each digit, it activates the corresponding anode and drives the correct segments for the hex nibble.

**Active-low:** On Basys 3, both anodes and cathodes are active-low (0 = ON).

---

### 10. `bf16_alu_top.v` — Top Module
**What it does:** Connects all sub-modules together in the correct pipeline order and maps them to Basys 3 I/O pins.

---

## Hardware I/O Guide

### Buttons

| Button | Function                        |
|--------|---------------------------------|
| BTNU   | Reset (clears all registers)    |
| BTNL   | Load operand A from switches    |
| BTNR   | Load operand B + mode           |
| BTNC   | Compute (manual clock edge)     |

### Switches

| Switches   | When Loading A | When Loading B       |
|------------|----------------|----------------------|
| SW[15:0]   | Operand A bits | Operand B bits       |
| SW[1:0]    | (ignored)      | Operation mode       |

**Mode encoding (SW[1:0] when loading B):**

| SW[1:0] | Operation     |
|---------|---------------|
| 00      | Addition      |
| 01      | Subtraction   |
| 10      | Multiplication|

### LEDs

| LED     | Meaning                        |
|---------|--------------------------------|
| LD[15:0]| Raw 16-bit result bits         |
| LD[15]  | Overflow (result = ±Infinity)  |
| LD[14]  | Underflow (result = 0)         |
| LD[13]  | NaN / Invalid operation        |

### 7-Segment Display

Shows the **4-digit hex representation** of the bfloat16 result.

**Example:** `3F80` on the display means `0x3F80` = 1.0 in bfloat16

---

## Step-by-Step: How to Use on Hardware

1. **Connect** the Basys 3 via USB
2. **Program** the board with the bitstream from Vivado
3. **Reset:** Press **BTNU** once to clear everything
4. **Enter Operand A:**
   - Set SW[15:0] to your first bfloat16 number
   - Press **BTNL** to latch it
5. **Enter Operand B + Mode:**
   - Set SW[15:2] to your second bfloat16 number
   - Set SW[1:0] to the mode (00=add, 01=sub, 10=mul)
   - Press **BTNR** to latch both
6. **Compute:**
   - Press **BTNC** to execute the operation
7. **Read result:**
   - 7-segment display shows hex result
   - LEDs[15:0] show raw bits
   - Top 3 LEDs show flags

---

## BFloat16 Quick Reference Table

| Value   | Hex    | Binary (S EXP MANT)          |
|---------|--------|------------------------------|
| 0.0     | 0x0000 | 0 00000000 0000000           |
| 1.0     | 0x3F80 | 0 01111111 0000000           |
| 2.0     | 0x4000 | 0 10000000 0000000           |
| 3.0     | 0x4040 | 0 10000000 1000000           |
| 4.0     | 0x4080 | 0 10000001 0000000           |
| -1.0    | 0xBF80 | 1 01111111 0000000           |
| 0.5     | 0x3F00 | 0 01111110 0000000           |
| +Inf    | 0x7F80 | 0 11111111 0000000           |
| -Inf    | 0xFF80 | 1 11111111 0000000           |
| NaN     | 0x7FC0 | 0 11111111 1000000           |

---

## How to Run in Vivado

### Simulation (Behavioral)

1. Open **Vivado** → Create or Open the project
2. Add all `.v` files from `src/` as design sources
3. Add `sim/tb_bf16_alu.v` as a simulation source
4. Click **Run Simulation → Run Behavioral Simulation**
5. Observe waveforms; check the Tcl console for PASS/FAIL messages

### Synthesis and Implementation

1. In Vivado, set `bf16_alu_top` as the **Top Module**
2. Add `constraints/basys3_bfloat16_alu.xdc` as the constraints file
3. Set the target part: **xc7a35tcpg236-1** (Basys 3)
4. Click **Run Synthesis**
5. Click **Run Implementation**
6. Click **Generate Bitstream**
7. Use **Hardware Manager** to program the board

### Vivado Project Settings

- **Target Language:** Verilog
- **Default Library:** work  
- **Part:** xc7a35tcpg236-1
- **Simulator:** Vivado Simulator (xsim)

---

## How Each Operation Works Step-by-Step

### Addition / Subtraction
```
1. Decode A and B → get sign, exp, mantissa for each
2. Check exceptions (NaN, Inf, Zero)
3. Align: right-shift the smaller number's mantissa by |exp_A - exp_B|
4. Add or subtract the mantissas (with sign logic)
5. Normalize: shift result until leading 1 is in correct position
6. Round: apply round-to-nearest
7. Encode: pack sign + exp + mantissa back to 16 bits
```

### Multiplication
```
1. Decode A and B
2. Check exceptions
3. result_sign = sign_A XOR sign_B
4. result_exp  = exp_A + exp_B - 127
5. result_mant = mant_A × mant_B (16-bit product)
6. Normalize the product (shift and adjust exponent)
7. Round and encode
```

---

## Known Limitations / Simplifications

1. **Subnormal numbers**: Subnormals (exponent = 0) are partially supported (detected, but computation may flush to zero).
2. **Guard/sticky bits**: The rounding module accepts guard/sticky inputs but the top module currently passes 0 for simplicity. For full IEEE compliance, extend the mantissa path to track these bits.
3. **Single-cycle operation**: The entire computation is combinational (no pipeline). This is correct but may limit clock frequency at high speeds.
4. **Mode input**: The mode is loaded from SW[1:0] when pressing BTNR. Make sure to set the mode switches *before* pressing BTNR.

---

## Extending the Project

- Add **division** support (mode `11`)
- Track guard and sticky bits through the pipeline for full rounding compliance
- Add a **state machine** to display A, B, and result in sequence
- Convert result to **decimal** display on 7-segment

---

*Project designed for the Digilent Basys 3 (Artix-7 XC7A35T) using Xilinx Vivado.*
