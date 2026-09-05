unit System;

interface

uses
  SysConst;

// ---------------------------------------------------------------------------

type
  PInterrupts = ^TInterrupts;
  TInterrupts = array[0..15] of Pointer;

const
  Interrupts: PInterrupts = _Addr_Interrupts;

// ---------------------------------------------------------------------------

type
  PSysCalls = ^TSysCalls;
  TSysCalls = array[0..255] of Pointer;

const
  SysCalls: PSysCalls = _Addr_SysCalls;

// ---------------------------------------------------------------------------

type
  TRegisters = array[0..15] of Cardinal;

  PSystemState = ^TSystemState;
  TSystemState = record
    PC:        Cardinal;
    Flags:     Byte;
    Padding:   array[0..2] of Byte;
    Registers: TRegisters;
    PanicCode: Cardinal;
    UserCode:  Cardinal;
   end;

const
  SystemState: PSystemState = _Addr_SystemState;

// ---------------------------------------------------------------------------

type
  PMemoryMap = ^TMemoryMap;
  TMemoryMap = record
    OEMAddress: Cardinal;
    OEMSize:    Cardinal;

    UserAddress: Cardinal;
    UserSize:    Cardinal;

    HeapAddress: Cardinal;
    HeapSize:    Cardinal;

    StackAddress: Cardinal;
    StackSize:    Cardinal;
  end;

const
  MemoryMap: PMemoryMap = _Addr_MemoryMap;

// ---------------------------------------------------------------------------

type
  TTimer = record
    Current:  Cardinal;
    Interval: Cardinal;
    Flags:    Byte;
    Padding:  array[0..6] of Byte;
  end;

  PTimers = ^TTimers;
  TTimers = array[0..1] of TTimer;

const
  Timers: PTimers = _Addr_Timers;

// ---------------------------------------------------------------------------

type
  PSystemRegisters = ^TSystemRegisters;
  TSystemRegisters = record
    RefreshRate: Cardinal;
    Elapsed:     Cardinal;
    Delta:       Single;
    Reserved:    Cardinal;
  end;

const
  SystemRegisters: PSystemRegisters = _Addr_SystemRegisters;

// ---------------------------------------------------------------------------

procedure DebugBreak;                            syscall _SysCall_DebugBreak;
procedure DebugPrint(AMessage: String); varargs; syscall _SysCall_DebugPrint;

// ---------------------------------------------------------------------------

procedure FillChar(AMem: Pointer; ASize: Cardinal; AValue: Byte);     syscall _SysCall_MemoryFill;
procedure Move(ASource, ADest: Pointer; ACount: Cardinal);            syscall _SysCall_MemoryCopy;
function  MCompare(AMemL, AMemR: Pointer; ACount: Cardinal): Integer; syscall _SysCall_MemoryCompare;

// ---------------------------------------------------------------------------

function  GetMem(ASize: Cardinal): Pointer;                      syscall _SysCall_HeapAlloc;
function  ResizeMem(AMem: Pointer; ANewSize: Cardinal): Pointer; syscall _SysCall_HeapRealloc;
procedure FreeMem(AMem: Pointer);                                syscall _SysCall_HeapFree;
function  MemSize(AMem: Pointer): Cardinal;                      syscall _SysCall_HeapSize;
function  MemFree: Cardinal;                                     syscall _SysCall_HeapAvailable;

// ---------------------------------------------------------------------------

type
  PChar = ^Char;

function  StrNew(ASize: Cardinal): PChar;             syscall _SysCall_StringNew;
function  StrInit(AInit: String): PChar;              syscall _SysCall_StringInit;
procedure StrDispose(AStr: PChar);                    syscall _SysCall_StringDispose;
function  StrLength(AStr: PChar): Cardinal;           syscall _SysCall_StringLength;
function  StrConcat(AStrL, AStrR: PChar): PChar;      syscall _SysCall_StringConcat;
function  StrCompare(AStrL, AStrR: PChar): Integer;   syscall _SysCall_StringCompare;
function  StrFormat(AFormat: String): PChar; varargs; syscall _SysCall_StringFormat;

// ---------------------------------------------------------------------------

implementation

end.
