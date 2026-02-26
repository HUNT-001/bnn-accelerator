`timescale 1ns / 1ps

//==============================================================================
// Standard Integrated Clock Gating Cell (ICG)
// Industry-standard latch-based clock gate to prevent glitches
//==============================================================================
module clock_gate_cell (
    input  wire clk,
    input  wire enable,
    input  wire test_enable,  // For DFT (Design-For-Test) bypass
    output wire gated_clk
);
    reg enable_latched;
    
    // Latch enable on negative edge (low phase) to avoid glitches
    // This is the industry-standard clock gating pattern
    always @(*) begin
        if (!clk)
            enable_latched = enable | test_enable;
    end
    
    // AND gate to produce gated clock
    assign gated_clk = clk & enable_latched;
    
endmodule