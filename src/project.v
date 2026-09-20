// SPDX-License-Identifier: Apache-2.0
`default_nettype none
module tt_um_gstj_lockin (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire signed [7:0] sample_signed = ui_in;
    wire [15:0] phase_step;
    wire [1:0] window_sel;
    wire sample_valid, clear, busy, accepted, new_result;
    wire [4:0] phase_index;
    wire result_write, result_is_q;
    wire signed [14:0] result_data;

    reference_generator refs (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .advance(accepted),
        .phase_step(phase_step),
        .phase_index(phase_index)
    );

    lockin_core core (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .enable(ena),
        .sample_valid(sample_valid),
        .sample(sample_signed),
        .phase_index(phase_index),
        .window_sel(window_sel),
        .busy(busy),
        .accepted(accepted),
        .result_write(result_write),
        .result_is_q(result_is_q),
        .result_data(result_data)
    );

    register_interface registers (
        .clk(clk),
        .rst_n(rst_n),
        .ena(ena),
        .data_in(ui_in),
        .address(uio_in[4:2]),
        .sample_strobe(uio_in[0]),
        .write_strobe(uio_in[1]),
        .snapshot_strobe(uio_in[5]),
        .busy(busy),
        .result_write(result_write),
        .result_is_q(result_is_q),
        .result_data(result_data),
        .sample_valid(sample_valid),
        .clear(clear),
        .phase_step(phase_step),
        .window_sel(window_sel),
        .read_data(uo_out),
        .new_result(new_result)
    );

    assign uio_out = {new_result, busy, 6'b0};
    assign uio_oe  = 8'b11000000;

    wire _unused = &{uio_in[7:6], 1'b0};
endmodule
`default_nettype wire
