# 32-bit RV32I RISC-V Processor ASIC Implementation

## Overview

A 32-bit RV32I RISC-V pipelined processor designed in Verilog HDL and implemented through a complete RTL-to-GDSII ASIC flow using the Sky130A PDK.

## Architecture

The processor implements a 5-stage pipeline:

- Instruction Fetch (IF)
- Instruction Decode (ID)
- Execute (EX)
- Memory Access (MEM)
- Write Back (WB)

The design includes:

- RV32I instruction support
- 32-bit register file
- ALU
- Immediate generation
- Control unit
- Data and instruction memory
- Data forwarding
- Load-use hazard detection
- Branch and jump handling

## Verification

Functional verification was performed using Vivado simulation.

Example instructions were used to verify:

```text
addi x1, x0, 5
addi x2, x0, 10
add  x3, x1, x2
sw   x3, 0(x0)
lw   x4, 0(x0)

## ASIC Implementation

The RTL design was taken through a complete RTL-to-GDSII ASIC flow using:

- Yosys for RTL synthesis
- OpenLane for automated ASIC implementation
- OpenROAD for floorplanning, placement, CTS, and routing
- Sky130A PDK
- KLayout for final GDSII visualization

The implementation flow included:

1. RTL synthesis
2. Floorplanning
3. Placement
4. Clock Tree Synthesis (CTS)
5. Global and detailed routing
6. Static Timing Analysis (STA)
7. Design Rule Checking (DRC)
8. GDSII generation

## Final Results

The final implementation achieved:

- Zero setup timing violations
- Zero hold timing violations
- Zero DRC violations
- Successful GDSII generation

Final layout was generated for the `sky130_fd_sc_hd` standard-cell library.

## Project Structure

```text
rtl/
├── riscv_pipeline_top.v
├── rv32i_alu.v
├── rv32i_control.v
├── rv32i_forward_hazard.v
├── rv32i_imm_gen.v
├── rv32i_mem.v
└── rv32i_regfile.v

simulation/
└── tb_riscv.v

openlane/
└── config.json

results/
├── riscv_pipeline_top.gds
└── riscv_pipeline_top.def
