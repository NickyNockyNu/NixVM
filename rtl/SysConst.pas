unit SysConst;

interface

const
  // System addresses
  _Addr_Interrupts       = $00000000;
  _Addr_SysCalls         = $00000040;
  _Addr_SystemState      = $00000440;
  _Addr_MemoryMap        = $00000490;
  _Addr_Timers           = $000004F8;
  _Addr_SystemRegisters  = $00000518;
  _Addr_OEM              = $00000528;

const
  // Interrupt ID's
  _Intr_Panic     = $00;
  _Intr_SysRq     = $01;
  _Intr_FPUError  = $02;
  _Intr_Timer0    = $0E;
  _Intr_Timer1    = $0F;

const
  // SysCall ID's
  _SysCall_DebugBreak       = $00;
  _SysCall_DebugPrint       = $01;
  _SysCall_DebugPrintLn     = $02;
  _SysCall_MemoryFill       = $10;
  _SysCall_MemoryCopy       = $11;
  _SysCall_MemoryCompare    = $12;
  _SysCall_HeapAlloc        = $20;
  _SysCall_HeapRealloc      = $21;
  _SysCall_HeapFree         = $22;
  _SysCall_HeapSize         = $23;
  _SysCall_HeapAvailable    = $24;
  _SysCall_HeapLoad         = $25;
  _SysCall_HeapSave         = $26;
  _SysCall_StringNew        = $30;
  _SysCall_StringInit       = $31;
  _SysCall_StringDispose    = $32;
  _SysCall_StringLength     = $33;
  _SysCall_StringSetLength  = $34;
  _SysCall_StringConcat     = $35;
  _SysCall_StringCopy       = $36;
  _SysCall_StringCompare    = $37;
  _SysCall_StringFormat     = $38;
  _SysCall_ArrayNew         = $40;
  _SysCall_ArrayDispose     = $41;
  _SysCall_ArrayLength      = $42;
  _SysCall_ArraySetLength   = $43;
  _SysCall_ArrayCopy        = $44;
  _SysCall_ArrayConcat      = $45;
  _SysCall_ArrayClear       = $46;

implementation

end.