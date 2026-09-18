// SPDX-License-Identifier: Apache-2.0
`default_nettype none
// Interfaz SINCRONICA. Strobes se reconocen una vez por flanco ascendente.
// Direccion y bus deben cumplir setup/hold a clk. No es SPI ni I2C.
module register_interface (
    input wire clk, rst_n, ena,
    input wire [7:0] data_in,
    input wire [2:0] address,
    input wire sample_strobe, write_strobe, snapshot_strobe,
    input wire busy, result_valid,
    input wire signed [15:0] result_i, result_q,
    output wire sample_valid, clear,
    output reg [15:0] phase_step,
    output reg [1:0] window_sel,
    output reg [7:0] read_data,
    output reg new_result
);
    reg prev_sample, prev_write, prev_snapshot;
    reg signed [15:0] snapshot_i, snapshot_q;
    reg overrun;
    wire write_event = ena && write_strobe && !prev_write;
    wire snapshot_event = ena && snapshot_strobe && !prev_snapshot;
    wire sample_event = ena && sample_strobe && !prev_sample;
    assign clear = write_event && ((address==3'd4) || (address==3'd5) ||
                   (address==3'd6) || ((address==3'd7) && data_in[0]));
    assign sample_valid = sample_event && !clear && !write_event;
    always @(posedge clk) begin
        if (!rst_n) begin
            prev_sample<=0; prev_write<=0; prev_snapshot<=0;
            phase_step<=16'h1000; window_sel<=2'd2;
            snapshot_i<=0; snapshot_q<=0; new_result<=0; overrun<=0;
        end else begin
            prev_sample<=sample_strobe; prev_write<=write_strobe;
            prev_snapshot<=snapshot_strobe;
            if (write_event) begin
                case (address)
                    3'd4: phase_step[7:0]<=data_in;
                    3'd5: phase_step[15:8]<=data_in;
                    3'd6: window_sel<=data_in[1:0];
                    default: begin end
                endcase
            end
            if (clear) begin
                snapshot_i<=0; snapshot_q<=0; new_result<=0; overrun<=0;
            end else begin
                if (sample_valid && busy) overrun<=1;
                if (result_valid) new_result<=1;
                // Captura atomica; resultado nuevo simultaneo se considera leido.
                if (snapshot_event) begin
                    snapshot_i<=result_i; snapshot_q<=result_q; new_result<=0;
                end
            end
        end
    end
    always @* begin
        case (address)
            3'd0: read_data=snapshot_i[7:0];
            3'd1: read_data=snapshot_i[15:8];
            3'd2: read_data=snapshot_q[7:0];
            3'd3: read_data=snapshot_q[15:8];
            3'd4: read_data=phase_step[7:0];
            3'd5: read_data=phase_step[15:8];
            3'd6: read_data={6'b0,window_sel};
            3'd7: read_data={5'b0,overrun,new_result,busy};
            default: read_data=8'b0;
        endcase
    end
    wire _unused = &{data_in[7:2],1'b0};
endmodule
`default_nettype wire
