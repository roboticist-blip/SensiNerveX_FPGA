`timescale 1ns / 1ps
// forward_engine.v - Computes pre-activation sums for hidden and output layers
module forward_engine #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS  = 12,
    parameter INPUTS     = 8,
    parameter HIDDEN     = 4,
    parameter OUTPUTS    = 2
)(
    input  wire clk,
    input  wire rst,

    input  wire start_l1,
    input  wire start_l2,

    input  wire [DATA_WIDTH*INPUTS-1:0] x_flat,
    input  wire [DATA_WIDTH*HIDDEN-1:0] hidden_act_flat,

    output reg        w_layer_sel,
    output reg  [2:0] w_row,
    output reg  [2:0] w_col,
    input  wire signed [DATA_WIDTH-1:0] w_data,

    output reg        b_layer_sel,
    output reg  [2:0] b_idx,
    input  wire signed [DATA_WIDTH-1:0] b_data,

    output reg [DATA_WIDTH*HIDDEN-1:0]  hidden_pre_flat,
    output reg [DATA_WIDTH*OUTPUTS-1:0] out_pre_flat,

    output reg busy,
    output reg done_l1,
    output reg done_l2,
    output reg overflow_flag
);

    
    localparam S_IDLE     = 3'd0,
               S_MAC_L1   = 3'd1,
               S_BIAS_L1  = 3'd2,
               S_NEXT_L1  = 3'd3,
               S_MAC_L2   = 3'd4,
               S_BIAS_L2  = 3'd5,
               S_NEXT_L2  = 3'd6;

    reg [2:0] state;

    reg [2:0] neuron_idx;
    reg [2:0] fanin_idx;

    wire signed [DATA_WIDTH-1:0] cur_x;
    wire signed [DATA_WIDTH-1:0] cur_h;

    assign cur_x = x_flat[fanin_idx*DATA_WIDTH +: DATA_WIDTH];
    assign cur_h = hidden_act_flat[fanin_idx*DATA_WIDTH +: DATA_WIDTH];

    reg mac_clr, mac_en;
    wire signed [DATA_WIDTH-1:0] mac_result;
    wire mac_overflow;
    wire signed [31:0] mac_acc;

    fixed_mac #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_BITS (FRAC_BITS),
        .ACC_WIDTH (32)
    ) u_mac (
        .clk        (clk),
        .rst        (rst),
        .clr        (mac_clr),
        .en         (mac_en),
        .a          (w_data),
        .b          ((state == S_MAC_L1) ? cur_x : cur_h),
        .acc        (mac_acc),
        .result_sat (mac_result),
        .overflow   (mac_overflow)
    );

    wire signed [DATA_WIDTH-1:0] biased_result;
    wire                         bias_add_overflow;
    fixed_adder #(.DATA_WIDTH(DATA_WIDTH)) u_bias_add (
        .a        (mac_result),
        .b        (b_data),
        .subtract (1'b0),
        .result   (biased_result),
        .overflow (bias_add_overflow)
    );

    always @(posedge clk) begin
        if (rst) begin
            state           <= S_IDLE;
            neuron_idx      <= 3'd0;
            fanin_idx       <= 3'd0;
            busy            <= 1'b0;
            done_l1         <= 1'b0;
            done_l2         <= 1'b0;
            mac_clr         <= 1'b0;
            mac_en          <= 1'b0;
            w_layer_sel     <= 1'b0;
            b_layer_sel     <= 1'b0;
            w_row           <= 3'd0;
            w_col           <= 3'd0;
            b_idx           <= 3'd0;
            hidden_pre_flat <= {(DATA_WIDTH*HIDDEN){1'b0}};
            out_pre_flat    <= {(DATA_WIDTH*OUTPUTS){1'b0}};
            overflow_flag   <= 1'b0;
        end else begin
            done_l1 <= 1'b0;
            done_l2 <= 1'b0;

            if (mac_overflow || bias_add_overflow)
                overflow_flag <= 1'b1;

            case (state)
                
                S_IDLE: begin
                    mac_clr <= 1'b0;
                    mac_en  <= 1'b0;
                    if (start_l1) begin
                        busy          <= 1'b1;
                        neuron_idx    <= 3'd0;
                        fanin_idx     <= 3'd0;
                        w_layer_sel   <= 1'b0;
                        b_layer_sel   <= 1'b0;
                        w_row         <= 3'd0;
                        w_col         <= 3'd0;
                        mac_clr       <= 1'b1;
                        mac_en        <= 1'b1;
                        overflow_flag <= 1'b0;
                        state         <= S_MAC_L1;
                    end else if (start_l2) begin
                        busy        <= 1'b1;
                        neuron_idx  <= 3'd0;
                        fanin_idx   <= 3'd0;
                        w_layer_sel <= 1'b1;
                        b_layer_sel <= 1'b1;
                        w_row       <= 3'd0;
                        w_col       <= 3'd0;
                        mac_clr     <= 1'b1;
                        mac_en      <= 1'b1;
                        state       <= S_MAC_L2;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                
                S_MAC_L1: begin
                    mac_clr <= 1'b0;
                    if (fanin_idx == INPUTS-1) begin
                        mac_en <= 1'b0;
                        b_idx  <= neuron_idx;
                        state  <= S_BIAS_L1;
                    end else begin
                        fanin_idx <= fanin_idx + 1'b1;
                        w_col     <= fanin_idx + 1'b1;
                        mac_en    <= 1'b1;
                    end
                end

                S_BIAS_L1: begin
                    hidden_pre_flat[neuron_idx*DATA_WIDTH +: DATA_WIDTH] <= biased_result;
                    state <= S_NEXT_L1;
                end

                S_NEXT_L1: begin
                    if (neuron_idx == HIDDEN-1) begin
                        busy    <= 1'b0;
                        done_l1 <= 1'b1;
                        state   <= S_IDLE;
                    end else begin
                        neuron_idx <= neuron_idx + 1'b1;
                        w_row      <= neuron_idx + 1'b1;
                        b_idx      <= neuron_idx + 1'b1;
                        fanin_idx  <= 3'd0;
                        w_col      <= 3'd0;
                        mac_clr    <= 1'b1;
                        mac_en     <= 1'b1;
                        state      <= S_MAC_L1;
                    end
                end

                
                S_MAC_L2: begin
                    mac_clr <= 1'b0;
                    if (fanin_idx == HIDDEN-1) begin
                        mac_en <= 1'b0;
                        b_idx  <= neuron_idx;
                        state  <= S_BIAS_L2;
                    end else begin
                        fanin_idx <= fanin_idx + 1'b1;
                        w_col     <= fanin_idx + 1'b1;
                        mac_en    <= 1'b1;
                    end
                end

                S_BIAS_L2: begin
                    out_pre_flat[neuron_idx*DATA_WIDTH +: DATA_WIDTH] <= biased_result;
                    state <= S_NEXT_L2;
                end

                S_NEXT_L2: begin
                    if (neuron_idx == OUTPUTS-1) begin
                        busy    <= 1'b0;
                        done_l2 <= 1'b1;
                        state   <= S_IDLE;
                    end else begin
                        neuron_idx <= neuron_idx + 1'b1;
                        w_row      <= neuron_idx + 1'b1;
                        b_idx      <= neuron_idx + 1'b1;
                        fanin_idx  <= 3'd0;
                        w_col      <= 3'd0;
                        mac_clr    <= 1'b1;
                        mac_en     <= 1'b1;
                        state      <= S_MAC_L2;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
