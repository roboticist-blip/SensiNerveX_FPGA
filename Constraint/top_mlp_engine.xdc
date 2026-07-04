## =============================================================================
## top_mlp_engine.xdc
## -----------------------------------------------------------------------------
## Xilinx Design Constraints for the Online-Learning MLP Engine
## Target board : RealDigital / AMD University Program "Boolean" board
## Target device: Xilinx Spartan-7 XC7S50CSGA324-1
##
## Pin locations below are taken directly from the OFFICIAL Boolean-board
## master constraints file published by AMD/Xilinx University Program:
##   Repository : https://github.com/Xilinx/xup_fpga_vivado_flow
##   File       : source/boolean/lab1/lab1_spartan.xdc  (MIT License)
## They are NOT guessed or inferred -- every PACKAGE_PIN value here matches
## that authoritative source. If you are using a revision of the Boolean
## board with a different silkscreen/schematic, cross-check against your
## board's own schematic/master XDC before trusting these locations blindly.
##
## Port names below match top_mlp_engine's port list exactly:
##   clk, btn0_start_raw, btn1_reset_raw, btn2_reinit_raw, btn3_raw,
##   sw[15:0], led[15:0]
## =============================================================================

## -----------------------------------------------------------------------------
## Clock (100 MHz on-board oscillator)
## -----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33} [get_ports {clk}]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports {clk}]

## Bank 0 voltage / configuration (required by the Boolean board's power rails)
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## -----------------------------------------------------------------------------
## On-board Slide Switches -- sw[15:0]
##   sw[7:0]  = input vector x0..x7        (top_mlp_engine / input_buffer)
##   sw[9:8]  = training labels d0,d1
##   sw[13:10] = unused by this design
##   sw[14]   = learning-rate select (0 = LR1 1/16, 1 = LR2 1/64)
##   sw[15]   = mode select          (0 = inference, 1 = training)
## -----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN V2 IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {PACKAGE_PIN U2 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]
set_property -dict {PACKAGE_PIN U1 IOSTANDARD LVCMOS33} [get_ports {sw[2]}]
set_property -dict {PACKAGE_PIN T2 IOSTANDARD LVCMOS33} [get_ports {sw[3]}]
set_property -dict {PACKAGE_PIN T1 IOSTANDARD LVCMOS33} [get_ports {sw[4]}]
set_property -dict {PACKAGE_PIN R2 IOSTANDARD LVCMOS33} [get_ports {sw[5]}]
set_property -dict {PACKAGE_PIN R1 IOSTANDARD LVCMOS33} [get_ports {sw[6]}]
set_property -dict {PACKAGE_PIN P2 IOSTANDARD LVCMOS33} [get_ports {sw[7]}]
set_property -dict {PACKAGE_PIN P1 IOSTANDARD LVCMOS33} [get_ports {sw[8]}]
set_property -dict {PACKAGE_PIN N2 IOSTANDARD LVCMOS33} [get_ports {sw[9]}]
set_property -dict {PACKAGE_PIN N1 IOSTANDARD LVCMOS33} [get_ports {sw[10]}]
set_property -dict {PACKAGE_PIN M2 IOSTANDARD LVCMOS33} [get_ports {sw[11]}]
set_property -dict {PACKAGE_PIN M1 IOSTANDARD LVCMOS33} [get_ports {sw[12]}]
set_property -dict {PACKAGE_PIN L1 IOSTANDARD LVCMOS33} [get_ports {sw[13]}]
set_property -dict {PACKAGE_PIN K2 IOSTANDARD LVCMOS33} [get_ports {sw[14]}]
set_property -dict {PACKAGE_PIN K1 IOSTANDARD LVCMOS33} [get_ports {sw[15]}]

## -----------------------------------------------------------------------------
## On-board push-buttons -- mapped to top_mlp_engine's named button ports
##   BTN0 -> btn0_start_raw   (start one inference/training run)
##   BTN1 -> btn1_reset_raw   (full synchronous reset)
##   BTN2 -> btn2_reinit_raw  (weight/bias reinitialization only)
##   BTN3 -> btn3_raw         (reserved, unused by the design)
## Buttons are normally open: they read '0' when not pressed and '1' while
## actively pressed. They are debounced and edge-detected on-chip
## (see debouncer.v / edge_detector.v) -- no board-level debounce hardware.
## -----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS33} [get_ports {btn0_start_raw}]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports {btn1_reset_raw}]
set_property -dict {PACKAGE_PIN H2 IOSTANDARD LVCMOS33} [get_ports {btn2_reinit_raw}]
set_property -dict {PACKAGE_PIN J1 IOSTANDARD LVCMOS33} [get_ports {btn3_raw}]

## -----------------------------------------------------------------------------
## On-board discrete LEDs -- led[15:0]
##   led[1:0]   = predicted class (one-hot)
##   led[2]     = training active
##   led[3]     = inference active
##   led[4]     = done (single-cycle pulse)
##   led[5]     = overflow / error (sticky)
##   led[6]     = weight-update active
##   led[7]     = forward-pass active
##   led[11:8]  = FSM state (debug)
##   led[15:12] = reserved (always 0)
## All LED signals on this board are active-high.
## -----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN G1 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN F1 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN F2 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN E2 IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN E5 IOSTANDARD LVCMOS33} [get_ports {led[7]}]
set_property -dict {PACKAGE_PIN E6 IOSTANDARD LVCMOS33} [get_ports {led[8]}]
set_property -dict {PACKAGE_PIN C3 IOSTANDARD LVCMOS33} [get_ports {led[9]}]
set_property -dict {PACKAGE_PIN B2 IOSTANDARD LVCMOS33} [get_ports {led[10]}]
set_property -dict {PACKAGE_PIN A2 IOSTANDARD LVCMOS33} [get_ports {led[11]}]
set_property -dict {PACKAGE_PIN B3 IOSTANDARD LVCMOS33} [get_ports {led[12]}]
set_property -dict {PACKAGE_PIN A3 IOSTANDARD LVCMOS33} [get_ports {led[13]}]
set_property -dict {PACKAGE_PIN B4 IOSTANDARD LVCMOS33} [get_ports {led[14]}]
set_property -dict {PACKAGE_PIN A4 IOSTANDARD LVCMOS33} [get_ports {led[15]}]

## -----------------------------------------------------------------------------
## Timing exceptions for asynchronous human-interface inputs
## -----------------------------------------------------------------------------
## Switches and buttons are driven by mechanical/manual action and are not
## synchronous to sys_clk_pin. They are debounced and re-synchronized inside
## the design (clock_enable_generator.v + debouncer.v + edge_detector.v)
## before being used by any state machine, so no meaningful setup/hold
## relationship exists between these ports and the system clock at the pad.
## Declaring them as false paths prevents Vivado from trying (and failing)
## to time an inherently asynchronous, mechanically-driven input, and keeps
## the timing report focused on the paths that actually matter.
set_false_path -from [get_ports {sw[*]}]
set_false_path -from [get_ports {btn0_start_raw}]
set_false_path -from [get_ports {btn1_reset_raw}]
set_false_path -from [get_ports {btn2_reinit_raw}]
set_false_path -from [get_ports {btn3_raw}]

## LED outputs are simple status indicators with no downstream timing
## requirement beyond "eventually visible to a human"; exclude them from
## the primary timing analysis as well.
set_false_path -to [get_ports {led[*]}]

## -----------------------------------------------------------------------------
## Peripherals present on the Boolean board but NOT used by this design.
## Left commented out intentionally -- uncomment only if you extend
## top_mlp_engine to drive these signals (e.g. richer input via UART, or
## RGB status LEDs). Pin locations are from the same official master XDC.
## -----------------------------------------------------------------------------
# On-board color (RGB) LEDs
# set_property -dict {PACKAGE_PIN V6 IOSTANDARD LVCMOS33} [get_ports {RGB0[0]}]; # RGB0_R
# set_property -dict {PACKAGE_PIN V4 IOSTANDARD LVCMOS33} [get_ports {RGB0[1]}]; # RGB0_G
# set_property -dict {PACKAGE_PIN U6 IOSTANDARD LVCMOS33} [get_ports {RGB0[2]}]; # RGB0_B
# set_property -dict {PACKAGE_PIN U3 IOSTANDARD LVCMOS33} [get_ports {RGB1[0]}]; # RGB1_R
# set_property -dict {PACKAGE_PIN V3 IOSTANDARD LVCMOS33} [get_ports {RGB1[1]}]; # RGB1_G
# set_property -dict {PACKAGE_PIN V5 IOSTANDARD LVCMOS33} [get_ports {RGB1[2]}]; # RGB1_B

# On-board UART (USB-UART bridge)
# set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {UART_rxd}]
# set_property -dict {PACKAGE_PIN U11 IOSTANDARD LVCMOS33} [get_ports {UART_txd}]

# On-board Bluetooth Low Energy UART
# set_property -dict {PACKAGE_PIN G5 IOSTANDARD LVCMOS33} [get_ports {ble_uart_tx}]
# set_property -dict {PACKAGE_PIN F5 IOSTANDARD LVCMOS33} [get_ports {ble_uart_rx}]
# set_property -dict {PACKAGE_PIN H6 IOSTANDARD LVCMOS33} [get_ports {ble_uart_rts}]
# set_property -dict {PACKAGE_PIN G6 IOSTANDARD LVCMOS33} [get_ports {ble_uart_cts}]

# On-board servo connectors
# set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {servo0}]
# set_property -dict {PACKAGE_PIN M16 IOSTANDARD LVCMOS33} [get_ports {servo1}]
# set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {servo2}]
# set_property -dict {PACKAGE_PIN L16 IOSTANDARD LVCMOS33} [get_ports {servo3}]
