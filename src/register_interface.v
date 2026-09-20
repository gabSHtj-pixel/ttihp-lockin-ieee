// SPDX-License-Identifier: Apache-2.0
`default_nettype none
module register_interface (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               ena,
    input  wire [7:0]         data_in,
    input  wire [2:0]         address,
    input  wire               sample_strobe,
    input  wire               write_strobe,
    input  wire               snapshot_strobe,
    input  wire               busy,
    input  wire               result_write,
    input  wire               result_is_q,
    input  wire signed [14:0] result_data,
    output wire               sample_valid,
    output wire               clear,
    output reg  [15:0]        phase_step,
    output reg  [1:0]         window_sel,
    output reg  [7:0]         read_data,
    output reg                new_result
);
    reg prev_sample, prev_write, prev_snapshot;
    reg signed [14:0] snapshot_i, snapshot_q;
    reg overrun;

    wire write_event = ena && write_strobe && !prev_write;
    wire snapshot_event = ena && snapshot_strobe && !prev_snapshot;
    wire sample_event = ena && sample_strobe && !prev_sample;

    assign clear = write_event && (
                   (address == 3'd4) ||
                   (address == 3'd5) ||
                   (address == 3'd6) ||
                   ((address == 3'd7) && data_in[0]));

    assign sample_valid = sample_event && !clear && !write_event;

    always @(posedge clk) begin
        if (!rst_n) begin
            prev_sample    <= 1'b0;
            prev_write     <= 1'b0;
            prev_snapshot  <= 1'b0;
            phase_step     <= 16'h1000;
            window_sel     <= 2'd2;
            snapshot_i     <= 15'sd0;
            snapshot_q     <= 15'sd0;
            new_result     <= 1'b0;
            overrun        <= 1'b0;
        end else begin
            prev_sample   <= sample_strobe;
            prev_write    <= write_strobe;
            prev_snapshot <= snapshot_strobe;

            if (write_event) begin
                case (address)
                    3'd4: phase_step[7:0]  <= data_in;
                    3'd5: phase_step[15:8] <= data_in;
                    3'd6: window_sel       <= data_in[1:0];
                    default: begin end
                endcase
            end

            if (clear) begin
                snapshot_i <= 15'sd0;
                snapshot_q <= 15'sd0;
                new_result <= 1'b0;
                overrun    <= 1'b0;
            end else begin
                if (sample_valid && busy)
                    overrun <= 1'b1;

                // Core writes I then Q on consecutive clocks. NEW_RESULT is
                // asserted only after Q is stored, so software never sees a
                // half-updated pair as a completed result.
                if (result_write) begin
                    if (result_is_q) begin
                        snapshot_q <= result_data;
                        new_result <= 1'b1;
                    end else begin
                        snapshot_i <= result_data;
                    end
                end

                // ACK: data stays latched, only the sticky flag is cleared.
                // If ACK coincides with a new Q result, ACK wins; the new pair
                // is already safely stored and is considered consumed.
                if (snapshot_event)
                    new_result <= 1'b0;
            end
        end
    end

    always @* begin
        case (address)
            3'd0: read_data = snapshot_i[7:0];
            3'd1: read_data = {snapshot_i[14], snapshot_i[14:8]};
            3'd2: read_data = snapshot_q[7:0];
            3'd3: read_data = {snapshot_q[14], snapshot_q[14:8]};
            3'd4: read_data = phase_step[7:0];
            3'd5: read_data = phase_step[15:8];
            3'd6: read_data = {6'b0, window_sel};
            3'd7: read_data = {5'b0, overrun, new_result, busy};
            default: read_data = 8'b0;
        endcase
    end

    wire _unused = &{data_in[7:2], 1'b0};
endmodule
`default_nettype wire
