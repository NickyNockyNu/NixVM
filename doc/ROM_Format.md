# NixVM Universal Cartridge (`.nvm`) File Format Specification
**Document Version:** 1.0  
**Format Identifier:** `NVMX`  
**File Extension:** `.nvm` (Standard Cartridge) | `.rom` (Legacy)  
**Byte Order:** Little-Endian  

---

## Table of Contents
1. [Format Overview](#1-format-overview)
2. [Cartridge Binary Structure](#2-cartridge-binary-structure)
3. [Header Field Specification (92 Bytes)](#3-header-field-specification)
4. [Cartridge Validation & Loading Protocol](#4-cartridge-validation--loading-protocol)
5. [Hardware ABI & Layout Integrity](#5-hardware-abi--layout-integrity)

---

## 1. Format Overview

The **NixVM Universal Cartridge Format (`.nvm`)** is a self-describing binary package format for executable games, demos, and applications running on the NixVM architecture and its derived fantasy consoles.

### Key Characteristics
* **Zero Host Dependencies:** Fully language-agnostic binary format.
* **Hardware Self-Describing:** Encapsulates target fantasy console requirements, program versioning, memory budgets (heap/stack), and execution base address.
* **Direct-to-Memory Streaming:** Designed so that host loaders can stream the code payload directly from disk into virtual memory in a single read operation with zero translation.

---

## 2. Cartridge Binary Structure

A `.nvm` file consists of a **fixed 92-byte header** followed immediately by the **executable machine code and data payload**:

```text
+-------------------------------------------------------------+ Byte 0 ($0000)
| Cartridge Header (Fixed 92 Bytes / $5C)                     |
|   - Magic Identifier ('NVMX')                               |
|   - Target Harness Specification (Name, Version)            |
|   - ROM Program Metadata (Title, Version)                   |
|   - Memory Configuration (Base Addr, User, Heap, Stack)     |
+-------------------------------------------------------------+ Byte 92 ($005C)
| Executable Code & Data Payload (UserSize Bytes)             |
|   - Machine Code Instructions (.text)                       |
|   - Static Strings, Tables, Embedded Binary Assets (.data)  |
|   - Reserved Memory Blocks (.res)                           |
+-------------------------------------------------------------+ End of File
```

---

## 3. Header Field Specification

The header is fixed at exactly **92 bytes** (`$5C` bytes) with zero alignment gaps.

### 3.1 Byte-by-Byte Offset Map

```text
Offset    Size  Type      Field Name       Description
--------------------------------------------------------------------------------
+$00      4     Char[4]   Signature        Magic file identifier: 'NVMX' ($584D564E)
+$04      32    Char[32]  Harness.Name     Target console name (null-padded ASCII)
+$24      2     UInt16    Harness.Major    Minimum target major version
+$26      2     UInt16    Harness.Minor    Minimum target minor version
+$28      32    Char[32]  ROM.Name         Program/game title (null-padded ASCII)
+$48      2     UInt16    ROM.Major        Program major version
+$4A      2     UInt16    ROM.Minor        Program minor version
+$4C      4     UInt32    UserAddress      Expected base execution address
+$50      4     UInt32    UserSize         Byte size of payload following header
+$54      4     UInt32    HeapSize         Requested dynamic heap budget in bytes
+$58      4     UInt32    StackSize        Requested hardware stack budget in bytes
--------------------------------------------------------------------------------
Total Size = 92 Bytes ($5C)
```

---

### 3.2 Detailed Field Descriptions

#### `Signature` (Offset `+$00`, 4 Bytes)
* **Value:** The 4 ASCII characters `'N', 'V', 'M', 'X'` (`$4E, $56, $4D, $58`).
* **Little-Endian 32-bit Integer:** `$584D564E`.
* **Purpose:** Identifies the file as a valid NixVM cartridge. Loaders must reject files with non-matching signatures.

#### `Harness.Name` (Offset `+$04`, 32 Bytes)
* **Type:** Fixed 32-byte null-padded ASCII string.
* **Purpose:** Specifies the target fantasy console or virtual system required to run this cartridge (e.g. `"NixBoy"`, `"NixConsole2D"`, `"Terminal"`).
* **Behavior:** If empty (`""`) or set to `"NixVM"`, the cartridge is considered a generic program and can run on any baseline harness.

#### `Harness.Major` / `Harness.Minor` (Offset `+$24`–`+$27`, 4 Bytes)
* **Type:** Two 16-bit unsigned integers (`UInt16`).
* **Purpose:** Defines the minimum required hardware version of the target fantasy console (e.g. `Major = 1, Minor = 0`).

#### `ROM.Name` (Offset `+$28`, 32 Bytes)
* **Type:** Fixed 32-byte null-padded ASCII string.
* **Purpose:** Human-readable title of the game or software (e.g. `"Space Invaders 32"`).

#### `ROM.Major` / `ROM.Minor` (Offset `+$48`–`+$4B`, 4 Bytes)
* **Type:** Two 16-bit unsigned integers (`UInt16`).
* **Purpose:** Version number of the game or program.

#### `UserAddress` (Offset `+$4C`, 4 Bytes)
* **Type:** 32-bit unsigned integer (`UInt32`).
* **Purpose:** The exact virtual memory address where this cartridge was compiled to execute (e.g. `$000004E0` or `$00020000`).
* **Safety:** Loaders verify this value against the host's `UserAddress` to guarantee binary layout compatibility (see Section 5).

#### `UserSize` (Offset `+$50`, 4 Bytes)
* **Type:** 32-bit unsigned integer (`UInt32`).
* **Purpose:** The exact byte length of the machine code and data payload following the 92-byte header.
* **Behavior:** If set to `0`, loaders compute the payload size as `FileSize - 92`.

#### `HeapSize` (Offset `+$54`, 4 Bytes)
* **Type:** 32-bit unsigned integer (`UInt32`).
* **Purpose:** The requested dynamic heap memory allocation budget in bytes (default: `65536` / 64 KB).

#### `StackSize` (Offset `+$58`, 4 Bytes)
* **Type:** 32-bit unsigned integer (`UInt32`).
* **Purpose:** The requested hardware stack memory allocation budget in bytes (default: `16384` / 16 KB).

---

## 4. Cartridge Validation & Loading Protocol

When a NixVM host harness loads a `.nvm` cartridge file, it must execute the following deterministic 6-step loading sequence:

```text
[ Load .nvm File ]
       │
       ▼
[ Step 1: Validate Header Signature ('NVMX') ] ──► (Fail? Abort: "Not a NixVM ROM")
       │
       ▼
[ Step 2: Validate Target Harness & Version ] ────► (Mismatch? Abort: "Wrong Harness")
       │
       ▼
[ Step 3: Validate Base Address Integrity ] ─────► (Mismatch? Abort: "Base Mismatch")
       │
       ▼
[ Step 4: Configure & Resize VM Memory Map ] ────► (Resize User, Heap, and Stack)
       │
       ▼
[ Step 5: Direct Stream Payload -> Memory ] ─────► (Write bytes into VM UserAddress)
       │
       ▼
[ Step 6: Reset CPU & Begin Execution ] ─────────► (PC := UserAddress, SP := StackTop)
```

### 4.1 Step-by-Step Loading Rules

1. **Signature Verification:**  
   Read the first 4 bytes. If `Signature != 'NVMX'`, abort immediately.
2. **Harness Compatibility Check:**  
   If `Header.Harness.Name` is non-empty and does not match the active harness name, abort with error:  
   `"Requires harness: <HarnessName>"`.  
   If the active harness version is lower than `Header.Harness.Major.Minor`, abort with error:  
   `"Requires harness version: <Major>.<Minor>"`.
3. **Base Address Check:**  
   If `Header.UserAddress > 0` and `Header.UserAddress != VM.UserAddress`, abort with error:  
   `"ROM base address mismatch: expected $<HeaderAddress>, harness is $<VMAddress>"`.
4. **Memory Allocation:**  
   Apply default values if header fields are zero:
   * `UserSize := (Header.UserSize > 0) ? Header.UserSize : (FileSize - 92)`
   * `HeapSize := (Header.HeapSize > 0) ? Header.HeapSize : 65536` (64 KB)
   * `StackSize := (Header.StackSize > 0) ? Header.StackSize : 16384` (16 KB)  
   Resize virtual memory: `VM.Resize(UserSize, HeapSize, StackSize)`.
5. **Direct Payload Transfer:**  
   Stream `UserSize` bytes from file offset `92` directly into virtual memory at `VM.UserAddress`.
6. **Execution Start:**  
   Reset CPU registers (`R0`..`R15 := 0`), set `PC := VM.UserAddress`, set `SP := VM.StackAddress`, set `Flags := $60`, and begin execution.

---

## 5. Hardware ABI & Layout Integrity

### Why Base Address Validation is Critical
Different fantasy consoles expose different amounts of memory-mapped I/O (MMIO) registers, framebuffers, and audio hardware in the **OEM Space** (`$000004E0`..`UserAddress`):

```text
Fantasy Console A (Text Terminal):
  Core System ($0000) ──► OEM Space (1 KB) ──► UserAddress = $000008E0

Fantasy Console B (2D Graphics Engine with Framebuffer):
  Core System ($0000) ──► OEM Space (128 KB) ─► UserAddress = $000204E0
```

* When an assembly program or compiler compiles code, all absolute function calls (`call MyFunction`), jump tables (`jmp @JumpTable`), and static data pointers (`mov r0, str_hello`) are linked against that specific `UserAddress`.
* By embedding `UserAddress` into the `.nvm` header, NixVM ensures that a ROM compiled for **Console B** will never accidentally run on **Console A** with misaligned memory references, preventing execution crashes before the first instruction runs.