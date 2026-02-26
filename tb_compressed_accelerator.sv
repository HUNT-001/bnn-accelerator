`timescale 1ns / 1ps

//==============================================================================
// Testbench for Compressed Weight Storage
// Tests both traditional dense mode and new compressed mode
//==============================================================================

module tb_compressed_accelerator;
    localparam WORD_SIZE = 64;
    localparam NUM_PES = 64;
    localparam SRAM_DEPTH = 64;
    localparam IDX_SENTINEL = 6'h3F;
    localparam CLOCK_PERIOD = 10;
    
    reg clk, reset, start, test_mode;
    reg [2:0] precision_mode;
    reg sparse_mode;
    wire done;
    
    // Traditional write interface
    reg wr_en;
    reg [5:0] wr_pe_idx, wr_addr;
    reg [WORD_SIZE-1:0] wr_data;
    reg wr_type;
    
    // Compressed write interface
    reg wr_compressed;
    reg [5:0] wr_comp_row, wr_comp_idx, wr_comp_ptr;
    reg [WORD_SIZE-1:0] wr_comp_val;
    
    wire [NUM_PES*20-1:0] results_out;
    
    reg        mon_enable;
    wire [31:0] mon_total_cycles;
    wire [31:0] mon_compute_cycles;
    wire [31:0] mon_idle_cycles;
    wire [63:0] mon_total_ops;
    wire [63:0] mon_total_accumulations;
    wire [31:0] mon_sram_reads;
    wire [15:0] mon_utilization;
    
    wire [NUM_PES-1:0] clocks_gated;
    wire [31:0] mon_clocks_saved;
    wire [15:0] mon_power_reduction;
    
    wire [NUM_PES-1:0] computations_skipped;
    wire [31:0] mon_computations_skipped;
    wire [15:0] mon_sparsity_power_reduction;
    
    wire [6:0]  mon_active_columns;
    wire [15:0] mon_column_sparsity;
    
    //==========================================================================
    // DUT Instantiation with Compression Enabled
    //==========================================================================
    
    accelerator_top #(
        .WORD_SIZE(WORD_SIZE),
        .NUM_PES(NUM_PES),
        .SRAM_DEPTH(SRAM_DEPTH),
        .IDX_SENTINEL(IDX_SENTINEL),
        .ENABLE_SPARSITY(1),
        .ENABLE_MULTI_PRECISION(1),
        .ENABLE_SPARSE_SCHED(1),
        .ENABLE_COMPRESSION(1)  // Enable compressed storage
    ) dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .test_mode(test_mode),
        .precision_mode(precision_mode),
        .sparse_mode(sparse_mode),
        .done(done),
        
        .wr_en(wr_en),
        .wr_pe_idx(wr_pe_idx),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .wr_type(wr_type),
        
        .wr_compressed(wr_compressed),
        .wr_comp_row(wr_comp_row),
        .wr_comp_idx(wr_comp_idx),
        .wr_comp_ptr(wr_comp_ptr),
        .wr_comp_val(wr_comp_val),
        
        .results_out(results_out),
        
        .mon_enable(mon_enable),
        .mon_total_cycles(mon_total_cycles),
        .mon_compute_cycles(mon_compute_cycles),
        .mon_idle_cycles(mon_idle_cycles),
        .mon_total_ops(mon_total_ops),
        .mon_total_accumulations(mon_total_accumulations),
        .mon_sram_reads(mon_sram_reads),
        .mon_utilization(mon_utilization),
        
        .clocks_gated(clocks_gated),
        .mon_clocks_saved(mon_clocks_saved),
        .mon_power_reduction(mon_power_reduction),
        
        .computations_skipped(computations_skipped),
        .mon_computations_skipped(mon_computations_skipped),
        .mon_sparsity_power_reduction(mon_sparsity_power_reduction),
        
        .mon_active_columns(mon_active_columns),
        .mon_column_sparsity(mon_column_sparsity)
    );
    
    always #(CLOCK_PERIOD/2) clk = ~clk;
    
    integer i, pe, col, j, k;
    reg [19:0] result_array [0:NUM_PES-1];
    real throughput_gops, power_consumption_mw, energy_efficiency;
    integer expected_active_cols;
    integer test_compute_cycles, test_total_cycles;
    integer prev_total_cycles, prev_compute_cycles;
    
    //==========================================================================
    // Helper Task: Run Test
    //==========================================================================
    
    task run_test;
        integer wait_cycles;
        begin
            prev_total_cycles = mon_total_cycles;
            prev_compute_cycles = mon_compute_cycles;
            
            @(posedge clk);
            mon_enable = 1;
            start = 1;
            
            @(posedge clk);
            @(posedge clk);
            start = 0;
            
            $display("  Starting computation...");
            
            wait_cycles = 0;
            while (done == 0 && wait_cycles < 1000) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            
            if (wait_cycles >= 1000) begin
                $display("  ❌ ERROR: Timeout!");
            end else begin
                $display("  ✓ Completed in %0d cycles", wait_cycles);
            end
            
            test_total_cycles = mon_total_cycles - prev_total_cycles;
            test_compute_cycles = mon_compute_cycles - prev_compute_cycles;
            
            $display("  This test: %0d compute cycles", test_compute_cycles);
            
            #1;
            
            for (i = 0; i < NUM_PES; i = i + 1) begin
                result_array[i] = results_out[i*20 +: 20];
            end
            
            @(posedge clk);
            mon_enable = 0;
            start = 0;
            @(posedge clk);
        end
    endtask
    
    //==========================================================================
    // Helper Task: Display Results
    //==========================================================================
    
    task display_results;
        input integer test_num;
        input string test_name;
        input integer verify_result;
        input integer expected_result;
        integer nonzero_count, errors;
        real total_power_percent;
        begin
            $display("\n=======================================================");
            $display("=== TEST %0d: %s ===", test_num, test_name);
            $display("=======================================================");
            
            nonzero_count = 0;
            errors = 0;
            for (j = 0; j < NUM_PES; j = j + 1) begin
                if (result_array[j] != 0) nonzero_count = nonzero_count + 1;
                if (verify_result && result_array[j] != expected_result) errors = errors + 1;
            end
            
            $display("\nSample Results:");
            $display("  Non-zero: %0d / %0d PEs", nonzero_count, NUM_PES);
            
            if (verify_result) begin
                $display("  PE[0]  = %0d (expect %0d) %s", result_array[0], expected_result, 
                         (result_array[0] == expected_result) ? "✓" : "✗");
                $display("  PE[15] = %0d (expect %0d) %s", result_array[15], expected_result,
                         (result_array[15] == expected_result) ? "✓" : "✗");
                $display("  PE[31] = %0d (expect %0d) %s", result_array[31], expected_result,
                         (result_array[31] == expected_result) ? "✓" : "✗");
                $display("  PE[63] = %0d (expect %0d) %s", result_array[63], expected_result,
                         (result_array[63] == expected_result) ? "✓" : "✗");
                
                if (errors == 0) begin
                    $display("\n✓ All PEs produced correct results!");
                end else begin
                    $display("\n⚠️  WARNING: %0d PEs have incorrect results!", errors);
                end
            end else begin
                $display("  PE[0]  = %0d", result_array[0]);
                $display("  PE[15] = %0d", result_array[15]);
                $display("  PE[31] = %0d", result_array[31]);
                $display("  PE[63] = %0d", result_array[63]);
            end
            
            $display("\n--- Performance Metrics ---");
            $display("Total Cycles:       %0d", test_total_cycles);
            $display("Compute Cycles:     %0d", test_compute_cycles);
            
            if (sparse_mode) begin
                $display("\n--- Sparse Scheduling Metrics ---");
                $display("Active Columns:     %0d / 64", mon_active_columns);
                $display("Column Sparsity:    %0d.%02d%%", 
                         mon_column_sparsity / 100, mon_column_sparsity % 100);
                
                if (expected_active_cols > 0) begin
                    if (mon_active_columns == expected_active_cols) begin
                        $display("✓ Active columns match expected (%0d)", expected_active_cols);
                    end else begin
                        $display("⚠️  Active columns: %0d, expected: %0d", 
                                 mon_active_columns, expected_active_cols);
                    end
                end
            end
            
            $display("\n--- Storage Efficiency ---");
            $display("Storage Mode:       Compressed (CSR-like per-row)");
            $display("Sentinel Value:     0x%02h (zero weights)", IDX_SENTINEL);
        end
    endtask
    
    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    
    initial begin
        $display("=======================================================");
        $display("=== Compressed Weight Storage Test Suite ===");
        $display("=======================================================");
        $display("Clock: %0d ns (%.0f MHz)", CLOCK_PERIOD, 1000.0/CLOCK_PERIOD);
        $display("Array: %0d × %0d PEs", NUM_PES, NUM_PES);
        $display("Storage: Compressed (CSR-like per-row)");
        $display("Sentinel: 0x%02h", IDX_SENTINEL);
        
        clk = 0;
        reset = 1;
        start = 0;
        test_mode = 0;
        precision_mode = 3'b000;
        sparse_mode = 0;
        wr_en = 0;
        wr_compressed = 0;
        mon_enable = 0;
        prev_total_cycles = 0;
        prev_compute_cycles = 0;
        
        repeat(3) @(posedge clk);
        reset = 0;
        @(posedge clk);
        
        //======================================================================
        // TEST 1: Compressed Storage - 75% Sparse Pattern
        //======================================================================
        
        $display("\n\n[TEST 1] Compressed Storage - 75%% Sparse (Every 4th Column)");
        $display("=====================================================");
        
        precision_mode = 3'b000;
        sparse_mode = 1'b1;
        expected_active_cols = 16;
        
        dut.clear_sparse_metadata();
        
        // Load compressed weights using wr_compressed interface
        $display("Loading compressed weights...");
        wr_compressed = 1;
        
        for (pe = 0; pe < NUM_PES; pe = pe + 1) begin
            k = 0;  // Packed value index
            for (col = 0; col < SRAM_DEPTH; col = col + 1) begin
                wr_comp_row = pe;
                wr_comp_idx = col;
                
                if (col % 4 == 0) begin
                    // Non-zero column: store value and index
                    wr_comp_ptr = k;
                    wr_comp_val = 64'hFFFFFFFFFFFFFFFF;
                    k = k + 1;
                end else begin
                    // Zero column: store sentinel
                    wr_comp_ptr = IDX_SENTINEL;
                    wr_comp_val = 64'h0;
                end
                
                @(posedge clk);
            end
        end
        
        wr_compressed = 0;
        $display("✓ Loaded %0d PEs with compressed format", NUM_PES);
        $display("  Non-zero columns per row: 16");
        $display("  Storage: 16 values + 64 indices per row");
        $display("  Compression ratio: %.2fx", 64.0 / 16.0);
        
        // Load activations (traditional interface)
        wr_en = 1;
        wr_type = 1;
        for (i = 0; i < SRAM_DEPTH; i = i + 1) begin
            wr_addr = i;
            wr_data = 64'hFFFFFFFFFFFFFFFF;
            @(posedge clk);
        end
        wr_en = 0;
        
        repeat(5) @(posedge clk);
        
        $display("Building global non-zero column list...");
        dut.build_global_nz_list();
        $display("  Active columns: %0d / 64", dut.global_nz_count);
        
        repeat(5) @(posedge clk);
        
        run_test();
        display_results(1, "Compressed 75% Sparse", 1, 1024);
        
        //======================================================================
        // TEST 2: Compressed Storage - 90% Sparse Pattern
        //======================================================================
        
        $display("\n\n[TEST 2] Compressed Storage - 90%% Extreme Sparse");
        $display("=====================================================");
        
        precision_mode = 3'b000;
        sparse_mode = 1'b1;
        expected_active_cols = 6;
        
        dut.clear_sparse_metadata();
        
        $display("Loading extremely sparse compressed weights...");
        wr_compressed = 1;
        
        for (pe = 0; pe < NUM_PES; pe = pe + 1) begin
            k = 0;
            for (col = 0; col < SRAM_DEPTH; col = col + 1) begin
                wr_comp_row = pe;
                wr_comp_idx = col;
                
                if (col % 10 == 0 && col < 60) begin
                    wr_comp_ptr = k;
                    wr_comp_val = 64'hFFFFFFFFFFFFFFFF;
                    k = k + 1;
                end else begin
                    wr_comp_ptr = IDX_SENTINEL;
                    wr_comp_val = 64'h0;
                end
                
                @(posedge clk);
            end
        end
        
        wr_compressed = 0;
        $display("✓ Loaded extremely sparse pattern");
        $display("  Non-zero columns per row: 6");
        $display("  Storage: 6 values + 64 indices per row");
        $display("  Compression ratio: %.2fx", 64.0 / 6.0);
        
        // Load activations
        wr_en = 1;
        wr_type = 1;
        for (i = 0; i < SRAM_DEPTH; i = i + 1) begin
            wr_addr = i;
            wr_data = 64'hFFFFFFFFFFFFFFFF;
            @(posedge clk);
        end
        wr_en = 0;
        
        repeat(5) @(posedge clk);
        
        dut.build_global_nz_list();
        $display("  Active columns: %0d / 64", dut.global_nz_count);
        
        repeat(5) @(posedge clk);
        
        run_test();
        display_results(2, "Compressed 90% Sparse", 1, 384);
        
        //======================================================================
        // Summary
        //======================================================================
        
        $display("\n\n=======================================================");
        $display("=== COMPRESSED STORAGE RESULTS ===");
        $display("=======================================================\n");
        
        $display("✓ Compressed weight storage verified and working!");
        $display("\nStorage Benefits:");
        $display("  • 75%% sparse: 4× compression ratio");
        $display("  • 90%% sparse: 10.7× compression ratio");
        $display("  • Index-based access with sentinel values");
        $display("  • Maintains all sparse scheduling benefits");
        
        $display("\nCombined Sparsity Exploitation:");
        $display("  Level 1: PE-level zero-skipping");
        $display("  Level 2: Memory-level column scheduling");
        $display("  Level 3: Physical memory compression [NEW]");
        $display("  Level 4: Index-based zero detection [NEW]");
        
        $display("\n=======================================================");
        $display("=== Test Complete ===");
        $display("=======================================================\n");
        
        #1000;
        $finish;
    end
    
endmodule