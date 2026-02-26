`timescale 1ns / 1ps

//==============================================================================
// Conv2 Hardware Bring-Up Test
// Single Output Channel (OC=0), Single Position (0,0)
// Verifies hardware matches software golden reference
//==============================================================================

module tb_conv2_bringup;
    
    //==========================================================================
    // Parameters (must match accelerator_top)
    //==========================================================================
    localparam WORD_SIZE = 64;
    localparam NUM_PES = 64;
    localparam SRAM_DEPTH = 64;
    localparam IDX_SENTINEL = 7'h7F;  // CRITICAL: Must match Python export (0x7F)
    localparam MAX_OUT_CH = 128;
    localparam ACC_WIDTH = 32;
    localparam CLOCK_PERIOD = 10;
    
    // Conv2 test configuration - UPDATE THESE FROM YOUR METADATA!
    localparam NUM_TILES = 18;        // From conv2_metadata.txt
    localparam EXPECTED_RESULT = 0;   // UPDATE with your golden result!
    
    //==========================================================================
    // DUT Signals
    //==========================================================================
    reg clk, reset, test_mode;
    reg start;
    wire done;
    reg [2:0] precision_mode;
    reg sparse_mode;
    
    // Compressed write interface
    reg wr_compressed;
    reg [5:0] wr_comp_row;
    reg [5:0] wr_comp_idx;
    reg [5:0] wr_comp_ptr;
    reg [WORD_SIZE-1:0] wr_comp_val;
    
    // Results
    wire [NUM_PES*20-1:0] results_out;
    
    // Output SRAM access (for reading final result)
    wire [ACC_WIDTH-1:0] out_sram_read_data;
    reg [7:0] out_sram_read_addr;
    
    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    accelerator_top #(
        .WORD_SIZE(WORD_SIZE),
        .NUM_PES(NUM_PES),
        .SRAM_DEPTH(SRAM_DEPTH),
        .IDX_SENTINEL(IDX_SENTINEL),
        .MAX_OUT_CH(MAX_OUT_CH),
        .ACC_WIDTH(ACC_WIDTH),
        .ENABLE_SPARSITY(1),
        .ENABLE_MULTI_PRECISION(1),
        .ENABLE_SPARSE_SCHED(0),  // Use dense mode for this test
        .ENABLE_COMPRESSION(1),   // MUST be enabled!
        .ENABLE_LAYER_EXEC(0)     // Manual tile control
    ) dut (
        .clk(clk),
        .reset(reset),
        
        // Single tile interface
        .start(start),
        .done(done),
        
        .test_mode(test_mode),
        .precision_mode(precision_mode),
        .sparse_mode(sparse_mode),
        
        // Compressed write interface
        .wr_en(1'b0),  // Not used
        .wr_pe_idx(6'd0),
        .wr_addr(6'd0),
        .wr_data(64'd0),
        .wr_type(1'b0),
        
        .wr_compressed(wr_compressed),
        .wr_comp_row(wr_comp_row),
        .wr_comp_idx(wr_comp_idx),
        .wr_comp_ptr(wr_comp_ptr),
        .wr_comp_val(wr_comp_val),
        
        // Results
        .results_out(results_out),
        
        // Output SRAM access
        .out_sram_read_data(out_sram_read_data),
        .out_sram_read_addr(out_sram_read_addr),
        
        // Monitoring (not used in this test)
        .mon_enable(1'b0),
        .mon_total_cycles(),
        .mon_compute_cycles(),
        .mon_idle_cycles(),
        .mon_total_ops(),
        .mon_total_accumulations(),
        .mon_sram_reads(),
        .mon_utilization(),
        .clocks_gated(),
        .mon_clocks_saved(),
        .mon_power_reduction(),
        .computations_skipped(),
        .mon_computations_skipped(),
        .mon_sparsity_power_reduction(),
        .mon_active_columns(),
        .mon_column_sparsity(),
        
        // Layer execution (not used)
        .layer_start(1'b0),
        .layer_done(),
        .cfg_num_out_tiles(8'd0),
        .cfg_num_col_tiles(8'd0),
        .cfg_precision_mode(3'd0),
        .cfg_sparse_mode(1'b0),
        .cfg_tile_start(8'd0),
        .tile_weights_ready(1'b0),
        .tile_acts_ready(1'b0),
        .mon_current_row_tile(),
        .mon_current_col_tile(),
        .mon_tiles_completed()
    );
    
    always #(CLOCK_PERIOD/2) clk = ~clk;
    
    //==========================================================================
    // Task: Load One Tile from Files
    //==========================================================================
    task load_tile_from_files;
        input integer tile_id;
        
        // File paths - ADJUST if your files are in a different location
        string idx_file, val_file, act_file;
        
        // Memory arrays to hold file data
        reg [7:0]  idx_mem [0:63];
        reg [63:0] val_mem [0:63];
        reg [63:0] act_mem [0:63];
        
        integer i, j;
        integer nz_count;
        
        begin
            // Construct file paths
            $sformatf(idx_file, "conv2_row000_tile%03d_idx.hex", tile_id);
            $sformatf(val_file, "conv2_row000_tile%03d_val.hex", tile_id);
            $sformatf(act_file, "conv2_input_pos0_tile%03d.hex", tile_id);
            
            // Read files into memory
            $readmemh(idx_file, idx_mem);
            $readmemh(val_file, val_mem);
            $readmemh(act_file, act_mem);
            
            // Load compressed weights via write interface
            wr_compressed = 1;
            nz_count = 0;
            
            // Load all 64 column indices and their values
            for (i = 0; i < SRAM_DEPTH; i = i + 1) begin
                wr_comp_row = 6'd0;  // PE row 0 (for OC=0)
                wr_comp_idx = i[5:0];
                
                // Get index value
                wr_comp_ptr = idx_mem[i][5:0];
                
                // If not sentinel, get corresponding value
                if (idx_mem[i] != 8'h7F) begin
                    wr_comp_val = val_mem[idx_mem[i]];
                    nz_count = nz_count + 1;
                end else begin
                    wr_comp_val = 64'h0;  // Don't care, won't be used
                end
                
                @(posedge clk);
            end
            
            wr_compressed = 0;
            @(posedge clk);
            
            // Load activations directly into activation SRAM
            for (i = 0; i < SRAM_DEPTH; i = i + 1) begin
                dut.activation_sram[i] = act_mem[i];
            end
            
            $display("  [%0t] Loaded tile %0d: %0d non-zero weights", 
                     $time, tile_id, nz_count);
        end
    endtask
    
    //==========================================================================
    // Task: Process One Tile
    //==========================================================================
    task process_tile;
        input integer tile_id;
        integer tile_result;
        begin
            // Load tile data
            load_tile_from_files(tile_id);
            
            // Start tile processing
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;
            
            // Wait for completion
            wait(done == 1);
            @(posedge clk);
            
            // Extract result from PE 0
            tile_result = results_out[19:0];  // PE 0's result
            
            // Accumulate into output SRAM
            dut.out_sram[0] = dut.out_sram[0] + tile_result;
            
            $display("  [%0t]   Tile result: %0d, Accumulator: %0d", 
                     $time, tile_result, dut.out_sram[0]);
            
            @(posedge clk);
        end
    endtask
    
    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    integer t;
    integer final_result;
    
    initial begin
        $display("\n");
        $display("=================================================================");
        $display("===  Conv2 Hardware Bring-Up Test                             ===");
        $display("=================================================================");
        $display("Target:   Conv2, Output Channel 0, Position (0,0)");
        $display("Tiles:    %0d tiles × 64 columns = %0d total columns", 
                 NUM_TILES, NUM_TILES * 64);
        $display("Expected: %0d (from software golden reference)", EXPECTED_RESULT);
        $display("=================================================================\n");
        
        // Initialize signals
        clk = 0;
        reset = 1;
        start = 0;
        test_mode = 0;
        precision_mode = 3'b000;  // 1-bit mode
        sparse_mode = 0;          // Dense mode (process all 64 columns)
        
        wr_compressed = 0;
        wr_comp_row = 0;
        wr_comp_idx = 0;
        wr_comp_ptr = 0;
        wr_comp_val = 0;
        
        out_sram_read_addr = 0;
        
        // Reset sequence
        repeat(5) @(posedge clk);
        reset = 0;
        repeat(3) @(posedge clk);
        
        // Clear output accumulator for OC=0
        dut.out_sram[0] = 32'd0;
        
        $display("Starting tile processing...\n");
        
        // Process all tiles sequentially
        for (t = 0; t < NUM_TILES; t = t + 1) begin
            $display("[Tile %0d/%0d]", t, NUM_TILES-1);
            process_tile(t);
        end
        
        // Read final accumulated result
        @(posedge clk);
        final_result = dut.out_sram[0];
        
        // Display results
        $display("\n");
        $display("=================================================================");
        $display("===  RESULTS                                                  ===");
        $display("=================================================================");
        $display("Hardware Result:  %0d", final_result);
        $display("Expected Result:  %0d", EXPECTED_RESULT);
        
        if (EXPECTED_RESULT != 0) begin
            $display("Difference:       %0d", final_result - EXPECTED_RESULT);
            
            if (final_result == EXPECTED_RESULT) begin
                $display("\n✅ PASS: Hardware matches software golden reference!");
                $display("=================================================================");
                $display("\n🎉 Conv2 bring-up successful!");
                $display("   Your hardware correctly processes real BNN model data.");
                $display("   Ready to scale to:");
                $display("     • All output channels (0-127)");
                $display("     • All spatial positions");
                $display("     • Other layers (Conv3-Conv6)");
            end else begin
                $display("\n❌ FAIL: Mismatch detected!");
                $display("=================================================================");
                display_debug_info();
            end
        end else begin
            $display("\n⚠️  WARNING: EXPECTED_RESULT not set in testbench!");
            $display("   Update EXPECTED_RESULT parameter with value from:");
            $display("   E:\\hardware_exports\\conv2_metadata.txt");
        end
        
        $display("\nSimulation Time: %0t", $time);
        $display("=================================================================\n");
        
        #1000;
        $finish;
    end
    
    //==========================================================================
    // Debug Information Display
    //==========================================================================
    task display_debug_info;
        integer ch;
        begin
            $display("\n🔍 Debug Information:");
            $display("─────────────────────────────────────────────────────────────");
            
            // Check per-tile results
            $display("\nPer-Tile Results:");
            $display("  (Run simulation again with detailed tile monitoring)");
            
            // Check accumulator
            $display("\nAccumulator Status:");
            for (ch = 0; ch < 8; ch = ch + 1) begin
                if (dut.out_sram[ch] != 0) begin
                    $display("  out_sram[%0d] = %0d", ch, dut.out_sram[ch]);
                end
            end
            
            // Common issues checklist
            $display("\n✓ Checklist:");
            $display("  1. Are all 18 .hex files in the simulation directory?");
            $display("  2. Is IDX_SENTINEL = 7'h7F in both Python and Verilog?");
            $display("  3. Does EXPECTED_RESULT match conv2_metadata.txt?");
            $display("  4. Is ENABLE_COMPRESSION = 1 in DUT?");
            $display("  5. Are tiles processed in order (0 → 17)?");
            $display("  6. Does accumulator persist between tiles?");
            $display("─────────────────────────────────────────────────────────────");
        end
    endtask
    
endmodule