// rv32i_forward_hazard.v
`timescale 1ns/1ps
module rv32i_forward_hazard (
    input  wire        ex_mem_RegWrite,
    input  wire [4:0]  ex_mem_rd,
    input  wire        mem_wb_RegWrite,
    input  wire [4:0]  mem_wb_rd,
    input  wire [4:0]  id_ex_rs1,
    input  wire [4:0]  id_ex_rs2,
    input  wire        id_ex_MemRead, // for stall detection (load-use)
    input  wire [4:0]  id_ex_rd,      // note: id_ex_rd is rd of EX stage (for load)
    input  wire [4:0]  if_rs1,
    input  wire [4:0]  if_rs2,
    output reg [1:0]   forwardA,      // 00 from reg, 01 from mem_wb, 10 from ex_mem
    output reg [1:0]   forwardB,
    output reg         stall          // single-cycle stall for load-use
);
    always @(*) begin
        // defaults
        forwardA = 2'b00; forwardB = 2'b00; stall = 1'b0;
        // EX/MEM forwarding
        if (ex_mem_RegWrite && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1))
            forwardA = 2'b10;
        if (ex_mem_RegWrite && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2))
            forwardB = 2'b10;
        // MEM/WB forwarding, but do not override EX/MEM
        if (mem_wb_RegWrite && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1) && !(ex_mem_RegWrite && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1)))
            forwardA = 2'b01;
        if (mem_wb_RegWrite && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2) && !(ex_mem_RegWrite && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2)))
            forwardB = 2'b01;

        // load-use stall detection (if EX stage is a load and its rd matches IF stage reg operands)
        stall = 1'b0;
        if (id_ex_MemRead) begin
            if ((id_ex_rd != 5'd0) && ((id_ex_rd == if_rs1) || (id_ex_rd == if_rs2))) begin
                stall = 1'b1;
            end
        end
    end
endmodule

