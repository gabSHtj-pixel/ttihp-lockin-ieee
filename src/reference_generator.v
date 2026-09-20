// SPDX-License-Identifier: Apache-2.0
`default_nettype none
module reference_generator (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,
    input  wire        advance,
    input  wire [15:0] phase_step,
    output wire [4:0]  phase_index
);
    reg [15:0] phase;

    assign phase_index = phase[15:11];

    always @(posedge clk) begin
        if (!rst_n)
            phase <= 16'd0;
        else if (clear)
            phase <= 16'd0;
        else if (advance)
            phase <= phase + phase_step;
    end
endmodule
`default_nettype wire
