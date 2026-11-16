/*
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

/*
 * 2-FF synchronizer for asynchronous inputs (buttons). Output lags the input
 * by two clocks.
 */
module input_sync #(
    parameter WIDTH = 4
) (
    input  wire             clk,
    input  wire             rst_n,

    input  wire [WIDTH-1:0] async_in,
    output wire [WIDTH-1:0] sync_out
);

    reg [WIDTH-1:0] meta_q;
    reg [WIDTH-1:0] sync_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            meta_q <= {WIDTH{1'b0}};
            sync_q <= {WIDTH{1'b0}};
        end else begin
            meta_q <= async_in;
            sync_q <= meta_q;
        end
    end

    assign sync_out = sync_q;

endmodule
