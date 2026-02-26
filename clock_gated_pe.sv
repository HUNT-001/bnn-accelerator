
`timescale 1ns / 1ps

//==============================================================================
// Clock-Gated Processing Element (PE) for BNN Accelerator
// 
// This module implements a binary neural network processing element with
// integrated clock gating for power optimization.
//
// Operation:
//   - Computes XNOR-popcount on 64-bit weight and activation vectors
//   - Accumulates results over multiple cycles
//   - Clock is gated when PE is not enabled (ce=0)
//
// Power Savings:
//   - Clock gating saves 20-40% dynamic power in idle/disabled states
//   - Combinational logic (XNOR, popcount) remains active for zero-delay
//==============================================================================

module clock_gated_pe #(
    parameter integer WORD_SIZE = 64
)(
    // Clock and control
    input  wire                              clk,
    input  wire                              reset,
    input  wire                              ce,          // Clock enable
    input  wire                              accumulate,  // 1=accumulate, 0=reset
    input  wire                              test_mode,   // DFT bypass
    
    // Data inputs
    input  wire [WORD_SIZE-1:0]              weight_in,
    input  wire [WORD_SIZE-1:0]              activation_in,
    input  wire [WORD_SIZE-1:0]              mask_in,
    
    // Data outputs
    output reg  [$clog2(WORD_SIZE+1)-1:0]    popcount_out,
    output reg  [15:0]                       accumulated_sum,
    
    // Power monitoring
    output wire                              clock_gated
);

    localparam integer PCW = $clog2(WORD_SIZE+1);  // Popcount width = 7 bits
    
    //==========================================================================
    // Clock Gating Logic
    //==========================================================================
    
    wire pe_enable = ce;  // Enable when clock-enabled
    wire gated_clk;
    
    // Instantiate industry-standard clock gate cell
    clock_gate_cell icg (
        .clk(clk),
        .enable(pe_enable),
        .test_enable(test_mode),  // Bypass for DFT
        .gated_clk(gated_clk)
    );
    
    // Report when clock is gated (active low logic)
    assign clock_gated = !pe_enable;
    
    //==========================================================================
    // Combinational XNOR-Popcount Logic
    // 
    // This logic is always active (not clock-gated) to provide zero-delay
    // computation path. Power is saved by gating the downstream registers.
    //==========================================================================
    
    // XNOR operation: matches = ~(A XOR B) & mask
    wire [WORD_SIZE-1:0] xnor_result = ~(weight_in ^ activation_in) & mask_in;
    
    // Popcount function: count number of 1s
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
    
    // Compute popcount (combinational - always active)
    wire [PCW-1:0] pc_comb = popcount64(xnor_result);
    
    //==========================================================================
    // Sequential Logic (Uses Gated Clock)
    //
    // These registers use the gated clock to save power when PE is disabled.
    // The 'ce' check is removed since clock gating handles enable logic.
    //==========================================================================
    
    // Pipeline register for popcount (for external observation if needed)
    always @(posedge gated_clk or posedge reset) begin
        if (reset)
            popcount_out <= {PCW{1'b0}};
        else
            popcount_out <= pc_comb;
    end
    
    // Accumulator register (main computational state)
    always @(posedge gated_clk or posedge reset) begin
        if (reset)
            accumulated_sum <= 16'd0;
        else begin
            if (!accumulate)
                accumulated_sum <= 16'd0;  // Reset accumulator
            else
                accumulated_sum <= accumulated_sum + pc_comb;  // Accumulate
        end
    end
    
endmodule