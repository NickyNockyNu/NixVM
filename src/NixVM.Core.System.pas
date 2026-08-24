{
  NixVM.Core.System.pas
    System memory layout

    Copyright (c) 2026 Nicholas Smith (writetonik@gmail.com)
    https://github.com/NickyNockyNu/NixVM

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
}

unit NixVM.Core.System;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  NixVM.Core.Registers;

type
  {$REGION 'Interrupts'}
  PInterrupts = ^TInterrupts;
  TInterrupts = packed record
  const
    Prefix = '_Intr_';
  type
    {$REGION 'ID'}
    ID = 0..15;

    IDHelper = record helper for ID
    const
      Panic    = 0;
      NMI      = 1;
      SysRq    = 1;
      FPUError = 2;
      Refresh  = 3;
      Scanline = 4;
      Timer0   = 14;
      Timer1   = 15;
    public
      function ToString: String;
    end;
    {$ENDREGION}

    THandler = function(AID: ID): Boolean of object;
  public
    Vectors: packed array[ID] of Cardinal;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'SysCalls'}
  PSysCalls = ^TSysCalls;
  TSysCalls = packed record
  const
    Prefix = '_SysCall_';
  type
    {$REGION 'ID'}
    ID = type Cardinal;

    IDHelper = record helper for ID
    const
      DebugBreak = 0;

      Memory = %10;
      MemoryFill    = Memory + 0;
      MemoryCopy    = Memory + 1;
      MemoryCompare = Memory + 2;

      Heap = $20;
      HeapAlloc     = Heap + 0;
      HeapRealloc   = Heap + 1;
      HeapFree      = Heap + 2;
      HeapSize      = Heap + 3;
      HeapAvailable = Heap + 4;

      &String = $30;
      StringNew     = &String + 0;
      StringInit    = &String + 1; // or StringNewFrom? (override that creates a string from a static string in memory)
      StringDispose = &String + 2;
      StringLength  = &String + 3;
      StringConcat  = &String + 4;
      StringCopy    = &String + 5;
      StringCompare = &String + 6;
    public
      function ToString: String;
    end;
    {$ENDREGION}

    THandler = function(AID: ID): Boolean of object;
  public
    Vectors: packed array[Byte] of Cardinal;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'SystemState'}
  PSystemState = ^TSystemState;
  TSystemState = packed record
  const
    Prefix = '_SysemState_';
  type
    {$REGION 'PanicCode'}
    TPanicCode = type Cardinal;

    TPanicCodeHelper = record helper for TPanicCode
    const
      None                 = 0;
      InvalidOperation     = 1;
      AccessViolationExec  = 2;
      AccessViolationRead  = 3;
      AccessViolationWrite = 4;
      StackOverflow        = 5;
      StackUnderflow       = 6;
      DivideByZero         = 7;
    public
      function ToString: String;
    end;
    {$ENDREGION}
  public
    Registers: TRegisters;
    PanicCode: TPanicCode;
    UserCode:  Cardinal;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'MemoryMap'}
  TMemoryMap = packed record
    OEMAddress:   Cardinal;
    OEMSize:      Cardinal;

    UserAddress:  Cardinal;
    UserSize:     Cardinal;

    HeapAddress:  Cardinal;
    HeapSize:     Cardinal;

    StackAddress: Cardinal;
    StackSize:    Cardinal;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'Timers'}
  TTimers = packed record
  type
    {$REGION 'Timer'}
    TTimer = packed record
    type
      {$REGION 'Flags'}
      TFlags = type Byte;

      TFlagsHelper = record helper for TFlags
      const
        EnabledMask   = 1 shl 0;
        DirectionMask = 1 shl 1;
        ModeMask      = 1 shl 2;
      private
        function  GetFlag(AMask: Integer):         Boolean;  inline;
        procedure SetFlag(AMask: Integer; AEnable: Boolean); inline;
      public
        property Enabled:   Boolean index EnabledMask   read GetFlag write SetFlag;
        property Direction: Boolean index DirectionMask read GetFlag write SetFlag;
        property Mode:      Boolean index ModeMask      read GetFlag write SetFlag;
      end;
      {$ENDREGION}
    public
      Current:  Cardinal;
      Interval: Cardinal;
      Flags:    TFlags;
      Padding:  array[0..6] of Byte;

      function Update(AMilliseconds: Cardinal): Boolean;
    end;
    {$ENDREGION}
  const
    Count = 2;
  public
    Timers: packed array[0..Count - 1] of TTimer;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'SystemRegisters'}
  TSystemRegisters = packed record
    RefreshRate: Cardinal;
    Elapsed:     Cardinal;
    Delta:       Single;
    Reserved:    Cardinal;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'CoreSystemMemory'}
  PCoreSystemMemory = ^TCoreSystemMemory;
  TCoreSystemMemory = packed record
  const
    InterruptsAddress   = 0;
    SysCallsAddress     = InterruptsAddress  + SizeOf(TInterrupts);
    SystemStateAddress  = SysCallsAddress    + SizeOf(TSysCalls);
    MemoryMapAddress    = SystemStateAddress + SizeOf(TSystemState);
    TimersAddress       = MemoryMapAddress   + SizeOf(TMemoryMap);
    RegistersAddress    = TimersAddress      + SizeOf(TTimers);
  public
    Interrupts:  TInterrupts;
    SysCalls:    TSysCalls;
    SystemState: TSystemState;
    MemoryMap:   TMemoryMap;
    Timers:      TTimers;
    Registers:   TSystemRegisters;

    procedure Reset;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Core.Strings;

{$REGION 'Interrupts'}
function TInterrupts.IDHelper.ToString: String;
begin
  case Self of
    Panic:    Result := Prefix + 'Panic';
    SysRq:    Result := Prefix + 'SysRq';
    FPUError: Result := Prefix + 'FPUError';
    Refresh:  Result := Prefix + 'Refresh';
    Scanline: Result := Prefix + 'Scanline';
    Timer0:   Result := Prefix + 'Timer0';
    Timer1:   Result := Prefix + 'Timer1';
  else
    Result := Prefix + IntToStr(Self);
  end;
end;

procedure TInterrupts.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);
end;
{$ENDREGION}

{$REGION 'SysCalls'}
function TSysCalls.IDHelper.ToString: String;
begin
  case Self of
    MemoryFill:    Result := Prefix + 'MemoryFill';
    MemoryCopy:    Result := Prefix + 'MemoryCopy';
    MemoryCompare: Result := Prefix + 'MemoryCompare';

    HeapAlloc:     Result := Prefix + 'HeapAlloc';
    HeapRealloc:   Result := Prefix + 'HeapRealloc';
    HeapFree:      Result := Prefix + 'HeapFree';
    HeapSize:      Result := Prefix + 'HeapSize';
    HeapAvailable: Result := Prefix + 'HeapAvailable';

    StringNew:     Result := Prefix + 'StringNew';
    StringInit:    Result := Prefix + 'StringInit';
    StringDispose: Result := Prefix + 'StringDispose';
    StringLength:  Result := Prefix + 'StringLength';
    StringConcat:  Result := Prefix + 'StringConcat';
    StringCopy:    Result := Prefix + 'StringCopy';
    StringCompare: Result := Prefix + 'StringCompare';
  else
    Result := Prefix + IntToStr(Self);
  end;
end;

procedure TSysCalls.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);
end;
{$ENDREGION}

{$REGION 'SystemState'}
function TSystemState.TPanicCodeHelper.ToString: String;
begin
  case Self of
    None:                 Result := Prefix + 'None';
    InvalidOperation:     Result := Prefix + 'InvalidOperation';
    AccessViolationExec:  Result := Prefix + 'AccessViolationExec';
    AccessViolationRead:  Result := Prefix + 'AccessViolationRead';
    AccessViolationWrite: Result := Prefix + 'AccessViolationWrite';
    StackOverflow:        Result := Prefix + 'StackOverflow';
    StackUnderflow:       Result := Prefix + 'StackUnderflow';
    DivideByZero:         Result := Prefix + 'DivideByZero';
  else
    Result := Prefix + IntToStr(Self);
  end;
end;

procedure TSystemState.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);
end;
{$ENDREGION}

{$REGION 'TMemoryMap'}
procedure TMemoryMap.Reset;
begin
  OEMAddress   := SizeOf(TCoreSystemMemory);
  OEMSize      := 0;

  UserAddress  := OEMAddress + OEMSize;
  UserSize     := 0;

  HeapAddress  := UserAddress + UserSize;
  HeapSize     := 0;

  StackAddress := HeapAddress + HeapSize;
  StackSize    := 0;
end;
{$ENDREGION}

{$REGION 'Timers'}
function TTimers.TTimer.TFlagsHelper.GetFlag(AMask: Integer): Boolean;
begin
  Result := (Self and AMask) <> 0;
end;

procedure TTimers.TTimer.TFlagsHelper.SetFlag(AMask: Integer; AEnable: Boolean);
begin
  if AEnable then
    Self := Self or AMask
  else
    Self := Self and not AMask;
end;

function TTimers.TTimer.Update(AMilliseconds: Cardinal): Boolean;
var
  Amount: Cardinal;
begin
  if not Flags.Enabled then
    Exit(False);

  if Flags.Mode then
    Amount := 1
  else
    Amount := AMilliseconds;

  if Flags.Direction then
  begin
    Current := Current + Amount;
    Result  := Current >= Interval;

    if Result then
    begin
      if Interval > 0 then
        Current := Current mod Interval
      else
        Current := 0;
    end;
  end
  else
  begin
    if Amount >= Current then
    begin
      Result := True;

      if Interval > 0 then
        Current := Interval - ((Amount - Current) mod Interval)
      else
        Current := 0;
    end
    else
    begin
      Result  := False;
      Current := Current - Amount;
    end;
  end;
end;

procedure TTimers.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);
end;
{$ENDREGION}

{$REGION 'SystemRegisters'}
procedure TSystemRegisters.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);

  RefreshRate := 60;
  Delta       := 1.0 / RefreshRate;
end;
{$ENDREGION}

{$REGION 'CoreSystemMemory'}
procedure TCoreSystemMemory.Reset;
begin
  Interrupts.Reset;
  SysCalls.Reset;
  SystemState.Reset;
  MemoryMap.Reset;
  Timers.Reset;
  Registers.Reset;
end;
{$ENDREGION}

end.
