`timescale 1ns / 1ps
// debouncer.v - Shift-register majority debouncer
module debouncer #(
    parameter SR_LEN = 4
)(
    input  wire clk,
    input  wire rst,
    input  wire tick_en,
    input  wire raw_in,
    output reg  clean_out
);

    reg [SR_LEN-1:0] shift_reg;

    always @(posedge clk) begin
        if (rst) begin
            shift_reg <= {SR_LEN{1'b0}};
            clean_out <= 1'b0;
        end else if (tick_en) begin
            shift_reg <= {shift_reg[SR_LEN-2:0], raw_in};
            if (&shift_reg[SR_LEN-2:0] && raw_in)
                clean_out <= 1'b1;
            else if (~(|shift_reg[SR_LEN-2:0]) && ~raw_in)
                clean_out <= 1'b0;
        end
    end

endmodule
