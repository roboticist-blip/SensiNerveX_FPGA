`timescale 1ns / 1ps
// bias_memory.v - Bias storage for hidden and output layers

module bias_memory #(
    parameter DATA_WIDTH = 16,
    parameter HIDDEN     = 4,
    parameter OUTPUTS    = 2
)(
    input  wire clk,
    input  wire rst,
    input  wire reinit,

    input  wire        we,
    input  wire        layer_sel,     // 0 = Bias1, 1 = Bias2
    input  wire [2:0]  idx,
    input  wire signed [DATA_WIDTH-1:0] wr_data,
    output reg  signed [DATA_WIDTH-1:0] rd_data
);

    integer i;

    reg signed [DATA_WIDTH-1:0] Bias1 [0:HIDDEN-1];
    reg signed [DATA_WIDTH-1:0] Bias2 [0:OUTPUTS-1];

    always @(posedge clk) begin
        if (rst || reinit) begin
            for (i = 0; i < HIDDEN; i = i + 1)
                Bias1[i] <= {DATA_WIDTH{1'b0}};
            for (i = 0; i < OUTPUTS; i = i + 1)
                Bias2[i] <= {DATA_WIDTH{1'b0}};
        end else if (we) begin
            if (layer_sel == 1'b0)
                Bias1[idx[1:0]] <= wr_data;
            else
                Bias2[idx[0]] <= wr_data;
        end
    end

    always @(*) begin
        if (layer_sel == 1'b0)
            rd_data = Bias1[idx[1:0]];
        else
            rd_data = Bias2[idx[0]];
    end

endmodule
