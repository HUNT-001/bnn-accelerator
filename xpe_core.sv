`timescale 1ns / 1ps
module xpe_core #(
    parameter integer WORD_SIZE       = 64,
    parameter integer PIPELINE        = 1,   // 0=comb, 1=one-stage reg
    parameter integer HAS_MASK        = 1
)(
    input  wire [WORD_SIZE-1:0] weight_word_in,
    input  wire [WORD_SIZE-1:0] activation_word_in,
    input  wire [WORD_SIZE-1:0] valid_mask_in,  // set bits=1 for valid positions when HAS_MASK=1
    input  wire                  clk,
    input  wire                  ce,    // clock enable for optional pipeline
    output reg  [$clog2(WORD_SIZE+1)-1:0] popcount_out
);
    localparam integer PCW = $clog2(WORD_SIZE+1);

    wire [WORD_SIZE-1:0] xnor_result_raw = ~(weight_word_in ^ activation_word_in);
    wire [WORD_SIZE-1:0] xnor_result     = (HAS_MASK) ? (xnor_result_raw & valid_mask_in) : xnor_result_raw;

    // Balanced adder tree popcount
    function [PCW-1:0] popcount64;
        input [WORD_SIZE-1:0] v;
        integer j;
        reg [PCW-1:0] s;
        begin
            s = {PCW{1'b0}};
            for (j = 0; j < WORD_SIZE; j = j + 1) begin
                s = s + v[j];
            end
            popcount64 = s;
        end
    endfunction

    wire [PCW-1:0] pc_comb = popcount64(xnor_result);

    generate
        if (PIPELINE != 0) begin : gen_pipe
            always @(posedge clk) begin
                if (ce) popcount_out <= pc_comb;
            end
        end else begin : gen_comb
            always @(*) begin
                popcount_out = pc_comb;
            end
        end
    endgenerate
endmodule