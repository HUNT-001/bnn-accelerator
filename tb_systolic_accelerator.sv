`timescale 1ns / 1ps
module tb_systolic_accelerator;
    localparam WORD_SIZE = 64;
    localparam NUM_PES = 64;
    localparam SRAM_DEPTH = 64;
    
    reg clk, reset, start;
    wire done;
    reg wr_en;
    reg [5:0] wr_pe_idx, wr_addr;
    reg [WORD_SIZE-1:0] wr_data;
    reg wr_type;
    wire [NUM_PES*16-1:0] results_out;
    
    accelerator_top #(
        .WORD_SIZE(WORD_SIZE),
        .NUM_PES(NUM_PES),
        .SRAM_DEPTH(SRAM_DEPTH)
    ) dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(done),
        .wr_en(wr_en),
        .wr_pe_idx(wr_pe_idx),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .wr_type(wr_type),
        .results_out(results_out)
    );
    
    always #5 clk = ~clk;
    
    integer i, j;
    integer pe, col;
    
    initial begin
        $display("=== Systolic Array Matrix-Vector Multiply Test ===");
        clk = 0;
        reset = 1;
        start = 0;
        wr_en = 0;
        wr_pe_idx = 0;
        wr_addr = 0;
        wr_data = 0;
        wr_type = 0;
        
        repeat(2) @(posedge clk);
        reset = 0;
        
        // Load identity matrix for simple test
        // Weight[i][j] = (i==j) ? all 1s : all 0s
        $display("Loading identity weight matrix...");
        wr_en = 1;
        wr_type = 0;
        
        for (pe = 0; pe < NUM_PES; pe = pe + 1) begin
            for (col = 0; col < SRAM_DEPTH; col = col + 1) begin
                wr_pe_idx = pe;
                wr_addr = col;
                // Identity: diagonal = all 1s, off-diagonal = 0
                if (pe == col)
                    wr_data = {WORD_SIZE{1'b1}};  // All 1s
                else
                    wr_data = {WORD_SIZE{1'b0}};  // All 0s
                @(posedge clk);
            end
        end
        
        // Load test activation vector
        $display("Loading activation vector...");
        wr_type = 1;
        for (i = 0; i < SRAM_DEPTH; i = i + 1) begin
            wr_addr = i;
            // Simple pattern: alternating bits
            wr_data = (i % 2 == 0) ? 64'hAAAAAAAAAAAAAAAA : 64'h5555555555555555;
            @(posedge clk);
        end
        
        wr_en = 0;
        $display("Data loaded. Starting computation...");
        
        // Start computation
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Wait for completion
        wait(done == 1);
        @(posedge clk);
        
        $display("\n=== RESULTS ===");
        $display("Matrix-Vector multiplication complete!");
        
        // Display first few results
        for (i = 0; i < 8; i = i + 1) begin
            $display("Output[%0d] = %0d", i, results_out[i*16 +: 16]);
        end
        
        $display("\nExpected: Identity matrix × vector = same vector");
        $display("For alternating pattern, each output should be 32 (half of 64 bits match)");
        
        #100;
        $finish;
    end
    
endmodule
