`timescale 1ns / 1ps
module tb_accelerator_top;
    localparam WORD_SIZE=64, SRAM_DEPTH=64, PE_ROWS=8, PE_COLS=8;
    reg clk, reset, start;
    wire done;

    reg wr_en;
    reg [5:0] wr_addr;
    reg [WORD_SIZE-1:0] wr_data;
    reg wr_type;

    accelerator_top #(.WORD_SIZE(WORD_SIZE), .PE_ROWS(PE_ROWS), .PE_COLS(PE_COLS), .SRAM_DEPTH(SRAM_DEPTH)) dut (
        .clk(clk), .reset(reset), .start(start), .done(done),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .wr_type(wr_type)
    );

    always #5 clk=~clk;

    integer i;
    initial begin
        clk=0; reset=1; start=0;
        wr_en=0; wr_addr=0; wr_data='0; wr_type=0;
        #20; reset=0;

        // Load weights: w[0]=random, rest zero (for demo)
        wr_en=1; wr_type=0;
        for (i=0;i<SRAM_DEPTH;i=i+1) begin
            wr_addr=i;
            wr_data = (i==0) ? 64'h589A86C459345B3C : 64'h0;
            @(posedge clk);
        end
        // Load activations: a[0]=pair, a[63]=zeros (demo)
        wr_type=1;
        for (i=0;i<SRAM_DEPTH;i=i+1) begin
            wr_addr=i;
            wr_data = (i==0) ? 64'h6FA49326961A604D : 64'h0;
            @(posedge clk);
        end
        wr_en=0;

        // Run
        @(posedge clk); start=1; @(posedge clk); start=0;

        wait(done==1);
        // Read totals via hierarchical reference (for TB only)
        // N = NUM_PES * SRAM_DEPTH * WORD_SIZE
        integer NUM_PES;
        integer N;
        integer signed_result;
        integer pc_total;

        NUM_PES = PE_ROWS*PE_COLS;
        N       = NUM_PES*SRAM_DEPTH*WORD_SIZE;

        pc_total = dut.total_popcount; // hierarchical TB access
        signed_result = (2*pc_total) - N;

        $display("Total popcount=%0d  N=%0d  2*pc-N=%0d", pc_total, N, signed_result);

        $finish;
    end
endmodule