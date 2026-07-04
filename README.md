# Online-Learning MLP Accelerator — Boolean Black Board (XC7S50CSGA324-1)

A standalone, synthesizable Verilog-2001 FPGA implementation of an
8 → 4 → 2 Multi-Layer Perceptron that performs **both online training
(backpropagation) and inference entirely inside the FPGA fabric** — no
MCU, no UART/SPI, no external RAM. Stimulus and control come from
onboard switches/buttons; status is reported on LEDs.

Verified in simulation with Icarus Verilog (`iverilog -g2001`): the
included self-checking testbench shows MSE decreasing monotonically
over 12 online-training epochs on a fixed sample, confirms weights are
updated by training, and confirms BTN2 restores deterministic initial
weights.

---

## 1. Numeric Format

Signed fixed-point, **Q4.12** (per project spec: 1 sign + 3 integer +
12 fraction bits = 16 bits total, i.e. standard two's-complement with
12 fractional bits, range ≈ [-8.0, +7.99976), resolution 2⁻¹² ≈
0.000244).

| Field       | Bits | Notes                          |
|-------------|------|---------------------------------|
| Sign        | [15] | 1 = negative                    |
| Integer     | [14:12] | 3 bits, part of two's-complement value |
| Fraction    | [11:0]  | 12 bits                        |

All arithmetic (`fixed_multiplier`, `fixed_adder`, `fixed_mac`) saturates
on overflow and rounds (round-half-up) on rescale. No floating point,
no IEEE-754 anywhere in the design.

---

## 2. Network Architecture

```
   x0 ─┐
   x1 ─┤                    h0 ─┐
   x2 ─┤     W1 (4x8)       h1 ─┤     W2 (2x4)
   x3 ─┼──── + Bias1 ───────h2 ─┼──── + Bias2 ──── y0 (class 0 score)
   x4 ─┤     ReLU           h3 ─┘     Hard-Sigmoid  y1 (class 1 score)
   x5 ─┤
   x6 ─┤
   x7 ─┘
   INPUTS=8              HIDDEN=4                OUTPUTS=2
```

- **Hidden layer activation:** ReLU(x) = max(0, x)
- **Output layer activation:** Hard-sigmoid y = clamp(0.5 + 0.25·x, 0, 1)
  (the 0.25 multiply is an arithmetic shift-right-by-2 — no multiplier
  hardware needed)
- **Loss:** Mean Squared Error (used conceptually; the RTL itself only
  needs the *derivative* of the loss w.r.t. output, i.e. `(y - d)`)
- **Learning algorithm:** full online backpropagation, one sample at a
  time, no mini-batches, no epochs — pure online SGD, exactly as
  specified.

---

## 3. Block Diagram

```
                         ┌─────────────────────────────────────────────┐
  SW[15] mode ─────────► │                                             │
  SW[14] LR sel ───────► │              control_fsm                    │
  BTN0 (start) ───►[deb]►│   (IDLE..LOAD_INPUT..FORWARD_L1..ACT_L1..   │
  BTN1 (reset) ───►[deb]►│    FORWARD_L2..ACT_L2..OUTPUT_ERROR..       │
  BTN2 (reinit) ──►[deb]►│    HIDDEN_ERROR..GRADIENT..WEIGHT_UPDATE..  │
                         │    DONE)                                    │
                         └──────┬──────────────┬──────────────┬────────┘
                                │ load/start   │ act1/act2 en │ start_*
                                ▼              ▼              ▼
  SW[7:0]  x ──►┌────────────┐  │       ┌───────────────┐  ┌─────────────────┐
  SW[9:8]  d ──►│input_buffer│  │       │activation_unit│  │ backprop_engine │
                └─────┬──────┘  │       │ (x4 ReLU,     │  │ ┌─────────────┐ │
                      │         │       │  x2 sigmoid)  │  │ │ error_unit  │ │
                      ▼         ▼       └───────┬───────┘  │ └─────────────┘ │
                 ┌─────────────────┐            │          │ ┌─────────────┐ │
                 │ forward_engine  │◄───────────┘          │ │gradient_unit│ │
                 │ (shared         │  hidden_act/y         │ └─────────────┘ │
                 │  fixed_mac)     │─────────────────────► │ ┌─────────────┐ │
                 └────────┬────────┘                       │ │weight_update│ │
                          │ rd A                           │ │_unit        │ │
                          ▼                                │ └─────┬───────┘ │
                 ┌─────────────────┐   rd B / write   ◄────┘       │         │
                 │  weight_memory  │◄──────────────────────────────┘         │
                 │  (W1 4x8, W2    │                                         │
                 │   2x4, dual     │        ┌──────────────┐                 │
                 │   read port)    │        │ bias_memory  │◄────────────────┘
                 └─────────────────┘        │(Bias1, Bias2)│
                                            └──────────────┘
                                                     │
                         ┌───────────────────────────┘
                         ▼
                 ┌─────────────────┐
                 │ output_decoder  │──► LED[15:0]
                 └─────────────────┘
```

---

## 4. State Transition Diagram (`control_fsm`)

```
        ┌──────┐  start_pulse
        │ IDLE │─────────────────┐
        └──┬───┘                 │
           ▲                     ▼
           │              ┌─────────────┐
           │              │ LOAD_INPUT  │  (latch SW[7:0]/SW[9:8])
           │              └──────┬──────┘
           │                     ▼
           │              ┌─────────────────┐
           │              │ FORWARD_LAYER1  │  (8x MAC per hidden neuron,
           │              └──────┬──────────┘   x4 neurons, shared MAC)
           │                     ▼
           │              ┌─────────────┐
           │              │  ACT_LAYER1 │  (ReLU x4, register hidden_act)
           │              └──────┬──────┘
           │                     ▼
           │              ┌─────────────────┐
           │              │ FORWARD_LAYER2  │  (4x MAC per output neuron,
           │              └──────┬──────────┘   x2 neurons, shared MAC)
           │                     ▼
           │              ┌─────────────┐
           │              │  ACT_LAYER2 │  (hard-sigmoid x2, register y)
           │              └──────┬──────┘
           │           inference │  training (SW[15])
           │        ┌────────────┴───────────┐
           │        ▼                        ▼
           │  ┌──────────┐           ┌───────────────┐
           │  │   DONE   │◄──┐       │ OUTPUT_ERROR  │  (delta_out = (y-d)*0.25)
           │  └────┬─────┘   │       └───────┬───────┘
           │       │         │               ▼
           └───────┘         │       ┌───────────────┐
                             │       │ HIDDEN_ERROR  │  (delta_hid = ΣW2·delta_out
                             │       └───────┬───────┘   masked by ReLU')
                             │               ▼
                             │       ┌───────────────┐
                             │       │   GRADIENT    │  (1-cycle bubble;
                             │       └───────┬───────┘   grad = delta*act,
                             │               ▼            done just-in-time)
                             │       ┌───────────────┐
                             └───────│ WEIGHT_UPDATE │  (46 sequential
                                     └───────────────┘   w/b updates,
                                                           w -= lr*grad)
```

---

## 5. Switch / Button / LED Map

| Signal    | Function                                            |
|-----------|------------------------------------------------------|
| SW[7:0]   | Input vector x0..x7 (each switch: 0 → 0.0, 1 → 1.0)   |
| SW[9:8]   | Labels d0,d1 (training target, same 0.0/1.0 mapping)  |
| SW[14]    | Learning rate: 0 = LR1 (1/16), 1 = LR2 (1/64)          |
| SW[15]    | Mode: 0 = inference, 1 = training                     |
| BTN0      | Start (begins one forward pass / training step)       |
| BTN1      | Synchronous reset (restores deterministic weights)     |
| BTN2      | Reinitialize weights only (does not touch FSM state)   |
| BTN3      | Reserved, unused                                       |
| LED[1:0]  | Predicted class (one-hot: which of y0/y1 is larger)    |
| LED[2]    | Training active                                        |
| LED[3]    | Inference active                                       |
| LED[4]    | Done                                                    |
| LED[5]    | Overflow/error (sticky until next start)                |
| LED[6]    | Weight-update active                                    |
| LED[7]    | Forward-pass active                                      |
| LED[11:8] | Debug: current FSM state (0=IDLE .. 10=DONE)             |
| LED[15:12]| Reserved                                                 |

**Design note on switch-driven inputs:** since the only stimulus device
is a set of on/off switches, each input/label bit is mapped to a binary
Q4.12 sample (1.0 or 0.0). This gives a fully digital, deterministic,
repeatable input set — enough to demonstrate online learning on
binary-pattern problems (e.g. AND/OR/XOR-style tasks) without an ADC or
host MCU. If richer analog stimulus is later required, replace
`input_buffer.v` with a version driven by an ADC or a small ROM-based
pattern sequencer; nothing else in the design needs to change.

---

## 6. Module Hierarchy

```
top_mlp_engine
├── clock_enable_generator      (debounce tick generator)
├── debouncer            (x3: BTN0, BTN1, BTN2)
├── edge_detector         (x2: start pulse, reinit pulse)
├── control_fsm                 (master FSM, 11 states)
├── input_buffer                (switch → Q4.12 latching)
├── weight_memory                (W1 4x8, W2 2x4, dual read port)
├── bias_memory                  (Bias1 4, Bias2 2)
├── forward_engine
│   └── fixed_mac
│   └── fixed_adder
├── activation_unit (x6: 4 ReLU + 2 hard-sigmoid, via generate)
├── backprop_engine
│   ├── error_unit
│   │   └── fixed_mac
│   │   └── fixed_adder
│   └── weight_update_unit
│       ├── gradient_unit
│       │   └── fixed_multiplier
│       └── fixed_adder
└── output_decoder               (LED mapping)
```

`fixed_multiplier`, `fixed_adder`, and `fixed_mac` are the shared
fixed-point primitives, reused throughout rather than re-implemented
per module (per spec: "reuse MAC hardware where practical").

---

## 7. Parameters

| Parameter    | Default | Description                          |
|--------------|---------|----------------------------------------|
| DATA_WIDTH   | 16      | Fixed-point word width                 |
| FRAC_BITS    | 12      | Fractional bits (Q4.12)                |
| INPUTS       | 8       | Input layer width                      |
| HIDDEN       | 4       | Hidden layer width                     |
| OUTPUTS      | 2       | Output layer width                     |
| CLK_FREQ_HZ  | 100e6   | System clock frequency (for debounce)  |

All are set at `top_mlp_engine`'s parameter list and propagate down
through every sub-module.

---

## 8. Resource Estimation (XC7S50CSGA324-1, rough order-of-magnitude)

The design uses **register-array storage** (not BRAM) for weights/
biases and a **single shared `fixed_mac`** per forward/backprop phase,
so LUT/FF usage is modest and DSP usage is minimal (Vivado will infer
DSP48E1 slices for the 16x16 multiplies inside `fixed_multiplier` /
`fixed_mac`).

| Resource         | Estimate | Notes                                       |
|-------------------|----------|---------------------------------------------|
| LUTs              | ~1,200–1,800 | control logic, muxes, saturation logic |
| Flip-Flops        | ~900–1,300  | 46 weights/biases × 16b + FSM + pipeline regs |
| DSP48E1 slices    | 2–4      | one per active `fixed_mac`/`fixed_multiplier` instance (2 MACs total: forward + backprop, plus the gradient multiplier) |
| BRAM              | 0        | all storage is distributed registers (small array sizes) |
| Max Fmax (typical Spartan-7 -1 speed grade) | 150–200 MHz | dominated by the fixed_mac multiply-accumulate + saturation compare chain |

XC7S50 has 32,600 LUTs / 65,200 FFs / 120 DSP48E1 slices / 2,700 Kb
BRAM, so this design uses well under 10% of the fabric — plenty of
headroom to scale INPUTS/HIDDEN/OUTPUTS up significantly if desired.

---

## 9. Timing Estimate

Per training sample (worst case, training mode):

| Phase            | Cycles (approx.)                         |
|-------------------|-------------------------------------------|
| LOAD_INPUT        | 1                                          |
| FORWARD_LAYER1     | HIDDEN × (INPUTS+2) ≈ 4×10 = 40           |
| ACT_LAYER1         | 1                                          |
| FORWARD_LAYER2     | OUTPUTS × (HIDDEN+2) ≈ 2×6 = 12           |
| ACT_LAYER2         | 1                                          |
| OUTPUT_ERROR       | OUTPUTS × 2 ≈ 4                            |
| HIDDEN_ERROR       | HIDDEN × (OUTPUTS+2) ≈ 4×4 = 16           |
| GRADIENT           | 1                                           |
| WEIGHT_UPDATE      | 46 weights/biases × 4 cycles ≈ 184        |
| **Total**          | **~260 clock cycles**                      |

At 100 MHz this is ~2.6 µs per online training step (inference-only
runs skip the last 5 phases: ~55 cycles ≈ 0.55 µs). Simulation in the
included testbench confirms the pipeline completes and produces sane,
converging results.

---

## 10. Vivado Synthesis Instructions

1. Create a new RTL project targeting `xc7s50csga324-1`.
2. Add all files in `rtl/` as design sources; set `top_mlp_engine` as
   the top module.
3. Add `tb/tb_top_mlp_engine.v` as a simulation-only source (or run it
   separately with Icarus Verilog / XSIM) — **do not** add it to the
   synthesis fileset.
4. Create an XDC constraints file mapping:
   - `clk` to the board's 100 MHz oscillator pin, with a
     `create_clock -period 10.000` constraint.
   - `btn0_start_raw`, `btn1_reset_raw`, `btn2_reinit_raw`, `btn3_raw`
     to the four onboard push buttons.
   - `sw[15:0]` to the 16 onboard switches.
   - `led[15:0]` to the 16 onboard LEDs.
5. Run Synthesis → Implementation → Generate Bitstream as usual.
6. Program the board, then:
   - Set SW[15]=0 (inference) or 1 (training), SW[14] for learning
     rate, SW[9:8] for label, SW[7:0] for input pattern.
   - Press BTN0 to start a pass; LED[4] lights when done.
   - Press BTN2 at any time to reload deterministic initial weights
     without a full reset.
   - Press BTN1 for a full synchronous reset.

---

## 11. Verification Summary

The included testbench (`tb/tb_top_mlp_engine.v`) is self-checking and
verifies:

1. Weights initialize to small deterministic nonzero values.
2. A full inference pass completes and produces a numeric result.
3. Repeated online-training steps on a fixed sample **monotonically
   reduce MSE** (verified: MSE fell from 0.2544 to 0.2293 over 12
   epochs with LR1 in the reference run).
4. Weights are actually modified by training (not just deltas computed
   and discarded).
5. BTN2 reinit restores the original deterministic weights.

Run it yourself:
```
iverilog -g2001 -o sim.vvp tb/tb_top_mlp_engine.v -y rtl
vvp sim.vvp
```

---

## 12. Known Simplifications / Notes for Further Hardening

These are documented deliberately so they're easy to revisit in
simulation before tape-out to real hardware:

- **Sigmoid derivative** in `error_unit.v` is approximated as a
  constant 0.25 (the slope of the hard-sigmoid's linear region) rather
  than a piecewise derivative that goes to zero in saturation. This
  keeps the backprop engine multiplier-free for that step; swap in a
  piecewise-select if you need the exact hard-sigmoid derivative.
- **Switch-driven inputs are binary** (0.0/1.0 per switch), not
  arbitrary Q4.12 samples — see §5 for the rationale and how to extend
  it.
- **Two independent read ports** on `weight_memory` (for forward vs.
  backprop) and a **single muxed read/write port** on `bias_memory`
  assume forward and backprop phases never overlap in time, which the
  `control_fsm` guarantees by construction.
- **Overflow (LED5)** aggregates saturation events from the forward
  engine's MAC/bias-add and the weight-update engine's gradient
  multiply/subtract; it's sticky per run and clears when a new run
  starts.
# SensiNerveX_FPGA
