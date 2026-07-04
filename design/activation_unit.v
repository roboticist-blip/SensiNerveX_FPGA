`timescale 1ns / 1ps
// activation_unit.v - Activation unit: ReLU (hidden) and HardSigmoid (output)

module activation_unit #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS  = 12
)(
    input  wire                         act_sel,
    input  wire signed [DATA_WIDTH-1:0] din,
    output reg  signed [DATA_WIDTH-1:0] dout
);

    localparam signed [DATA_WIDTH-1:0] ONE_Q  = (1 <<< FRAC_BITS);
    localparam signed [DATA_WIDTH-1:0] ZERO_Q = {DATA_WIDTH{1'b0}};

    reg signed [DATA_WIDTH-1:0] sigmoid_lin;

    always @(*) begin
        if (act_sel == 1'b0) begin
            dout = din[DATA_WIDTH-1] ? ZERO_Q : din;
        end else begin
            sigmoid_lin = HALF_Q(din);
            if (sigmoid_lin > ONE_Q)
                dout = ONE_Q;
            else if (sigmoid_lin < ZERO_Q)
                dout = ZERO_Q;
            else
                dout = sigmoid_lin;
        end
    end

    function signed [DATA_WIDTH-1:0] HALF_Q;
        input signed [DATA_WIDTH-1:0] x;
        begin
            HALF_Q = (1 <<< (FRAC_BITS-1)) + (x >>> 2);
        end
    endfunction

endmodule
