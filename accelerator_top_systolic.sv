`timescale 1ns / 1ps
module accelerator_top #(
    parameter integer WORD_SIZE  = 64,
    parameter integer NUM_PES    = 64,
    parameter integer SRAM_DEPTH = 64
)(
    input  wire                   clk,
    input  wire                   reset,
    input  wire                   start,
    output reg                    done,

    // Write interface for loading weights (64×64 matrix)
    input  wire                   wr_en,
    input  wire [5:0]             wr_pe_idx,    // Which PE (0-63)
    input  wire [5:0]             wr_addr,      // Which column (0-63)
    input  wire [WORD_SIZE-1:0]   wr_data,
    input  wire                   wr_type,      // 0=weights, 1=activations
    
    // Output results
    output reg  [NUM_PES*16-1:0]  results_out
);

    // Weight SRAM: 64 PEs × 64 words × 64 bits
    reg [WORD_SIZE-1:0] weight_sram [0:NUM_PES-1][0:SRAM_DEPTH-1];
    
    // Activation SRAM: 64 words × 64 bits
    reg [WORD_SIZE-1:0] activation_sram [0:SRAM_DEPTH-1];
    
    // Write logic
    always @(posedge clk) begin
        if (wr_en) begin
            if (wr_type == 1'b0)
                weight_sram[wr_pe_idx][wr_addr] <= wr_data;
            else
                activation_sram[wr_addr] <= wr_data;
        end
    end
    
    // FSM
    localparam [2:0] S_IDLE   = 3'd0,
                     S_INIT   = 3'd1,
                     S_COMPUTE = 3'd2,
                     S_DONE   = 3'd3;
    reg [2:0] state, nstate;
    
    reg [7:0] col_idx;        // Which column (0-63)
    reg       ce_array;
    reg       accumulate;
    
    // Flatten weight matrix (current column)
    wire [NUM_PES*WORD_SIZE-1:0] weights_flat;
    genvar k;
    generate
        for (k = 0; k < NUM_PES; k = k + 1) begin: weight_feed
            assign weights_flat[(k+1)*WORD_SIZE-1 : k*WORD_SIZE] = 
                   weight_sram[k][col_idx];
        end
    endgenerate
    
    // Current activation (broadcast to all PEs)
    wire [WORD_SIZE-1:0] activation_broadcast = activation_sram[col_idx];
    wire [WORD_SIZE-1:0] mask_broadcast = {WORD_SIZE{1'b1}};
    
    // Results
    wire [NUM_PES*16-1:0] results_flat;
    
    // Instantiate systolic array
    systolic_array #(
        .NUM_PES(NUM_PES),
        .WORD_SIZE(WORD_SIZE)
    ) sys_array (
        .clk(clk),
        .reset(reset),
        .ce(ce_array),
        .accumulate(accumulate),
        .weights_flat(weights_flat),
        .activation_broadcast(activation_broadcast),
        .mask_broadcast(mask_broadcast),
        .results_flat(results_flat)
    );
    
    // FSM sequential
    always @(posedge clk or posedge reset) begin
        if (reset) state <= S_IDLE;
        else state <= nstate;
    end
    
    // Datapath
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            col_idx <= 8'd0;
            ce_array <= 1'b0;
            accumulate <= 1'b0;
            done <= 1'b0;
            results_out <= {(NUM_PES*16){1'b0}};
        end else begin
            done <= 1'b0;
            
            case (state)
                S_IDLE: begin
                    col_idx <= 8'd0;
                    ce_array <= 1'b0;
                    accumulate <= 1'b0;
                end
                
                S_INIT: begin
                    // Reset accumulators
                    ce_array <= 1'b1;
                    accumulate <= 1'b0;
                    col_idx <= 8'd0;
                end
                
                S_COMPUTE: begin
                    ce_array <= 1'b1;
                    accumulate <= 1'b1;  // Start accumulating
                    
                    if (col_idx < SRAM_DEPTH - 1)
                        col_idx <= col_idx + 8'd1;
                end
                
                S_DONE: begin
                    done <= 1'b1;
                    ce_array <= 1'b0;
                    // Latch final results
                    results_out <= results_flat;
                end
            endcase
        end
    end
    
    // FSM combinational
    always @(*) begin
        nstate = state;
        case (state)
            S_IDLE:    if (start) nstate = S_INIT;
            S_INIT:    nstate = S_COMPUTE;
            S_COMPUTE: if (col_idx == SRAM_DEPTH - 1) nstate = S_DONE;
            S_DONE:    if (!start) nstate = S_IDLE;
        endcase
    end
    
endmodule
