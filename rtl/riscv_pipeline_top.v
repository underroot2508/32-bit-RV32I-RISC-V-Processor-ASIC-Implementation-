// riscv_pipeline_top.v
`timescale 1ns/1ps
module riscv_pipeline_top(
    input wire clk,
    input wire reset,

    output wire [31:0] debug_pc,
    output wire [31:0] debug_instr,
    output wire [31:0] debug_alu,
    
    output wire [31:0] debug_wb_data,
    output wire [4:0]  debug_wb_rd,
    output wire        debug_wb_we
); // parameters
    parameter IMEM_WORDS = 64;
    parameter DMEM_WORDS = 64;

    // ---------- core regs/wires ----------
    // program counter
    reg [31:0] pc, pc_next;

    // pipeline regs IF/ID
    reg [31:0] if_id_pc;
    reg [31:0] if_id_instr;
    reg        if_id_valid;

    // ID/EX
    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_rs1_data;
    reg [31:0] id_ex_rs2_data;
    reg [31:0] id_ex_imm;
    reg [4:0]  id_ex_rs1;
    reg [4:0]  id_ex_rs2;
    reg [4:0]  id_ex_rd;
    reg [6:0]  id_ex_opcode;
    reg [2:0]  id_ex_funct3;
    reg [6:0]  id_ex_funct7;
    reg        id_ex_RegWrite, id_ex_MemRead, id_ex_MemWrite, id_ex_MemToReg;
    reg        id_ex_ALUSrc, id_ex_Branch, id_ex_Jump;
    reg [1:0]  id_ex_ALUOp;

    // EX/MEM
    reg [31:0] ex_mem_pc;
    reg [31:0] ex_mem_alu_out;
    reg [31:0] ex_mem_rs2;
    reg [4:0]  ex_mem_rd;
    reg        ex_mem_RegWrite, ex_mem_MemRead, ex_mem_MemWrite, ex_mem_MemToReg;
    reg        ex_mem_BranchTaken;
    reg [31:0] ex_mem_branch_target;

    // MEM/WB
    reg [31:0] mem_wb_pc;
    reg [31:0] mem_wb_alu_out;
    reg [31:0] mem_wb_memdata;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_RegWrite, mem_wb_MemToReg;

    // expose regfile and dmem for TB visibility (declare here and pass into submodules)
    reg [31:0] regfile [0:31]; // for testbench access if desired
    // memories are inside mem module; expose dmem via interface later (not required)

    // ---------- internal wires ----------
    wire [31:0] instr_if;
    wire [31:0] imem_data;
    wire [31:0] dmem_rdata;

    // instantiate memory module
    // we will directly access imem via addr and dmem read/write via signals
    // signals to mem module
    wire  mem_dread;
    wire  mem_dwrite;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    

    rv32i_mem #(.IMEM_WORDS(IMEM_WORDS), .DMEM_WORDS(DMEM_WORDS)) mem0 (
        .clk(clk), .rst(reset),
        .imem_addr(pc), .imem_data(imem_data),
        .dmem_read(mem_dread), .dmem_write(mem_dwrite),
        .dmem_addr(mem_addr), .dmem_wdata(mem_wdata),
        .dmem_rdata(dmem_rdata)
    );

    assign instr_if = imem_data;

    // register file instance (use internal regs for synthesis-friendly code)
    // We'll use a regfile module to manage writes and reads; but we also expose regfile array for visibility.
    wire [31:0] rf_rdata1, rf_rdata2;
    wire rf_we;
    wire [4:0] rf_waddr;
    wire [31:0] rf_wdata;
    // connect regfile instance
    rv32i_regfile rf0 (
        .clk(clk), .rst(reset),
        .we(rf_we), .waddr(rf_waddr), .wdata(rf_wdata),
        .raddr1(if_id_instr[19:15]), .raddr2(if_id_instr[24:20]),
        .rdata1(rf_rdata1), .rdata2(rf_rdata2)
    );

    // imm gen instance (uses IF/ID instruction)
    wire [31:0] imm_id;
    rv32i_imm_gen immgen0(.instr(if_id_instr), .imm(imm_id));

    // control unit instance
    wire RegWrite_id, MemRead_id, MemWrite_id, MemToReg_id, ALUSrc_id, Branch_id, Jump_id;
    wire [1:0] ALUOp_id;
    rv32i_control ctrl0(.opcode(if_id_instr[6:0]),
                        .RegWrite(RegWrite_id), .MemRead(MemRead_id),
                        .MemWrite(MemWrite_id), .MemToReg(MemToReg_id),
                        .ALUSrc(ALUSrc_id), .Branch(Branch_id),
                        .Jump(Jump_id), .ALUOp(ALUOp_id));

    // forwarding & hazard unit wires
    wire [1:0] forwardA, forwardB;
    wire stall;
    rv32i_forward_hazard fwd0(
        .ex_mem_RegWrite(ex_mem_RegWrite), .ex_mem_rd(ex_mem_rd),
        .mem_wb_RegWrite(mem_wb_RegWrite), .mem_wb_rd(mem_wb_rd),
        .id_ex_rs1(id_ex_rs1), .id_ex_rs2(id_ex_rs2),
        .id_ex_MemRead(id_ex_MemRead), .id_ex_rd(id_ex_rd),
        .if_rs1(if_id_instr[19:15]), .if_rs2(if_id_instr[24:20]),
        .forwardA(forwardA), .forwardB(forwardB), .stall(stall)
    );

    // ALU instance wires
    reg [31:0] alu_in1, alu_in2;
    wire [31:0] alu_result;
    wire        alu_zero;
    reg [3:0]   alu_ctrl_ex;

    rv32i_alu alu0(
        .a(alu_in1), .b(alu_in2),
        .alu_ctrl(alu_ctrl_ex), .result(alu_result), .zero(alu_zero)
    );

    // ---------- initial / reset ----------
    integer i;
    initial begin
        // init regfile for simulation visibility & convenience
        for (i = 0; i < 32; i = i + 1) regfile[i] = 32'b0;
        pc = 32'b0;
        if_id_pc = 0; if_id_instr = 32'h00000013; if_id_valid = 1'b0;
        id_ex_pc = 0; id_ex_rs1_data = 0; id_ex_rs2_data = 0; id_ex_imm = 0;
        id_ex_rs1 = 0; id_ex_rs2 = 0; id_ex_rd = 0;
        id_ex_opcode = 0; id_ex_funct3 = 0; id_ex_funct7 = 0;
        id_ex_RegWrite = 0; id_ex_MemRead = 0; id_ex_MemWrite = 0; id_ex_MemToReg = 0;
        id_ex_ALUSrc = 0; id_ex_Branch = 0; id_ex_Jump = 0; id_ex_ALUOp = 2'b00;
        ex_mem_pc = 0; ex_mem_alu_out = 0; ex_mem_rs2 = 0; ex_mem_rd = 0;
        ex_mem_RegWrite = 0; ex_mem_MemRead = 0; ex_mem_MemWrite = 0; ex_mem_MemToReg = 0;
        ex_mem_BranchTaken = 0; ex_mem_branch_target = 0;
        mem_wb_pc = 0; mem_wb_alu_out = 0; mem_wb_memdata = 0; mem_wb_rd = 0;
        mem_wb_RegWrite = 0; mem_wb_MemToReg = 0;
    end

    // ---------- IF stage: pc update ----------
    wire [31:0] pc_plus4 = pc + 4;
    always @(posedge clk or posedge reset) begin
        if (reset) pc <= 32'b0;
        else pc <= pc_next;
    end

    // ---------- IF/ID pipeline register ----------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            if_id_instr <= 32'h00000013;
            if_id_pc <= 32'b0;
            if_id_valid <= 1'b0;
        end else begin
            if (!stall) begin
                if_id_instr <= instr_if;
                if_id_pc <= pc;
                if_id_valid <= 1'b1;
            end else begin
                // hold IF/ID on stall
                if_id_instr <= if_id_instr;
                if_id_pc <= if_id_pc;
                if_id_valid <= if_id_valid;
            end
        end
    end

    // ---------- ID/EX pipeline register ----------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            id_ex_pc <= 0;
            id_ex_rs1_data <= 0; id_ex_rs2_data <= 0; id_ex_imm <= 0;
            id_ex_rs1 <= 0; id_ex_rs2 <= 0; id_ex_rd <= 0;
            id_ex_opcode <= 0; id_ex_funct3 <= 0; id_ex_funct7 <= 0;
            id_ex_RegWrite <= 0; id_ex_MemRead <= 0; id_ex_MemWrite <= 0; id_ex_MemToReg <= 0;
            id_ex_ALUSrc <= 0; id_ex_Branch <= 0; id_ex_Jump <= 0; id_ex_ALUOp <= 2'b00;
        end else begin
            if (stall) begin
                // insert bubble
                id_ex_pc <= 0;
                id_ex_rs1_data <= 0; id_ex_rs2_data <= 0; id_ex_imm <= 0;
                id_ex_rs1 <= 0; id_ex_rs2 <= 0; id_ex_rd <= 0;
                id_ex_opcode <= 0; id_ex_funct3 <= 0; id_ex_funct7 <= 0;
                id_ex_RegWrite <= 0; id_ex_MemRead <= 0; id_ex_MemWrite <= 0; id_ex_MemToReg <= 0;
                id_ex_ALUSrc <= 0; id_ex_Branch <= 0; id_ex_Jump <= 0; id_ex_ALUOp <= 2'b00;
            end else begin
                id_ex_pc <= if_id_pc;
                // register read - use rf module outputs
                id_ex_rs1_data <= rf_rdata1;
                id_ex_rs2_data <= rf_rdata2;
                id_ex_imm <= imm_id;
                id_ex_rs1 <= if_id_instr[19:15];
                id_ex_rs2 <= if_id_instr[24:20];
                id_ex_rd  <= if_id_instr[11:7];
                id_ex_opcode <= if_id_instr[6:0];
                id_ex_funct3 <= if_id_instr[14:12];
                id_ex_funct7 <= if_id_instr[31:25];
                // control pass
                id_ex_RegWrite <= RegWrite_id;
                id_ex_MemRead  <= MemRead_id;
                id_ex_MemWrite <= MemWrite_id;
                id_ex_MemToReg <= MemToReg_id;
                id_ex_ALUSrc   <= ALUSrc_id;
                id_ex_Branch   <= Branch_id;
                id_ex_Jump     <= Jump_id;
                id_ex_ALUOp    <= ALUOp_id;
            end
        end
    end

    // ---------- EX stage (ALU control + forwarding) ----------
    // ALU control mapping - combinational
    always @(*) begin
        alu_ctrl_ex = 4'b0000; // default ADD
        if (id_ex_ALUOp == 2'b00) begin
            alu_ctrl_ex = 4'b0000; // add (for lw/sw)
        end else if (id_ex_ALUOp == 2'b01) begin
            alu_ctrl_ex = 4'b0001; // sub for branch compare
        end else if (id_ex_ALUOp == 2'b10) begin
            case (id_ex_funct3)
                3'b000: alu_ctrl_ex = (id_ex_funct7[5]) ? 4'b0001 : 4'b0000; // sub/add
                3'b111: alu_ctrl_ex = 4'b0010; // and
                3'b110: alu_ctrl_ex = 4'b0011; // or
                3'b100: alu_ctrl_ex = 4'b0100; // xor
                3'b001: alu_ctrl_ex = 4'b0101; // sll
                3'b101: alu_ctrl_ex = (id_ex_funct7[5]) ? 4'b0111 : 4'b0110; // sra/srl
                3'b010: alu_ctrl_ex = 4'b1000; // slt
                3'b011: alu_ctrl_ex = 4'b1001; // sltu
                default: alu_ctrl_ex = 4'b0000;
            endcase
        end else if (id_ex_ALUOp == 2'b11) begin
            alu_ctrl_ex = 4'b0000; // LUI/AUIPC treated via ALUSrc and imm
        end
    end

    // operand selection with forwarding
    always @(*) begin
        // default from ID/EX
        alu_in1 = id_ex_rs1_data;
        alu_in2 = id_ex_rs2_data;
        // forwardA
        case (forwardA)
            2'b10: alu_in1 = ex_mem_alu_out;
            2'b01: alu_in1 = (mem_wb_MemToReg) ? mem_wb_memdata : mem_wb_alu_out;
            default: alu_in1 = id_ex_rs1_data;
        endcase
        // forwardB
        case (forwardB)
            2'b10: alu_in2 = ex_mem_alu_out;
            2'b01: alu_in2 = (mem_wb_MemToReg) ? mem_wb_memdata : mem_wb_alu_out;
            default: alu_in2 = id_ex_rs2_data;
        endcase
        // ALUSrc override
        if (id_ex_ALUSrc) alu_in2 = id_ex_imm;
        // AUIPC and LUI adjustments
        if (id_ex_opcode == 7'b0010111) begin // AUIPC
            alu_in1 = id_ex_pc;
            alu_in2 = id_ex_imm;
        end
        if (id_ex_opcode == 7'b0110111) begin // LUI
            alu_in1 = 32'b0;
            alu_in2 = id_ex_imm;
        end
    end

    // ---------- EX->MEM pipeline update ----------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ex_mem_pc <= 0; ex_mem_alu_out <= 0; ex_mem_rs2 <= 0; ex_mem_rd <= 0;
            ex_mem_RegWrite <= 0; ex_mem_MemRead <= 0; ex_mem_MemWrite <= 0; ex_mem_MemToReg <= 0;
            ex_mem_BranchTaken <= 0; ex_mem_branch_target <= 0;
        end else begin
            ex_mem_pc <= id_ex_pc;
            ex_mem_alu_out <= alu_result;
            ex_mem_rs2 <= id_ex_rs2_data; // store original reg data (before ALUSrc override)
            ex_mem_rd <= id_ex_rd;
            ex_mem_RegWrite <= id_ex_RegWrite;
            ex_mem_MemRead <= id_ex_MemRead;
            ex_mem_MemWrite <= id_ex_MemWrite;
            ex_mem_MemToReg <= id_ex_MemToReg;
            ex_mem_BranchTaken <= (id_ex_Branch && alu_zero) || id_ex_Jump;
            ex_mem_branch_target <= id_ex_Jump ? (alu_in1 + id_ex_imm) : (id_ex_pc + id_ex_imm);
        end
    end

    // ---------- MEM stage ----------
    // data memory control signals
    assign mem_dread = ex_mem_MemRead;
    assign mem_dwrite = ex_mem_MemWrite;
    assign mem_addr = ex_mem_alu_out;
    assign mem_wdata = ex_mem_rs2;

    // mem read handled inside mem module (dmem_rdata)
    // register MEM/WB
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_wb_pc <= 0; mem_wb_alu_out <= 0; mem_wb_memdata <= 0; mem_wb_rd <= 0;
            mem_wb_RegWrite <= 0; mem_wb_MemToReg <= 0;
        end else begin
            // write to dmem already performed in mem module
            mem_wb_pc <= ex_mem_pc;
            mem_wb_alu_out <= ex_mem_alu_out;
            mem_wb_memdata <= dmem_rdata;
            mem_wb_rd <= ex_mem_rd;
            mem_wb_RegWrite <= ex_mem_RegWrite;
            mem_wb_MemToReg <= ex_mem_MemToReg;
        end
    end

    // ---------- WB stage ----------
    // drive regfile write port signals through rf0 instance (we earlier instantiated)
    // But rf0 had read ports tied to IF instruction addresses; we need to write via its write port:
    // To do that, we used the rf0 instance's write interface earlier; capture values here:
    // We'll drive rf0's write signals by connecting to wires - but simplest is to reinstantiate a regfile that supports external control.
    // For cleanliness, do a small direct write into the regfile array here (synthesizable).
    // NOTE: For synthesis, using a single regfile instance is recommended; here we emulate write by reusing regs for visibility.

    // We'll use the rf0 instance's write port through wires -- create wires and connect with assign.
    // To keep top-level clear we declare these wires earlier and now set them:
    // But since rv32i_regfile handles writes itself, we must route signals to it; earlier rf0 used its own raddr ports.
    // We'll now connect the write interface via continuous updates using registers updated at posedge clk.
    // We declared rf_we, rf_waddr, rf_wdata earlier for that purpose.

    // wires rf_we, rf_waddr, rf_wdata are outputs of this logic:
    reg write_enable_reg;
    reg [4:0] write_addr_reg;
    reg [31:0] write_data_reg;
    assign rf_we = write_enable_reg;
    assign rf_waddr = write_addr_reg;
    assign rf_wdata = write_data_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            write_enable_reg <= 1'b0;
            write_addr_reg <= 5'b0;
            write_data_reg <= 32'b0;
        end else begin
            write_enable_reg <= 1'b0; // default no write
            write_addr_reg <= 5'b0;
            write_data_reg <= 32'b0;
            if (mem_wb_RegWrite && (mem_wb_rd != 5'b0)) begin
                write_enable_reg <= 1'b1;
                write_addr_reg <= mem_wb_rd;
                if (mem_wb_MemToReg) write_data_reg <= mem_wb_memdata;
                else write_data_reg <= mem_wb_alu_out;
            end
        end
    end

    // For visibility, also maintain regfile array (shadow) for TB access
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1) regfile[i] <= 32'b0;
        end else begin
            if (write_enable_reg && (write_addr_reg != 5'b0))
                regfile[write_addr_reg] <= write_data_reg;
        end
    end

    // ---------- PC next logic and IF flush ----------
    always @(*) begin
        pc_next = pc + 4;
        if (ex_mem_BranchTaken) begin
            pc_next = ex_mem_branch_target;
        end
        if (stall) pc_next = pc; // hold PC on stall
    end

    // ---------------- expose debug signals as output wires (optional) ----------------
    // For testbench ease, map some internals to hierarchical names (the TB can reference top.uut.*)
    // Not adding explicit outputs to keep top module port list small.

// ====================================================
    // Debug Outputs
    // ====================================================

    assign debug_pc    = pc;
    assign debug_instr = if_id_instr;
    assign debug_alu   = ex_mem_alu_out;
    assign debug_wb_data = write_data_reg;
    assign debug_wb_rd   = write_addr_reg;
    assign debug_wb_we   = write_enable_reg;

endmodule

