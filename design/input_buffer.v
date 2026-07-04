`timescale 1ns / 1ps
// input_buffer.v - Latches switch inputs and labels into Q4.12 registers
module input_buffer #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS  = 12,
    parameter INPUTS     = 8,
    parameter OUTPUTS    = 2
)(
    input  wire clk,
    input  wire rst,
    input  wire load,

    input  wire [INPUTS-1:0] sw_inputs,
    input  wire [OUTPUTS-1:0] sw_labels,

    output reg [DATA_WIDTH*INPUTS-1:0]  x_flat,
    output reg [DATA_WIDTH*OUTPUTS-1:0] d_flat
);

    localparam signed [DATA_WIDTH-1:0] ONE_Q  = (1 <<< FRAC_BITS);
    localparam signed [DATA_WIDTH-1:0] ZERO_Q = {DATA_WIDTH{1'b0}};

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            x_flat <= {(DATA_WIDTH*INPUTS){1'b0}};
            d_flat <= {(DATA_WIDTH*OUTPUTS){1'b0}};
        end else if (load) begin
            for (i = 0; i < INPUTS; i = i + 1)
                x_flat[i*DATA_WIDTH +: DATA_WIDTH] <= sw_inputs[i] ? ONE_Q : ZERO_Q;
            for (i = 0; i < OUTPUTS; i = i + 1)
                d_flat[i*DATA_WIDTH +: DATA_WIDTH] <= sw_labels[i] ? ONE_Q : ZERO_Q;
        end
    end

endmodule
