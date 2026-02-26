🚀 BNN Hardware Accelerator



SystemVerilog-based FPGA/ASIC Accelerator for Binary Neural Networks



A high-performance Binary Neural Network (BNN) accelerator implemented in SystemVerilog, optimized for FPGA and ASIC deployment.

The design achieves 79.29% test accuracy on CIFAR-10 using efficient XNOR–Popcount compute primitives and sparsity-aware optimizations.



📌 Overview



This project implements a fully hardware-mapped BNN inference engine featuring:



Bitwise XNOR–Popcount MAC replacement



Broadcast and Systolic dataflow architectures



Sparse-aware Processing Elements (PEs)



Clock-gated low-power design



Compressed tiled weight storage (.hex-based loading)



Full verification testbench



The accelerator is designed for energy-efficient edge AI inference.



🧠 Design Architecture

1️⃣ Compute Primitive



Binary convolution using XNOR + Popcount



Replaces traditional multiply-accumulate (MAC)



Significantly reduces DSP usage



2️⃣ Dataflow Architectures

🔹 Broadcast Topology



Centralized weight broadcasting



Lower control complexity



Suitable for smaller PE arrays



🔹 Systolic Array



Pipelined data propagation



High throughput



Better scalability for large feature maps



3️⃣ Processing Elements

⚙️ adaptive\_pe.sv



Runtime performance monitoring



Dynamic utilization tracking



Configurable compute pipeline depth



⚙️ sparse\_aware\_pe.sv



Zero-skipping logic



Sparsity exploitation



Reduced switching activity



4️⃣ Memory System



Tiled weight storage



Compressed binary weights



.hex-based initialization



FPGA BRAM friendly



📂 Repository Structure

File	Description

accelerator\_top\_broadcast.sv	Broadcast-style top-level architecture

accelerator\_top\_systolic.sv	Systolic array top-level architecture

adaptive\_pe.sv	Adaptive performance-aware PE

sparse\_aware\_pe.sv	Sparsity-exploiting PE

tb\_compressed\_accelerator.sv	Full-system verification testbench

🛠 Toolchain

Stage	Tool

RTL Design	SystemVerilog

Simulation	Vivado / ModelSim

Training	PyTorch

Dataset	CIFAR-10

Target	FPGA / ASIC

📊 Performance Results



Test Accuracy: 79.29% on CIFAR-10



Binary convolution via XNOR-popcount



Supports sparse weight compression



Clock gating enabled for dynamic power reduction



FPGA-friendly BRAM mapping



🔋 Power Optimization Features



Clock gating in inactive PEs



Sparse-aware zero skipping



Reduced switching activity through binary arithmetic



DSP-free computation



🧪 Verification



Full SystemVerilog testbench (tb\_compressed\_accelerator.sv)



Compressed weight loading validation



End-to-end inference verification



Functional correctness against PyTorch baseline



🎯 Target Applications



Edge AI inference



Low-power embedded vision



FPGA-based AI accelerators



Custom ASIC ML inference engines



📈 Key Contributions



Dual-topology BNN hardware implementation



Adaptive PE architecture with monitoring logic



Sparse-aware execution model



Hardware–software co-design workflow (PyTorch → .hex → RTL)

