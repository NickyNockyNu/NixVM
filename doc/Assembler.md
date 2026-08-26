# NixVM Assembler & Toolchain Reference
**Document Version:** 1.0  
**Target Assembler:** `nvma` (NixVM Assembler) / `nvmd` (NixVM Disassembler)  
**File Extensions:** `.asm`, `.inc` (Source) | `.nvm` (Cartridge) | `.bin` (Raw)  

---

## Table of Contents
1. [Source Code Anatomy & Syntax Rules](#1-source-code-anatomy--syntax-rules)
2. [Constants & Symbolic Definitions (`.equ`)](#2-constants--symbolic-definitions-equ)
3. [Labels & Lexical Scoping](#3-labels--lexical-scoping)
4. [Numeric Literals & Multipliers (`k` / `m`)](#4-numeric-literals--multipliers-k--m)
5. [Label Offset Arithmetic (`Label + Offset`)](#5-label-offset-arithmetic)
6. [Complete Directives Reference](#6-complete-directives-reference)
   * [6.1 Program & Target Configuration](#61-program--target-configuration)
   * [6.2 Data Definition Directives](#62-data-definition-directives)
   * [6.3 Memory & Asset Directives](#63-memory--asset-directives)
7. [Command-Line Tools (`nvma` & `nvmd`)](#7-command-line-tools-nvma--nvmd)

---

## 1. Source Code Anatomy & Syntax Rules

An assembly source file (`.asm`) consists of lines containing **labels**, **instructions**, **directives**, and **comments**.

### 1.1 Line Structure
Every line follows this structure:
```text
[Label:]   [Mnemonic / Directive]   [Operands]   [; Comment]
```

### 1.2 General Syntax Rules
* **Case Insensitivity:** All mnemonics (`mov`, `MOV`), register names (`r0`, `R0`, `sp`, `SP`), and directives (`.db`, `.DB`, `.include`) are case-insensitive.
* **Whitespace:** Whitespace (spaces and tabs `#9`) separates tokens and is otherwise ignored. Blank lines are preserved in disassembled listings for readability.
* **Comments:** Any text following a semicolon `;` up to the end of the line is treated as a comment and preserved in Intermediate Representation (IR) listings.
* **String Literals:** Enclosed in double quotes `"Hello"` or single quotes `'Hello'`. Double quotes inside strings are escaped by doubling them (`""`).

---

## 2. Constants & Symbolic Definitions (`.equ`)

Compile-time constants can be defined using `.equ` or `.const`.

### 2.1 Syntax
```text
<NAME> .equ <VALUE>
<NAME> .const <VALUE>
```

### 2.2 Features
* Constants are resolved entirely at compile time and consume **0 bytes** of runtime memory.
* Constants can be used anywhere a numeric literal is accepted (instructions, data directives, memory allocations).

### 2.3 Example
```text
; Struct field offsets
PLAYER_X      .equ 0
PLAYER_Y      .equ 4
PLAYER_HEALTH .equ 8

; Bitmasks and settings
FLAG_ALIVE    .equ %00000001
MAX_ENEMIES   .equ 16
VRAM_BUFFER   .equ 64k

@Start:
  mov   r0, MAX_ENEMIES
  bset  r1, FLAG_ALIVE
  ldo   r2, r3, PLAYER_HEALTH   ; Load from [r3 + 8]
```

---

## 3. Labels & Lexical Scoping

NixVM implements a **two-tier lexical scoping model** that prevents naming collisions between subroutines.

```text
GlobalLabel:          ; Scope opens: "GlobalLabel"
  @local_label:       ; Mangled as "GlobalLabel@local_label"
    ...
    jnz @local_label  ; Jumps to "GlobalLabel@local_label"

OtherFunction:        ; New global scope opens: "OtherFunction"
  @local_label:       ; Mangled as "OtherFunction@local_label" (No collision!)
    ...
    jnz @local_label  ; Jumps to "OtherFunction@local_label"
```

### 3.1 Global Labels
* **Syntax:** Any identifier that **does not start with `@`**, followed by a colon `:` (e.g. `Main:`, `UpdatePlayer:`, `_data_table:`).
* **Scope:** Visible globally across all included source files.
* **Action:** Resets the active local scope to itself.

### 3.2 Scoped Local Labels
* **Syntax:** Any identifier **starting with `@`**, followed by a colon `:` (e.g. `@loop:`, `@exit:`, `@skip:`).
* **Scope:** Scoped exclusively to the most recent preceding Global Label.
* **Advantage:** Eliminates unique label naming fatigue (`@loop1`, `@loop2`, `@loop3`)—subroutines can reuse names like `@loop` and `@done` without collision.

---

## 4. Numeric Literals & Multipliers (`k` / `m`)

NixVM provides rich number formats and built-in unit multipliers across all operands and directives.

### 4.1 Supported Number Formats

| Format | Syntax Example | Parsed Value |
| :--- | :--- | :--- |
| **Decimal** | `100`, `-50` | `100`, `-50` |
| **Pascal Hexadecimal** | `$1A2F`, `-$10` | `6671`, `-16` |
| **C-Style Hexadecimal** | `0x1A2F` | `6671` |
| **Pascal Binary** | `%10101010` | `170` |
| **C-Style Binary** | `0b10101010` | `170` |
| **Floating-Point Single** | `3.14159`, `-0.5`, `1.0e-5` | 32-Bit IEEE-754 Bitcast |

### 4.2 Suffix Multipliers (`K` and `M`)
Appending `K` (Kilobytes, $\times 1,024$) or `M` (Megabytes, $\times 1,048,576$) applies a hardware multiplier:

* `16k` $\to$ `16,384`
* `64k` $\to$ `65,536`
* `$10k` $\to$ `$4000` (`16 * 1024 = 16,384`)
* `1m` $\to$ `1,048,576`

---

## 5. Label Offset Arithmetic (`Label + Offset`)

NixVM supports compile-time label arithmetic in any operand position.

### 5.1 Syntax
* `<Label> + <Offset>`
* `<Label> - <Offset>`

*(Where `<Offset>` can be an integer number, hex value, or `.equ` constant).*

### 5.2 Semantics
During link time, the final 32-bit address is computed as:
$$\text{Address} = \text{Address}(\text{Label}) \pm \text{Offset}$$

### 5.3 Example
```text
_table: .db 10, 20, 30, 40, 50

@Start:
  ; Read 3rd element directly (_table + 2)
  mov   r1, _table + 2
  ldb   r0, [r1]          ; r0 = 30

  ; Offset with an EQU constant
  ldo   r0, r2, _player + PLAYER_HEALTH
```

---

## 6. Complete Directives Reference

---

### 6.1 Program & Target Configuration

---

#### `.target` — Specify Target Fantasy Console
Declares the target fantasy console harness and minimum required version.

* **Syntax:** `.target "<HarnessName>" [, <Major>, <Minor>]`
* **Example:**
  ```text
  .target "NixConsole2D", 1, 0
  ```

---

#### `.base` — Specify Execution Base Address
Declares the required base execution address (`UserAddress`) in virtual memory.

* **Syntax:** `.base <Address>`
* **Example:**
  ```text
  .base $000004E0
  ```

---

#### `.name` — Set ROM Title
Sets the human-readable title stored in the cartridge header.

* **Syntax:** `.name "<Title>"`
* **Example:**
  ```text
  .name "Space Invaders 32"
  ```

---

#### `.version` — Set ROM Program Version
Sets the program major and minor version numbers in the cartridge header.

* **Syntax:** `.version <Major>, <Minor>`
* **Example:**
  ```text
  .version 1, 2
  ```

---

#### `.heap` — Request Dynamic Heap Size
Sets the initial heap allocation budget for the cartridge. Supports `k`/`m` multipliers.

* **Syntax:** `.heap <Size>`
* **Example:**
  ```text
  .heap 128k              ; Request 131,072 bytes heap
  ```

---

#### `.stack` — Request Hardware Stack Size
Sets the stack allocation budget for the cartridge. Supports `k`/`m` multipliers.

* **Syntax:** `.stack <Size>`
* **Example:**
  ```text
  .stack 16k              ; Request 16,384 bytes stack
  ```

---

### 6.2 Data Definition Directives

---

#### `.db` / `.byte` — Define 8-Bit Bytes
Emits a sequence of 8-bit unsigned bytes or ASCII characters.

* **Syntax:** `.db <val1> [, <val2>, ...]`
* **Example:**
  ```text
  .db $01, $02, $FF, 128
  .db "ABC", 0
  ```

---

#### `.dw` / `.word` — Define 16-Bit Words
Emits a sequence of 16-bit little-endian words.

* **Syntax:** `.dw <val1> [, <val2>, ...]`
* **Example:**
  ```text
  .dw 1000, $04E0, $FFFF
  ```

---

#### `.dd` / `.dword` — Define 32-Bit DWords
Emits a sequence of 32-bit little-endian integers or addresses.

* **Syntax:** `.dd <val1> [, <val2>, ...]`
* **Example:**
  ```text
  .dd $12345678, @MyFunction, 100000
  ```

---

#### `.float` / `.single` — Define 32-Bit Floating-Point Numbers
Emits a sequence of 32-bit IEEE-754 Single-precision floating-point numbers.

* **Syntax:** `.float <val1> [, <val2>, ...]`
* **Example:**
  ```text
  .float 3.1415927, -0.5, 100.0, 1.25e-3
  ```

---

#### `.str` / `.ds` / `.ascii` — Define Literal String (Exact Bytes)
Emits a raw ASCII string without appending an automatic null terminator.

* **Syntax:** `.str <string_or_bytes>`
* **Example:**
  ```text
  _msg: .str "Hello", 13, 10, "World!"
  ```

---

#### `.asciiz` / `.strz` / `.dsz` — Define Null-Terminated String
Emits an ASCII string and automatically guarantees a trailing `#0` null terminator.

* **Syntax:** `.asciiz <string_or_bytes>`
* **Example:**
  ```text
  _msg: .asciiz "Score: %d", 13, 10
  ```

---

### 6.3 Memory & Asset Directives

---

#### `.res` / `.resb` — Reserve Uninitialized / Zeroed Bytes
Reserves a contiguous block of zeroed memory without bloating the `.asm` file.

* **Syntax:** `.res <ByteCount>`
* **Example:**
  ```text
  _vram_buffer: .res 64k           ; Allocate 65,536 bytes
  _player_data: .res 128
  ```

---

#### `.align` — Memory Alignment
Pads memory with zeroes (or an optional pad byte) until the current address is divisible by `<Boundary>`.

* **Syntax:** `.align <Boundary> [, <PadByte>]`
* **Example:**
  ```text
  .align 4              ; Align to 4-byte boundary with $00
  .align 8, $FF         ; Align to 8-byte boundary with $FF (NOP)
  ```

---

#### `.embed` / `.includeb` — Embed Binary Asset File
Embeds an external raw binary asset (sprites, sounds, tilemaps, fonts) directly into memory at assemble time.

* **Syntax:** `.embed "<FilePath>"`
* **Example:**
  ```text
  _sprites: .embed "assets/hero.spr"
  _sound:   .embed "assets/jump.wav"
  ```

---

#### `.include` — Include Assembly Source File
Inlines an external `.asm` or `.inc` source file directly into the compilation stream. Features recursive include depth and automatic circular-include protection.

* **Syntax:** `.include "<FilePath>"`
* **Example:**
  ```text
  .include "target_nix2d.inc"
  .include "math_utils.asm"
  ```

---

## 7. Command-Line Tools (`nvma` & `nvmd`)

The NixVM SDK includes two command-line utilities:

---

### 7.1 `nvma` — The NixVM Command-Line Assembler

Assembles `.asm` source files into `.nvm` cartridges or raw `.bin` binaries.

```bash
# Basic Assembly to Cartridge
nvma game.asm

# Specify Output File and Custom Memory Sizes
nvma game.asm -o bin/game.nvm -heap 128k -stack 32k

# Emit Raw Binary Payload without Cartridge Header
nvma font.asm -raw -o font.bin

# Generate Assembly Listing (.lst)
nvma game.asm -l listing.lst

# Verbose Output Mode
nvma game.asm -v
```

#### Command-Line Options:
* `-o <file>` : Specify output binary filename (default: `<input>.nvm` or `<input>.bin`).
* `-b <addr>` : Override expected base address (e.g. `-b $000004E0`).
* `-h <size>` / `-heap <size>` : Override heap allocation size (e.g. `-h 1m`, `-h 64k`).
* `-s <size>` / `-stack <size>` : Override stack allocation size (e.g. `-s 32k`).
* `-l <file>` : Generate formatted assembly listing file (`.lst`).
* `-raw` : Output raw binary payload without `TROMHeader`.
* `-v` / `--verbose` : Display detailed memory and target metadata summary.

---

### 7.2 `nvmd` — The NixVM Command-Line Disassembler

Disassembles `.nvm` cartridges or raw binaries into clean, reconstructible assembly listings.

```bash
# Disassemble a ROM directly to stdout
nvmd game.nvm

# Disassemble a ROM to a new .asm source file
nvmd game.nvm -o game_disasm.asm

# Disassemble a raw binary at a specific base address
nvmd payload.bin -raw -b $000004E0 -o payload.asm
```

#### Command-Line Options:
* `-o <file>` : Write disassembly to file instead of stdout.
* `-b <addr>` : Specify base execution address when disassembling raw binaries (default: `$000004E0`).
* `-raw` : Treat input file as a raw binary without a ROM header.
* `-v` / `--verbose` : Display header and metadata information.