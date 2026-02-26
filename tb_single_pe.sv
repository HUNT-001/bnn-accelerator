`timescale 1ns / 1ps

//==============================================================================
// Simple Debug Testbench for Multi-Precision PE
// Tests a single PE to verify basic functionality
//==============================================================================

module tb_single_pe_debug;
    parameter WORD_SIZE = 64;
    parameter CLOCK_PERIOD = 10;
    
    reg clk, reset, ce, accumulate, test_mode;
    reg [2:0] precision_mode;
    reg [WORD_SIZE-1:0] weight_in, activation_in, mask_in;
    wire [19:0] accumulated_sum;
    wire clock_gated, computation_skipped;
    
    // Instantiate single adaptive PE
    adaptive_pe #(
        .MAX_WIDTH(WORD_SIZE),
        .MAX_ACC_WIDTH(20)
    ) dut (
        .clk(clk),
        .reset(reset),
        .ce(ce),
        .accumulate(accumulate),
        .test_mode(test_mode),
        .precision_mode(precision_mode),
        .weight_in(weight_in),
        .activation_in(activation_in),
        .mask_in(mask_in),
        .accumulated_sum(accumulated_sum),
        .clock_gated(clock_gated),
        .computation_skipped(computation_skipped),
        .active_precision()
    );
    
    always #(CLOCK_PERIOD/2) clk = ~clk;
    
    integer cycle;
    
    initial begin
        $display("=======================================================");
        $display("=== Single PE Debug Test ===");
        $display("=======================================================");
        
        // Initialize
        clk = 0;
        reset = 1;
        ce = 0;
        accumulate = 0;
        test_mode = 0;
        precision_mode = 3'b000;
        weight_in = 64'h0;
        activation_in = 64'h0;
        mask_in = {WORD_SIZE{1'b1}};
        cycle = 0;
        
        repeat(3) @(posedge clk);
        reset = 0;
        @(posedge clk);
        
        //======================================================================
        // TEST 1: 1-bit mode simple test
        //======================================================================
        $display("\n[TEST 1] 1-bit BNN - Simple Pattern");
        precision_mode = 3'b000;
        
        // First cycle: Initialize (accumulate=0)
        ce = 1;
        accumulate = 0;
        weight_in = 64'hFFFFFFFFFFFFFFFF;  // All 1s
        activation_in = 64'hAAAAAAAAAAAAAAAA;  // Alternating
        @(posedge clk);
        $display("Cycle %0d: acc=0, result=%0d (expect: 0)", cycle++, accumulated_sum);
        
        // Accumulate for 3 cycles
        accumulate = 1;
        repeat(3) begin
            @(posedge clk);
            $display("Cycle %0d: acc=1, result=%0d (expect: 32 per cycle)", cycle++, accumulated_sum);
        end
        
        $display("Final accumulated sum: %0d (expected: 96)", accumulated_sum);
        
        @(posedge clk);
        ce = 0;
        repeat(2) @(posedge clk);
        
        //======================================================================
        // TEST 2: 2-bit mode
        //======================================================================
        $display("\n[TEST 2] 2-bit Mode - Simple Pattern");
        precision_mode = 3'b001;
        cycle = 0;
        
        // Initialize
        ce = 1;
        accumulate = 0;
        weight_in = {32{2'b11}};  // All 3s
        activation_in = {32{2'b10}};  // All 2s
        @(posedge clk);
        $display("Cycle %0d: acc=0, result=%0d (expect: 0)", cycle++, accumulated_sum);
        
        // Accumulate for 2 cycles
        accumulate = 1;
        repeat(2) begin
            @(posedge clk);
            $display("Cycle %0d: acc=1, result=%0d (expect: 192 per cycle)", cycle++, accumulated_sum);
        end
        
        $display("Final accumulated sum: %0d (expected: 384)", accumulated_sum);
        
        @(posedge clk);
        ce = 0;
        repeat(2) @(posedge clk);
        
        //======================================================================
        // TEST 3: 4-bit mode
        //======================================================================
        $display("\n[TEST 3] 4-bit Mode - Simple Pattern");
        precision_mode = 3'b010;
        cycle = 0;
        
        // Initialize
        ce = 1;
        accumulate = 0;
        weight_in = {16{4'hF}};  // All 15s
        activation_in = {16{4'h8}};  // All 8s
        @(posedge clk);
        $display("Cycle %0d: acc=0, result=%0d (expect: 0)", cycle++, accumulated_sum);
        
        // Accumulate for 2 cycles
        accumulate = 1;
        repeat(2) begin
            @(posedge clk);
            $display("Cycle %0d: acc=1, result=%0d (expect: 1920 per cycle)", cycle++, accumulated_sum);
        end
        
        $display("Final accumulated sum: %0d (expected: 3840)", accumulated_sum);
        
        @(posedge clk);
        ce = 0;
        repeat(2) @(posedge clk);
        
        //======================================================================
        // TEST 4: 8-bit mode
        //======================================================================
        $display("\n[TEST 4] 8-bit Mode - Simple Pattern");
        precision_mode = 3'b011;
        cycle = 0;
        
        // Initialize
        ce = 1;
        accumulate = 0;
        weight_in = {8{8'hFF}};  // All 255s
        activation_in = {8{8'h80}};  // All 128s
        @(posedge clk);
        $display("Cycle %0d: acc=0, result=%0d (expect: 0)", cycle++, accumulated_sum);
        
        // Accumulate for 2 cycles
        accumulate = 1;
        repeat(2) begin
            @(posedge clk);
            $display("Cycle %0d: acc=1, result=%0d (expect: 261120 per cycle)", cycle++, accumulated_sum);
        end
        
        $display("Final accumulated sum: %0d (expected: 522240)", accumulated_sum);
        
        $display("\n=======================================================");
        $display("Debug test complete!");
        $display("Check if results match expected values.");
        $display("=======================================================\n");
        
        #100;
        $finish;
    end
    
endmodule