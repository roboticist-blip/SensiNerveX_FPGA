`timescale 1ns / 1ps
// fixed_multiplier.v - Signed fixed-point multiplier (combinational)
module fixed_multiplier #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS  = 12
)(
    input  wire signed [DATA_WIDTH-1:0] a,
    input  wire signed [DATA_WIDTH-1:0] b,
    output reg  signed [DATA_WIDTH-1:0] result,
    output reg                          overflow
);

    localparam signed [DATA_WIDTH-1:0] MAX_VAL = {1'b0, {(DATA_WIDTH-1){1'b1}}};
    localparam signed [DATA_WIDTH-1:0] MIN_VAL = {1'b1, {(DATA_WIDTH-1){1'b0}}};

    // Full precision product: Q(2*INT).(2*FRAC)
    wire signed [2*DATA_WIDTH-1:0] full_product;
    reg  signed [2*DATA_WIDTH-1:0] shifted;

    assign full_product = a * b;

    always @(*) begin
        shifted = (full_product + (1 <<< (FRAC_BITS-1))) >>> FRAC_BITS;

        if (shifted > $signed({{(2*DATA_WIDTH-DATA_WIDTH){1'b0}}, MAX_VAL})) begin
            result   = MAX_VAL;
            overflow = 1'b1;
        end else if (shifted < $signed({{(2*DATA_WIDTH-DATA_WIDTH){1'b1}}, MIN_VAL})) begin
            result   = MIN_VAL;
            overflow = 1'b1;
        end else begin
            result   = shifted[DATA_WIDTH-1:0];
            overflow = 1'b0;
        end
    end

endmodule
