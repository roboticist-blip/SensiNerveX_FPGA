# Operating Manual — Online-Learning MLP Engine (Boolean Black Board)

This is a step-by-step guide for operating the `top_mlp_engine` design
**after** it has been synthesized, implemented, and flashed onto the
Boolean Black Board (XC7S50CSGA324-1). No PC connection, terminal, or
host software is needed at runtime — everything is controlled with the
onboard switches, push buttons, and LEDs.

---

## 1. Before You Start

- Confirm the bitstream has been programmed successfully (Vivado
  Hardware Manager shows "Programming Successful", or the board's
  DONE/programming LED is lit, per your board's normal indication).
- All 16 switches and all 4 push buttons are active on this design —
  there is no separate "enable" jumper.
- The board's 100 MHz onboard oscillator drives the design directly;
  no external clock source is required.

**First power-up / first use:** press and release **BTN1 (Reset)**
once before doing anything else. This guarantees the weight and bias
memories are loaded with their deterministic initial values, even
though a power-on reset also runs automatically for the first ~16
clock cycles after configuration.

---

## 2. Switch Map (SW[15:0])

| Switch(es) | Name           | Meaning                                                              |
|------------|----------------|-----------------------------------------------------------------------|
| SW[7:0]    | Input vector   | x0..x7 — one bit per input neuron. **OFF = 0.0, ON = 1.0** (Q4.12)    |
| SW[9:8]    | Labels         | d0, d1 — target output values for **training mode only**. Same OFF=0.0 / ON=1.0 mapping |
| SW[13:10]  | Unused         | Leave in any position; they have no effect                            |
| SW[14]     | Learning rate  | **OFF = LR1 (1/16)** — faster, coarser updates. **ON = LR2 (1/64)** — slower, finer updates |
| SW[15]     | Mode           | **OFF = Inference** (forward pass only, no weight changes). **ON = Training** (full forward + backprop, weights updated) |

> Because the only input device is a bank of switches, each input and
> label is a binary sample (0.0 or 1.0), not an arbitrary analog
> value. This is enough to demonstrate real online learning on
> binary-pattern problems (e.g. AND/OR/XOR-style 8-bit patterns).

---

## 3. Button Map

| Button | Name            | Behavior                                                                 |
|--------|-----------------|----------------------------------------------------------------------------|
| BTN0   | Start           | Press and release to begin **one** forward pass (inference mode) or **one** full training step (training mode), using the current switch settings. This is a one-shot trigger — each press runs exactly one sample. |
| BTN1   | Reset           | Synchronous system reset. Restores deterministic initial weights/biases and returns the FSM to IDLE. Hold briefly (a clean press/release is enough — the debouncer takes care of contact bounce). |
| BTN2   | Reinitialize    | Reloads the deterministic initial weights and biases **without** a full system reset — useful for restarting a training run from scratch mid-session without disturbing anything else. |
| BTN3   | Reserved        | No function in this build. Safe to leave alone.                            |

**Important:** don't press BTN0 again while a run is already in
progress (LED[7] or LED[6] lit — see below). The design ignores extra
button presses while busy, but for clean operation always wait for
LED[4] (Done) before starting the next sample.

---

## 4. LED Map (status output)

| LED       | Name              | Meaning                                                                 |
|-----------|-------------------|----------------------------------------------------------------------------|
| LED[1:0]  | Predicted class   | One-hot indicator of which output neuron scored higher: `01` = class 0 (y0 > y1), `10` = class 1 (y1 > y0) |
| LED[2]    | Training active   | Lit for the entire duration of a training run                             |
| LED[3]    | Inference active  | Lit for the entire duration of an inference-only run                      |
| LED[4]    | Done              | Pulses on for one cycle when the current run finishes — on real hardware this reads as a brief flash; watch for it after pressing BTN0 |
| LED[5]    | Overflow / error  | Lit if any internal fixed-point computation saturated during the run. Sticky — stays lit until the next BTN0 press. Occasional overflow during early training with LR1 and large inputs is expected and not harmful; it just means a value was clamped to the representable range. |
| LED[6]    | Weight-update active | Lit only during the WEIGHT_UPDATE phase of a training run                |
| LED[7]    | Forward-pass active  | Lit during the forward computation (both layers) of any run              |
| LED[11:8] | FSM state (debug) | 4-bit binary code of the current internal state — see table below         |
| LED[15:12]| Reserved          | Always 0                                                                    |

### FSM state codes (LED[11:8])

| Code | State           | Code | State           |
|------|------------------|------|------------------|
| 0    | IDLE             | 6    | OUTPUT_ERROR     |
| 1    | LOAD_INPUT       | 7    | HIDDEN_ERROR     |
| 2    | FORWARD_LAYER1   | 8    | GRADIENT         |
| 3    | ACT_LAYER1       | 9    | WEIGHT_UPDATE    |
| 4    | FORWARD_LAYER2   | 10   | DONE             |
| 5    | ACT_LAYER2       |      |                  |

This is mainly useful if you're probing the board with a logic
analyzer or just want to visually confirm the pipeline is progressing
through each phase (you'll see LED[11:8] count up quickly, then reset
to 0000 once DONE fires and the FSM returns to IDLE).

---

## 5. Running a Single Inference

1. Set **SW[15] = OFF** (inference mode).
2. Set **SW[7:0]** to the input pattern you want to classify (each
   switch ON = 1.0, OFF = 0.0 for that input).
3. SW[9:8] (labels) are ignored in inference mode — leave them in any
   position.
4. Press and release **BTN0**.
5. LED[3] (Inference active) and LED[7] (Forward-pass active) will
   light briefly as the pipeline runs.
6. Watch for **LED[4] (Done)** to flash — the run is complete
   (typically under 1 µs, so on real hardware this happens almost
   instantly after the button press; the LED flash is very brief but
   visible).
7. Read the result from **LED[1:0]**:
   - `01` → the network predicts class 0
   - `10` → the network predicts class 1
8. Repeat from step 2 for a new input pattern.

---

## 6. Running One Online-Training Step

1. Set **SW[15] = ON** (training mode).
2. Set **SW[14]** to your desired learning rate (OFF = LR1/faster,
   ON = LR2/finer).
3. Set **SW[7:0]** to the input pattern for this training sample.
4. Set **SW[9:8]** to the desired/target label for this sample
   (e.g. `01` if you want the network to learn "this input → class 0").
5. Press and release **BTN0**.
6. LED[2] (Training active) lights for the whole run; LED[7]
   (Forward-pass active) lights during the forward pass, then LED[6]
   (Weight-update active) lights during the backprop/update phase.
7. Wait for **LED[4] (Done)** to flash — the weights and biases have
   now been updated based on this one sample (pure online SGD, no
   batching).
8. To continue training, repeat from step 3 with the next sample
   (same pattern, if you're reinforcing one association, or a
   different pattern for the next training example).

**Tip — watching learning happen:** repeatedly train on the *same*
input/label pair (same SW[7:0]/SW[9:8], SW[15]=ON) and periodically
switch to SW[15]=OFF to run inference on that same pattern. You should
see LED[1:0] converge toward the target class as more training steps
accumulate, and the predicted-class LEDs stabilize once the network
has "learned" that pattern.

---

## 7. Typical Session Walkthrough

Example: teach the network that input pattern `1111_1111` should map
to class 0, and pattern `0000_0000` should map to class 1.

1. Press **BTN1** (fresh start, deterministic weights loaded).
2. Set SW[15]=ON (training), SW[14]=OFF (LR1), SW[7:0]=`11111111`,
   SW[9:8]=`01`. Press BTN0, wait for LED[4].
3. Set SW[7:0]=`00000000`, SW[9:8]=`10` (keep training mode). Press
   BTN0, wait for LED[4].
4. Repeat steps 2–3 alternately, 10–20 times each, to reinforce both
   associations.
5. Switch to inference: SW[15]=OFF, SW[7:0]=`11111111`. Press BTN0.
   Check LED[1:0] — after enough training it should read `01`.
6. Switch SW[7:0]=`00000000` (still inference). Press BTN0. Check
   LED[1:0] — it should read `10`.
7. If the predictions haven't separated cleanly yet, go back to step
   2 and continue alternating training steps — this is expected online
   SGD behavior; convergence speed depends on the learning rate chosen
   and how many training steps you run.

---

## 8. Restarting / Recovering

| Situation | What to do |
|-----------|------------|
| Want a completely fresh start (weights + FSM state) | Press **BTN1** |
| Want to reset only the weights/biases mid-session (keep going without a full reset) | Press **BTN2** |
| LED[5] (Overflow) stays lit and results look wrong | Press **BTN1** to reset, then retrain with SW[14]=ON (the smaller LR2 learning rate) to reduce the chance of saturation on aggressive updates |
| Board seems unresponsive to BTN0 | Check LED[11:8] — if it's stuck on a nonzero code, the FSM may be waiting on something unexpected; press BTN1 to force a clean reset |
| Nothing happens at all after programming | Re-check that the bitstream programmed successfully and that the board's oscillator/clock pin constraint in your XDC matches the actual clock source |

---

## 9. Quick Reference Card

```
 SWITCHES                          BUTTONS
 SW[7:0]  = input pattern          BTN0 = start one run
 SW[9:8]  = label (training only)  BTN1 = full reset
 SW[14]   = 0:LR1(1/16) 1:LR2(1/64) BTN2 = reinit weights only
 SW[15]   = 0:inference 1:training  BTN3 = unused

 LEDS
 LED[1:0]   = predicted class (01 / 10)
 LED[2]     = training active     LED[6] = weight-update active
 LED[3]     = inference active    LED[7] = forward-pass active
 LED[4]     = done (flash)        LED[5] = overflow (sticky)
 LED[11:8]  = FSM state (debug)
```

---

## 10. Limitations to Keep in Mind While Operating

- Inputs and labels are **binary only** (each switch is 0.0 or 1.0) —
  this is a hardware I/O constraint of using switches as the only
  input device, not a limitation of the learning algorithm itself.
- Each BTN0 press trains on exactly **one sample** — there is no
  batching, no automatic multi-sample training loop, and no epoch
  counter visible on the LEDs. Repeated presses are how you run
  multiple "epochs" on hand-selected patterns.
- LED[4] (Done) is a single-cycle pulse. On real hardware at 100 MHz
  it will appear as a very brief flash rather than a steady light —
  if you're not sure whether a run finished, just check LED[2]/LED[3]
  (active flags) have gone low, which confirms the run has completed.
