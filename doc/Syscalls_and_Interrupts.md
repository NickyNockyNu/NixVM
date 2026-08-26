# NixVM SysCalls & Interrupts Specification
**Document Version:** 1.0  
**Target Architecture:** 32-Bit NixVM Core System Services  
**Byte Order:** Little-Endian  

---

## Table of Contents
1. [Interrupt Architecture Overview](#1-interrupt-architecture-overview)
2. [Interrupt Vector Table (`$00000000`–`$0000003F`)](#2-interrupt-vector-table)
3. [Hardware Panic Subsystem](#3-hardware-panic-subsystem)
4. [System Call (SysCall) Architecture Overview](#4-system-call-syscall-architecture-overview)
5. [SysCall Calling Convention & Register ABI](#5-syscall-calling-convention--register-abi)
6. [Complete SysCall Reference](#6-complete-syscall-reference)
   * [6.1 Debugging Services (`$00`–`$0F`)](#61-debugging-services)
   * [6.2 Block Memory Services (`$10`–`$1F`)](#62-block-memory-services)
   * [6.3 Dynamic Heap Services (`$20`–`$2F`)](#63-dynamic-heap-services)
   * [6.4 Managed String Services (`$30`–`$3F`)](#64-managed-string-services)

---

## 1. Interrupt Architecture Overview

NixVM supports **16 prioritized hardware and software interrupts** (IDs `0` through `15`).

### 1.1 Interrupt Dispatch Sequence
When an interrupt is triggered (via the `int <id>` instruction, hardware timer expiry, or CPU fault):

1. **Mask Check:** The CPU checks `Flags.InterruptsEnabled` (Bit 5). If interrupts are disabled (`0`), standard maskable interrupts are ignored.  
   *(Note: Interrupt 0 `Panic` and Interrupt 1 `NMI` are non-maskable and ignore this flag).*
2. **Context Save:** The CPU pushes the current execution state onto the hardware stack:
   ```text
   Push(Flags)    ; Saves 8-bit Processor Flags
   Push(PC)       ; Saves 32-bit Return Address
   ```
3. **Interrupt Masking:** The CPU disables interrupts (`Flags.InterruptsEnabled := 0`) to prevent nested re-entrancy.
4. **Vector Dispatch:** The CPU reads the target address from the Interrupt Vector Table at `$00000000 + (ID * 4)` and jumps to that address (`PC := VectorTable[ID]`).
5. **Interrupt Return:** The handler concludes with the **`iret`** instruction, which atomically pops `PC` followed by `Flags`, restoring the exact pre-interrupt state.

---

## 2. Interrupt Vector Table

The Interrupt Vector Table resides at fixed physical addresses **`$00000000`–`$0000003F`** (16 entries $\times$ 4 bytes):

| ID | Vector Address | Vector Name | Type | Priority | Trigger Condition |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`0`** | `$00000000` | **`Panic`** | NMI | 1 (Highest) | Unrecoverable CPU fault, out-of-bounds access, or stack error. |
| **`1`** | `$00000004` | **`NMI` / `SysRq`** | NMI | 2 | Host system request or non-maskable external event. |
| **`2`** | `$00000008` | **`FPUError`** | Maskable | 3 | Floating-point domain error (e.g. DivByZero, Sqrt of negative). |
| **`3`** | `$0000000C` | **`Reserved`** | Maskable | 4 | Reserved for fantasy console peripherals (e.g. VBLANK). |
| **`4`** | `$00000010` | **`Reserved`** | Maskable | 5 | Reserved for fantasy console peripherals (e.g. Scanline). |
| **`5`..`13`**| `$00000014`..`$00000034`| **`User`** | Maskable | 6..14 | Software-defined interrupts / Gamepad inputs. |
| **`14`**| `$00000038` | **`Timer0`** | Maskable | 15 | Hardware Timer 0 interval elapsed. |
| **`15`**| `$0000003C` | **`Timer1`** | Maskable | 16 (Lowest) | Hardware Timer 1 interval elapsed. |

### 2.1 Installing an Interrupt Handler
To install a custom handler in assembly:
```text
; Install custom Timer0 handler
mov   r0, @OnTimer0Tick
sto   $00000000, r0, $38  ; Write address to Vector 14 ($00 + 14 * 4 = $38)

; Enable interrupts
bsetf $20                 ; Set Flags.InterruptsEnabled
```

---

## 3. Hardware Panic Subsystem

When the CPU encounters a fatal error, it initiates a **Hardware Panic**:

1. **State Snapshot:** The processor saves an exact snapshot of `PC`, `Flags`, and registers `R0`..`R15` into the System State area at `$00000440`–`$00000487`.
2. **Error Logging:** The error category is written to `PanicCode` (`$00000488`) and the faulting address or opcode is written to `UserCode` (`$0000048C`).
3. **Dispatch / Halt:** If Vector 0 (`Panic`) contains a valid executable address, the CPU jumps to the in-VM panic handler. If Vector 0 is unpopulated (`0`) or invalid, the CPU halts permanently and triggers a host debugger dump.

### 3.1 Panic Error Codes (`$00000488`)

| Code | Identifier | Description | `UserCode` (`$048C`) Payload |
| :--- | :--- | :--- | :--- |
| **`0`** | `None` | Normal execution / No error. | — |
| **`1`** | `InvalidOperation` | CPU encountered an undefined or illegal opcode byte. | The invalid opcode byte. |
| **`2`** | `AccessViolationExec`| CPU attempted to execute non-executable memory. | The invalid `PC` address. |
| **`3`** | `AccessViolationRead`| CPU attempted an illegal memory read. | Faulting memory address. |
| **`4`** | `AccessViolationWrite`| CPU attempted an illegal memory write. | Faulting memory address. |
| **`5`** | `StackOverflow` | Stack pointer (`SP`) decremented past stack allocation boundary. | Current `SP` address. |
| **`6`** | `StackUnderflow` | `pop` or `ret` executed with empty stack (`SP >= StackBase`). | Current `SP` address. |
| **`7`** | `DivideByZero` | Division or modulo by zero with `DivZPanicEnabled` active. | Divisor value (`0`). |

---

## 4. System Call (SysCall) Architecture Overview

NixVM provides **256 System Call entry points** (IDs `$00` through `$FF`).

```text
Assembly Instruction:  syscall <id>
                       │
                       ▼
         +-----------------------------+
         | Vector Table Entry [$40+ID] |
         +-----------------------------+
                 /             \
       Valid In-VM Addr?        Entry == $0?
              /                     \
             ▼                       ▼
   [ Execute In-VM Code ]    [ Native Host SysCall Handler ]
   (Pushes PC, Jumps to Addr) (Direct C++/Pascal/Host Execution)
```

### 4.1 Hybrid Execution Model
* **Native Host Handlers:** If a vector entry in the SysCall table (`$00000040`–`$0000043F`) is `0`, the SysCall is executed natively by the host harness at full host speed.
* **In-VM Overrides:** If a program writes an executable address into the SysCall Vector Table, the CPU pushes return `PC` and executes the custom in-VM routine like a subroutine.

---

## 5. SysCall Calling Convention & Register ABI

System Calls use the standard processor registers for input and output:

| Register | SysCall ABI Role | Description |
| :--- | :--- | :--- |
| **`R0`** | **`P1` / `Ret`** | **Parameter 1 / Return Value:** Primary input argument, and holds the return result upon completion. |
| **`R1`** | **`P2`** | **Parameter 2 / Format Arg 1:** Second input argument or first formatting parameter. |
| **`R2`** | **`P3`** | **Parameter 3 / Format Arg 2:** Third input argument or second formatting parameter. |
| **`R3`** | **`P4`** | **Parameter 4 / Format Arg 3:** Fourth input argument or third formatting parameter. |
| **`R4`..`R15`**| **Format Args** | For `DebugPrint` and `StringFormat`, registers `R4` through `R15` provide up to 15 total formatting parameters! |

---

## 6. Complete SysCall Reference

---

### 6.1 Debugging Services (`$00`–`$0F`)

---

#### `$00` — `DebugBreak`
Triggers an immediate host debugger break and outputs the full CPU register state, flags, and memory telemetry.

* **Parameters:** None
* **Returns:** None
* **Example:**
  ```text
  syscall $00             ; Trigger host debugger breakpoint
  ```

---

#### `$01` — `DebugPrint`
Formats a string and outputs it directly to the host console, terminal, or log window.

* **Parameters:**
  * `P1` (`R0`): Memory address of format string (null-terminated or managed `TString`).
  * `P2` (`R1`): Optional format argument 1.
  * `P3` (`R2`): Optional format argument 2.
  * `P4` (`R3`): Optional format argument 3.
  * `R4`..`R15`: Additional format arguments 4 through 15.
* **Returns:** None
* **Format Placeholders Supported:**
  * `%d` / `%i` : Signed 32-bit integer (`-1234`)
  * `%u` : Unsigned 32-bit integer (`65535`)
  * `%x` : Compact hexadecimal (`1a`)
  * `%X` : 8-digit uppercase hexadecimal (`0000001A`)
  * `%f` : Compact floating-point (`3.14`)
  * `%F` : Full 7-decimal floating-point (`3.1400000`)
  * `%s` : Nested string pointer (reads null-terminated string at target address)
  * `%c` : Single ASCII character
  * `%%` : Literal `%` character
* **Example:**
  ```text
  mov   r0, _fmt_str      ; P1 = Format string
  mov   r1, [player_x]    ; P2 = %d
  mov   r2, [player_y]    ; P3 = %d
  syscall $01             ; DebugPrint

  _fmt_str: .str "Player Position: (%d, %d)\n", 0
  ```

---

### 6.2 Block Memory Services (`$10`–`$1F`)

---

#### `$10` — `MemoryFill`
Fills a contiguous block of virtual memory with a specified byte value.

* **Parameters:**
  * `P1` (`R0`): Destination start address.
  * `P2` (`R1`): Byte count (size).
  * `P3` (`R2`): Fill byte value (`0..255`).
* **Returns:** None
* **Example:**
  ```text
  mov   r0, $00020000     ; Destination address
  mov   r1, 64k           ; Size = 65,536 bytes
  mov   r2, 0             ; Clear with zero
  syscall $10             ; MemoryFill
  ```

---

#### `$11` — `MemoryCopy`
Copies a contiguous block of memory from a source address to a destination address.

* **Parameters:**
  * `P1` (`R0`): Source start address.
  * `P2` (`R1`): Destination start address.
  * `P3` (`R2`): Byte count (size).
* **Returns:** None
* **Example:**
  ```text
  mov   r0, _src_buffer   ; Source
  mov   r1, _dst_buffer   ; Destination
  mov   r2, 256           ; Size
  syscall $11             ; MemoryCopy
  ```

---

#### `$12` — `MemoryCompare`
Lexicographically compares two memory blocks byte-by-byte.

* **Parameters:**
  * `P1` (`R0`): Memory block A start address.
  * `P2` (`R1`): Memory block B start address.
  * `P3` (`R2`): Byte count (size).
* **Returns:**
  * `R0` (`Ret`):
    * `< 0` : Block A is less than Block B.
    * `0` : Block A is identical to Block B.
    * `> 0` : Block A is greater than Block B.
* **Example:**
  ```text
  mov   r0, _data_a
  mov   r1, _data_b
  mov   r2, 16
  syscall $12             ; MemoryCompare
  cmp   r0, 0
  je    @BlocksMatch
  ```

---

### 6.3 Dynamic Heap Services (`$20`–`$2F`)

All heap allocations are managed dynamically in the virtual machine's heap area and aligned to 4-byte boundaries.

---

#### `$20` — `HeapAlloc`
Allocates a block of dynamic memory on the heap.

* **Parameters:**
  * `P1` (`R0`): Requested byte size.
* **Returns:**
  * `R0` (`Ret`): 32-bit memory address of allocated block, or `0` if out of memory.
* **Example:**
  ```text
  mov   r0, 1024          ; Allocate 1 KB
  syscall $20             ; HeapAlloc
  cmp   r0, 0
  je    @OutOfMemory
  mov   [my_buffer], r0   ; Store allocated address
  ```

---

#### `$21` — `HeapRealloc`
Resizes an existing heap allocation, preserving existing data up to the minimum of old and new sizes.

* **Parameters:**
  * `P1` (`R0`): Existing memory block address (or `0` to allocate new).
  * `P2` (`R1`): New requested byte size.
* **Returns:**
  * `R0` (`Ret`): New memory address of resized block, or `0` on error.
* **Example:**
  ```text
  mov   r0, [my_buffer]   ; Existing pointer
  mov   r1, 2048          ; Expand to 2 KB
  syscall $21             ; HeapRealloc
  mov   [my_buffer], r0
  ```

---

#### `$22` — `HeapFree`
Deallocates a previously allocated heap block and returns its memory to the free pool.

* **Parameters:**
  * `P1` (`R0`): Memory block address to free.
* **Returns:** None
* **Example:**
  ```text
  mov   r0, [my_buffer]
  syscall $22             ; HeapFree
  ```

---

#### `$23` — `HeapSize`
Queries the exact allocated byte capacity of a heap block.

* **Parameters:**
  * `P1` (`R0`): Memory block address.
* **Returns:**
  * `R0` (`Ret`): Allocation size in bytes (or `0` if invalid address).
* **Example:**
  ```text
  mov   r0, [my_buffer]
  syscall $23             ; HeapSize -> r0 holds size
  ```

---

#### `$24` — `HeapAvailable`
Queries the total amount of free, unallocated heap memory remaining.

* **Parameters:** None
* **Returns:**
  * `R0` (`Ret`): Total free heap capacity in bytes.
* **Example:**
  ```text
  syscall $24             ; HeapAvailable
  mov   r1, r0            ; r1 = Free bytes
  ```

---

### 6.4 Managed String Services (`$30`–`$3F`)

NixVM provides built-in high-level **managed strings** (`TString`). 

#### Anatomy of a Managed `TString` in Memory:
```text
Address:   [Ptr - 4]          [Ptr] ... [Ptr + Length - 1]   [Ptr + Length]
          +------------------+------------------------------+---------------+
Content:  | Length (32-bit)  | ASCII Character Payload      | #0 Terminator |
          +------------------+------------------------------+---------------+
```
* The string pointer returned to code points **directly to the character payload**, making it 100% compatible with standard C-style pointer operations, while preserving instant $O(1)$ length lookups at `[Ptr - 4]`.

---

#### `$30` — `StringNew`
Allocates a new, uninitialized managed string on the heap of the specified length.

* **Parameters:**
  * `P1` (`R0`): Character capacity / length.
* **Returns:**
  * `R0` (`Ret`): Managed string pointer on the heap.
* **Example:**
  ```text
  mov   r0, 32            ; Allocate string of length 32
  syscall $30             ; StringNew
  ```

---

#### `$31` — `StringInit`
Creates a managed string on the heap by copying an existing static string literal from memory.

* **Parameters:**
  * `P1` (`R0`): Memory address of null-terminated static string.
* **Returns:**
  * `R0` (`Ret`): Newly allocated managed string pointer on heap.
* **Example:**
  ```text
  mov   r0, _static_text  ; Pointer to static string
  syscall $31             ; StringInit -> r0 is a managed heap string
  ```

---

#### `$32` — `StringDispose`
Deallocates a managed string from the heap.

* **Parameters:**
  * `P1` (`R0`): Managed string pointer.
* **Returns:** None
* **Example:**
  ```text
  mov   r0, [player_name]
  syscall $32             ; StringDispose
  ```

---

#### `$33` — `StringLength`
Returns the character length of a string in $O(1)$ constant time.

* **Parameters:**
  * `P1` (`R0`): String pointer (managed `TString` or null-terminated static string).
* **Returns:**
  * `R0` (`Ret`): Character count.
* **Example:**
  ```text
  mov   r0, [player_name]
  syscall $33             ; StringLength -> r0 = Length
  ```

---

#### `$34` — `StringConcat`
Concatenates two strings together and returns a newly allocated managed string.

* **Parameters:**
  * `P1` (`R0`): String A pointer.
  * `P2` (`R1`): String B pointer.
* **Returns:**
  * `R0` (`Ret`): Newly allocated managed string `A + B`.
* **Example:**
  ```text
  mov   r0, [first_name]
  mov   r1, [last_name]
  syscall $34             ; StringConcat -> r0 = "FirstLast"
  ```

---

#### `$35` — `StringCopy`
Extracts a substring (equivalent to Pascal `Copy` or JavaScript `substring`) and returns a new managed string.

* **Parameters:**
  * `P1` (`R0`): Source string pointer.
  * `P2` (`R1`): 1-based start index.
  * `P3` (`R2`): Character count to copy.
* **Returns:**
  * `R0` (`Ret`): Newly allocated substring.
* **Example:**
  ```text
  mov   r0, [full_title]
  mov   r1, 1             ; Start at char 1
  mov   r2, 4             ; Copy 4 chars
  syscall $35             ; StringCopy
  ```

---

#### `$36` — `StringCompare`
Compares two strings lexicographically.

* **Parameters:**
  * `P1` (`R0`): String A pointer.
  * `P2` (`R1`): String B pointer.
* **Returns:**
  * `R0` (`Ret`):
    * `-1` : String A is less than String B.
    * `0` : String A is identical to String B.
    * `1` : String A is greater than String B.
* **Example:**
  ```text
  mov   r0, [input_name]
  mov   r1, _secret_password
  syscall $36             ; StringCompare
  cmp   r0, 0
  je    @AccessGranted
  ```

---

#### `$37` — `StringFormat`
Formats a string with arguments (supporting `%d`, `%x`, `%X`, `%f`, `%F`, `%s`, `%c`) and returns a newly allocated managed string on the heap.

* **Parameters:**
  * `P1` (`R0`): Format string pointer.
  * `P2` (`R1`): Format argument 1.
  * `P3` (`R2`): Format argument 2.
  * `P4` (`R3`): Format argument 3.
  * `R4`..`R15`: Additional format arguments 4 through 15.
* **Returns:**
  * `R0` (`Ret`): Newly allocated formatted managed string on the heap.
* **Example:**
  ```text
  mov   r0, _fmt_stats    ; P1 = Format string
  mov   r1, [level]       ; P2 = %d
  mov   r2, [score]       ; P3 = %d
  syscall $37             ; StringFormat -> r0 holds new heap string!
  mov   [status_str], r0

  _fmt_stats: .str "Level %d: Score = %d", 0
  ```