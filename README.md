# NixVM — Virtual Microprocessor & Fantasy Console Engine

**Copyright (c) 2026 Nicholas Smith**  
*Licensed under the GNU General Public License v3.0*

---

## 📖 Overview

**NixVM** is a modular, high-performance 32-bit virtual RISC microprocessor, memory architecture, and toolchain designed as a universal foundation for building **fantasy consoles, retro computers, and embedded scripting runtimes**.

Instead of reinventing custom instruction sets and memory controllers for every new virtual console, NixVM provides an extensible, dependency-free core engine with first-class tooling: A Pascal compiler (`nvmc`), an Intermediate Representation (IR) linker, a full text assembler (`nvma`), a reverse-engineering disassembler (`nvmd`), and a universal cartridge packaging system (`.nvm`).

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

## 📚 Technical Documentation

Explore the complete, language-agnostic hardware specification manuals:

| Specification Document | Description |
| :--- | :--- |
| **[CPU & Instruction Set Reference](doc/CPU.md)** | Core processor architecture, register map, flags layout, ABI calling conventions, and complete datasheet for all 80+ instructions. |
| **[Memory & MMIO Reference](doc/Memory.md)** | Virtual memory map, Core System Area (`$0000`–`$04DF`), System Registers (`Delta`/`Elapsed`), hardware timers, and OEM peripheral mapping. |
| **[SysCalls & Interrupts Reference](doc/Syscalls_and_Interrupts.md)** | Complete SysCall ABI, heap/string services, hardware panic error codes, and the 16 prioritized interrupt vectors. |
| **[Assembler & Toolchain Guide](doc/Assembler.md)** | Assembly syntax, directives (`.embed`, `.include`, `.align`, `.res`), label scoping (`@local`), constants (`.equ`), and CLI tool documentation. |
| **[ROM Cartridge Format (`.nvm`)](doc/ROM_Format.md)** | The official 92-byte `NVMX` cartridge header specification, loading protocol, and hardware layout integrity checks. |

---

## 🛠️ Quick Start (assembler)

### 1. Writing Your First Program (`hello.asm`)

```text
.include "target_test.inc"

.name    "Hello World"
.heap    0
.stack   256

@Start:
  mov   r0, _fmt_str
  mov   r1, _msg_hello
  mov   r2, _msg_world
  syscall $01               ; Invoke DebugPrint
  halt

_fmt_str:   .str "%s, %s!\n", 0
_msg_hello: .str "Hello", 0
_msg_world: .str "World", 0
```

---

### 2. Assembling to Cartridge (`nvma`)

Compile the assembly source into a `.nvm` cartridge using the command-line assembler:

```bash
# Assembles hello.asm -> hello.nvm
nvma hello.asm -v
```

**Output:**
```text
NixVM Assembler v1.0
Copyright (c) 2026 Nicholas Smith
https://github.com/NickyNockyNu/NixVM

Assembling "hello.asm" ...

SUCCESS: Output written to "hello.nvm"
  Base Address: $000004E0
  Code Size:    56 bytes
  Target:       "Test" (v1.0)
  ROM Title:    "Hello World" (v1.0)
  Heap Size:    0 bytes
  Stack Size:   256 bytes
```

---

### 3. Disassembling a ROM (`nvmd`)

Inspect or reverse-engineer any compiled cartridge back into structured assembly:

```bash
# Disassemble cartridge directly to screen
nvmd hello.nvm
```

**Output:**
```text
.target	"Test", 1, 0
.name	"Hello World"
.base	$4E0
.stack	256

  call	sub_000004E8
  halt

sub_000004E8:
  mov	r0, data_00000502
  mov	r1, data_0000050C
  mov	r2, data_00000512
  syscall	$1              ; _SysCall_DebugPrint
  ret

data_00000502:
  .str	"%s, %s!\n", 0

data_0000050C:
  .str	"Hello", 0

data_00000512:
  .str	"World", 0
```

---

### 4. Running a Cartridge in a Custom Fantasy Console Harness

To run a cartridge in a host fantasy console harness:

```pascal
type
  TMySystemMemory = record
    // Put your custom system memory layout in here
  end;
  
  TMyConsole = class(TCustomHarness<TMySystemMemory>);
    // Define your consoles custom behaviour in here
    // (See the custom harness source for more information (documentation is WiP))
  end;
  
begin
  // Create an instance of your console and load a ROM
  TMyConsole.Run('roms/myrom.nvm');
end.
```

---

## 🛠️ Quick Start (pascal)

### 1. Writing Your First Program (`HelloWorld.pas`)

```pascal
program HelloWorld targets Test;

{$HEAP 0}
{$STACK 128}
{$BASE $4E0}

uses
  System;

begin
  Writeln('Hello, World!');
end.
```

---

### 2. Compiling to Cartridge (`nvma`)

Compile the pascal source into a `.nvm` cartridge using the command-line compiler:

```bash
# Compiles HelloWorld.pas -> HelloWorld.nvm
nvmc HelloWorld.pas -v
```

**Output:**
```text
NixVM Pascal Compiler v1.0
Copyright (c) 2026 Nicholas Smith
https://github.com/NickyNockyNu/NixVM

Compiling "HelloWorld.pas" ...
SUCCESS: Cartridge written to "HelloWorld.nvm"

        ROM: HelloWorld v1.0
    Harness: Test v1.0
UserAddress: 0x000004E0
   UserSize: 42
   HeapSize: 0
  StackSize: 128
```

---

## 📂 Project Structure

```text
NixVM/
├── src/     # Lean, dependency-free core VM engine
│   ├── NixVM.Core.CPU.pas                  # 32-bit RISC CPU fetch-decode-execute engine
│   ├── NixVM.Core.Instructions.pas         # Opcode tables and instruction definitions
│   ├── NixVM.Core.Memory.pas               # Sandboxed memory, dynamic heap, and managed strings
│   ├── NixVM.Core.Registers.pas            # Register file, flags helpers, and aliases
│   ├── NixVM.Core.ROM.pas                  # NVMX Universal Cartridge header definition
│   ├── NixVM.Core.Strings.pas              # Zero-dependency string formatting intrinsics
│   ├── NixVM.Core.System.pas               # Core System area layout, SysCalls, and Interrupts
│   ├── NixVM.Tools.IR.pas                  # Intermediate Representation & symbol resolver
│   ├── NixVM.Tools.Assembler.pas           # Full multi-file text assembler
│   ├── NixVM.Tools.Disasm.pas              # Intelligent binary disassembler
│   ├── NixVM.Tools.Compiler.pas            # Pascal compiler
│   ├── NixVM.Tools.Compiler.AST.pas        # Abstract Syntax Tree
│   ├── NixVM.Tools.Compiler.CodeGen.pas    # IR code generator for the NixVM CPU
│   ├── NixVM.Tools.Compiler.Lexer.pas      # Pascal lexer / tokenizer
│   ├── NixVM.Tools.Compiler.Parser.pas     # Recursive Descent Parser
│   ├── NixVM.Tools.Compiler.Semantics.pas  # Semantic analyzer, symbol table and type checker
│   ├── NixVM.Harness.pas                   # Base execution harness & cartridge loader
│   ├── NixVM.Harness.Timing.pas            # Stopwatch & microsecond precision timing
│   └── NixVM.Harness.Window.pas            # Windows GUI harness & message loop
└── doc/     # Technical architecture specifications
    ├── CPU.md                      # CPU & Instruction set reference
    ├── Memory.md                   # Memory map & system registers
    ├── Syscalls_and_Interrupts.md  # SysCall API & interrupt vectors
    ├── Assembler.md                # Assembly syntax & directive reference
    └── ROM_Format.md               # .nvm Cartridge binary specification
```

---

## 📜 License

NixVM is open-source software licensed under the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for more details.