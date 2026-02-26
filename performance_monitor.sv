`timescale 1ns / 1ps

module performance_monitor #(
    parameter NUM_PES = 64,
    parameter WORD_SIZE = 64
)(
    input wire clk,
    input wire reset,
    input wire enable,  // Start monitoring
    
    // Signals from accelerator
    input wire [2:0] fsm_state,
    input wire       ce_array,
    input wire       accumulate,
    input wire [6:0] compute_count,
    
    // Per-PE monitoring
    input wire [NUM_PES-1:0] pe_active,  // Which PEs are computing
    
    // Outputs - Performance metrics
    output reg [31:0] total_cycles,
    output reg [31:0] compute_cycles,
    output reg [31:0] idle_cycles,
    output reg [31:0] stall_cycles,
    
    // Operations count
    output reg [63:0] total_xnor_ops,      // Total XNOR operations
    output reg [63:0] total_popcount_ops,  // Total popcount operations
    output reg [63:0] total_accumulations, // Total accumulations
    
    // Power estimation (activity factors)
    output reg [31:0] pe_active_cycles,    // Cycles where PEs were active
    output reg [31:0] sram_read_count,     // SRAM read operations
    output reg [31:0] sram_write_count,    // SRAM write operations
    
    // Utilization metrics
    output reg [15:0] avg_pe_utilization   // Percentage (0-10000 = 0-100.00%)
);

    // State encoding (must match accelerator_top)
    localparam S_IDLE    = 3'd0;
    localparam S_INIT    = 3'd1;
    localparam S_COMPUTE = 3'd2;
    localparam S_DONE    = 3'd3;
    
    // Cycle counters
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            total_cycles    <= 32'd0;
            compute_cycles  <= 32'd0;
            idle_cycles     <= 32'd0;
            stall_cycles    <= 32'd0;
        end else if (enable) begin
            total_cycles <= total_cycles + 1;
            
            case (fsm_state)
                S_IDLE:    idle_cycles    <= idle_cycles + 1;
                S_COMPUTE: compute_cycles <= compute_cycles + 1;
                S_INIT:    ; // Don't count init
                S_DONE:    ; // Don't count done
                default:   stall_cycles   <= stall_cycles + 1;
            endcase
        end
    end
    
    // Operations counters
    integer active_pe_count;
    integer i;
    
    always @(*) begin
        active_pe_count = 0;
        for (i = 0; i < NUM_PES; i = i + 1) begin
            active_pe_count = active_pe_count + pe_active[i];
        end
    end
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            total_xnor_ops      <= 64'd0;
            total_popcount_ops  <= 64'd0;
            total_accumulations <= 64'd0;
            pe_active_cycles    <= 32'd0;
            sram_read_count     <= 32'd0;
        end else if (enable && fsm_state == S_COMPUTE && ce_array) begin
            // Each PE does: 1 XNOR + 1 popcount per cycle
            total_xnor_ops     <= total_xnor_ops + (active_pe_count * WORD_SIZE);
            total_popcount_ops <= total_popcount_ops + active_pe_count;
            
            if (accumulate) begin
                total_accumulations <= total_accumulations + active_pe_count;
            end
            
            // SRAM reads: 1 activation + NUM_PES weights per cycle
            sram_read_count <= sram_read_count + (NUM_PES + 1);
            
            // Track PE activity
            if (|pe_active) begin
                pe_active_cycles <= pe_active_cycles + 1;
            end
        end
    end
    
    // Calculate average PE utilization (updated at end of computation)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            avg_pe_utilization <= 16'd0;
        end else if (fsm_state == S_DONE && enable) begin
            // Utilization = (active_cycles / total_cycles) * 100.00%
            // Multiply by 10000 for 2 decimal places
            if (total_cycles > 0) begin
                avg_pe_utilization <= (pe_active_cycles * 16'd10000) / total_cycles;
            end
        end
    end
    
endmodule
