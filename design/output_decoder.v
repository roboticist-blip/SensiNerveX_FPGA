`timescale 1ns / 1ps
// output_decoder.v - Map internal status signals to LED bus
module output_decoder #(
    parameter DATA_WIDTH = 16,
    parameter OUTPUTS    = 2
)(
    input  wire clk,
    input  wire rst,

    input  wire [DATA_WIDTH*OUTPUTS-1:0] y_flat,
    input  wire        training_active,
    input  wire        inference_active,
    input  wire        done_flag,
    input  wire        overflow_any,
    input  wire        wupd_active,
    input  wire        fwd_pass_active,
    input  wire [3:0]  fsm_state,

    output reg  [15:0] led
);

    wire signed [DATA_WIDTH-1:0] y0 = y_flat[0 +: DATA_WIDTH];
    wire signed [DATA_WIDTH-1:0] y1 = y_flat[DATA_WIDTH +: DATA_WIDTH];

    reg [1:0] predicted_class;
    reg       overflow_sticky;

    always @(*) begin
        predicted_class = (y1 > y0) ? 2'b10 : 2'b01;
    end

    always @(posedge clk) begin
        if (rst)
            overflow_sticky <= 1'b0;
        else if (fsm_state == 4'd0)
            overflow_sticky <= 1'b0;
        else if (overflow_any)
            overflow_sticky <= 1'b1;
    end

    always @(*) begin
        led            = 16'b0;
        led[1:0]       = predicted_class;
        led[2]         = training_active;
        led[3]         = inference_active;
        led[4]         = done_flag;
        led[5]         = overflow_sticky;
        led[6]         = wupd_active;
        led[7]         = fwd_pass_active;
        led[11:8]      = fsm_state;
        led[15:12]     = 4'b0000;
    end

endmodule
