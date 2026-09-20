// SPDX-License-Identifier: Apache-2.0
`default_nettype none
module tt_um_gstj_lockin (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input wire ena, clk, rst_n
);
    wire signed [7:0] sample_signed;
    assign sample_signed = ui_in;    
    wire [15:0] phase_step;
    wire [1:0] window_sel;
    wire sample_valid, clear, busy, accepted, result_valid, new_result;
    wire signed [7:0] ref_i, ref_q;
    wire signed [15:0] result_i, result_q;
    reference_generator refs (
        .clk(clk), .rst_n(rst_n), .clear(clear), .advance(accepted),
        .phase_step(phase_step), .ref_i(ref_i), .ref_q(ref_q)
    );
    lockin_core core (
        .clk(clk), .rst_n(rst_n), .clear(clear), .enable(ena),
        .sample_valid(sample_valid), .sample(sample_signed),
        .ref_i(ref_i), .ref_q(ref_q), .window_sel(window_sel),
        .busy(busy), .accepted(accepted),
        .result_i(result_i), .result_q(result_q), .result_valid(result_valid)
    );
    register_interface registers (
        .clk(clk), .rst_n(rst_n), .ena(ena), .data_in(ui_in),
        .address(uio_in[4:2]), .sample_strobe(uio_in[0]),
        .write_strobe(uio_in[1]), .snapshot_strobe(uio_in[5]),
        .busy(busy), .result_valid(result_valid),
        .result_i(result_i), .result_q(result_q),
        .sample_valid(sample_valid), .clear(clear),
        .phase_step(phase_step), .window_sel(window_sel),
        .read_data(uo_out), .new_result(new_result)
    );
    assign uio_out = {new_result,busy,6'b0};
    assign uio_oe = 8'b11000000;
    wire _unused = &{uio_in[7:6],1'b0};
endmodule
`default_nettype wire
