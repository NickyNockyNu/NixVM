# NixVM — Virtual Microprocessor & Fantasy Console Engine

**Copyright (c) 2026 Nicholas Smith**  
*Licensed under the GNU General Public License v3.0*

---

## 📖 Overview

**NixVM** is a modular, high-performance 32-bit virtual RISC microprocessor, memory architecture, and toolchain designed as a universal foundation for building **fantasy consoles, retro computers, and embedded scripting runtimes**.

Instead of reinventing custom instruction sets and memory controllers for every new virtual console, NixVM provides an extensible, dependency-free core engine with first-class tooling: A Pascal compiler, an Intermediate Representation (IR) linker, a full text assembler, a reverse-engineering disassembler, a universal cartridge packaging system (`.nvm`), and a vm harness system for creating stand alone executable (`.exe`) files. 

---

## ⚡ Key Architectural Features

* **32-Bit Register Architecture:** 16 general-purpose 32-bit registers (`R0`–`R15`), condition code setters (`sete`..`setge`), bit manipulation (`bset`, `bclr`, `btst`), and dedicated hardware frame pointers (`BP`, `SP`).
* **Auto-Prefetching Immediate Pipeline:** Transparent immediate operand decoding via hardware pseudo-register `R13` (`Imm`) providing clean, branchless ALU operations with zero opcode duplication.
* **Integrated 32-Bit FPU:** Hardware IEEE-754 Single-precision floating-point unit (`fadd`, `fsub`, `fmul`, `fdiv`, `fsin`, `fcos`, `ftan`, `fsqrt`, `fln`, `fexp`).
* **Sandboxed Memory Model:** Power-of-two virtual memory addressing with zero-overhead wrapping and memory bounds protection.
* **High-Level System Services:** Built-in dynamic heap management, managed string operations with $O(1)$ length lookups, formatted I/O (`DebugPrint`, `StringFormat`), and programmable hardware timers.
* **Cooperative Frame Engine:** Throttled host execution with cooperative yielding (`yield`), real-time delta timing (`Delta`), and hardware interrupt support.
* **Universal Cartridge Format (`.nvm`):** Self-describing, binary-safe ROM cartridge format specifying target hardware requirements and memory budgets.

---

## 📚 Technical Documentation (WiP, often out of date)

Explore the complete, language-agnostic hardware specification manuals:

| Specification Document | Description |
| :--- | :--- |
| **[CPU & Instruction Set Reference](doc/CPU.md)** | Core processor architecture, register map, flags layout, ABI calling conventions, and complete datasheet for all 80+ instructions. |
| **[Memory & MMIO Reference](doc/Memory.md)** | Virtual memory map, Core System Area (`$0000`–`$04DF`), System Registers (`Delta`/`Elapsed`), hardware timers, and OEM peripheral mapping. |
| **[SysCalls & Interrupts Reference](doc/Syscalls_and_Interrupts.md)** | Complete SysCall ABI, heap/string services, hardware panic error codes, and the 16 prioritized interrupt vectors. |
| **[Assembler & Toolchain Guide](doc/Assembler.md)** | Assembly syntax, directives (`.embed`, `.include`, `.align`, `.res`), label scoping (`@local`), constants (`.equ`), and CLI tool documentation. |
| **[ROM Cartridge Format (`.nvm`)](doc/ROM_Format.md)** | The official 92-byte `NVMX` cartridge header specification, loading protocol, and hardware layout integrity checks. |

---

## 📜 License

NixVM is open-source software licensed under the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for more details.