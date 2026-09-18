// SPDX-License-Identifier: Apache-2.0
`default_nettype none
// Doble demodulacion con UN multiplicador reutilizado.
// Filtro: promedio por bloques de 16,64,256,1024 muestras.
module lockin_core (
    input wire clk, rst_n, clear, enable, sample_valid,
    input wire signed [7:0] sample, ref_i, ref_q,
    input wire [1:0] window_sel,
    output wire busy, accepted,
    output reg signed [15:0] result_i, result_q,
    output reg result_valid
);
    localparam IDLE=2'd0, MIX_I=2'd1, MIX_Q=2'd2;
    reg [1:0] state;
    reg signed [7:0] sample_hold, i_hold, q_hold;
    reg signed [25:0] sum_i, sum_q;
    reg [9:0] sample_count;
    wire signed [7:0] reference = state==MIX_I ? i_hold : q_hold;
    wire signed [15:0] product = sample_hold * reference;
    wire signed [25:0] extended_product = $signed({{10{product[15]}}, product});
    wire signed [25:0] accumulator = state==MIX_I ? sum_i : sum_q;
    wire signed [25:0] next_sum = accumulator + extended_product;
    wire [3:0] shift_count = 4'd4 + {1'b0,window_sel,1'b0};
    wire [9:0] last_count = window_sel==0 ? 10'd15 :
                            window_sel==1 ? 10'd63 :
                            window_sel==2 ? 10'd255 : 10'd1023;
    wire signed [25:0] averaged_i = sum_i >>> shift_count;
    wire signed [25:0] averaged_q = next_sum >>> shift_count;
    assign busy = state!=IDLE;
    assign accepted = rst_n && enable && !clear && !busy && sample_valid;
    always @(posedge clk) begin
        if (!rst_n) begin
            state<=IDLE; sample_hold<=0; i_hold<=0; q_hold<=0;
            sum_i<=0; sum_q<=0; sample_count<=0;
            result_i<=0; result_q<=0; result_valid<=0;
        end else if (clear) begin
            state<=IDLE; sample_hold<=0; i_hold<=0; q_hold<=0;
            sum_i<=0; sum_q<=0; sample_count<=0;
            result_i<=0; result_q<=0; result_valid<=0;
        end else begin
            result_valid<=0;
            if (enable) begin
                case (state)
                    IDLE: if (sample_valid) begin
                        sample_hold<=sample; i_hold<=ref_i; q_hold<=ref_q;
                        state<=MIX_I;
                    end
                    MIX_I: begin sum_i<=next_sum; state<=MIX_Q; end
                    MIX_Q: begin
                        state<=IDLE;
                        if (sample_count==last_count) begin
                            result_i<=$signed(averaged_i[15:0]); result_q<=$signed(averaged_q[15:0]);
                            result_valid<=1;
                            sum_i<=0; sum_q<=0; sample_count<=0;
                        end else begin
                            sum_q<=next_sum; sample_count<=sample_count+1'b1;
                        end
                    end
                    default: state<=IDLE;
                endcase
            end
        end
    end
    // Promedios siempre caben en 16 bits por rango de operandos y ventana.
    wire _unused = &{averaged_i[25:16],averaged_q[25:16],1'b0};
endmodule
`default_nettype wire