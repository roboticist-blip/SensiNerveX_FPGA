`timescale 1ns / 1ps
// top_mlp_engine.v - Top-level MLP engine connecting submodules and I/O
module top_mlp_engine #(
    parameter DATA_WIDTH   = 16,
    parameter FRAC_BITS    = 12,
    parameter INPUTS       = 8,
    parameter HIDDEN       = 4,
    parameter OUTPUTS      = 2,
    parameter CLK_FREQ_HZ  = 100_000_000
)(
    input  wire        clk,
    input  wire        btn0_start_raw,
    input  wire        btn1_reset_raw,
    input  wire        btn2_reinit_raw,
    input  wire        btn3_raw,
    input  wire [15:0] sw,
    output wire [15:0] led
);

    // Power-on reset stretch: purely counter-derived, with no dependency on any debounced button (avoids a circular reset dependency where
    // the debouncers would need "rst" before "rst" itself is known). In real silicon flip-flops power up at a defined value (0 on this
    // architecture's FFs) so this class of X-propagation is a simulation artifact; por_rst below is what makes the design robust in both
    // simulation AND on real hardware.
    reg [3:0] por_cnt = 4'd0;
    reg       por_rst = 1'b1;
    always @(posedge clk) begin
        if (por_cnt != 4'hF) begin
            por_cnt <= por_cnt + 1'b1;
            por_rst <= 1'b1;
        end else begin
            por_rst <= 1'b0;
        end
    end

    wire tick_en;
    clock_enable_generator #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ), .TICK_HZ(1000)
    ) u_tick (
        .clk(clk), .rst(por_rst), .tick_en(tick_en)
    );

    wire btn0_clean, btn1_clean, btn2_clean;

    debouncer u_db0 (.clk(clk), .rst(por_rst), .tick_en(tick_en), .raw_in(btn0_start_raw),  .clean_out(btn0_clean));
    debouncer u_db1 (.clk(clk), .rst(por_rst), .tick_en(tick_en), .raw_in(btn1_reset_raw),  .clean_out(btn1_clean));
    debouncer u_db2 (.clk(clk), .rst(por_rst), .tick_en(tick_en), .raw_in(btn2_reinit_raw), .clean_out(btn2_clean));

    wire rst = por_rst | btn1_clean;

    wire start_pulse;
    edge_detector u_edge_start (.clk(clk), .rst(por_rst), .din(btn0_clean), .rising_pulse(start_pulse));

    wire reinit_pulse;
    edge_detector u_edge_reinit (.clk(clk), .rst(por_rst), .din(btn2_clean), .rising_pulse(reinit_pulse));

    wire [7:0] sw_inputs = sw[7:0];
    wire [1:0] sw_labels = sw[9:8];
    wire       lr_sel    = sw[14];   // 0 = LR1 (1/16), 1 = LR2 (1/64)
    wire       train_mode = sw[15]; // 0 = inference, 1 = training

    wire load_input, start_l1, act1_en, start_l2, act2_en;
    wire start_out_err, start_hid_err, start_wupd;
    wire training_active, inference_active, fwd_pass_active, wupd_active, done_flag;
    wire [3:0] fsm_state;

    wire fwd_done_l1, fwd_done_l2;
    wire bp_done_out_err, bp_done_hid_err, bp_done_wupd;

    control_fsm u_fsm (
        .clk(clk), .rst(rst),
        .start_pulse(start_pulse),
        .train_mode(train_mode),
        .fwd_done_l1(fwd_done_l1),
        .fwd_done_l2(fwd_done_l2),
        .bp_done_out_err(bp_done_out_err),
        .bp_done_hid_err(bp_done_hid_err),
        .bp_done_wupd(bp_done_wupd),
        .load_input(load_input),
        .start_l1(start_l1),
        .act1_en(act1_en),
        .start_l2(start_l2),
        .act2_en(act2_en),
        .start_out_err(start_out_err),
        .start_hid_err(start_hid_err),
        .start_wupd(start_wupd),
        .training_active(training_active),
        .inference_active(inference_active),
        .fwd_pass_active(fwd_pass_active),
        .wupd_active(wupd_active),
        .done_flag(done_flag),
        .state_out(fsm_state)
    );

    wire [DATA_WIDTH*INPUTS-1:0]  x_flat;
    wire [DATA_WIDTH*OUTPUTS-1:0] d_flat;

    input_buffer #(
        .DATA_WIDTH(DATA_WIDTH), .FRAC_BITS(FRAC_BITS),
        .INPUTS(INPUTS), .OUTPUTS(OUTPUTS)
    ) u_inbuf (
        .clk(clk), .rst(rst), .load(load_input),
        .sw_inputs(sw_inputs), .sw_labels(sw_labels),
        .x_flat(x_flat), .d_flat(d_flat)
    );

    wire        w_layer_sel_a;
    wire [2:0]  w_row_a, w_col_a;
    wire signed [DATA_WIDTH-1:0] w_data_a;

    wire        w_layer_sel_b;
    wire [2:0]  w_row_b, w_col_b;
    wire signed [DATA_WIDTH-1:0] w_data_b;

    wire        we, wr_layer_sel;
    wire [2:0]  wr_row, wr_col;
    wire signed [DATA_WIDTH-1:0] wr_data;

    weight_memory #(
        .DATA_WIDTH(DATA_WIDTH), .INPUTS(INPUTS), .HIDDEN(HIDDEN), .OUTPUTS(OUTPUTS)
    ) u_wmem (
        .clk(clk), .rst(rst), .reinit(reinit_pulse),
        .rd_layer_sel_a(w_layer_sel_a), .rd_row_a(w_row_a), .rd_col_a(w_col_a), .rd_data_a(w_data_a),
        .rd_layer_sel_b(w_layer_sel_b), .rd_row_b(w_row_b), .rd_col_b(w_col_b), .rd_data_b(w_data_b),
        .we(we), .wr_layer_sel(wr_layer_sel), .wr_row(wr_row), .wr_col(wr_col), .wr_data(wr_data)
    );

    wire        fwd_b_layer_sel;
    wire [2:0]  fwd_b_idx;
    wire        bp_b_we, bp_b_layer_sel;
    wire [2:0]  bp_b_idx;
    wire signed [DATA_WIDTH-1:0] bp_b_wr_data;
    wire signed [DATA_WIDTH-1:0] bias_rd_data;

    wire bias_layer_sel = fwd_pass_active ? fwd_b_layer_sel : bp_b_layer_sel;
    wire [2:0] bias_idx  = fwd_pass_active ? fwd_b_idx       : bp_b_idx;

    bias_memory #(
        .DATA_WIDTH(DATA_WIDTH), .HIDDEN(HIDDEN), .OUTPUTS(OUTPUTS)
    ) u_bmem (
        .clk(clk), .rst(rst), .reinit(reinit_pulse),
        .we(bp_b_we), .layer_sel(bias_layer_sel), .idx(bias_idx),
        .wr_data(bp_b_wr_data), .rd_data(bias_rd_data)
    );

    wire [DATA_WIDTH*HIDDEN-1:0]  hidden_pre_flat;
    wire [DATA_WIDTH*OUTPUTS-1:0] out_pre_flat;
    wire [DATA_WIDTH*HIDDEN-1:0]  hidden_act_flat;
    wire [DATA_WIDTH*OUTPUTS-1:0] y_flat;
    wire fwd_overflow_flag;

    forward_engine #(
        .DATA_WIDTH(DATA_WIDTH), .FRAC_BITS(FRAC_BITS),
        .INPUTS(INPUTS), .HIDDEN(HIDDEN), .OUTPUTS(OUTPUTS)
    ) u_fwd (
        .clk(clk), .rst(rst),
        .start_l1(start_l1), .start_l2(start_l2),
        .x_flat(x_flat), .hidden_act_flat(hidden_act_flat),
        .w_layer_sel(w_layer_sel_a), .w_row(w_row_a), .w_col(w_col_a), .w_data(w_data_a),
        .b_layer_sel(fwd_b_layer_sel), .b_idx(fwd_b_idx), .b_data(bias_rd_data),
        .hidden_pre_flat(hidden_pre_flat), .out_pre_flat(out_pre_flat),
        .busy(), .done_l1(fwd_done_l1), .done_l2(fwd_done_l2),
        .overflow_flag(fwd_overflow_flag)
    );

    wire [DATA_WIDTH*HIDDEN-1:0]  hidden_act_comb;
    wire [DATA_WIDTH*OUTPUTS-1:0] y_comb;

    genvar gh, go;
    generate
        for (gh = 0; gh < HIDDEN; gh = gh + 1) begin : GEN_RELU
            activation_unit #(.DATA_WIDTH(DATA_WIDTH), .FRAC_BITS(FRAC_BITS)) u_relu (
                .act_sel(1'b0),
                .din (hidden_pre_flat[gh*DATA_WIDTH +: DATA_WIDTH]),
                .dout(hidden_act_comb[gh*DATA_WIDTH +: DATA_WIDTH])
            );
        end
        for (go = 0; go < OUTPUTS; go = go + 1) begin : GEN_SIGMOID
            activation_unit #(.DATA_WIDTH(DATA_WIDTH), .FRAC_BITS(FRAC_BITS)) u_sigmoid (
                .act_sel(1'b1),
                .din (out_pre_flat[go*DATA_WIDTH +: DATA_WIDTH]),
                .dout(y_comb[go*DATA_WIDTH +: DATA_WIDTH])
            );
        end
    endgenerate

    reg [DATA_WIDTH*HIDDEN-1:0]  hidden_act_reg;
    reg [DATA_WIDTH*OUTPUTS-1:0] y_reg;

    always @(posedge clk) begin
        if (rst) begin
            hidden_act_reg <= {(DATA_WIDTH*HIDDEN){1'b0}};
            y_reg          <= {(DATA_WIDTH*OUTPUTS){1'b0}};
        end else begin
            if (act1_en) hidden_act_reg <= hidden_act_comb;
            if (act2_en) y_reg          <= y_comb;
        end
    end

    assign hidden_act_flat = hidden_act_reg;
    assign y_flat           = y_reg;

    wire [DATA_WIDTH*OUTPUTS-1:0] output_delta_flat;
    wire [DATA_WIDTH*HIDDEN-1:0]  hidden_delta_flat;
    wire bp_busy;
    wire bp_overflow_flag;

    backprop_engine #(
        .DATA_WIDTH(DATA_WIDTH), .FRAC_BITS(FRAC_BITS),
        .INPUTS(INPUTS), .HIDDEN(HIDDEN), .OUTPUTS(OUTPUTS)
    ) u_bp (
        .clk(clk), .rst(rst),
        .start_out_err(start_out_err),
        .start_hid_err(start_hid_err),
        .start_wupd(start_wupd),
        .lr_sel(lr_sel),
        .x_flat(x_flat), .hidden_act_flat(hidden_act_flat),
        .hidden_pre_flat(hidden_pre_flat),
        .y_flat(y_flat), .d_flat(d_flat),
        .w_layer_sel_b(w_layer_sel_b), .w_row_b(w_row_b), .w_col_b(w_col_b), .w_data_b(w_data_b),
        .we(we), .wr_layer_sel(wr_layer_sel), .wr_row(wr_row), .wr_col(wr_col), .wr_data(wr_data),
        .b_we(bp_b_we), .b_layer_sel(bp_b_layer_sel), .b_idx(bp_b_idx),
        .b_wr_data(bp_b_wr_data), .b_rd_data(bias_rd_data),
        .output_delta_flat(output_delta_flat),
        .hidden_delta_flat(hidden_delta_flat),
        .busy(bp_busy),
        .done_out_err(bp_done_out_err),
        .done_hid_err(bp_done_hid_err),
        .done_wupd(bp_done_wupd),
        .overflow_flag(bp_overflow_flag)
    );

    output_decoder #(
        .DATA_WIDTH(DATA_WIDTH), .OUTPUTS(OUTPUTS)
    ) u_outdec (
        .clk(clk), .rst(rst),
        .y_flat(y_flat),
        .training_active(training_active),
        .inference_active(inference_active),
        .done_flag(done_flag),
        .overflow_any(fwd_overflow_flag | bp_overflow_flag),
        .wupd_active(wupd_active),
        .fwd_pass_active(fwd_pass_active),
        .fsm_state(fsm_state),
        .led(led)
    );

endmodule
