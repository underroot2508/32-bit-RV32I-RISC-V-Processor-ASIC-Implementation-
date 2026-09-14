// rv32i_mem.v
`timescale 1ns/1ps
module rv32i_mem #(
    parameter IMEM_WORDS = 64,
    parameter DMEM_WORDS = 64
)(
    input  wire              clk,
    input  wire              rst,
    // instruction memory interface (read-only)
    input  wire  [31:0]      imem_addr,
    output wire  [31:0]      imem_data,
    // data memory interface (read/write)
    input  wire              dmem_read,
    input  wire              dmem_write,
    input  wire  [31:0]      dmem_addr,
    input  wire  [31:0]      dmem_wdata,
    output reg   [31:0]      dmem_rdata
);
    // behavioral arrays
    reg [31:0] imem [0:IMEM_WORDS-1];
    reg [31:0] dmem [0:DMEM_WORDS-1];
    integer i;

   initial begin
    imem[0] = 32'h00500093; // addi x1,x0,5
    imem[1] = 32'h00A00113; // addi x2,x0,10
    imem[2] = 32'h002081B3; // add x3,x1,x2
    imem[3] = 32'h00302023; // sw x3,0(x0)
    imem[4] = 32'h00002203; // lw x4,0(x0)

    for (i = 5; i < IMEM_WORDS; i = i + 1)
        imem[i] = 32'h00000013;

    for (i = 0; i < DMEM_WORDS; i = i + 1)
        dmem[i] = 32'h0;
end

    // IMEM read (combinational word aligned)
    assign imem_data = imem[imem_addr[11:2]];

    // DMEM read/write (behavioral synchronous write, combinational read of last stored)
    always @(posedge clk) begin
        if (dmem_write) begin
            dmem[dmem_addr[11:2]] <= dmem_wdata;
        end
        if (dmem_read) begin
            dmem_rdata <= dmem[dmem_addr[11:2]];
        end else begin
            dmem_rdata <= 32'b0;
        end
    end

endmodule

