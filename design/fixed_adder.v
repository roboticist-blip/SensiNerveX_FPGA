`timescale 1ns / 1ps
// fixed_adder.v - Signed fixed-point adder/subtractor with saturation
module fixed_adder #(
    parameter DATA_WIDTH = 16
)(
    input  wire signed [DATA_WIDTH-1:0] a,
    input  wire signed [DATA_WIDTH-1:0] b,
    input  wire                         subtract,
    output reg  signed [DATA_WIDTH-1:0] result,
    output reg                          overflow
);

    localparam signed [DATA_WIDTH-1:0] MAX_VAL = {1'b0, {(DATA_WIDTH-1){1'b1}}};
    localparam signed [DATA_WIDTH-1:0] MIN_VAL = {1'b1, {(DATA_WIDTH-1){1'b0}}};

    reg signed [DATA_WIDTH:0] sum_ext;

    always @(*) begin
        if (subtract)
            sum_ext = {a[DATA_WIDTH-1], a} - {b[DATA_WIDTH-1], b};
        else
            sum_ext = {a[DATA_WIDTH-1], a} + {b[DATA_WIDTH-1], b};

        if (sum_ext > $signed({1'b0, MAX_VAL})) begin
            result   = MAX_VAL;
            overflow = 1'b1;
        end else if (sum_ext < $signed({1'b1, MIN_VAL})) begin
            result   = MIN_VAL;
            overflow = 1'b1;
        end else begin
            result   = sum_ext[DATA_WIDTH-1:0];
            overflow = 1'b0;
        end
    end

endmodule
