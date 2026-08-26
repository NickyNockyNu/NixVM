# NixVM Memory Architecture & Memory-Mapped I/O Specification
**Document Version:** 1.0  
**Target Architecture:** 32-Bit NixVM Core Memory System  
**Byte Order:** Little-Endian  

---

## Table of Contents
1. [Memory Model & Sandboxing](#1-memory-model--sandboxing)
2. [Global Memory Map Overview](#2-global-memory-map-overview)
3. [Core System Memory Area (`$00000000`–`$000004DF`)](#3-core-system-memory-area)
4. [System Registers (`$000004D0`–`$000004DF`)](#4-system-registers)
5. [Hardware Timers Subsystem (`$000004B0`–`$000004CF`)](#5-hardware-timers-subsystem)
6. [System State & Panic Diagnostics (`$00000440`–`$0000048F`)](#6-system-state--panic-diagnostics)
7. [Memory Map Table Pointers (`$00000490`–`$000004AF`)](#7-memory-map-table-pointers)
8. [OEM Hardware Space (MMIO & Peripherals)](#8-oem-hardware-space-mmio--peripherals)
9. [User Code, Managed Heap & Stack Spaces](#9-user-code-managed-heap--stack-spaces)

---

## 1. Memory Model & Sandboxing

NixVM implements a flat, byte-addressed, 32-bit physical address space.

* **Sandboxing & Wrapping:** The VM's physical address space is strictly sized to a power of two ($2^N$ bytes). All address references are hardware-masked:
  $$\text{Physical Address} = \text{Virtual Address} \land (\text{MemorySize} - 1)$$
  This guarantees that out-of-bounds memory accesses wrap predictably within the virtual machine's memory boundaries without crashing the host application.
* **Byte Order:** All multi-byte values (16-bit Words, 32-bit DWords, IEEE-754 Floats) are stored in **Little-Endian** format (least significant byte at the lowest address).
* **Data Alignment:** Memory reads and writes support arbitrary byte alignment, but 32-bit aligned accesses (addresses divisible by 4) provide optimal performance.

---

## 2. Global Memory Map Overview

The virtual memory map is partitioned into distinct functional regions:

```text
+-------------------------------------------------------------+ $00000000
| Core System Memory (Fixed 1,248 Bytes)                      |
|   - Interrupt Vector Table       ($00000000 - $0000003F)    |
|   - SysCall Vector Table         ($00000040 - $0000043F)    |
|   - System State & Panic Area    ($00000440 - $0000048F)    |
|   - Memory Map Pointers Table    ($00000490 - $000004AF)    |
|   - Hardware Timers (Timer 0/1)  ($000004B0 - $000004CF)    |
|   - System Registers (Delta/FPS) ($000004D0 - $000004DF)    |
+-------------------------------------------------------------+ OEMAddress ($000004E0)
| OEM Hardware Space (Console Registers, VRAM, Audio Buffers) |
+-------------------------------------------------------------+ UserAddress
| User Program Code & Static Data (.text / .data / .rodata)   |
+-------------------------------------------------------------+ HeapAddress
| Dynamic Managed Heap (Grows upwards towards high memory)    |
+-------------------------------------------------------------+ StackAddress - StackSize
| Hardware Stack Space (Grows downwards from top of memory)   |
+-------------------------------------------------------------+ MemorySize
```

---

## 3. Core System Memory Area

The lowest **1,248 bytes** ($00000000..$000004DF) are reserved for internal CPU hardware control, vector tables, and status registers.

### 3.1 Memory Layout Offset Map

| Address Range | Byte Size | Name / Functional Block | Description |
| :--- | :--- | :--- | :--- |
| `$00000000`–`$0000003F` | 64 | **Interrupt Vector Table** | 16 Vectors $\times$ 4-byte 32-bit entry addresses. |
| `$00000040`–`$0000043F` | 1,024 | **SysCall Vector Table** | 256 Vectors $\times$ 4-byte 32-bit entry addresses. |
| `$00000440`–`$0000048F` | 80 | **System State Snapshot** | CPU register snapshot, Panic code, and User diagnostic code. |
| `$00000490`–`$000004AF` | 32 | **Memory Map Table** | Base pointers and sizes for OEM, User, Heap, and Stack regions. |
| `$000004B0`–`$000004CF` | 32 | **Hardware Timers** | Registers for Timer 0 (`$04B0`) and Timer 1 (`$04C0`). |
| `$000004D0`–`$000004DF` | 16 | **System Registers** | Refresh rate, elapsed runtime, and frame delta time. |

---

## 4. System Registers

The System Registers are located at fixed address **`$000004D0`**. They provide real-time timing, profiling, and engine synchronization telemetry.

```text
Address:   $04D0          $04D4          $04D8          $04DC
          +--------------+--------------+--------------+--------------+
Field:    | RefreshRate  |   Elapsed    |    Delta     |   Reserved   |
          +--------------+--------------+--------------+--------------+
Type:         UInt32         UInt32         Single         UInt32
Access:       Read/Write     Read-Only      Read-Only      Read/Write
```

### 4.1 Field Breakdown

| Address Offset | Field Name | Data Type | Access | Description |
| :--- | :--- | :--- | :--- | :--- |
| **`$000004D0`** | **`RefreshRate`** | `UInt32` | Read/Write | Target refresh rate in Hertz (default: `60`). Used by the host harness to throttle execution frame timing. |
| **`$000004D4`** | **`Elapsed`** | `UInt32` | Read-Only | Total milliseconds elapsed since the virtual machine started running. |
| **`$000004D8`** | **`Delta`** | `Single` (32-bit Float) | Read-Only | Elapsed duration of the previous frame in seconds (e.g. `0.0166667` for 60 FPS). Initialized to `1.0 / RefreshRate`. |
| **`$000004DC`** | **`Reserved`** | `UInt32` | Read/Write | Reserved for future architecture extensions. |

### 4.2 Assembly Example: Delta-Time Movement
```text
; Read frame delta time from $04D8
ld    r1, [$04D8]        ; r1 = Delta (Float)
fmul  r1, [player_speed] ; r1 = player_speed * Delta
fadd  r0, r1             ; player_x = player_x + movement
```

---

## 5. Hardware Timers Subsystem

NixVM features two independent, programmable hardware timers mapped at **`$000004B0`** (Timer 0) and **`$000004C0`** (Timer 1).

### 5.1 Timer Register Layout (16 Bytes per Timer)

```text
Offset:    +$00           +$04           +$08     +$09..+$0F
          +--------------+--------------+--------+------------------+
Field:    |   Current    |   Interval   | Flags  |     Padding      |
          +--------------+--------------+--------+------------------+
Type:         UInt32         UInt32       UInt8        7 Bytes
```

* **Timer 0 Base Address:** `$000004B0`
* **Timer 1 Base Address:** `$000004C0`

| Field Offset | Field Name | Data Type | Description |
| :--- | :--- | :--- | :--- |
| **`+$00`** | **`Current`** | `UInt32` | Current countdown or count-up accumulator. |
| **`+$04`** | **`Interval`** | `UInt32` | Target period value. |
| **`+$08`** | **`Flags`** | `UInt8` | Timer configuration bitfield (see below). |
| **`+$09`..`+$0F`** | **`Padding`** | 7 Bytes | Reserved alignment padding. |

### 5.2 Timer Flags Bitfield (`+$08`)

```text
Bit:    7   6   5   4   3     2         1         0
     +--------------------+-------+-----------+---------+
     |      Reserved      | Mode  | Direction | Enabled |
     +--------------------+-------+-----------+---------+
```

| Bit | Flag Name | Mask | Description |
| :--- | :--- | :--- | :--- |
| **0** | **`Enabled`** | `$01` | `1` = Timer is active and ticking; `0` = Timer is stopped. |
| **1** | **`Direction`** | `$02` | `0` = **Count Down** (`Current` decrements to 0); `1` = **Count Up** (`Current` increments to `Interval`). |
| **2** | **`Mode`** | `$04` | `0` = **Time Mode** (ticks in milliseconds); `1` = **Frame Mode** (ticks by 1 on every frame). |
| **3..7**| **Reserved** | `$F8` | Unused. Always set to `0`. |

### 5.3 Interrupt Generation
* When **Timer 0** reaches its interval, it triggers **Interrupt 14** (`_Intr_Timer0`).
* When **Timer 1** reaches its interval, it triggers **Interrupt 15** (`_Intr_Timer1`).
* After triggering, `Current` resets automatically based on `Current mod Interval` to ensure zero timing drift.

---

## 6. System State & Panic Diagnostics

Located at **`$00000440`–`$0000048F`**, this area holds an exact diagnostic snapshot of the processor registers when an interrupt or hardware Panic occurs.

### 6.1 Diagnostic Register Map

| Address Offset | Field Name | Data Type | Description |
| :--- | :--- | :--- | :--- |
| **`$00000440`** | **`PC`** | `UInt32` | Program counter at the time of the fault/interrupt. |
| **`$00000444`** | **`Flags`** | `UInt8` | Processor flags at the time of the fault/interrupt. |
| **`$00000445`..`$0447`**| **Padding** | 3 Bytes | Reserved alignment padding. |
| **`$00000448`..`$0487`**| **`R0`..`R15`**| 16 $\times$ `UInt32` | Full snapshot of all 16 general-purpose registers. |
| **`$00000488`** | **`PanicCode`** | `UInt32` | Hardware panic error identifier (see below). |
| **`$0000048C`** | **`UserCode`** | `UInt32` | Faulting memory address, opcode, or user error payload. |

### 6.2 Hardware Panic Codes (`$00000488`)

| Code | Panic Identifier | Description | `UserCode` Payload |
| :--- | :--- | :--- | :--- |
| **`0`** | `None` | No panic condition. | — |
| **`1`** | `InvalidOperation` | CPU encountered an undefined opcode. | The illegal opcode byte. |
| **`2`** | `AccessViolationExec`| CPU attempted to execute non-executable memory. | Faulting `PC` address. |
| **`3`** | `AccessViolationRead`| CPU attempted to read out of memory bounds. | Faulting memory address. |
| **`4`** | `AccessViolationWrite`| CPU attempted to write out of memory bounds. | Faulting memory address. |
| **`5`** | `StackOverflow` | Stack Pointer (`SP`) exceeded stack allocation limit. | Current `SP` value. |
| **`6`** | `StackUnderflow` | `pop` or `ret` executed with empty stack (`SP >= StackBase`). | Current `SP` value. |
| **`7`** | `DivideByZero` | Integer division or modulo by zero with `DivZPanicEnabled` set. | Divisor value (`0`). |

---

## 7. Memory Map Table Pointers

Located at **`$00000490`–`$000004AF`**, this table contains 32-bit pointers and sizes defining the active memory layout of the running virtual machine:

```text
Address:   $0490        $0498        $04A0        $04A8
          +------------+------------+------------+------------+
Field:    | OEM Space  | User Space | Heap Space | Stack Base |
          +------------+------------+------------+------------+
Layout:   [Addr, Size] [Addr, Size] [Addr, Size] [Addr, Size]
```

| Address Offset | Field Name | Data Type | Description |
| :--- | :--- | :--- | :--- |
| **`$00000490`** | **`OEMAddress`** | `UInt32` | Start address of OEM MMIO space (typically `$000004E0`). |
| **`$00000494`** | **`OEMSize`** | `UInt32` | Total byte size allocated for OEM hardware space. |
| **`$00000498`** | **`UserAddress`** | `UInt32` | Start address of user code and static data (`.text`). |
| **`$0000049C`** | **`UserSize`** | `UInt32` | Total byte size of user code payload. |
| **`$000004A0`** | **`HeapAddress`** | `UInt32` | Base address of dynamic managed heap memory. |
| **`$000004A4`** | **`HeapSize`** | `UInt32` | Total byte size allocated for dynamic heap memory. |
| **`$000004A8`** | **`StackAddress`**| `UInt32` | Base (lowest address) of the stack allocation. |
| **`$000004AC`** | **`StackSize`** | `UInt32` | Total byte size reserved for the hardware stack. |

---

## 8. OEM Hardware Space (MMIO & Peripherals)

The OEM Hardware Space begins immediately following the Core System Memory at **`OEMAddress`** (default: **`$000004E0`**).

* **Purpose:** Custom fantasy consoles map their hardware peripherals (VRAM framebuffers, tilemap layers, sprite attribute tables, sound synthesizer registers, and gamepad I/O ports) into this space.
* **Layout:** Defined by the child fantasy console specification.
* **Direct Access:** Assembly and compiled code access peripheral registers directly using standard memory instructions:
  ```text
  ; Example: Writing to a Fantasy Console VRAM Color Register
  mov   r0, $00000500     ; OEM Palette Register 0
  mov   r1, $00FF00FF     ; Magenta (32-bit RGBA)
  st    [r0], r1          ; Update palette color immediately
  ```

---

## 9. User Code, Managed Heap & Stack Spaces

### 9.1 User Code & Data Space (`UserAddress`..`HeapAddress`)
* **Base Address:** Starts immediately after OEM space (`UserAddress = (SizeOf(Core) + OEMSize + 3) & ~3`).
* **Content:** Stores the compiled executable machine code, static string literals, constant lookup tables, and initialized global data.
* **Execution Rights:** The CPU enforces execution permissions: `PC` must reside between `UserAddress` and `HeapAddress + HeapSize`. Executing memory outside this range triggers an immediate `AccessViolationExec` Panic.

### 9.2 Dynamic Managed Heap (`HeapAddress`..`StackAddress - StackSize`)
* **Growth:** Grows upwards towards high memory.
* **Allocation:** Managed via VM System Calls (`HeapAlloc`, `HeapRealloc`, `HeapFree`, `StringNew`, etc.).
* **Alignment:** All heap block payloads are aligned to 4-byte boundaries.

### 9.3 Hardware Stack (`StackAddress - StackSize`..`StackAddress`)
* **Top of Stack:** Initialized to the highest memory address (`StackAddress = TotalMemorySize`).
* **Growth:** Grows downwards towards the heap.
* **Overflow Protection:** If `SP` decrements below `StackAddress - StackSize`, the CPU triggers an immediate `StackOverflow` Panic.
* **Underflow Protection:** If `SP` increments above `StackAddress`, the CPU triggers an immediate `StackUnderflow` Panic.