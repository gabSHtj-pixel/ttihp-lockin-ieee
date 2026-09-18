// SPDX-License-Identifier: Apache-2.0
`default_nettype none
// Fase avanza SOLO cuando el nucleo acepta una muestra.
// Coseno y -seno: convencion I=A/2*cos(phi), Q=A/2*sin(phi).
module reference_generator (
    input wire clk, rst_n, clear, advance,
    input wire [15:0] phase_step,
    output wire signed [7:0] ref_i, ref_q
);
    reg [15:0] phase;
    wire [4:0] sine_address = phase[15:11];
    wire [4:0] cosine_address = sine_address + 5'd8;
    function signed [7:0] sine_lut;
        input [4:0] address;
        begin
            case (address)
                5'd0: sine_lut = 8'sd0;
                5'd1: sine_lut = 8'sd25;
                5'd2: sine_lut = 8'sd49;
                5'd3: sine_lut = 8'sd71;
                5'd4: sine_lut = 8'sd90;
                5'd5: sine_lut = 8'sd106;
                5'd6: sine_lut = 8'sd117;
                5'd7: sine_lut = 8'sd125;
                5'd8: sine_lut = 8'sd127;
                5'd9: sine_lut = 8'sd125;
                5'd10: sine_lut = 8'sd117;
                5'd11: sine_lut = 8'sd106;
                5'd12: sine_lut = 8'sd90;
                5'd13: sine_lut = 8'sd71;
                5'd14: sine_lut = 8'sd49;
                5'd15: sine_lut = 8'sd25;
                5'd16: sine_lut = 8'sd0;
                5'd17: sine_lut = -8'sd25;
                5'd18: sine_lut = -8'sd49;
                5'd19: sine_lut = -8'sd71;
                5'd20: sine_lut = -8'sd90;
                5'd21: sine_lut = -8'sd106;
                5'd22: sine_lut = -8'sd117;
                5'd23: sine_lut = -8'sd125;
                5'd24: sine_lut = -8'sd127;
                5'd25: sine_lut = -8'sd125;
                5'd26: sine_lut = -8'sd117;
                5'd27: sine_lut = -8'sd106;
                5'd28: sine_lut = -8'sd90;
                5'd29: sine_lut = -8'sd71;
                5'd30: sine_lut = -8'sd49;
                5'd31: sine_lut = -8'sd25;
                default: sine_lut = 8'sd0;
            endcase
        end
    endfunction
    assign ref_i = sine_lut(cosine_address);
    assign ref_q = -sine_lut(sine_address);
    always @(posedge clk) begin
        if (!rst_n) phase <= 16'd0;
        else if (clear) phase <= 16'd0;
        else if (advance) phase <= phase + phase_step;
    end
    wire _unused = &{phase[10:0], 1'b0};
endmodule
`default_nettype wire
