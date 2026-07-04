`timescale 1ns / 1ps
// weight_memory.v - Weight storage for W1 and W2 with two read ports
module weight_memory #(
    parameter DATA_WIDTH = 16,
    parameter INPUTS     = 8,
    parameter HIDDEN     = 4,
    parameter OUTPUTS    = 2
)(
    input  wire clk,
    input  wire rst,
    input  wire reinit,

    input  wire        rd_layer_sel_a,
    input  wire [2:0]  rd_row_a,
    input  wire [2:0]  rd_col_a,
    output reg  signed [DATA_WIDTH-1:0] rd_data_a,

    input  wire        rd_layer_sel_b,
    input  wire [2:0]  rd_row_b,
    input  wire [2:0]  rd_col_b,
    output reg  signed [DATA_WIDTH-1:0] rd_data_b,

    input  wire        we,
    input  wire        wr_layer_sel,
    input  wire [2:0]  wr_row,
    input  wire [2:0]  wr_col,
    input  wire signed [DATA_WIDTH-1:0] wr_data
);

    integer i, j;

    reg signed [DATA_WIDTH-1:0] W1 [0:HIDDEN-1][0:INPUTS-1];
    reg signed [DATA_WIDTH-1:0] W2 [0:OUTPUTS-1][0:HIDDEN-1];

    
    function signed [DATA_WIDTH-1:0] init_weight;
        input [31:0] idx;
        begin
            case (idx % 8)
                0: init_weight = 16'sh0400;
                1: init_weight = 16'shFC00;
                2: init_weight = 16'sh0200;
                3: init_weight = 16'shFE00;
                4: init_weight = 16'sh0100;
                5: init_weight = 16'shFF00;
                6: init_weight = 16'sh0600;
                default: init_weight = 16'shFD00;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst || reinit) begin
            for (i = 0; i < HIDDEN; i = i + 1)
                for (j = 0; j < INPUTS; j = j + 1)
                    W1[i][j] <= init_weight(i*INPUTS + j);
            for (i = 0; i < OUTPUTS; i = i + 1)
                for (j = 0; j < HIDDEN; j = j + 1)
                    W2[i][j] <= init_weight(HIDDEN*INPUTS + i*HIDDEN + j);
        end else if (we) begin
            if (wr_layer_sel == 1'b0)
                W1[wr_row[1:0]][wr_col[2:0]] <= wr_data;
            else
                W2[wr_row[0]][wr_col[1:0]] <= wr_data;
        end
    end

    always @(*) begin
        if (rd_layer_sel_a == 1'b0)
            rd_data_a = W1[rd_row_a[1:0]][rd_col_a[2:0]];
        else
            rd_data_a = W2[rd_row_a[0]][rd_col_a[1:0]];
    end

    always @(*) begin
        if (rd_layer_sel_b == 1'b0)
            rd_data_b = W1[rd_row_b[1:0]][rd_col_b[2:0]];
        else
            rd_data_b = W2[rd_row_b[0]][rd_col_b[1:0]];
    end

endmodule
