`timescale 1ns / 1ps

//==============================================================================
// Adaptive Multi-Precision Processing Element
//
// Supports dynamic bit-width computation:
//   - 1-bit: 64 parallel XNOR-popcount operations (BNN mode)
//   - 2-bit: 32 parallel 2×2 multiplications
//   - 4-bit: 16 parallel 4×4 multiplications
//   - 8-bit: 8 parallel 8×8 multiplications
//
// Features:
//   - Zero-skipping for all precision modes
//   - Clock gating for power optimization
//   - 20-bit accumulator supports up to 1M accumulations
//   - Maintains sparsity benefits across all precisions
//==============================================================================

module adaptive_pe #(
    parameter integer MAX_WIDTH = 64,
    parameter integer MAX_ACC_WIDTH = 20  // Support up to 1M accumulations
)(
    input  wire                         clk,
    input  wire                         reset,
    input  wire                         ce,
    input  wire                         accumulate,
    input  wire                         test_mode,
    
    // Precision control
    input  wire [2:0]                   precision_mode,
    // 000 = 1-bit (64 parallel ops)
    // 001 = 2-bit (32 parallel ops)  
    // 010 = 4-bit (16 parallel ops)
    // 011 = 8-bit (8 parallel ops)
    
    // Data inputs
    input  wire [MAX_WIDTH-1:0]         weight_in,
    input  wire [MAX_WIDTH-1:0]         activation_in,
    input  wire [MAX_WIDTH-1:0]         mask_in,
    
    // Outputs
    output reg  [MAX_ACC_WIDTH-1:0]     accumulated_sum,
    
    // Power monitoring
    output wire                         clock_gated,
    output wire                         computation_skipped,
    output wire [2:0]                   active_precision  // For monitoring
);

    //==========================================================================
    // Precision Configuration
    //==========================================================================
    
    reg [6:0] active_bits;      // How many bits are active
    reg [5:0] parallel_ops;     // How many parallel operations
    reg [8:0] max_value;        // Maximum value per operation
    
    always @(*) begin
        case (precision_mode)
            3'b000: begin  // 1-bit BNN
                active_bits = 7'd64;
                parallel_ops = 6'd64;
                max_value = 9'd1;
            end
            3'b001: begin  // 2-bit
                active_bits = 7'd64;
                parallel_ops = 6'd32;
                max_value = 9'd3;
            end
            3'b010: begin  // 4-bit
                active_bits = 7'd64;
                parallel_ops = 6'd16;
                max_value = 9'd15;
            end
            3'b011: begin  // 8-bit
                active_bits = 7'd64;
                parallel_ops = 6'd8;
                max_value = 9'd255;
            end
            default: begin  // Default to 1-bit
                active_bits = 7'd64;
                parallel_ops = 6'd64;
                max_value = 9'd1;
            end
        endcase
    end
    
    assign active_precision = precision_mode;
    
    //==========================================================================
    // Sparsity Detection
    //==========================================================================
    
    wire weight_is_zero, activation_is_zero;
    wire weight_is_sparse, activation_is_sparse;
    
    sparse_detector #(
        .WORD_SIZE(MAX_WIDTH)
    ) weight_detector (
        .data_in(weight_in),
        .is_zero(weight_is_zero),
        .is_sparse(weight_is_sparse)
    );
    
    sparse_detector #(
        .WORD_SIZE(MAX_WIDTH)
    ) activation_detector (
        .data_in(activation_in),
        .is_zero(activation_is_zero),
        .is_sparse(activation_is_sparse)
    );
    
    wire skip_compute = weight_is_zero || activation_is_zero;
    assign computation_skipped = skip_compute && ce;
    
    //==========================================================================
    // Clock Gating
    //==========================================================================
    
    wire pe_enable = ce && !skip_compute;
    wire gated_clk;
    
    clock_gate_cell icg (
        .clk(clk),
        .enable(pe_enable),
        .test_enable(test_mode),
        .gated_clk(gated_clk)
    );
    
    assign clock_gated = !pe_enable;
    
    //==========================================================================
    // Multi-Precision Computation Engine
    //==========================================================================
    
    // Result from computation (max 20 bits for accumulation)
    reg [MAX_ACC_WIDTH-1:0] compute_result;
    
    always @(*) begin
        case (precision_mode)
            3'b000: compute_result = compute_1bit();
            3'b001: compute_result = compute_2bit();
            3'b010: compute_result = compute_4bit();
            3'b011: compute_result = compute_8bit();
            default: compute_result = {MAX_ACC_WIDTH{1'b0}};
        endcase
    end
    
    //==========================================================================
    // 1-bit BNN Computation (XNOR-Popcount)
    //==========================================================================
    
    function [MAX_ACC_WIDTH-1:0] compute_1bit;
        reg [MAX_WIDTH-1:0] xnor_result;
        integer i, count;
        begin
            xnor_result = ~(weight_in ^ activation_in) & mask_in;
            count = 0;
            for (i = 0; i < MAX_WIDTH; i = i + 1) begin
                count = count + xnor_result[i];
            end
            compute_1bit = count[MAX_ACC_WIDTH-1:0];
        end
    endfunction
    
    //==========================================================================
    // 2-bit Computation (32 parallel 2-bit multiplications)
    //==========================================================================
    
    function [MAX_ACC_WIDTH-1:0] compute_2bit;
        integer i;
        reg [1:0] w, a;
        reg [3:0] product;
        integer sum;
        begin
            sum = 0;
            for (i = 0; i < 32; i = i + 1) begin
                w = weight_in[i*2 +: 2];
                a = activation_in[i*2 +: 2];
                product = w * a;  // 2-bit × 2-bit = max 4-bit result
                sum = sum + product;
            end
            compute_2bit = sum[MAX_ACC_WIDTH-1:0];
        end
    endfunction
    
    //==========================================================================
    // 4-bit Computation (16 parallel 4-bit multiplications)
    //==========================================================================
    
    function [MAX_ACC_WIDTH-1:0] compute_4bit;
        integer i;
        reg [3:0] w, a;
        reg [7:0] product;
        integer sum;
        begin
            sum = 0;
            for (i = 0; i < 16; i = i + 1) begin
                w = weight_in[i*4 +: 4];
                a = activation_in[i*4 +: 4];
                product = w * a;  // 4-bit × 4-bit = max 8-bit result
                sum = sum + product;
            end
            compute_4bit = sum[MAX_ACC_WIDTH-1:0];
        end
    endfunction
    
    //==========================================================================
    // 8-bit Computation (8 parallel 8-bit multiplications)
    //==========================================================================
    
    function [MAX_ACC_WIDTH-1:0] compute_8bit;
        integer i;
        reg [7:0] w, a;
        reg [15:0] product;
        integer sum;
        begin
            sum = 0;
            for (i = 0; i < 8; i = i + 1) begin
                w = weight_in[i*8 +: 8];
                a = activation_in[i*8 +: 8];
                product = w * a;  // 8-bit × 8-bit = max 16-bit result
                sum = sum + product;
            end
            compute_8bit = sum[MAX_ACC_WIDTH-1:0];
        end
    endfunction
    
    //==========================================================================
    // Accumulator
    //==========================================================================
    
    always @(posedge gated_clk or posedge reset) begin
        if (reset) begin
            accumulated_sum <= {MAX_ACC_WIDTH{1'b0}};
        end else begin
            if (!accumulate) begin
                accumulated_sum <= {MAX_ACC_WIDTH{1'b0}};
            end else begin
                accumulated_sum <= accumulated_sum + compute_result;
            end
        end
    end
    
endmodule