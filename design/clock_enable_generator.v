`timescale 1ns / 1ps
// clock_enable_generator.v - Produces periodic tick enable from system clock
module clock_enable_generator #(
    parameter CLK_FREQ_HZ = 100_000_000,
    parameter TICK_HZ     = 1_000
)(
    input  wire clk,
    input  wire rst,
    output reg  tick_en
);

    localparam integer DIVIDE = CLK_FREQ_HZ / TICK_HZ;
    localparam integer CNT_WIDTH = $clog2(DIVIDE);

    reg [CNT_WIDTH-1:0] count;

    always @(posedge clk) begin
        if (rst) begin
            count   <= {CNT_WIDTH{1'b0}};
            tick_en <= 1'b0;
        end else if (count == DIVIDE - 1) begin
            count   <= {CNT_WIDTH{1'b0}};
            tick_en <= 1'b1;
        end else begin
            count   <= count + 1'b1;
            tick_en <= 1'b0;
        end
    end

endmodule
