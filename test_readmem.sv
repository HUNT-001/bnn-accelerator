`timescale 1ns / 1ps

module test_readmem;
    reg [7:0] test_mem [0:63];
    
    initial begin
        $display("Attempting to read file...");
        
        // Try absolute path
        $readmemh("E:/project_2/project_2.srcs/sim_1/imports/hardware_exports/conv2_row000_tile000_idx.hex", test_mem);
        
        $display("File read successfully!");
        $display("First few values:");
        $display("  [0] = %h", test_mem[0]);
        $display("  [1] = %h", test_mem[1]);
        $display("  [2] = %h", test_mem[2]);
        $display("  [3] = %h", test_mem[3]);
        
        $finish;
    end
endmodule