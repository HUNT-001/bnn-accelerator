`timescale 1ns / 1ps
module tb_pe_array;
    localparam ROWS=8, COLS=8, NUM_PES=ROWS*COLS, WORD_SIZE=64, PCW=$clog2(WORD_SIZE+1);
    reg clk, ce;
    reg  [NUM_PES*WORD_SIZE-1:0] wf, af, mf;
    wire [NUM_PES*PCW-1:0]       pf;

    pe_array #(.ROWS(ROWS), .COLS(COLS), .WORD_SIZE(WORD_SIZE), .PIPELINE(1)) dut (
        .clk(clk), .ce(ce),
        .weights_in_flat(wf),
        .activations_in_flat(af),
        .valid_mask_flat(mf),
        .popcounts_out_flat(pf)
    );

    always #5 clk=~clk;

    integer i;
    initial begin
        clk=0; ce=1;
        wf='0; af='0; mf={NUM_PES*WORD_SIZE{1'b1}};

        // PE0 random, PE63 ones-vs-zeros
        wf[WORD_SIZE-1:0] = 64'h589A86C459345B3C;
        af[WORD_SIZE-1:0] = 64'h6FA49326961A604D;

        wf[(NUM_PES*WORD_SIZE)-1:(NUM_PES-1)*WORD_SIZE] = 64'hFFFF_FFFF_FFFF_FFFF;
        af[(NUM_PES*WORD_SIZE)-1:(NUM_PES-1)*WORD_SIZE] = 64'h0000_0000_0000_0000;

        @(posedge clk); @(posedge clk); // allow pipeline
        if (pf[PCW-1:0] == 28) $display("PASS PE0=28"); else $display("FAIL PE0=%0d", pf[PCW-1:0]);
        if (pf[NUM_PES*PCW-1:(NUM_PES-1)*PCW] == 0) $display("PASS PE63=0"); else $display("FAIL PE63=%0d", pf[NUM_PES*PCW-1:(NUM_PES-1)*PCW]);

        $finish;
    end
endmodule