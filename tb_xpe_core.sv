`timescale 1ns / 1ps
module tb_xpe_core;
    localparam WORD_SIZE = 64;
    localparam PCW = $clog2(WORD_SIZE+1);

    reg  clk, ce;
    reg  [WORD_SIZE-1:0] w, a, m;
    wire [PCW-1:0]       pc;

    xpe_core #(.WORD_SIZE(WORD_SIZE), .PIPELINE(1), .HAS_MASK(1)) dut (
        .weight_word_in(w),
        .activation_word_in(a),
        .valid_mask_in(m),
        .clk(clk),
        .ce(ce),
        .popcount_out(pc)
    );

    always #5 clk = ~clk;

    initial begin
        clk=0; ce=1;
        // all zeros -> XNOR=1 across 64 -> popcount 64
        w = 64'h0; a = 64'h0; m = {WORD_SIZE{1'b1}}; @(posedge clk);
        @(posedge clk);
        if (pc == 64) $display("PASS all-zero");
        else $display("FAIL all-zero got %0d", pc);

        // ones vs zeros -> popcount 0
        w = 64'hFFFF_FFFF_FFFF_FFFF; a = 64'h0; m = {WORD_SIZE{1'b1}}; @(posedge clk);
        @(posedge clk);
        if (pc == 0) $display("PASS ones-vs-zeros"); else $display("FAIL ones-vs-zeros %0d", pc);

        // random with mask only lower 32 valid
        w = 64'h589A86C459345B3C; a = 64'h6FA49326961A604D; m = 64'h0000_0000_FFFF_FFFF; @(posedge clk);
        @(posedge clk);
        $display("Masked pc = %0d", pc);

        $finish;
    end
endmodule