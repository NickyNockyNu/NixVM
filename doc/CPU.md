# NixVM CPU Architecture & Instruction Set Reference
**Document Version:** 1.0  
**Target Architecture:** 32-Bit NixVM Core Processor  
**Byte Order:** Little-Endian  

---

## Table of Contents
1. [Architecture Overview](#1-architecture-overview)
2. [Instruction Encoding](#2-instruction-encoding)
3. [Register Set](#3-register-set)
4. [Processor Flags Register](#4-processor-flags-register)
5. [Stack Architecture & Calling Convention (ABI)](#5-stack-architecture--calling-convention-abi)
6. [Instruction Set Reference](#6-instruction-set-reference)
   * [6.1 System & Control](#61-system--control)
   * [6.2 Data Movement & Extension](#62-data-movement--extension)
   * [6.3 Unsigned Integer Arithmetic](#63-unsigned-integer-arithmetic)
   * [6.4 Signed Integer Arithmetic](#64-signed-integer-arithmetic)
   * [6.5 Bitwise Logic & Shift Operations](#65-bitwise-logic--shift-operations)
   * [6.6 Bit Manipulation & Flag Control](#66-bit-manipulation--flag-control)
   * [6.7 Memory Load & Store](#67-memory-load--store)
   * [6.8 Branches, Jumps & Loops](#68-branches-jumps--loops)
   * [6.9 Subroutines, Stack & Execution Flow](#69-subroutines-stack--execution-flow)
   * [6.10 Floating-Point Unit (FPU)](#610-floating-point-unit-fpu)
   * [6.11 Condition Code Setters (`setcc`)](#611-condition-code-setters-setcc)

---

## 1. Architecture Overview

The NixVM processor is a 32-bit register-based virtual processor designed for high performance, ease of code generation, and predictable execution timing.

* **Data Word Size:** 32-bit unsigned/signed integers and IEEE-754 Single-precision floating-point numbers.
* **Address Space:** 32-bit byte-addressed flat memory space ($00000000..$FFFFFFFF) with power-of-two hardware wrapping.
* **Pipeline Mechanism:** Prefetch-decode stage with transparent immediate operand loading via hardware pseudo-register `R13` (`Imm`).
* **Execution Paradigm:** Deterministic instruction execution with cooperative host-yielding (`yield`).

---

## 2. Instruction Encoding

Every instruction begins with a fixed **16-bit instruction word**, optionally followed by one or two 32-bit trailing data values:

```text
Bit:  15       12 11        8 7            0
     +-----------+-----------+--------------+
     |   Reg B   |   Reg A   |    Opcode    |
     +-----------+-----------+--------------+
     [4-bit ID]   [4-bit ID]     [8-bit ID]
```

### 2.1 Instruction Size Categories

| Parameter Format | Byte Size | Layout in Memory |
| :--- | :--- | :--- |
| **`None`** | 2 Bytes | `[ Opcode (8b) \| RegA (4b) \| RegB (4b) ]` |
| **`R1`** | 2 Bytes | `[ Opcode (8b) \| RegA (4b) \| 0000 (4b) ]` |
| **`R1R2`** (Register) | 2 Bytes | `[ Opcode (8b) \| RegA (4b) \| RegB (4b) ]` |
| **`R1R2`** (Immediate) | 6 Bytes | `[ Opcode (8b) \| RegA (4b) \| 1101 (4b) ] + [ 32-bit Immediate ]` |
| **`RImm`** (Register) | 2 Bytes | `[ Opcode (8b) \| 0000 (4b) \| RegB (4b) ]` |
| **`RImm`** (Immediate) | 6 Bytes | `[ Opcode (8b) \| 0000 (4b) \| 1101 (4b) ] + [ 32-bit Immediate ]` |
| **`Imm`** | 6 Bytes | `[ Opcode (8b) \| 0000 (4b) \| 0000 (4b) ] + [ 32-bit Target/Immediate ]` |
| **`R1Imm`** | 6 Bytes | `[ Opcode (8b) \| RegA (4b) \| 0000 (4b) ] + [ 32-bit Target/Immediate ]` |
| **`R1R2Imm`** (Register Base) | 6 Bytes | `[ Opcode (8b) \| RegA (4b) \| RegB (4b) ] + [ 32-bit Displacement ]` |
| **`R1R2Imm`** (Immediate Base) | 10 Bytes | `[ Opcode (8b) \| RegA (4b) \| 1101 (4b) ] + [ 32-bit Base ] + [ 32-bit Disp ]` |

---

## 3. Register Set

The processor features sixteen 32-bit general-purpose registers (`R0` through `R15`), an 8-bit `Flags` register, and a 32-bit Program Counter (`PC`).

```text
+----------+------------+----------------------------------------------------+
| Register | Standard   | Architectural / ABI Purpose                        |
| Index    | Alias      |                                                    |
+----------+------------+----------------------------------------------------+
| R0       | Ret, P1    | Function Return Value / SysCall Parameter 1        |
| R1       | P2         | SysCall Parameter 2 / General Scratch              |
| R2       | P3         | SysCall Parameter 3 / General Scratch              |
| R3       | P4         | SysCall Parameter 4 / General Scratch              |
| R4..R12  | _4.._12    | General Purpose Scratch Registers                  |
| R13      | Imm        | Hardware Pseudo-Register (Immediate Accumulator)   |
| R14      | BP         | Base Pointer (Stack Frame Anchor)                  |
| R15      | SP         | Stack Pointer (Top of Stack)                       |
+----------+------------+----------------------------------------------------+
| PC       | --         | Program Counter (Address of next instruction)      |
| Flags    | --         | Processor Status & Control Flags (8-bit)           |
+----------+------------+----------------------------------------------------+
```

### 3.1 The `R13` (`Imm`) Hardware Pseudo-Register
Register index `13` is hardwired as the CPU's **Immediate Accumulator**.
* When an instruction encodes `RegB = 13`, the CPU instruction fetch unit **automatically reads the trailing 32-bit DWORD from the instruction stream and writes it into `R13`** before the instruction handler executes.
* This allows all standard two-operand instructions (`mov`, `add`, `sub`, `cmp`, `and`, `or`, `bset`, etc.) to operate seamlessly on 32-bit constants without requiring separate opcode variants.

---

## 4. Processor Flags Register

The 8-bit `Flags` register maintains arithmetic condition codes, floating-point status, and hardware control masks.

```text
Bit:    7       6       5       4       3       2       1       0
     +-------+-------+-------+-------+-------+-------+-------+-------+
     |   -   |   D   |   I   |   F   |   O   |   C   |   N   |   Z   |
     +-------+-------+-------+-------+-------+-------+-------+-------+
      (Res)   DivZ    Intr    FPU     Over    Carry   Neg     Zero
              Panic   Enable  Error   flow
```

| Bit | Flag | Mask | Description |
| :--- | :--- | :--- | :--- |
| **0** | **`Z`** (Zero) | `$01` | Set (`1`) if the result of an operation is equal to `0`; cleared (`0`) otherwise. |
| **1** | **`N`** (Negative) | `$02` | Set (`1`) if the most significant bit (bit 31) of the result is `1`; cleared otherwise. |
| **2** | **`C`** (Carry) | `$04` | Set (`1`) if an unsigned addition produced a carry, or unsigned subtraction produced a borrow. |
| **3** | **`O`** (Overflow) | `$08` | Set (`1`) if a signed arithmetic operation resulted in an integer overflow/underflow. |
| **4** | **`F`** (FPU Error) | `$10` | Set (`1`) if a floating-point exception occurred (e.g. DivByZero, Sqrt of negative, Log of zero/negative). |
| **5** | **`I`** (Interrupts) | `$20` | Control Flag: `1` = Software & hardware interrupts enabled; `0` = Interrupts masked. |
| **6** | **`D`** (DivZ Panic) | `$40` | Control Flag: `1` = Integer divide-by-zero triggers an immediate hardware Panic; `0` = Returns 0 and sets `Zero`/`Carry`. |
| **7** | **Reserved** | `$80` | Unused. Always reads `0`. |

* **Hardware Default Flags State:** `$60` (`%01100000`) — Both `InterruptsEnabled` and `DivZPanicEnabled` are active on reset.

---

## 5. Stack Architecture & Calling Convention (ABI)

### 5.1 Stack Properties
* **Growth Direction:** Downward (from high memory towards low memory).
* **Alignment:** 32-bit (4-byte) aligned.
* **Stack Pointer (`SP` / `R15`):** Points to the most recently pushed 32-bit DWORD on the stack.

### 5.2 Stack Frame Anatomy (`enter` / `leave`)

When a subroutine establishes a standard stack frame using `enter <size>` and returns with `leave`:

```text
High Memory
  |  ... (Caller's Stack Frame) ...
  |  Parameter N
  |  ...
  |  Parameter 5
  |  Return Address (Pushed automatically by CALL)
  |  Saved Frame Pointer (Old BP, pushed by ENTER)  <-- [BP points here]
  |  Local Variable 1  [BP - 4]
  |  Local Variable 2  [BP - 8]
  |  ...
  v  Local Variable N  [BP - size]                  <-- [SP points here]
Low Memory
```

### 5.3 Standard Subroutine Calling Convention
* **Parameters 1 to 4:** Passed in registers `R0`, `R1`, `R2`, `R3` (`P1`–`P4`).
* **Parameters 5+:** Pushed onto the stack in right-to-left order prior to `call`.
* **Return Value:** Returned in `R0` (`Ret`).
* **Volatile (Caller-Saved) Registers:** `R0`, `R1`, `R2`, `R3`, `R13`. May be overwritten by the callee.
* **Non-Volatile (Callee-Saved) Registers:** `R4`–`R12`, `R14` (`BP`), `R15` (`SP`). Must be preserved across calls.

---

## 6. Instruction Set Reference

---

### 6.1 System & Control

---

#### `halt` — Halt Processor Execution
**Opcode:** `$00` | **Format:** `None` | **Size:** 2 Bytes

* **Syntax:** `halt`
* **Operation:**
  ```text
  HaltState = True
  ```
* **Flags Affected:** None
* **Description:** Permanently suspends CPU execution. The processor will execute no further instructions until an external hardware reset or non-maskable panic interrupt occurs.
* **Example:**
  ```text
  halt
  ```

---

#### `yield` — Yield Execution Time-Slice
**Opcode:** `$01` | **Format:** `None` | **Size:** 2 Bytes

* **Syntax:** `yield`
* **Operation:**
  ```text
  YieldState = True
  ```
* **Flags Affected:** None
* **Description:** Cooperatively suspends CPU instruction execution for the remainder of the current host frame window. Control returns to the host harness to process display presentation, audio mixing, and OS events. Execution resumes automatically at `PC + 2` on the next frame tick.
* **Example:**
  ```text
  @GameLoop:
    call  UpdateGame
    call  RenderGame
    yield             ; Done for this frame!
    jmp   @GameLoop
  ```

---

#### `nop` — No Operation
**Opcode:** `$FF` | **Format:** `None` | **Size:** 2 Bytes

* **Syntax:** `nop`
* **Operation:**
  ```text
  PC = PC + 2
  ```
* **Flags Affected:** None
* **Description:** Performs no operation other than advancing the program counter.
* **Example:**
  ```text
  nop
  ```

---

### 6.2 Data Movement & Extension

---

#### `mov` — Move 32-Bit Value
**Opcode:** `$10` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:** 
  * `mov <rdest>, <rsrc>`
  * `mov <rdest>, <imm32>`
* **Operation:**
  ```text
  rdest = rsrc
  ```
* **Flags Affected:** None
* **Description:** Copies the 32-bit value of `rsrc` (or a 32-bit immediate constant) into `rdest`.
* **Examples:**
  ```text
  mov r0, r1          ; Copy r1 into r0
  mov r0, 100         ; Load immediate 100 into r0
  mov r0, data_buffer ; Load 32-bit memory address into r0
  ```

---

#### `swap` — Swap Two Registers
**Opcode:** `$11` | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:** `swap <ra>, <rb>`
* **Operation:**
  ```text
  temp = ra
  ra   = rb
  rb   = temp
  ```
* **Flags Affected:** None
* **Description:** Atomically exchanges the 32-bit contents of register `ra` and register `rb`.
* **Example:**
  ```text
  swap r0, r1
  ```

---

#### `cmp` — Compare Two Values
**Opcode:** `$12` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:**
  * `cmp <ra>, <rb>`
  * `cmp <ra>, <imm32>`
* **Operation:**
  ```text
  temp64 = uint64(ra) - uint64(rb)
  temp32 = uint32(temp64 & 0xFFFFFFFF)
  Flags.UpdateZN(temp32)
  Flags.Carry    = (ra < rb)
  Flags.Overflow = ((ra ^ rb) & (ra ^ temp32) & 0x80000000) != 0
  ```
* **Flags Affected:** `Z`, `N`, `C`, `O`
* **Description:** Computes `ra - rb` to set the arithmetic condition flags, discarding the result without modifying `ra`.
* **Examples:**
  ```text
  cmp r0, r1          ; Compare r0 with r1
  cmp r0, 10          ; Compare r0 with immediate 10
  je  @IsEqual        ; Jump if r0 == 10
  ```

---

#### `lea` — Load Effective Address
**Opcode:** `$13` | **Format:** `R1R2Imm` | **Size:** 6 Bytes (Register Base) / 10 Bytes (Immediate Base)

* **Syntax:**
  * `lea <rdest>, <rbase>, <disp32>`
  * `lea <rdest>, <imm_base>, <disp32>`
* **Operation:**
  ```text
  rdest = rbase + disp32
  Flags.UpdateZN(rdest)
  ```
* **Flags Affected:** `Z`, `N`
* **Description:** Computes the address formed by adding base register `rbase` and a 32-bit displacement `disp32`, storing the result in `rdest`.
* **Examples:**
  ```text
  lea r0, r1, 16          ; r0 = r1 + 16
  lea r0, bp, -8          ; r0 = address of local variable at [BP - 8]
  lea r0, player_base, 32 ; r0 = player_base + 32
  ```

---

#### `zextb` — Zero-Extend Byte to DWord
**Opcode:** `$14` | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:** `zextb <rdest>, <rsrc>`
* **Operation:**
  ```text
  rdest = rsrc & 0x000000FF
  Flags.UpdateZN(rdest)
  ```
* **Flags Affected:** `Z`, `N`
* **Description:** Clears bits 8..31 of `rsrc` and writes the resulting 8-bit unsigned value into `rdest`.
* **Example:**
  ```text
  zextb r0, r1
  ```

---

#### `zextw` — Zero-Extend Word to DWord
**Opcode:** `$15` | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:** `zextw <rdest>, <rsrc>`
* **Operation:**
  ```text
  rdest = rsrc & 0x0000FFFF
  Flags.UpdateZN(rdest)
  ```
* **Flags Affected:** `Z`, `N`
* **Description:** Clears bits 16..31 of `rsrc` and writes the resulting 16-bit unsigned value into `rdest`.
* **Example:**
  ```text
  zextw r0, r1
  ```

---

### 6.3 Unsigned Integer Arithmetic

---

#### `add` — Unsigned Integer Addition
**Opcode:** `$20` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:**
  * `add <rdest>, <rsrc>`
  * `add <rdest>, <imm32>`
* **Operation:**
  ```text
  temp64 = uint64(rdest) + uint64(rsrc)
  rdest  = uint32(temp64 & 0xFFFFFFFF)
  Flags.UpdateZN(rdest)
  Flags.Carry    = (temp64 > 0xFFFFFFFF)
  Flags.Overflow = ((left ^ rdest) & (right ^ rdest) & 0x80000000) != 0
  ```
* **Flags Affected:** `Z`, `N`, `C`, `O`
* **Examples:**
  ```text
  add r0, r1
  add r0, 4
  ```

---

#### `sub` — Unsigned Integer Subtraction
**Opcode:** `$21` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:**
  * `sub <rdest>, <rsrc>`
  * `sub <rdest>, <imm32>`
* **Operation:**
  ```text
  temp64 = uint64(rdest) - uint64(rsrc)
  rdest  = uint32(temp64 & 0xFFFFFFFF)
  Flags.UpdateZN(rdest)
  Flags.Carry    = (rdest < rsrc)
  Flags.Overflow = ((left ^ right) & (left ^ rdest) & 0x80000000) != 0
  ```
* **Flags Affected:** `Z`, `N`, `C`, `O`
* **Examples:**
  ```text
  sub r0, r1
  sub r0, 1
  ```

---

#### `mul` — Unsigned Integer Multiplication
**Opcode:** `$22` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:**
  * `mul <rdest>, <rsrc>`
  * `mul <rdest>, <imm32>`
* **Operation:**
  ```text
  temp64 = uint64(rdest) * uint64(rsrc)
  rdest  = uint32(temp64 & 0xFFFFFFFF)
  Flags.UpdateZN(rdest)
  Flags.Carry    = (temp64 > 0xFFFFFFFF)
  Flags.Overflow = Flags.Carry
  ```
* **Flags Affected:** `Z`, `N`, `C`, `O`
* **Examples:**
  ```text
  mul r0, r1
  mul r0, 10
  ```

---

#### `div` — Unsigned Integer Division
**Opcode:** `$23` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:**
  * `div <rdest>, <rsrc>`
  * `div <rdest>, <imm32>`
* **Operation:**
  ```text
  if rsrc == 0 then
    rdest = 0
    Flags.Zero = 1; Flags.Carry = 1
    if Flags.DivZPanicEnabled then Panic(DivideByZero)
  else
    rdest = rdest div rsrc
    Flags.UpdateZN(rdest)
  ```
* **Flags Affected:** `Z`, `N`, `C`
* **Examples:**
  ```text
  div r0, r1
  div r0, 2
  ```

---

#### `mod` — Unsigned Integer Modulo / Remainder
**Opcode:** `$24` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:**
  * `mod <rdest>, <rsrc>`
  * `mod <rdest>, <imm32>`
* **Operation:**
  ```text
  if rsrc == 0 then
    rdest = 0
    Flags.Zero = 1; Flags.Carry = 1
    if Flags.DivZPanicEnabled then Panic(DivideByZero)
  else
    rdest = rdest mod rsrc
    Flags.UpdateZN(rdest)
  ```
* **Flags Affected:** `Z`, `N`, `C`
* **Examples:**
  ```text
  mod r0, r1
  mod r0, 16
  ```

---

### 6.4 Signed Integer Arithmetic

---

#### `imul` — Signed Integer Multiplication
**Opcode:** `$30` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:**
  * `imul <rdest>, <rsrc>`
  * `imul <rdest>, <imm32>`
* **Operation:**
  ```text
  temp64 = int64(int32(rdest)) * int64(int32(rsrc))
  rdest  = uint32(temp64 & 0xFFFFFFFF)
  Flags.UpdateZN(rdest)
  Flags.Overflow = (temp64 < -2147483648) or (temp64 > 2147483647)
  Flags.Carry    = Flags.Overflow
  ```
* **Flags Affected:** `Z`, `N`, `C`, `O`
* **Example:**
  ```text
  imul r0, -5
  ```

---

#### `idiv` — Signed Integer Division
**Opcode:** `$31` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:**
  * `idiv <rdest>, <rsrc>`
  * `idiv <rdest>, <imm32>`
* **Operation:**
  ```text
  if (rsrc == 0) or (rdest == 0x80000000 and rsrc == -1) then
    rdest = 0
    Flags.Zero = 1; Flags.Carry = 1
    if Flags.DivZPanicEnabled then Panic(DivideByZero)
  else
    rdest = uint32(int32(rdest) div int32(rsrc))
    Flags.UpdateZN(rdest)
  ```
* **Flags Affected:** `Z`, `N`, `C`
* **Example:**
  ```text
  idiv r0, -2
  ```

---

#### `imod` — Signed Integer Modulo
**Opcode:** `$32` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:**
  * `imod <rdest>, <rsrc>`
  * `imod <rdest>, <imm32>`
* **Operation:**
  ```text
  if rsrc == 0 then
    rdest = 0
    Flags.Zero = 1; Flags.Carry = 1
    if Flags.DivZPanicEnabled then Panic(DivideByZero)
  else
    rdest = uint32(int32(rdest) mod int32(rsrc))
    Flags.UpdateZN(rdest)
  ```
* **Flags Affected:** `Z`, `N`, `C`
* **Example:**
  ```text
  imod r0, 10
  ```

---

#### `isar` — Integer Arithmetic Shift Right
**Opcode:** `$33` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:**
  * `isar <rdest>, <rsrc>`
  * `isar <rdest>, <shift_count>`
* **Operation:**
  ```text
  count = rsrc & 0x1F
  rdest = uint32(int32(rdest) sar count)
  Flags.UpdateZN(rdest)
  ```
* **Flags Affected:** `Z`, `N`
* **Description:** Performs a signed arithmetic right shift, shifting in sign bits (bit 31) from the left to preserve negative signed values.
* **Example:**
  ```text
  isar r0, 2          ; Signed divide by 4
  ```

---

#### `ineg` — Integer Negation (Two's Complement)
**Opcode:** `$34` | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:** `ineg <rdest>, <rsrc>`
* **Operation:**
  ```text
  rdest = uint32(-int32(rsrc))
  Flags.UpdateZN(rdest)
  Flags.Overflow = (rsrc == 0x80000000)
  Flags.Carry    = (rsrc != 0)
  ```
* **Flags Affected:** `Z`, `N`, `C`, `O`
* **Example:**
  ```text
  ineg r0, r1         ; r0 = -r1
  ```

---

#### `iextb` — Sign-Extend Byte to DWord
**Opcode:** `$35` | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:** `iextb <rdest>, <rsrc>`
* **Operation:**
  ```text
  rdest = uint32(int32(int8(rsrc & 0xFF)))
  Flags.UpdateZN(rdest)
  ```
* **Flags Affected:** `Z`, `N`
* **Description:** Sign-extends the low 8-bit byte of `rsrc` across all 32 bits of `rdest`.
* **Example:**
  ```text
  iextb r0, r1
  ```

---

#### `iextw` — Sign-Extend Word to DWord
**Opcode:** `$36` | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:** `iextw <rdest>, <rsrc>`
* **Operation:**
  ```text
  rdest = uint32(int32(int16(rsrc & 0xFFFF)))
  Flags.UpdateZN(rdest)
  ```
* **Flags Affected:** `Z`, `N`
* **Description:** Sign-extends the low 16-bit word of `rsrc` across all 32 bits of `rdest`.
* **Example:**
  ```text
  iextw r0, r1
  ```

---

### 6.5 Bitwise Logic & Shift Operations

---

#### `and` — Bitwise AND
**Opcode:** `$40` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:** `and <rdest>, <rsrc>`
* **Operation:** `rdest = rdest & rsrc; Flags.UpdateZN(rdest)`
* **Flags Affected:** `Z`, `N`
* **Example:** `and r0, $0F`

---

#### `or` — Bitwise OR
**Opcode:** `$41` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:** `or <rdest>, <rsrc>`
* **Operation:** `rdest = rdest | rsrc; Flags.UpdateZN(rdest)`
* **Flags Affected:** `Z`, `N`
* **Example:** `or r0, $80`

---

#### `xor` — Bitwise Exclusive OR
**Opcode:** `$42` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:** `xor <rdest>, <rsrc>`
* **Operation:** `rdest = rdest ^ rsrc; Flags.UpdateZN(rdest)`
* **Flags Affected:** `Z`, `N`
* **Example:** `xor r0, r0` (Clears `r0` to 0)

---

#### `shl` — Logical Shift Left
**Opcode:** `$43` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:** `shl <rdest>, <shift_count>`
* **Operation:** `rdest = (rdest << (shift_count & 0x1F)); Flags.UpdateZN(rdest)`
* **Flags Affected:** `Z`, `N`
* **Example:** `shl r0, 3` (Multiply by 8)

---

#### `shr` — Logical Shift Right
**Opcode:** `$44` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:** `shr <rdest>, <shift_count>`
* **Operation:** `rdest = (rdest >> (shift_count & 0x1F)); Flags.UpdateZN(rdest)`
* **Flags Affected:** `Z`, `N`
* **Example:** `shr r0, 2` (Unsigned divide by 4)

---

#### `not` — Bitwise NOT (Invert)
**Opcode:** `$45` | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:** `not <rdest>, <rsrc>`
* **Operation:** `rdest = ~rsrc; Flags.UpdateZN(rdest)`
* **Flags Affected:** `Z`, `N`
* **Example:** `not r0, r1`

---

### 6.6 Bit Manipulation & Flag Control

---

#### `bset` — Bit Set (Register)
**Opcode:** `$D0` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:** `bset <rdest>, <mask>`
* **Operation:**
  ```text
  rdest = rdest | mask
  Flags.UpdateZN(rdest)
  ```
* **Flags Affected:** `Z`, `N`
* **Description:** Sets all bits in `rdest` that are set in `mask`.
* **Example:** `bset r0, %00000001` (Sets bit 0)

---

#### `bclr` — Bit Clear (Register BIC)
**Opcode:** `$D1` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:** `bclr <rdest>, <mask>`
* **Operation:**
  ```text
  rdest = rdest & (~mask)
  Flags.UpdateZN(rdest)
  ```
* **Flags Affected:** `Z`, `N`
* **Description:** Clears all bits in `rdest` that are set in `mask`.
* **Example:** `bclr r0, $80` (Clears bit 7)

---

#### `btst` — Bit Test (Register)
**Opcode:** `$D2` | **Format:** `R1R2` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:** `btst <ra>, <mask>`
* **Operation:**
  ```text
  Flags.UpdateZN(ra & mask)
  ```
* **Flags Affected:** `Z`, `N`
* **Description:** Performs a bitwise AND between `ra` and `mask`, updating the `Zero` and `Negative` condition flags without modifying `ra`.
* **Examples:**
  ```text
  btst r0, FLAG_ALIVE
  jnz  @PlayerIsAlive     ; Direct conditional branch!
  ```

---

#### `bsetf` — Bit Set Flags Register
**Opcode:** `$D3` | **Format:** `RImm` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:** `bsetf <mask>`
* **Operation:**
  ```text
  Flags = Flags | (mask & 0xFF)
  ```
* **Flags Affected:** Specific bits set in `mask`
* **Description:** Sets control/status bits directly in the processor `Flags` register.
* **Example:**
  ```text
  bsetf $20               ; Enable Interrupts (Sets Bit 5)
  bsetf $40               ; Enable DivByZero Panic (Sets Bit 6)
  ```

---

#### `bclrf` — Bit Clear Flags Register
**Opcode:** `$D4` | **Format:** `RImm` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:** `bclrf <mask>`
* **Operation:**
  ```text
  Flags = Flags & (~(mask & 0xFF))
  ```
* **Flags Affected:** Specific bits cleared in `mask`
* **Description:** Clears control/status bits directly in the processor `Flags` register.
* **Example:**
  ```text
  bclrf $20               ; Disable Interrupts (Clears Bit 5)
  bclrf $40               ; Disable DivByZero Panic (Clears Bit 6)
  ```

---

#### `btstf` — Bit Test Flags Register
**Opcode:** `$D5` | **Format:** `RImm` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:** `btstf <mask>`
* **Operation:**
  ```text
  Flags.UpdateZN(Flags & (mask & 0xFF))
  ```
* **Flags Affected:** `Z`, `N`
* **Description:** Tests specific bits of the `Flags` register into the `Zero` condition flag.
* **Example:**
  ```text
  btstf $20               ; Check if Interrupts are enabled
  jnz   @IntsAreOn
  ```

---

### 6.7 Memory Load & Store

---

#### `ldb` / `ldw` / `ld` — Load from Address in Register
**Opcodes:** `$50` (`ldb`), `$51` (`ldw`), `$52` (`ld`) | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:**
  * `ldb <rdest>, [<raddr>]` (Load 8-bit unsigned Byte)
  * `ldw <rdest>, [<raddr>]` (Load 16-bit unsigned Word)
  * `ld  <rdest>, [<raddr>]` (Load 32-bit DWord)
* **Operation:**
  ```text
  rdest = Memory.Read[8/16/32](raddr)
  ```
* **Flags Affected:** None
* **Examples:**
  ```text
  ldb r0, [r1]        ; Read 8-bit byte at address in r1 into r0
  ld  r0, [r1]        ; Read 32-bit dword at address in r1 into r0
  ```

---

#### `stb` / `stw` / `st` — Store to Address in Register
**Opcodes:** `$53` (`stb`), `$54` (`stw`), `$55` (`st`) | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:**
  * `stb [<raddr>], <rsrc>` (Store 8-bit Byte)
  * `stw [<raddr>], <rsrc>` (Store 16-bit Word)
  * `st  [<raddr>], <rsrc>` (Store 32-bit DWord)
* **Operation:**
  ```text
  Memory.Write[8/16/32](raddr, rsrc)
  ```
* **Flags Affected:** None
* **Examples:**
  ```text
  stb [r0], r1        ; Write low 8 bits of r1 to address in r0
  st  [r0], r1        ; Write 32 bits of r1 to address in r0
  ```

---

#### `ldib` / `ldiw` / `ldi` — Load Indirect and Post-Increment Pointer
**Opcodes:** `$56` (`ldib`), `$57` (`ldiw`), `$58` (`ldi`) | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:**
  * `ldib <rdest>, [<raddr++>]`
  * `ldiw <rdest>, [<raddr++>]`
  * `ldi  <rdest>, [<raddr++>]`
* **Operation:**
  ```text
  rdest = Memory.Read[8/16/32](raddr)
  raddr = raddr + (1 for byte, 2 for word, 4 for dword)
  ```
* **Flags Affected:** None
* **Example:**
  ```text
  ldi r0, [r1]        ; r0 = [r1]; r1 = r1 + 4
  ```

---

#### `stib` / `stiw` / `sti` — Store Indirect and Post-Increment Pointer
**Opcodes:** `$59` (`stib`), `$5A` (`stiw`), `$5B` (`sti`) | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:**
  * `stib [<raddr++>], <rsrc>`
  * `stiw [<raddr++>], <rsrc>`
  * `sti  [<raddr++>], <rsrc>`
* **Operation:**
  ```text
  Memory.Write[8/16/32](raddr, rsrc)
  raddr = raddr + (1 for byte, 2 for word, 4 for dword)
  ```
* **Flags Affected:** None
* **Example:**
  ```text
  sti [r0], r1        ; [r0] = r1; r0 = r0 + 4
  ```

---

#### `stsb` / `stsw` / `sts` — Stream Copy Between Pointers
**Opcodes:** `$5C` (`stsb`), `$5D` (`stsw`), `$5E` (`sts`) | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:**
  * `stsb [<rdst++>], [<rsrc++>]`
  * `stsw [<rdst++>], [<rsrc++>]`
  * `sts  [<rdst++>], [<rsrc++>]`
* **Operation:**
  ```text
  Memory.Write[8/16/32](rdst, Memory.Read[8/16/32](rsrc))
  rdst = rdst + (1/2/4)
  rsrc = rsrc + (1/2/4)
  ```
* **Flags Affected:** None
* **Description:** Copies one memory unit from `[rsrc]` to `[rdst]` and advances both pointers. Ideal for string copying and block memory loops.

---

#### `ldob` / `ldow` / `ldo` — Load with Displacement Offset
**Opcodes:** `$60` (`ldob`), `$61` (`ldow`), `$62` (`ldo`) | **Format:** `R1R2Imm` | **Size:** 6 Bytes

* **Syntax:**
  * `ldob <rdest>, <rbase>, <disp32>`
  * `ldow <rdest>, <rbase>, <disp32>`
  * `ldo  <rdest>, <rbase>, <disp32>`
* **Operation:**
  ```text
  rdest = Memory.Read[8/16/32](rbase + disp32)
  ```
* **Flags Affected:** None
* **Examples:**
  ```text
  ldo r0, bp, -4          ; Read local variable at [BP - 4]
  ldo r0, r1, PLAYER_HP   ; Read struct member at [r1 + 8]
  ```

---

#### `stob` / `stow` / `sto` — Store with Displacement Offset
**Opcodes:** `$63` (`stob`), `$64` (`stow`), `$65` (`sto`) | **Format:** `R1R2Imm` | **Size:** 6 Bytes

* **Syntax:**
  * `stob <rbase>, <rsrc>, <disp32>`
  * `stow <rbase>, <rsrc>, <disp32>`
  * `sto  <rbase>, <rsrc>, <disp32>`
* **Operation:**
  ```text
  Memory.Write[8/16/32](rbase + disp32, rsrc)
  ```
* **Flags Affected:** None
* **Examples:**
  ```text
  sto bp, r0, -8          ; Store r0 into local variable at [BP - 8]
  sto r1, r0, PLAYER_HP   ; Store r0 into struct member at [r1 + 8]
  ```

---

### 6.8 Branches, Jumps & Loops

---

#### `jmp` — Unconditional Jump
**Opcode:** `$78` | **Format:** `RImm` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:**
  * `jmp <target_label>`
  * `jmp <raddr>`
* **Operation:** `PC = target`
* **Flags Affected:** None
* **Examples:**
  ```text
  jmp @Loop
  jmp r0                  ; Dynamic jump table dispatch
  ```

---

#### `jnz` / `je` / `jl` / `jle` / `jg` / `jge` / `jb` / `jae` — Conditional Jumps
**Opcodes:** `$70`–`$77` | **Format:** `Imm` | **Size:** 6 Bytes

* **Syntax:** `<jcc> <target_label>`
* **Conditions:**
  * **`jnz`** (`$70`): Jump if `Zero == 0` (Not Equal / Not Zero).
  * **`je`**  (`$71`): Jump if `Zero == 1` (Equal / Zero).
  * **`jl`**  (`$72`): Jump if `Negative != Overflow` (Signed Less Than).
  * **`jle`** (`$73`): Jump if `Zero == 1` or `(Negative != Overflow)` (Signed Less or Equal).
  * **`jg`**  (`$74`): Jump if `Zero == 0` and `(Negative == Overflow)` (Signed Greater Than).
  * **`jge`** (`$75`): Jump if `Negative == Overflow` (Signed Greater or Equal).
  * **`jb`**  (`$76`): Jump if `Carry == 1` (Unsigned Below).
  * **`jae`** (`$77`): Jump if `Carry == 0` (Unsigned Above or Equal).
* **Operation:**
  ```text
  if ConditionMet then
    PC = target_label
  ```
* **Flags Affected:** None

---

#### `loop` — Decrement Register and Jump if Non-Zero
**Opcode:** `$79` | **Format:** `R1Imm` | **Size:** 6 Bytes

* **Syntax:** `loop <rcounter>, <target_label>`
* **Operation:**
  ```text
  rcounter = rcounter - 1
  if rcounter > 0 then
    PC = target_label
  ```
* **Flags Affected:** None
* **Description:** Decrements loop counter `rcounter` by 1. If `rcounter > 0`, jumps to `target_label`.
* **Example:**
  ```text
  mov   r0, 10
  @Loop:
    call  DoWork
    loop  r0, @Loop       ; Executes exactly 10 times!
  ```

---

### 6.9 Subroutines, Stack & Execution Flow

---

#### `call` — Call Subroutine
**Opcode:** `$80` | **Format:** `RImm` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:**
  * `call <subroutine_label>`
  * `call <raddr>`
* **Operation:**
  ```text
  Push(PC)                ; Pushes address of next instruction
  PC = target
  ```
* **Flags Affected:** None

---

#### `ret` — Return from Subroutine
**Opcode:** `$83` | **Format:** `None` | **Size:** 2 Bytes

* **Syntax:** `ret`
* **Operation:** `PC = Pop()`
* **Flags Affected:** None

---

#### `syscall` — Invoke System Call
**Opcode:** `$81` | **Format:** `RImm` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:** `syscall <id>`
* **Operation:** Invokes Host/VM System Call `id`.
* **Flags Affected:** Determined by specific SysCall.

---

#### `int` — Software Interrupt
**Opcode:** `$82` | **Format:** `RImm` | **Size:** 2 Bytes (Register) / 6 Bytes (Immediate)

* **Syntax:** `int <interrupt_id>`
* **Operation:**
  ```text
  Push(Flags)
  Push(PC)
  Flags.InterruptsEnabled = 0
  PC = CoreSystem.Interrupts.Vectors[interrupt_id]
  ```
* **Flags Affected:** `InterruptsEnabled := 0`

---

#### `iret` — Return from Interrupt
**Opcode:** `$84` | **Format:** `None` | **Size:** 2 Bytes

* **Syntax:** `iret`
* **Operation:**
  ```text
  PC    = Pop()
  Flags = Pop() & 0xFF
  ```
* **Flags Affected:** All (Restored from stack).

---

#### `enter` — Create Stack Frame
**Opcode:** `$85` | **Format:** `Imm` | **Size:** 6 Bytes

* **Syntax:** `enter <local_vars_size>`
* **Operation:**
  ```text
  Push(BP)
  BP = SP
  SP = SP - local_vars_size
  ```
* **Flags Affected:** None

---

#### `leave` — Destroy Stack Frame
**Opcode:** `$86` | **Format:** `None` | **Size:** 2 Bytes

* **Syntax:** `leave`
* **Operation:**
  ```text
  SP = BP
  BP = Pop()
  ```
* **Flags Affected:** None

---

#### `push` / `pop` — Push / Pop 32-Bit Value
**Opcodes:** `$90` (`push`), `$91` (`pop`) | **Sizes:** 2/6 Bytes (`push`), 2 Bytes (`pop`)

* **Syntax:**
  * `push <rsrc>`
  * `push <imm32>`
  * `pop <rdest>`
* **Operation:**
  ```text
  Push: SP = SP - 4; Memory.Write32(SP, val)
  Pop:  val = Memory.Read32(SP); SP = SP + 4
  ```
* **Flags Affected:** None

---

#### `pushf` / `popf` — Push / Pop Flags Register
**Opcodes:** `$92` (`pushf`), `$93` (`popf`) | **Size:** 2 Bytes

* **Syntax:** `pushf` / `popf`
* **Operation:** Pushes / Pops the 8-bit `Flags` register to/from the stack.

---

#### `pushr` / `popr` — Push / Pop Multiple Registers
**Opcodes:** `$94` (`pushr`), `$95` (`popr`) | **Format:** `Imm` | **Size:** 6 Bytes

* **Syntax:**
  * `pushr <count>` (Pushes `R[count-1]` down to `R0`)
  * `popr  <count>` (Pops `R0` up to `R[count-1]`)
* **Operation:** Batch saves/restores `count` registers (1..16) on the stack.

---

### 6.10 Floating-Point Unit (FPU)

All FPU instructions operate on 32-bit IEEE-754 Single-precision floating-point numbers stored in standard registers.

---

#### `fadd` / `fsub` / `fmul` / `fdiv` — Basic Float Arithmetic
**Opcodes:** `$B0` (`fadd`), `$B1` (`fsub`), `$B2` (`fmul`), `$B3` (`fdiv`) | **Format:** `R1R2` | **Size:** 2/6 Bytes

* **Syntax:** `<fop> <rdest>, <rsrc>`
* **Operation:** Computes `rdest = rdest (+, -, *, /) rsrc` as 32-bit Single float.
* **Flags Affected:** `Z`, `N`, `F` (on division by zero).

---

#### `itof` — Integer to Float Conversion
**Opcode:** `$B4` | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:** `itof <rdest>, <rsrc>`
* **Operation:** Converts signed 32-bit integer `rsrc` to Single float in `rdest`.

---

#### `ftoi` — Float to Integer Truncation
**Opcode:** `$B5` | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:** `ftoi <rdest>, <rsrc>`
* **Operation:** Truncates Single float `rsrc` toward zero to signed 32-bit integer in `rdest`.

---

#### `frnd` — Float to Integer Rounding
**Opcode:** `$B6` | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:** `frnd <rdest>, <rsrc>`
* **Operation:** Rounds Single float `rsrc` to the nearest signed 32-bit integer in `rdest`.

---

#### `fsin` / `fcos` / `ftan` / `fatan` — Trigonometric Functions
**Opcodes:** `$B7` (`fsin`), `$B8` (`fcos`), `$B9` (`ftan`), `$BA` (`fatan`) | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:** `<ftrig> <rdest>, <rsrc>`
* **Operation:** Computes `Sin`, `Cos`, `Tan`, or `ArcTan` of radian angle in `rsrc`.

---

#### `fexp` / `fln` / `fsqrt` — Exponential, Logarithm & Square Root
**Opcodes:** `$BB` (`fexp`), `$BC` (`fln`), `$BD` (`fsqrt`) | **Format:** `R1R2` | **Size:** 2 Bytes

* **Syntax:** `<fmath> <rdest>, <rsrc>`
* **Operation:** Computes $e^x$, $\ln(x)$, or $\sqrt{x}$. Sets `FPUException` (`F`) flag on domain errors ($x \le 0$ for ln, $x < 0$ for sqrt).

---

#### `fce` — Clear FPU Exception Flag
**Opcode:** `$BE` | **Format:** `None` | **Size:** 2 Bytes

* **Syntax:** `fce`
* **Operation:** `Flags.FPUException = 0`

---

#### `fcmp` — Floating-Point Comparison
**Opcode:** `$BF` | **Format:** `R1R2` | **Size:** 2/6 Bytes

* **Syntax:** `fcmp <ra>, <rb>`
* **Operation:** Compares float `ra` with `rb`, updating `Zero` and `Negative` flags.

---

### 6.11 Condition Code Setters (`setcc`)

Evaluates processor condition flags and writes `1` (true) or `0` (false) into destination register `rdest`.

| Opcode | Mnemonic | Syntax | Condition | Operation |
| :--- | :--- | :--- | :--- | :--- |
| **`$C0`** | **`sete`** | `sete <rdest>` | `Zero == 1` | `rdest = (Zero == 1) ? 1 : 0` |
| **`$C1`** | **`setne`**| `setne <rdest>`| `Zero == 0` | `rdest = (Zero == 0) ? 1 : 0` |
| **`$C2`** | **`setl`** | `setl <rdest>` | `N != O` | `rdest = (N != O) ? 1 : 0` |
| **`$C3`** | **`setle`**| `setle <rdest>`| `Zero or (N != O)` | `rdest = (Zero or (N != O)) ? 1 : 0` |
| **`$C4`** | **`setg`** | `setg <rdest>` | `~Zero and (N == O)`| `rdest = (~Zero and (N == O)) ? 1 : 0`|
| **`$C5`** | **`setge`**| `setge <rdest>`| `N == O` | `rdest = (N == O) ? 1 : 0` |