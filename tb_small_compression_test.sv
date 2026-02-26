`timescale 1ns / 1ps
//==============================================================================
// Minimal test to isolate 1-bit computation
// Verifies XNOR-popcount logic works correctly
//==============================================================================
module tb_1bit_debug;
    parameter WORD_SIZE = 64;
    parameter CLOCK_PERIOD = 10;
    
    reg clk, reset, ce, accumulate, test_mode;
    reg [2:0] precision_mode;
    reg [WORD_SIZE-1:0] weight_in, activation_in, mask_in;
    wire [19:0] accumulated_sum;
    
    // Instantiate PE
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
        .clock_gated(),
        .computation_skipped(),
        .active_precision()
    );
    
    always #(CLOCK_PERIOD/2) clk = ~clk;
    
    // Corrected Manual computation function
    function integer manual_popcount;
        input [63:0] w, a, m;
        // Declarations must come BEFORE the 'begin' block in Verilog
        reg [63:0] xnor_res;
        integer i, cnt;
        begin
            xnor_res = ~(w ^ a) & m;
            cnt = 0;
            for (i = 0; i < 64; i = i + 1) begin
                cnt = cnt + xnor_res[i];
            end
            manual_popcount = cnt;
        end
    endfunction
    
    integer expected, actual;
    
    initial begin
        $display("=== 1-bit Doubling Debug ===\n");
        
        clk = 0;
        reset = 1;
        ce = 0;
        accumulate = 0;
        test_mode = 0;
        precision_mode = 3'b000;  // 1-bit mode
        mask_in = {64{1'b1}};
        
        repeat(3) @(posedge clk);
        reset = 0;
        @(posedge clk);
        
        // Test case: All 1s vs Alternating
        weight_in = 64'hFFFFFFFFFFFFFFFF;
        activation_in = 64'hAAAAAAAAAAAAAAAA;
        
        expected = manual_popcount(weight_in, activation_in, mask_in);
        $display("Test Setup:");
        $display("  weight     = 0x%h", weight_in);
        $display("  activation = 0x%h", activation_in);
        $display("  Expected popcount = %0d\n", expected);
        
        // Clear accumulator
        ce = 1;
        accumulate = 0;
        @(posedge clk);
        $display("After clear: accumulated_sum = %0d (expect 0)", accumulated_sum);
        
        if (accumulated_sum != 0) begin
            $display("ERROR: Did not clear!");
        end
        
        // Accumulate once
        accumulate = 1;
        @(posedge clk);
        actual = accumulated_sum;
        $display("After 1 accumulation: accumulated_sum = %0d (expect %0d)", actual, expected);
        
        if (actual == expected) begin
            $display("V CORRECT: Adding %0d per cycle", expected);
        end else if (actual == expected * 2) begin
            $display("X DOUBLING ERROR: Adding %0d instead of %0d", actual, expected);
            $display("  This means compute_result is returning %0d instead of %0d", actual, expected);
        end else begin
            $display("X UNKNOWN ERROR: Got %0d, expected %0d", actual, expected);
        end
        
        // Try one more accumulation
        @(posedge clk);
        $display("After 2 accumulations: accumulated_sum = %0d (expect %0d)", accumulated_sum, expected*2);
        
        // Now test with different pattern
        $display("\n--- Test with opposite activation pattern ---");
        activation_in = 64'h5555555555555555;  // Opposite of 0xAAAA
        expected = manual_popcount(weight_in, activation_in, mask_in);
        $display("  activation = 0x%h", activation_in);
        $display("  Expected popcount = %0d", expected);
        
        accumulate = 0;
        @(posedge clk);
        accumulate = 1;
        @(posedge clk);
        $display("  Result after 1 cycle = %0d (expect %0d)", accumulated_sum, expected);
        
        $display("\n=== Debug Complete ===");
        $finish;
    end
    
endmodule