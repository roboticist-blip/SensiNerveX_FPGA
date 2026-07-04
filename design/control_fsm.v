`timescale 1ns / 1ps
// control_fsm.v - Master FSM coordinating forward/backprop pipeline
module control_fsm (
    input  wire clk,
    input  wire rst,

    input  wire start_pulse,      // BTN0 edge-detected
    input  wire train_mode,       // SW[15]: 0 = inference, 1 = training

    input  wire fwd_done_l1,
    input  wire fwd_done_l2,
    input  wire bp_done_out_err,
    input  wire bp_done_hid_err,
    input  wire bp_done_wupd,

    output reg load_input,
    output reg start_l1,
    output reg act1_en,
    output reg start_l2,
    output reg act2_en,
    output reg start_out_err,
    output reg start_hid_err,
    output reg start_wupd,

    output reg training_active,
    output reg inference_active,
    output reg fwd_pass_active,
    output reg wupd_active,
    output reg done_flag,

    output reg [3:0] state_out
);

    localparam S_IDLE          = 4'd0,
               S_LOAD_INPUT    = 4'd1,
               S_FORWARD_L1    = 4'd2,
               S_ACT_L1        = 4'd3,
               S_FORWARD_L2    = 4'd4,
               S_ACT_L2        = 4'd5,
               S_OUTPUT_ERROR  = 4'd6,
               S_HIDDEN_ERROR  = 4'd7,
               S_GRADIENT      = 4'd8,
               S_WEIGHT_UPDATE = 4'd9,
               S_DONE          = 4'd10;

    reg [3:0] state;

    always @(posedge clk) begin
        if (rst) begin
            state            <= S_IDLE;
            load_input       <= 1'b0;
            start_l1         <= 1'b0;
            act1_en          <= 1'b0;
            start_l2         <= 1'b0;
            act2_en          <= 1'b0;
            start_out_err    <= 1'b0;
            start_hid_err    <= 1'b0;
            start_wupd       <= 1'b0;
            training_active  <= 1'b0;
            inference_active <= 1'b0;
            fwd_pass_active  <= 1'b0;
            wupd_active      <= 1'b0;
            done_flag        <= 1'b0;
        end else begin
            load_input    <= 1'b0;
            start_l1      <= 1'b0;
            act1_en       <= 1'b0;
            start_l2      <= 1'b0;
            act2_en       <= 1'b0;
            start_out_err <= 1'b0;
            start_hid_err <= 1'b0;
            start_wupd    <= 1'b0;
            done_flag     <= 1'b0;

            case (state)
                S_IDLE: begin
                    training_active  <= 1'b0;
                    inference_active <= 1'b0;
                    fwd_pass_active  <= 1'b0;
                    wupd_active      <= 1'b0;
                    if (start_pulse) begin
                        training_active  <= train_mode;
                        inference_active <= ~train_mode;
                        load_input       <= 1'b1;
                        state            <= S_LOAD_INPUT;
                    end
                end

                S_LOAD_INPUT: begin
                    fwd_pass_active <= 1'b1;
                    start_l1        <= 1'b1;
                    state           <= S_FORWARD_L1;
                end

                S_FORWARD_L1: begin
                    if (fwd_done_l1)
                        state <= S_ACT_L1;
                end

                S_ACT_L1: begin
                    act1_en  <= 1'b1;
                    start_l2 <= 1'b1;
                    state    <= S_FORWARD_L2;
                end

                S_FORWARD_L2: begin
                    if (fwd_done_l2) begin
                        fwd_pass_active <= 1'b0;
                        state           <= S_ACT_L2;
                    end
                end

                S_ACT_L2: begin
                    act2_en <= 1'b1;
                    if (training_active)
                        state <= S_OUTPUT_ERROR;
                    else
                        state <= S_DONE;
                end

                S_OUTPUT_ERROR: begin
                    start_out_err <= 1'b1;
                    if (bp_done_out_err)
                        state <= S_HIDDEN_ERROR;
                end

                S_HIDDEN_ERROR: begin
                    start_hid_err <= 1'b1;
                    if (bp_done_hid_err)
                        state <= S_GRADIENT;
                end

                S_GRADIENT: begin
                    state <= S_WEIGHT_UPDATE;
                end

                S_WEIGHT_UPDATE: begin
                    wupd_active <= 1'b1;
                    start_wupd  <= 1'b1;
                    if (bp_done_wupd) begin
                        wupd_active <= 1'b0;
                        state       <= S_DONE;
                    end
                end

                S_DONE: begin
                    done_flag <= 1'b1;
                    state     <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    always @(*) state_out = state;

endmodule
