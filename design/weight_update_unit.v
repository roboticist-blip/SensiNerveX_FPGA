`timescale 1ns / 1ps
// weight_update_unit.v - Performs sequential weight and bias updates
//
// TIMING FIX: the arithmetic (index decode -> operand mux -> multiplier ->
// LR shift -> subtractor) used to be one unbroken combinational cloud that
// was only latched in S_WRITE, even though the FSM already spends 4 clocks
// per element. That crammed ~18 logic levels into a single 10 ns hop
// (100 MHz clock) and caused WNS = -4.838 ns / 103 failing setup endpoints,
// all landing on wr_data_reg / b_..._data_reg / overflow_flag_reg.
//
// Fix: register the intermediate results at each existing FSM state
// boundary so the same 4 cycles are actually used to pipeline the work
// instead of re-deriving everything combinationally right before the final
// write. No extra latency is introduced - it is the same 4-state sequence,
// now with real pipeline registers between the stages:
//   S_SET_ADDR  -> freeze operand selection (act_val_r/delta_val_r/...)
//   S_READ_WAIT -> run the multiply on registered operands, capture result
//   S_COMPUTE   -> latch memory read data + final scaled delta
//   S_WRITE     -> do only the (short) subtract and store
module weight_update_unit #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS  = 12,
    parameter INPUTS     = 8,
    parameter HIDDEN     = 4,
    parameter OUTPUTS    = 2
)(
    input  wire clk,
    input  wire rst,

    input  wire start,
    input  wire lr_sel,

    input  wire [DATA_WIDTH*INPUTS-1:0]  x_flat,
    input  wire [DATA_WIDTH*HIDDEN-1:0]  hidden_act_flat,
    input  wire [DATA_WIDTH*OUTPUTS-1:0] output_delta_flat,
    input  wire [DATA_WIDTH*HIDDEN-1:0]  hidden_delta_flat,


    output reg        rd_layer_sel,
    output reg  [2:0] rd_row,
    output reg  [2:0] rd_col,
    input  wire signed [DATA_WIDTH-1:0] rd_data,


    output reg        we,
    output reg         wr_layer_sel,
    output reg  [2:0]  wr_row,
    output reg  [2:0]  wr_col,
    output reg  signed [DATA_WIDTH-1:0] wr_data,


    output reg        b_we,
    output reg        b_layer_sel,
    output reg [2:0]  b_idx,
    output reg signed [DATA_WIDTH-1:0] b_wr_data,
    input  wire signed [DATA_WIDTH-1:0] b_rd_data,

    output reg busy,
    output reg done,
    output reg overflow_flag
);

    localparam S_IDLE       = 3'd0,
               S_SET_ADDR   = 3'd1,
               S_READ_WAIT  = 3'd2,
               S_COMPUTE    = 3'd3,
               S_WRITE      = 3'd4,
               S_NEXT       = 3'd5;

    localparam TOTAL_W = HIDDEN*INPUTS + OUTPUTS*HIDDEN;
    localparam TOTAL_B = HIDDEN + OUTPUTS;
    localparam TOTAL   = TOTAL_W + TOTAL_B;

    reg [2:0] state;
    reg [7:0] idx;

    wire is_weight = (idx < TOTAL_W);
    wire is_l1     = (idx < HIDDEN*INPUTS);
    wire is_bias   = (idx >= TOTAL_W);
    wire is_bias1  = is_bias && (idx < TOTAL_W + HIDDEN);


    wire [2:0] l1_row = idx / INPUTS;
    wire [2:0] l1_col = idx % INPUTS;
    wire [7:0] idx_l2 = idx - HIDDEN*INPUTS;
    wire [2:0] l2_row = idx_l2 / HIDDEN;
    wire [2:0] l2_col = idx_l2 % HIDDEN;

    wire [7:0] idx_b  = idx - TOTAL_W;
    wire [2:0] b1_idx = idx_b;
    wire [2:0] b2_idx = idx_b - HIDDEN;


    wire signed [DATA_WIDTH-1:0] act_val = is_l1 ? x_flat[l1_col*DATA_WIDTH +: DATA_WIDTH]
                                                   : hidden_act_flat[l2_col*DATA_WIDTH +: DATA_WIDTH];

    wire signed [DATA_WIDTH-1:0] delta_val = is_l1 ? hidden_delta_flat[l1_row*DATA_WIDTH +: DATA_WIDTH]
                                                     : output_delta_flat[l2_row*DATA_WIDTH +: DATA_WIDTH];
    wire signed [DATA_WIDTH-1:0] bias_delta_val = is_bias1 ? hidden_delta_flat[b1_idx*DATA_WIDTH +: DATA_WIDTH]
                                                              : output_delta_flat[b2_idx*DATA_WIDTH +: DATA_WIDTH];

    wire [2:0] lr_shift = lr_sel ? 3'd6 : 3'd4;

    reg signed [DATA_WIDTH-1:0] act_val_r, delta_val_r, bias_delta_val_r;
    reg                         is_weight_r1;

    reg signed [DATA_WIDTH-1:0] grad_r, scaled_grad_b_r;
    reg                         grad_overflow_r;
    reg                         is_weight_r2;

    reg signed [DATA_WIDTH-1:0] old_val_r, scaled_r;
    reg                         is_weight_r3;

    wire signed [DATA_WIDTH-1:0] grad_w;
    wire                         grad_overflow;
    gradient_unit #(.DATA_WIDTH(DATA_WIDTH), .FRAC_BITS(FRAC_BITS)) u_grad (
        .delta(delta_val_r), .activation(act_val_r), .grad(grad_w), .overflow(grad_overflow)
    );

    wire signed [DATA_WIDTH-1:0] scaled_grad_w = grad_r >>> lr_shift;

    wire signed [DATA_WIDTH-1:0] new_val;
    wire upd_overflow;
    fixed_adder #(.DATA_WIDTH(DATA_WIDTH)) u_upd_sub (
        .a(old_val_r), .b(scaled_r), .subtract(1'b1), .result(new_val), .overflow(upd_overflow)
    );

    always @(posedge clk) begin
        if (rst) begin
            state        <= S_IDLE;
            idx          <= 8'd0;
            busy         <= 1'b0;
            done         <= 1'b0;
            we           <= 1'b0;
            b_we         <= 1'b0;
            rd_layer_sel <= 1'b0;
            rd_row       <= 3'd0;
            rd_col       <= 3'd0;
            wr_layer_sel <= 1'b0;
            wr_row       <= 3'd0;
            wr_col       <= 3'd0;
            wr_data      <= {DATA_WIDTH{1'b0}};
            b_layer_sel   <= 1'b0;
            b_idx         <= 3'd0;
            b_wr_data     <= {DATA_WIDTH{1'b0}};
            overflow_flag <= 1'b0;

            act_val_r        <= {DATA_WIDTH{1'b0}};
            delta_val_r      <= {DATA_WIDTH{1'b0}};
            bias_delta_val_r <= {DATA_WIDTH{1'b0}};
            is_weight_r1     <= 1'b0;

            grad_r          <= {DATA_WIDTH{1'b0}};
            scaled_grad_b_r <= {DATA_WIDTH{1'b0}};
            grad_overflow_r <= 1'b0;
            is_weight_r2    <= 1'b0;

            old_val_r    <= {DATA_WIDTH{1'b0}};
            scaled_r     <= {DATA_WIDTH{1'b0}};
            is_weight_r3 <= 1'b0;
        end else begin
            done <= 1'b0;
            we   <= 1'b0;
            b_we <= 1'b0;

            if (state == S_WRITE && (grad_overflow_r || upd_overflow))
                overflow_flag <= 1'b1;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        busy          <= 1'b1;
                        idx           <= 8'd0;
                        overflow_flag <= 1'b0;
                        state         <= S_SET_ADDR;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                S_SET_ADDR: begin
                    if (is_weight) begin
                        rd_layer_sel <= is_l1 ? 1'b0 : 1'b1;
                        rd_row       <= is_l1 ? l1_row : l2_row;
                        rd_col       <= is_l1 ? l1_col : l2_col;
                    end else begin
                        b_layer_sel <= is_bias1 ? 1'b0 : 1'b1;
                        b_idx       <= is_bias1 ? b1_idx : b2_idx;
                    end

                    act_val_r        <= act_val;
                    delta_val_r      <= delta_val;
                    bias_delta_val_r <= bias_delta_val;
                    is_weight_r1     <= is_weight;

                    state <= S_READ_WAIT;
                end

                S_READ_WAIT: begin
                    grad_r          <= grad_w;
                    scaled_grad_b_r <= bias_delta_val_r >>> lr_shift;
                    grad_overflow_r <= grad_overflow;
                    is_weight_r2    <= is_weight_r1;

                    state <= S_COMPUTE;
                end

                S_COMPUTE: begin
                    old_val_r    <= is_weight_r2 ? rd_data : b_rd_data;
                    scaled_r     <= is_weight_r2 ? scaled_grad_w : scaled_grad_b_r;
                    is_weight_r3 <= is_weight_r2;

                    state <= S_WRITE;
                end

                S_WRITE: begin
                    if (is_weight_r3) begin
                        we           <= 1'b1;
                        wr_layer_sel <= is_l1 ? 1'b0 : 1'b1;
                        wr_row       <= is_l1 ? l1_row : l2_row;
                        wr_col       <= is_l1 ? l1_col : l2_col;
                        wr_data      <= new_val;
                    end else begin
                        b_we        <= 1'b1;
                        b_layer_sel <= is_bias1 ? 1'b0 : 1'b1;
                        b_idx       <= is_bias1 ? b1_idx : b2_idx;
                        b_wr_data   <= new_val;
                    end
                    state <= S_NEXT;
                end

                S_NEXT: begin
                    if (idx == TOTAL-1) begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        idx   <= idx + 1'b1;
                        state <= S_SET_ADDR;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule