// rv32i_regfile.v
`timescale 1ns/1ps
module rv32i_regfile (
    input  wire         clk,
    input  wire         rst,       // active high reset (for init in simulation)
    input  wire         we,        // write enable
    input  wire [4:0]   waddr,
    input  wire [31:0]  wdata,
    input  wire [4:0]   raddr1,
    input  wire [4:0]   raddr2,
    output wire [31:0]  rdata1,
    output wire [31:0]  rdata2
);
    reg [31:0] regs [0:31];
    integer i;
    // init on reset only for simulation convenience
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) regs[i] <= 32'b0;
        end else begin
            if (we && (waddr != 5'd0)) begin
                regs[waddr] <= wdata;
            end
        end
    end

    // combinational read ports (x0 always zero)
    assign rdata1 = (raddr1 == 5'd0) ? 32'b0 : regs[raddr1];
    assign rdata2 = (raddr2 == 5'd0) ? 32'b0 : regs[raddr2];

endmodule

