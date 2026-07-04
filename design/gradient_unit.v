`timescale 1ns / 1ps
// gradient_unit.v - Combinational gradient primitive (delta * activation)
module gradient_unit #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS  = 12
)(
    input  wire signed [DATA_WIDTH-1:0] delta,
    input  wire signed [DATA_WIDTH-1:0] activation,
    output wire signed [DATA_WIDTH-1:0] grad,
    output wire                         overflow
);

    fixed_multiplier #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_BITS (FRAC_BITS)
    ) u_mult (
        .a        (delta),
        .b        (activation),
        .result   (grad),
        .overflow (overflow)
    );

endmodule
