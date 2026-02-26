`timescale 1ns / 1ps
// Systolic PE: performs XNOR-popcount and accumulates
module systolic_pe #(
    parameter integer WORD_SIZE = 64
)(
    input  wire                         clk,
    input  wire                         reset,
    input  wire                         ce,
    input  wire                         accumulate,  // 1=accumulate, 0=reset
    
    input  wire [WORD_SIZE-1:0]         weight_in,
    input  wire [WORD_SIZE-1:0]         activation_in,
    input  wire [WORD_SIZE-1:0]         mask_in,
    
    output reg  [$clog2(WORD_SIZE+1)-1:0] popcount_out,
    output reg  [15:0]                   accumulated_sum  // 16-bit accumulator
);
    localparam integer PCW = $clog2(WORD_SIZE+1);
    
    // XNOR and popcount (same as before)
    wire [WORD_SIZE-1:0] xnor_result = ~(weight_in ^ activation_in) & mask_in;
    
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
    
    wire [PCW-1:0] pc_current = popcount64(xnor_result);
    
    // Pipeline popcount
    always @(posedge clk or posedge reset) begin
        if (reset)
            popcount_out <= {PCW{1'b0}};
        else if (ce)
            popcount_out <= pc_current;
    end
    
    // Accumulator
    always @(posedge clk or posedge reset) begin
        if (reset)
            accumulated_sum <= 16'd0;
        else if (ce) begin
            if (accumulate)
                accumulated_sum <= accumulated_sum + popcount_out;
            else
                accumulated_sum <= 16'd0;  // Reset accumulator
        end
    end
    
endmodule
