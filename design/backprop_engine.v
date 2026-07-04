`timescale 1ns / 1ps
// backprop_engine.v - Backprop wrapper: error unit and weight update
module backprop_engine #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS  = 12,
    parameter INPUTS     = 8,
    parameter HIDDEN     = 4,
    parameter OUTPUTS    = 2
)(
    input  wire clk,
    input  wire rst,

    input  wire start_out_err,
    input  wire start_hid_err,
    input  wire start_wupd,
    input  wire lr_sel,

    input  wire [DATA_WIDTH*INPUTS-1:0]  x_flat,
    input  wire [DATA_WIDTH*HIDDEN-1:0]  hidden_act_flat,
    input  wire [DATA_WIDTH*HIDDEN-1:0]  hidden_pre_flat,
    input  wire [DATA_WIDTH*OUTPUTS-1:0] y_flat,
    input  wire [DATA_WIDTH*OUTPUTS-1:0] d_flat,

    output wire        w_layer_sel_b,
    output wire [2:0]  w_row_b,
    output wire [2:0]  w_col_b,
    input  wire signed [DATA_WIDTH-1:0] w_data_b,

    output wire        we,
    output wire        wr_layer_sel,
    output wire [2:0]  wr_row,
    output wire [2:0]  wr_col,
    output wire signed [DATA_WIDTH-1:0] wr_data,

    output wire        b_we,
    output wire        b_layer_sel,
    output wire [2:0]  b_idx,
    output wire signed [DATA_WIDTH-1:0] b_wr_data,
    input  wire signed [DATA_WIDTH-1:0] b_rd_data,

    output wire [DATA_WIDTH*OUTPUTS-1:0] output_delta_flat,
    output wire [DATA_WIDTH*HIDDEN-1:0]  hidden_delta_flat,

    output wire busy,
    output wire done_out_err,
    output wire done_hid_err,
    output wire done_wupd,
    output wire overflow_flag
);

    wire        eu_w_layer_sel;
    wire [2:0]  eu_w_row, eu_w_col;
    wire        eu_busy;

    wire        wu_rd_layer_sel;
    wire [2:0]  wu_rd_row, wu_rd_col;
    wire        wu_busy;
    wire        wu_overflow_flag;

    assign overflow_flag = wu_overflow_flag;

    assign w_layer_sel_b = wu_busy ? wu_rd_layer_sel : eu_w_layer_sel;
    assign w_row_b        = wu_busy ? wu_rd_row       : eu_w_row;
    assign w_col_b         = wu_busy ? wu_rd_col       : eu_w_col;

    assign busy = eu_busy | wu_busy;

    error_unit #(
        .DATA_WIDTH(DATA_WIDTH), .FRAC_BITS(FRAC_BITS),
        .HIDDEN(HIDDEN), .OUTPUTS(OUTPUTS)
    ) u_error (
        .clk(clk), .rst(rst),
        .start_out_err(start_out_err),
        .start_hid_err(start_hid_err),
        .y_flat(y_flat),
        .d_flat(d_flat),
        .hidden_pre_flat(hidden_pre_flat),
        .w_layer_sel(eu_w_layer_sel),
        .w_row(eu_w_row),
        .w_col(eu_w_col),
        .w_data(w_data_b),
        .output_delta_flat(output_delta_flat),
        .hidden_delta_flat(hidden_delta_flat),
        .busy(eu_busy),
        .done_out_err(done_out_err),
        .done_hid_err(done_hid_err)
    );

    weight_update_unit #(
        .DATA_WIDTH(DATA_WIDTH), .FRAC_BITS(FRAC_BITS),
        .INPUTS(INPUTS), .HIDDEN(HIDDEN), .OUTPUTS(OUTPUTS)
    ) u_wupd (
        .clk(clk), .rst(rst),
        .start(start_wupd),
        .lr_sel(lr_sel),
        .x_flat(x_flat),
        .hidden_act_flat(hidden_act_flat),
        .output_delta_flat(output_delta_flat),
        .hidden_delta_flat(hidden_delta_flat),
        .rd_layer_sel(wu_rd_layer_sel),
        .rd_row(wu_rd_row),
        .rd_col(wu_rd_col),
        .rd_data(w_data_b),
        .we(we),
        .wr_layer_sel(wr_layer_sel),
        .wr_row(wr_row),
        .wr_col(wr_col),
        .wr_data(wr_data),
        .b_we(b_we),
        .b_layer_sel(b_layer_sel),
        .b_idx(b_idx),
        .b_wr_data(b_wr_data),
        .b_rd_data(b_rd_data),
        .busy(wu_busy),
        .done(done_wupd),
        .overflow_flag(wu_overflow_flag)
    );

endmodule
