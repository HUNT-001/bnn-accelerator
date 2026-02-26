`timescale 1ns / 1ps
module accelerator_top #(
    parameter integer WORD_SIZE  = 64,
    parameter integer PE_ROWS    = 8,
    parameter integer PE_COLS    = 8,
    parameter integer SRAM_DEPTH = 64
)(
    input  wire                   clk,
    input  wire                   reset,
    input  wire                   start,
    output reg                    done,

    input  wire                   wr_en,
    input  wire [5:0]             wr_addr,
    input  wire [WORD_SIZE-1:0]   wr_data,
    input  wire                   wr_type
);
    localparam integer NUM_PES = PE_ROWS*PE_COLS;
    localparam integer PCW     = $clog2(WORD_SIZE+1);

    reg [WORD_SIZE-1:0] weight_sram    [0:SRAM_DEPTH-1];
    reg [WORD_SIZE-1:0] activation_sram[0:SRAM_DEPTH-1];
                 
    always @(posedge clk) begin
        if (wr_en) begin
            if (!wr_type) weight_sram[wr_addr] <= wr_data;
            else activation_sram[wr_addr] <= wr_data;
        end
    end

    localparam [2:0] S_IDLE=3'd0, S_LOAD=3'd1, S_RUN=3'd2, S_DONE=3'd3;
    reg [2:0] state, nstate;

    reg [7:0] rd_idx;
    reg [7:0] run_cycles;
    reg       ce_array;

    wire [NUM_PES*WORD_SIZE-1:0] w_flat, a_flat, m_flat;
    wire [NUM_PES*PCW-1:0]       pc_flat;
    reg  [31:0]                  total_popcount;

    genvar k;
    generate
        for (k=0;k<NUM_PES;k=k+1) begin: feed
            assign w_flat[(k+1)*WORD_SIZE-1 : k*WORD_SIZE] = weight_sram[rd_idx];
            assign a_flat[(k+1)*WORD_SIZE-1 : k*WORD_SIZE] = activation_sram[rd_idx];
            assign m_flat[(k+1)*WORD_SIZE-1 : k*WORD_SIZE] = {WORD_SIZE{1'b1}};
        end
    endgenerate

    pe_array #(
        .ROWS(PE_ROWS), .COLS(PE_COLS), .WORD_SIZE(WORD_SIZE), .PIPELINE(1)
    ) peA (
        .clk(clk), .ce(ce_array),
        .weights_in_flat(w_flat),
        .activations_in_flat(a_flat),
        .valid_mask_flat(m_flat),
        .popcounts_out_flat(pc_flat)
    );

    wire [PCW-1:0] pc_array [0:NUM_PES-1];
    generate
        for (k=0; k<NUM_PES; k=k+1) begin: extract_pc
            assign pc_array[k] = pc_flat[(k+1)*PCW-1 : k*PCW];
        end
    endgenerate

    wire [PCW+1:0] sum_stage1 [0:31];
    wire [PCW+2:0] sum_stage2 [0:15];
    wire [PCW+3:0] sum_stage3 [0:7];
    wire [PCW+4:0] sum_stage4 [0:3];
    wire [PCW+5:0] sum_stage5 [0:1];
    wire [12:0] cycle_sum;
    
    generate
        for (k=0; k<32; k=k+1) begin: stage1
            assign sum_stage1[k] = pc_array[2*k] + pc_array[2*k+1];
        end
        for (k=0; k<16; k=k+1) begin: stage2
            assign sum_stage2[k] = sum_stage1[2*k] + sum_stage1[2*k+1];
        end
        for (k=0; k<8; k=k+1) begin: stage3
            assign sum_stage3[k] = sum_stage2[2*k] + sum_stage2[2*k+1];
        end
        for (k=0; k<4; k=k+1) begin: stage4
            assign sum_stage4[k] = sum_stage3[2*k] + sum_stage3[2*k+1];
        end
        for (k=0; k<2; k=k+1) begin: stage5
            assign sum_stage5[k] = sum_stage4[2*k] + sum_stage4[2*k+1];
        end
    endgenerate
    
    assign cycle_sum = sum_stage5[0] + sum_stage5[1];

    always @(posedge clk or posedge reset) begin
        if (reset) state <= S_IDLE;
        else state <= nstate;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rd_idx <= 8'd0;
            run_cycles <= 8'd0;
            ce_array <= 1'b0;
            total_popcount <= 32'd0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    total_popcount <= 32'd0;
                    rd_idx <= 8'd0;
                    run_cycles <= 8'd0;
                    ce_array <= 1'b0;
                end
                S_LOAD: begin
                    ce_array <= 1'b1;
                    rd_idx <= 8'd0;
                    run_cycles <= 8'd0;
                end
                S_RUN: begin
                    run_cycles <= run_cycles + 8'd1;
                    
                    if (run_cycles > 8'd0 && run_cycles <= SRAM_DEPTH) begin
                        total_popcount <= total_popcount + cycle_sum;
                    end
                    
                    if (rd_idx < SRAM_DEPTH - 1) begin
                        rd_idx <= rd_idx + 8'd1;
                    end
                end
                S_DONE: begin
                    done <= 1'b1;
                    ce_array <= 1'b0;
                end
            endcase
        end
    end

    always @(*) begin
        nstate = state;
        case (state)
            S_IDLE: if (start) nstate = S_LOAD;
            S_LOAD: nstate = S_RUN;
            S_RUN:  if (run_cycles == SRAM_DEPTH + 1) nstate = S_DONE;
            S_DONE: if (!start) nstate = S_IDLE;
        endcase
    end
    
endmodule
