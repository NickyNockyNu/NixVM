unit SysConst;

interface

const
  // System addresses
  _Addr_Interrupts       = $00000000;
  _Addr_SysCalls         = $00000040;
  _Addr_SystemState      = $00000440;
  _Addr_MemoryMap        = $00000490;
  _Addr_Timers           = $000004B0;
  _Addr_SystemRegisters  = $000004D0;

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
  _SysCall_MemoryFill       = $02;
  _SysCall_MemoryCopy       = $03;
  _SysCall_MemoryCompare    = $04;
  _SysCall_HeapAlloc        = $20;
  _SysCall_HeapRealloc      = $21;
  _SysCall_HeapFree         = $22;
  _SysCall_HeapSize         = $23;
  _SysCall_HeapAvailable    = $24;
  _SysCall_StringNew        = $30;
  _SysCall_StringInit       = $31;
  _SysCall_StringDispose    = $32;
  _SysCall_StringLength     = $33;
  _SysCall_StringConcat     = $34;
  _SysCall_StringCopy       = $35;
  _SysCall_StringCompare    = $36;
  _SysCall_StringFormat     = $37;

implementation

end.
