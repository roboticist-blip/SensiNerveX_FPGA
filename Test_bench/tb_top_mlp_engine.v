// tb_top_mlp_engine.v - Self-checking testbench for top_mlp_engine
`timescale 1ns / 1ps

module tb_top_mlp_engine;

    localparam DATA_WIDTH = 16;
    localparam FRAC_BITS  = 12;
    localparam CLK_PERIOD = 10; // 100 MHz

    reg clk;
    reg btn0_start_raw, btn1_reset_raw, btn2_reinit_raw, btn3_raw;
    reg [15:0] sw;
    wire [15:0] led;

    integer i;
    integer epoch;
    integer sample_idx;
    integer ones;
    integer rnd;
    localparam integer NUM_TRAIN_STEPS = 2000;
    localparam integer NUM_INFER_SAMPLES = 50;

    integer train_pattern   [0:NUM_TRAIN_STEPS-1];
    integer train_label     [0:NUM_TRAIN_STEPS-1];
    real    train_y0        [0:NUM_TRAIN_STEPS-1];
    real    train_y1        [0:NUM_TRAIN_STEPS-1];
    real    train_mse       [0:NUM_TRAIN_STEPS-1];

    integer infer_pattern   [0:NUM_INFER_SAMPLES-1];
    integer infer_label     [0:NUM_INFER_SAMPLES-1];
    integer infer_predicted [0:NUM_INFER_SAMPLES-1];
    real    infer_y0        [0:NUM_INFER_SAMPLES-1];
    real    infer_y1        [0:NUM_INFER_SAMPLES-1];

    real    mse_first, mse_last;
    real    y0_real, y1_real;

    top_mlp_engine #(
        .DATA_WIDTH(DATA_WIDTH), .FRAC_BITS(FRAC_BITS),
        .CLK_FREQ_HZ(100_000_000)
    ) dut (
        .clk(clk),
        .btn0_start_raw (btn0_start_raw),
        .btn1_reset_raw (btn1_reset_raw),
        .btn2_reinit_raw(btn2_reinit_raw),
        .btn3_raw       (btn3_raw),
        .sw(sw),
        .led(led)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;
    initial begin
        $dumpfile("sim.vcd");
        $dumpvars(0, tb_top_mlp_engine);
    end

    // Convert a Q4.12 hex readout on LED-visible internal signals is not
    // directly observable from the top-level LED bus (LEDs only show the 1-bit predicted class + status). For verification purposes this
    // testbench also taps the DUT's internal y_reg via hierarchical reference, which is acceptable in simulation-only testbenches.
    function real q412_to_real;
        input signed [DATA_WIDTH-1:0] val;
        begin
            q412_to_real = $itor(val) / (1 <<< FRAC_BITS);
        end
    endfunction

    // Since the debouncer requires several tick_en pulses (~1 kHz derived from a 100 MHz clock) to register a button press, we speed up BTN detection for simulation by directly forcing the debounced signals' 
    // upstream raw inputs to be held long enough. At 100 MHz, one 1 kHz tick = 100,000 clk cycles; to keep simulation time reasonable we instead force the internal debounced signals directly via hierarchical access, 
    // bypassing the analog debounce timing (this is standard practice for verifying the digital core without waiting out the debounce filter in RTL simulation).
    task press_start;
        begin
            force dut.u_db0.clean_out = 1'b1;
            @(posedge clk);
            @(posedge clk);
            force dut.u_db0.clean_out = 1'b0;
            @(posedge clk);
            release dut.u_db0.clean_out;
        end
    endtask

    task press_reinit;
        begin
            force dut.u_db2.clean_out = 1'b1;
            @(posedge clk);
            @(posedge clk);
            force dut.u_db2.clean_out = 1'b0;
            @(posedge clk);
            release dut.u_db2.clean_out;
        end
    endtask

    task wait_done;
        begin
            wait (led[4] == 1'b1);
            @(posedge clk);
        end
    endtask

    task run_sample;
        input [7:0] pattern;
        input [1:0] label;
        input       train; // 1 = training mode, 0 = inference
        begin
            sw[7:0]  = pattern;
            sw[9:8]  = label;
            sw[14]   = 1'b0;
            sw[15]   = train;
            @(posedge clk);
            press_start;
            wait_done;
        end
    endtask

    real err0, err1, mse;

    initial begin
        $display(" top_mlp_engine self-checking testbench");
        $display("---------------------------------------");


        btn0_start_raw  = 1'b0;
        btn1_reset_raw  = 1'b1;
        btn2_reinit_raw = 1'b0;
        btn3_raw        = 1'b0;
        sw              = 16'h0000;

        repeat (10) @(posedge clk);
        btn1_reset_raw = 1'b0;
        repeat (30) @(posedge clk);
        if (dut.u_wmem.W1[0][0] === 16'sh0000) begin
            $display("FAIL: W1[0][0] initialized to zero (spec requires nonzero init)");
            $finish;
        end else begin
            $display("PASS: weights initialized to nonzero deterministic values");
        end

        $display(" %0d training steps", NUM_TRAIN_STEPS);
        $display("------------------------------------");

        for (epoch = 0; epoch < NUM_TRAIN_STEPS; epoch = epoch + 1) begin
            // Deterministic unique training dataset
            train_pattern[epoch] = ((epoch * 37 + 91) ^ (epoch << 3) ^ (epoch >> 2)) & 8'hFF;

            ones = train_pattern[epoch][0] + train_pattern[epoch][1] +
                   train_pattern[epoch][2] + train_pattern[epoch][3] +
                   train_pattern[epoch][4] + train_pattern[epoch][5] +
                   train_pattern[epoch][6] + train_pattern[epoch][7];

            if (ones >= 4)
                train_label[epoch] = 2'b01;
            else
                train_label[epoch] = 2'b10;

            run_sample(train_pattern[epoch][7:0], train_label[epoch][1:0], 1'b1);
            y0_real = q412_to_real(dut.y_reg[0 +: DATA_WIDTH]);
            y1_real = q412_to_real(dut.y_reg[DATA_WIDTH +: DATA_WIDTH]);
            err0 = y0_real - ((train_label[epoch][0]) ? 1.0 : 0.0);
            err1 = y1_real - ((train_label[epoch][1]) ? 1.0 : 0.0);
            mse  = (err0*err0 + err1*err1) / 2.0;

            train_y0[epoch]  = y0_real;
            train_y1[epoch]  = y1_real;
            train_mse[epoch] = mse;

            if (epoch == 0) mse_first = mse;
            mse_last = mse;

            if ((epoch % 50) == 0)
                $display("Step %0d/%0d Pattern=%b Label=%b MSE=%f", epoch, NUM_TRAIN_STEPS, train_pattern[epoch][7:0], train_label[epoch][1:0], mse);
        end

        $display("-------------------------------------------------------");
        $display(" Training results");
        $display(" First MSE: %f", mse_first);
        $display(" Last  MSE: %f", mse_last);
        if (mse_last < mse_first)
            $display(" Training improved the loss.");
        else
            $display(" Training did not reduce the loss.");
        $display("-------------------------------------------------------");
        /* Full training log suppressed. Progress printed every 50 samples.\n        for (epoch = 0; epoch < NUM_TRAIN_STEPS; epoch = epoch + 1) begin\n            $display("train %0d: pattern=%b label=%b y0=%f y1=%f mse=%f",
                     epoch,
                     train_pattern[epoch][7:0],
                     train_label[epoch][1:0],
                     train_y0[epoch],
                     train_y1[epoch],
                     train_mse[epoch]);
        end
        */

        if (dut.u_wmem.W1[0][0] !== 16'sh0400) begin
            $display("PASS: W1[0][0] updated by online training (no longer initial value)");
        end else begin
            $display("FAIL: W1[0][0] unchanged after training");
        end

        press_reinit;
        repeat (2) @(posedge clk);
        if (dut.u_wmem.W1[0][0] === 16'sh0400) begin
            $display("PASS: BTN2 reinit restored deterministic initial weights");
        end else begin
            $display("FAIL: reinit did not restore initial weights");
        end

        for (sample_idx = 0; sample_idx < NUM_INFER_SAMPLES; sample_idx = sample_idx + 1) begin
            infer_pattern[sample_idx]   = sample_idx[7:0];
            infer_label[sample_idx]     = sample_idx[1:0];
            run_sample(infer_pattern[sample_idx][7:0], infer_label[sample_idx][1:0], 1'b0);
            infer_y0[sample_idx]        = q412_to_real(dut.y_reg[0 +: DATA_WIDTH]);
            infer_y1[sample_idx]        = q412_to_real(dut.y_reg[DATA_WIDTH +: DATA_WIDTH]);
            infer_predicted[sample_idx]  = led[0] ? 1 : 0;
        end

        $display("-------------------------------------------------------");
        $display(" %0d inference samples completed", NUM_INFER_SAMPLES);
        $display("-------------------------------------------------------");
        for (sample_idx = 0; sample_idx < NUM_INFER_SAMPLES; sample_idx = sample_idx + 1) begin
            $display("infer %0d: pattern=%b label=%b y0=%f y1=%f predicted=%0d",
                     sample_idx,
                     infer_pattern[sample_idx][7:0],
                     infer_label[sample_idx][1:0],
                     infer_y0[sample_idx],
                     infer_y1[sample_idx],
                     infer_predicted[sample_idx]);
        end

        $display(" Testbench complete");
        $display("-------------------");
        $finish;
    end

    initial begin
        #200_000_000;
        $display("TIMEOUT: simulation exceeded time budget");
        $finish;
    end

endmodule
