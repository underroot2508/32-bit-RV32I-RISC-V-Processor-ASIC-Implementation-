
`timescale 1ns/1ps

module rv32i_alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  alu_ctrl,
    output reg  [31:0] result,
    output wire        zero
);

    wire signed [31:0] as = a;
    wire signed [31:0] bs = b;

    always @(*) begin
        case (alu_ctrl)
            4'b0000: result = a + b;            // ADD
            4'b0001: result = a - b;            // SUB
            4'b0010: result = a & b;            // AND
            4'b0011: result = a | b;            // OR
            4'b0100: result = a ^ b;            // XOR
            4'b0101: result = a << b[4:0];      // SLL
            4'b0110: result = a >> b[4:0];      // SRL
            4'b0111: result = as >>> b[4:0];    // SRA (arith right shift)
            4'b1000: result = (a < b) ? 32'b1 : 32'b0;   // SLTU
            4'b1001: result = (as < bs) ? 32'b1 : 32'b0; // SLT
            default: result = 32'b0;            // default only once
        endcase
    end

    assign zero = (result == 32'b0);

endmodule

