`timescale 1ns / 1ps
module pe_array #(
    parameter integer ROWS      = 8,
    parameter integer COLS      = 8,
    parameter integer WORD_SIZE = 64,
    parameter integer PIPELINE  = 1
)(
    input  wire                         clk,
    input  wire                         ce,
    input  wire [ROWS*COLS*WORD_SIZE-1:0] weights_in_flat,
    input  wire [ROWS*COLS*WORD_SIZE-1:0] activations_in_flat,
    input  wire [ROWS*COLS*WORD_SIZE-1:0] valid_mask_flat,
    output wire [ROWS*COLS*$clog2(WORD_SIZE+1)-1:0] popcounts_out_flat
);
    localparam integer NUM_PES = ROWS*COLS;
    localparam integer PCW     = $clog2(WORD_SIZE+1);

    genvar i;
    generate
        for (i = 0; i < NUM_PES; i = i + 1) begin : pe_gen
            xpe_core #(
                .WORD_SIZE (WORD_SIZE),
                .PIPELINE  (PIPELINE),
                .HAS_MASK  (1)
            ) xpe_i (
                .weight_word_in     (weights_in_flat     [ (i+1)*WORD_SIZE-1 : i*WORD_SIZE ]),
                .activation_word_in (activations_in_flat [ (i+1)*WORD_SIZE-1 : i*WORD_SIZE ]),
                .valid_mask_in      (valid_mask_flat     [ (i+1)*WORD_SIZE-1 : i*WORD_SIZE ]),
                .clk                (clk),
                .ce                 (ce),
                .popcount_out       (popcounts_out_flat  [ (i+1)*PCW-1 : i*PCW ])
            );
        end
    endgenerate
endmodule