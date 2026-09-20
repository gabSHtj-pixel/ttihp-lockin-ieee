// SPDX-License-Identifier: Apache-2.0
`default_nettype none
module lockin_core (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               clear,
    input  wire               enable,
    input  wire               sample_valid,
    input  wire signed [7:0]  sample,
    input  wire [4:0]         phase_index,
    input  wire [1:0]         window_sel,
    output wire               busy,
    output wire               accepted,
    output wire               result_write,
    output wire               result_is_q,
    output wire signed [14:0] result_data
);
    localparam [2:0] IDLE  = 3'd0;
    localparam [2:0] MIX_I = 3'd1;
    localparam [2:0] MIX_Q = 3'd2;
    localparam [2:0] AVG_I = 3'd3;
    localparam [2:0] AVG_Q = 3'd4;

    reg [2:0] state;
    reg signed [7:0] sample_hold;
    reg [4:0] phase_hold;

    // Worst case: 1024 * 128 * 127 = 16,646,144.
    // Signed 25-bit range is -16,777,216 .. +16,777,215, so 25 bits is exact.
    reg signed [24:0] sum_i, sum_q;
    reg [9:0] sample_count;

    // Serial constant/reference multiply state.  The signed sample (with the
    // reference sign applied) is shifted while the reference magnitude is
    // consumed LSB-first.  Partial products are accumulated directly into the
    // 25-bit I/Q sum, avoiding a separate multiplier/product accumulator.
    reg signed [14:0] serial_term;
    reg [6:0] serial_coef;
    reg [2:0] serial_bit;

    // ---- Compact exact 32-point sine LUT ---------------------------------
    // Fold the 32 phases into nine non-negative magnitudes (0..8) and apply
    // the half-cycle sign.  Values are identical to the original 32-entry LUT.
    wire [4:0] cosine_address = phase_index + 5'd8;
    wire use_q_reference = (state == MIX_I);
    wire [4:0] lut_address = use_q_reference ? phase_hold : cosine_address;
    wire [3:0] lut_pos = lut_address[3:0];
    wire [3:0] lut_mag_index = lut_pos[3] ? (4'd0 - lut_pos) : lut_pos;

    reg [6:0] lut_magnitude;
    always @* begin
        case (lut_mag_index)
            4'd0: lut_magnitude = 7'd0;
            4'd1: lut_magnitude = 7'd25;
            4'd2: lut_magnitude = 7'd49;
            4'd3: lut_magnitude = 7'd71;
            4'd4: lut_magnitude = 7'd90;
            4'd5: lut_magnitude = 7'd106;
            4'd6: lut_magnitude = 7'd117;
            4'd7: lut_magnitude = 7'd125;
            4'd8: lut_magnitude = 7'd127;
            default: lut_magnitude = 7'd0;
        endcase
    end

    // Sine sign is the half-cycle MSB. Q=-sin(phi), so Q simply flips
    // that sign. Zero magnitude makes the sign don't-care.
    wire selected_reference_sign = lut_address[4] ^ use_q_reference;
    wire [6:0] reference_magnitude = lut_magnitude;

    wire signed [14:0] sample_now_ext = {{7{sample[7]}}, sample};
    wire signed [14:0] sample_hold_ext = {{7{sample_hold[7]}}, sample_hold};
    wire signed [14:0] start_term_idle = selected_reference_sign
                                       ? -sample_now_ext : sample_now_ext;
    wire signed [14:0] start_term_q = selected_reference_sign
                                    ? -sample_hold_ext : sample_hold_ext;

    wire signed [24:0] term_extended = {{10{serial_term[14]}}, serial_term};
    wire signed [24:0] active_sum = (state == MIX_I) ? sum_i : sum_q;
    wire signed [24:0] mix_next = serial_coef[0]
                                ? (active_sum + term_extended)
                                : active_sum;

    // Window end test written as reductions rather than a 10-bit variable
    // comparator/mux tree.
    reg last_sample;
    always @* begin
        case (window_sel)
            2'd0: last_sample = &sample_count[3:0];
            2'd1: last_sample = &sample_count[5:0];
            2'd2: last_sample = &sample_count[7:0];
            default: last_sample = &sample_count[9:0];
        endcase
    end
    wire signed [24:0] average_source = (state == AVG_I) ? sum_i : sum_q;
    reg signed [14:0] average_value;
    always @* begin
        case (window_sel)
            2'd0: average_value = average_source[18:4];
            2'd1: average_value = average_source[20:6];
            2'd2: average_value = average_source[22:8];
            default: average_value = average_source[24:10];
        endcase
    end

    assign busy = (state != IDLE);
    assign accepted = rst_n && enable && !clear && (state == IDLE) && sample_valid;
    assign result_write = (state == AVG_I) || (state == AVG_Q);
    assign result_is_q = (state == AVG_Q);
    assign result_data = average_value;

    always @(posedge clk) begin
        if (!rst_n) begin
            state        <= IDLE;
            sample_hold  <= 8'sd0;
            phase_hold   <= 5'd0;
            sum_i        <= 25'sd0;
            sum_q        <= 25'sd0;
            sample_count <= 10'd0;
            serial_term  <= 15'sd0;
            serial_coef  <= 7'd0;
            serial_bit   <= 3'd0;
        end else if (clear) begin
            state        <= IDLE;
            sample_hold  <= 8'sd0;
            phase_hold   <= 5'd0;
            sum_i        <= 25'sd0;
            sum_q        <= 25'sd0;
            sample_count <= 10'd0;
            serial_term  <= 15'sd0;
            serial_coef  <= 7'd0;
            serial_bit   <= 3'd0;
        end else if (enable) begin
            case (state)
                IDLE: begin
                    if (sample_valid) begin
                        sample_hold <= sample;
                        phase_hold  <= phase_index;
                        serial_term <= start_term_idle;
                        serial_coef <= reference_magnitude;
                        serial_bit  <= 3'd0;
                        state       <= MIX_I;
                    end
                end

                MIX_I: begin
                    sum_i <= mix_next;
                    if (serial_bit == 3'd6) begin
                        // Reuse the same serial datapath for Q.
                        serial_term <= start_term_q;
                        serial_coef <= reference_magnitude;
                        serial_bit  <= 3'd0;
                        state       <= MIX_Q;
                    end else begin
                        serial_term <= serial_term <<< 1;
                        serial_coef <= serial_coef >> 1;
                        serial_bit  <= serial_bit + 3'd1;
                    end
                end

                MIX_Q: begin
                    sum_q <= mix_next;
                    if (serial_bit == 3'd6) begin
                        serial_bit <= 3'd0;
                        if (last_sample) begin
                            // sum_i already contains this sample; mix_next is
                            // the corresponding completed Q sum.
                            sum_q <= mix_next;
                            state <= AVG_I;
                        end else begin
                            sample_count <= sample_count + 10'd1;
                            state <= IDLE;
                        end
                    end else begin
                        serial_term <= serial_term <<< 1;
                        serial_coef <= serial_coef >> 1;
                        serial_bit  <= serial_bit + 3'd1;
                    end
                end

                AVG_I: begin
                    state <= AVG_Q;
                end

                AVG_Q: begin
                    // register_interface captures result_data on both AVG
                    // cycles.  Clear the block only after Q has been captured.
                    sum_i        <= 25'sd0;
                    sum_q        <= 25'sd0;
                    sample_count <= 10'd0;
                    state        <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
