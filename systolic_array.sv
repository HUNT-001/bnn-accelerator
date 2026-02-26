`timescale 1ns / 1ps
module systolic_array #(
    parameter integer NUM_PES   = 64,
    parameter integer WORD_SIZE = 64
)(
    input  wire                              clk,
    input  wire                              reset,
    input  wire                              ce,
    input  wire                              accumulate,
    
    // Each PE gets different weight row
    input  wire [NUM_PES*WORD_SIZE-1:0]     weights_flat,
    // All PEs get same activation (broadcast)
    input  wire [WORD_SIZE-1:0]             activation_broadcast,
    input  wire [WORD_SIZE-1:0]             mask_broadcast,
    
    // Each PE outputs its accumulated result
    output wire [NUM_PES*16-1:0]            results_flat
);
    localparam integer PCW = $clog2(WORD_SIZE+1);
    
    genvar i;
    generate
        for (i = 0; i < NUM_PES; i = i + 1) begin: pe_array
            systolic_pe #(
                .WORD_SIZE(WORD_SIZE)
            ) pe_inst (
                .clk(clk),
                .reset(reset),
                .ce(ce),
                .accumulate(accumulate),
                
                // Each PE gets its own weight row
                .weight_in(weights_flat[(i+1)*WORD_SIZE-1 : i*WORD_SIZE]),
                // All PEs get same activation (broadcast)
                .activation_in(activation_broadcast),
                .mask_in(mask_broadcast),
                
                .popcount_out(),  // Not used externally
                .accumulated_sum(results_flat[(i+1)*16-1 : i*16])
            );
        end
    endgenerate
    
endmodule
