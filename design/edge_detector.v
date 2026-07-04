`timescale 1ns / 1ps
// edge_detector.v - Produces a single-cycle pulse on rising edge
module edge_detector (
    input  wire clk,
    input  wire rst,
    input  wire din,
    output wire rising_pulse
);

    reg din_d;

    always @(posedge clk) begin
        if (rst)
            din_d <= 1'b0;
        else
            din_d <= din;
    end

    assign rising_pulse = din & ~din_d;

endmodule
