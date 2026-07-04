`timescale 1ns / 1ps
// fixed_mac.v - Reusable fixed-point multiply-accumulate unit

module fixed_mac #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS  = 12,
    parameter ACC_WIDTH  = 32
)(
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clr,
    input  wire                         en,
    input  wire signed [DATA_WIDTH-1:0] a,
    input  wire signed [DATA_WIDTH-1:0] b,

    output reg signed [ACC_WIDTH-1:0]   acc,
    output reg signed [DATA_WIDTH-1:0]  result_sat,
    output reg                          overflow
);

localparam signed [DATA_WIDTH-1:0] MAX_VAL =
        {1'b0,{(DATA_WIDTH-1){1'b1}}};

localparam signed [DATA_WIDTH-1:0] MIN_VAL =
        {1'b1,{(DATA_WIDTH-1){1'b0}}};

(* use_dsp = "yes" *)
wire signed [2*DATA_WIDTH-1:0] product;

assign product = a * b;

wire signed [ACC_WIDTH-1:0] product_ext =
    {{(ACC_WIDTH-2*DATA_WIDTH){product[2*DATA_WIDTH-1]}},product};

wire signed [ACC_WIDTH-1:0] product_scaled =
    (product_ext + (1 <<< (FRAC_BITS-1))) >>> FRAC_BITS;

reg signed [ACC_WIDTH-1:0] product_pipe;

always @(posedge clk) begin

    if(rst)
        product_pipe <= 0;

    else if(en)
        product_pipe <= product_scaled;

end

always @(posedge clk) begin

    if(rst)
        acc <= 0;

    else if(clr)
        acc <= en ? product_pipe : 0;

    else if(en)
        acc <= acc + product_pipe;

end

wire signed [ACC_WIDTH-1:0] max_val_ext =
        {{(ACC_WIDTH-DATA_WIDTH){1'b0}},MAX_VAL};

wire signed [ACC_WIDTH-1:0] min_val_ext =
        {{(ACC_WIDTH-DATA_WIDTH){1'b1}},MIN_VAL};

always @(*) begin

    if(acc > max_val_ext) begin
        result_sat = MAX_VAL;
        overflow   = 1'b1;
    end

    else if(acc < min_val_ext) begin
        result_sat = MIN_VAL;
        overflow   = 1'b1;
    end

    else begin
        result_sat = acc[DATA_WIDTH-1:0];
        overflow   = 1'b0;
    end

end

endmodule