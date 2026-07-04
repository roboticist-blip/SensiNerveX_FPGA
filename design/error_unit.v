`timescale 1ns / 1ps
// error_unit.v - Computes output and hidden layer errors/deltas
module error_unit #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS  = 12,
    parameter HIDDEN     = 4,
    parameter OUTPUTS    = 2
)(
    input  wire clk,
    input  wire rst,

    input  wire start_out_err,
    input  wire start_hid_err,

    input  wire [DATA_WIDTH*OUTPUTS-1:0] y_flat,
    input  wire [DATA_WIDTH*OUTPUTS-1:0] d_flat,
    input  wire [DATA_WIDTH*HIDDEN-1:0]  hidden_pre_flat,
    output reg        w_layer_sel,
    output reg  [2:0] w_row,
    output reg  [2:0] w_col,
    input  wire signed [DATA_WIDTH-1:0] w_data,

    output reg [DATA_WIDTH*OUTPUTS-1:0] output_delta_flat,
    output reg [DATA_WIDTH*HIDDEN-1:0]  hidden_delta_flat,

    output reg busy,
    output reg done_out_err,
    output reg done_hid_err
);

    localparam S_IDLE      = 3'd0,
               S_OUT_ERR   = 3'd1,
               S_OUT_NEXT  = 3'd2,
               S_HID_ADDR  = 3'd3,
               S_HID_ACC   = 3'd6,
               S_HID_APPLY = 3'd4,
               S_HID_NEXT  = 3'd5;

    reg [2:0] state;
    reg [2:0] out_idx;
    reg [2:0] hid_idx;
    reg [2:0] k_idx;

    wire signed [DATA_WIDTH-1:0] y_cur = y_flat[out_idx*DATA_WIDTH +: DATA_WIDTH];
    wire signed [DATA_WIDTH-1:0] d_cur = d_flat[out_idx*DATA_WIDTH +: DATA_WIDTH];

    wire signed [DATA_WIDTH-1:0] err_val;
    fixed_adder #(.DATA_WIDTH(DATA_WIDTH)) u_err_sub (
        .a(y_cur), .b(d_cur), .subtract(1'b1), .result(err_val), .overflow()
    );

    wire signed [DATA_WIDTH-1:0] out_delta_val = err_val >>> 2;

    reg mac_clr, mac_en;
    wire signed [DATA_WIDTH-1:0] mac_result;
    wire signed [31:0] mac_acc;
    wire signed [DATA_WIDTH-1:0] cur_delta = output_delta_flat[k_idx*DATA_WIDTH +: DATA_WIDTH];

    fixed_mac #(
        .DATA_WIDTH(DATA_WIDTH), .FRAC_BITS(FRAC_BITS), .ACC_WIDTH(32)
    ) u_mac (
        .clk(clk), .rst(rst), .clr(mac_clr), .en(mac_en),
        .a(w_data), .b(cur_delta),
        .acc(mac_acc), .result_sat(mac_result), .overflow()
    );

    wire signed [DATA_WIDTH-1:0] hid_pre_cur = hidden_pre_flat[hid_idx*DATA_WIDTH +: DATA_WIDTH];
    wire signed [DATA_WIDTH-1:0] hid_delta_val = hid_pre_cur[DATA_WIDTH-1] ? {DATA_WIDTH{1'b0}} : mac_result;

    always @(posedge clk) begin
        if (rst) begin
            state             <= S_IDLE;
            out_idx           <= 3'd0;
            hid_idx           <= 3'd0;
            k_idx             <= 3'd0;
            busy              <= 1'b0;
            done_out_err      <= 1'b0;
            done_hid_err      <= 1'b0;
            mac_clr           <= 1'b0;
            mac_en            <= 1'b0;
            w_layer_sel       <= 1'b1;
            w_row             <= 3'd0;
            w_col             <= 3'd0;
            output_delta_flat <= {(DATA_WIDTH*OUTPUTS){1'b0}};
            hidden_delta_flat <= {(DATA_WIDTH*HIDDEN){1'b0}};
        end else begin
            done_out_err <= 1'b0;
            done_hid_err <= 1'b0;

            case (state)
                S_IDLE: begin
                    mac_clr <= 1'b0;
                    mac_en  <= 1'b0;
                    if (start_out_err) begin
                        busy    <= 1'b1;
                        out_idx <= 3'd0;
                        state   <= S_OUT_ERR;
                    end else if (start_hid_err) begin
                        busy        <= 1'b1;
                        hid_idx     <= 3'd0;
                        k_idx       <= 3'd0;
                        w_layer_sel <= 1'b1;
                        w_row       <= 3'd0;
                        w_col       <= 3'd0;
                        mac_clr     <= 1'b0;
                        mac_en      <= 1'b0;
                        state       <= S_HID_ADDR;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                
                S_OUT_ERR: begin
                    output_delta_flat[out_idx*DATA_WIDTH +: DATA_WIDTH] <= out_delta_val;
                    state <= S_OUT_NEXT;
                end

                S_OUT_NEXT: begin
                    if (out_idx == OUTPUTS-1) begin
                        busy         <= 1'b0;
                        done_out_err <= 1'b1;
                        state        <= S_IDLE;
                    end else begin
                        out_idx <= out_idx + 1'b1;
                        state   <= S_OUT_ERR;
                    end
                end

                    S_HID_ADDR: begin
                    mac_clr <= (k_idx == 3'd0) ? 1'b1 : 1'b0;
                    mac_en  <= 1'b1;
                    state   <= S_HID_ACC;
                end

                S_HID_ACC: begin
                    mac_clr <= 1'b0;
                    mac_en  <= 1'b0;
                    if (k_idx == OUTPUTS-1) begin
                        state <= S_HID_APPLY;
                    end else begin
                        k_idx <= k_idx + 1'b1;
                        w_row <= k_idx + 1'b1;
                        state <= S_HID_ADDR;
                    end
                end

                S_HID_APPLY: begin
                    hidden_delta_flat[hid_idx*DATA_WIDTH +: DATA_WIDTH] <= hid_delta_val;
                    state <= S_HID_NEXT;
                end

                S_HID_NEXT: begin
                    if (hid_idx == HIDDEN-1) begin
                        busy         <= 1'b0;
                        done_hid_err <= 1'b1;
                        state        <= S_IDLE;
                    end else begin
                        hid_idx <= hid_idx + 1'b1;
                        w_col   <= hid_idx + 1'b1;
                        k_idx   <= 3'd0;
                        w_row   <= 3'd0;
                        mac_clr <= 1'b0;
                        mac_en  <= 1'b0;
                        state   <= S_HID_ADDR;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule