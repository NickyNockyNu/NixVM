{
  NixVM.Harness.pas
    The root class that hold everything together.

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

unit NixVM.Harness;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  NixVM.Core.Memory,
  NixVM.Core.Registers,
  NixVM.Core.Instructions,
  NixVM.Core.CPU,
  NixVM.Core.System,
  NixVM.Harness.Timing;

type
  {$REGION 'CustomHarness'}
  TCustomHarness<TSystemMemory: record> = class
  private
    FMemory: TMemory<TSystemMemory>;
    FCPU:    TCPU;

    FRunning: Boolean;

    FElapsedTimer: TStopwatch;
    FFrameTimer:   TStopwatch;
    FUpdateTimer:  TStopwatch;

    FFrameCount: Cardinal;

    FFramesPerSecond:       Cardinal;
    FInstructionsPerSecond: Cardinal;

    FCPUBatchSize:  Cardinal;
    FCPUBatchCount: Cardinal;

    function GetElapsed: Double;   inline;
    function GetFPS:     Cardinal; inline;
    function GetIPS:     Cardinal; inline;
    function GetMIPS:    Double;   inline;

    procedure Execute;
    procedure CPUExecute;

    procedure UpdateTimers(AMilliseconds: Cardinal);
  protected
    procedure Initialize; virtual;
    procedure Finalize;   virtual;

    procedure Started; virtual;
    procedure Stopped; virtual;

    procedure Update(const ADelta: TTicks); virtual;

    procedure EverySecond; virtual;

    function HandleSysCall    (ASysCall:   TSysCalls.ID):   Boolean; virtual;
    function DispatchInterrupt(AInterrupt: TInterrupts.ID): Boolean; virtual;

    procedure HandlePanic; virtual;
  public
    constructor Create;
    destructor  Destroy; override;

    procedure Start;
    procedure Stop;

    procedure DebugBreak; virtual;
    procedure DebugPrint(const AString: AnsiString); virtual;

    property Memory: TMemory<TSystemMemory> read FMemory;
    property CPU:    TCPU                   read FCPU;

    property Running: Boolean read FRunning;

    property Elapsed: Double read GetElapsed;

    property FPS:  Cardinal read GetFPS;
    property IPS:  Cardinal read GetIPS;
    property MIPS: Double   read GetMIPS;

    property CPUBatchSize:  Cardinal read FCPUBatchSize write FCPUBatchSize;
    property CPUBatchCount: Cardinal read FCPUBatchCount;
  public
    class procedure Run;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Core.Strings;

{$REGION 'CustomHarness'}
function TCustomHarness<TSystemMemory>.GetElapsed: Double;
begin
  if FRunning then
    Result := FElapsedTimer.Elapsed.InSeconds
  else
    Result := 0;
end;

function TCustomHarness<TSystemMemory>.GetFPS: Cardinal;
begin
  if FRunning then
    Result := FFramesPerSecond
  else
    Result := 0;
end;

function TCustomHarness<TSystemMemory>.GetIPS: Cardinal;
begin
  if FRunning then
    Result := FInstructionsPerSecond
  else
    Result := 0;
end;

function TCustomHarness<TSystemMemory>.GetMIPS: Double;
begin
  Result := GetIPS;

  if Result > 0 then
    Result := Result / 1000000;
end;

procedure TCustomHarness<TSystemMemory>.Execute;
var
  SecondTimer: TStopwatch;
  DeltaTicks:  TTicks;
  DeltaTime:   Double;
begin
  FElapsedTimer.Start;
  FFrameTimer.Start;
  FUpdateTimer.Start;
  SecondTimer.Start;

  while FRunning do
  begin
    CPUExecute;

    DeltaTicks := FUpdateTimer.Update;
    DeltaTime  := DeltaTicks.InSeconds;

    FMemory.CoreSystem.Registers.Elapsed := Cardinal(UInt64(FElapsedTimer.Elapsed.InMilliseconds) and $FFFFFFFF);
    FMemory.CoreSystem.Registers.Delta   := DeltaTime;

    UpdateTimers(Cardinal(DeltaTicks.InMilliseconds));
    Update(DeltaTicks);

    Inc(FFrameCount);

    if SecondTimer.Elapsed.InSeconds >= 1 then
    begin
      FFramesPerSecond       := Round(FFrameCount    / SecondTimer.Elapsed.InSeconds);
      FInstructionsPerSecond := Round(FCPU.StepCount / SecondTimer.Elapsed.InSeconds);

      FFrameCount    := 0;
      FCPU.StepCount := 0;

      SecondTimer.Start;

      EverySecond;
    end;
  end;
end;

procedure TCustomHarness<TSystemMemory>.CPUExecute;
var
  RefreshRate: Cardinal;
  ExecuteTime: Double;
begin
  RefreshRate := FMemory.CoreSystem.Registers.RefreshRate;

  if RefreshRate = 0 then
    RefreshRate := 60;

  ExecuteTime := 1 / RefreshRate;

  FCPUBatchCount := 0;

  while FFrameTimer.Elapsed.InSeconds < ExecuteTime do
  begin
    if FCPU.HaltState then
    begin
      FFrameTimer.WaitUntil(ExecuteTime);
      Break;
    end
    else
    begin
      FCPU.Execute(FCPUBatchSize);
      Inc(FCPUBatchCount);

      if FCPU.YieldState or FCPU.HaltState then
      begin
        FFrameTimer.WaitUntil(ExecuteTime);
        Break;
      end;
    end;
  end;

  YieldCPU;

  FFrameTimer.Start;
end;

procedure TCustomHarness<TSystemMemory>.UpdateTimers(AMilliseconds: Cardinal);
begin
  for var i := 0 to TTimers.Count - 1 do
    if FMemory.CoreSystem.Timers.Timers[i].Update(AMilliseconds) then
      DispatchInterrupt(TInterrupts.ID.Timer0 + i);
end;

procedure TCustomHarness<TSystemMemory>.Initialize;
begin
  // Set the memory size here
end;

procedure TCustomHarness<TSystemMemory>.Finalize;
begin

end;

procedure TCustomHarness<TSystemMemory>.Started;
begin
  // If you adjust the memory size here you must reset the memory and CPU
end;

procedure TCustomHarness<TSystemMemory>.Stopped;
begin

end;

procedure TCustomHarness<TSystemMemory>.Update(const ADelta: TTicks);
begin

end;

procedure TCustomHarness<TSystemMemory>.EverySecond;
begin
  //DebugBreak;
end;

function TCustomHarness<TSystemMemory>.HandleSysCall(ASysCall: TSysCalls.ID): Boolean;
begin
  Result := True;

  with FCPU.Registers do
    case ASysCall of
      TSysCalls.ID.DebugBreak: DebugBreak;
      TSysCalls.ID.DebugPrint: DebugPrint(FMemory.Heap.Strings.Format(FMemory.ReadString(R0), THeap.TStringManager.TFormatArgs(R), 1));

      TSysCalls.ID.MemoryFill:          FMemory.Fill(R0, R1, R2);
      TSysCalls.ID.MemoryCopy:          FMemory.Copy(R0, R1, R2);
      TSysCalls.ID.MemoryCompare: R0 := FMemory.Compare(R0, R1, R2);

      TSysCalls.ID.HeapAlloc:     R0 := FMemory.HeapAlloc(R0);
      TSysCalls.ID.HeapRealloc:   R0 := FMemory.HeapRealloc(R0, R1);
      TSysCalls.ID.HeapFree:            FMemory.HeapFree(R0);
      TSysCalls.ID.HeapSize:      R0 := FMemory.HeapSize(R0);
      TSysCalls.ID.HeapAvailable: R0 := FMemory.HeapAvailable;

      TSysCalls.ID.StringNew:     R0 := FMemory.StringNew(R0);
      TSysCalls.ID.StringInit:    R0 := FMemory.StringNew(FMemory.ReadString(R0));
      TSysCalls.ID.StringDispose:       FMemory.StringDispose(R0);
      TSysCalls.ID.StringLength:  R0 := FMemory.StringLength(R0);
      TSysCalls.ID.StringConcat:  R0 := FMemory.StringConcat(R0, R1);
      TSysCalls.ID.StringCopy:    R0 := FMemory.StringCopy(R0, R1, R2);
      TSysCalls.ID.StringCompare: R0 := FMemory.StringCompare(R0, R1);
      TSysCalls.ID.StringFormat:  R0 := FMemory.StringFormat(R0, THeap.TStringManager.TFormatArgs(R), 1);
    else
      Result := False;
    end;
end;

function TCustomHarness<TSystemMemory>.DispatchInterrupt(AInterrupt: TInterrupts.ID): Boolean;
var
  MaxInstructions: Integer;
begin
  if FRunning then
  begin
    case AInterrupt of
      TInterrupts.ID.Timer0..TInterrupts.ID.Timer0 + (TTimers.Count - 1):
        // If timer MaxInstructions are zero they'll simply begin execution on the next CPUExecute cycle.
        // Or we can give them a batch size here if we need timer code to be executed as soon as possible (this will add a tiny bit of lag to our update cycle).
        MaxInstructions := 0;
    else
      MaxInstructions := FCPUBatchSize;
    end;

    Result := FCPU.Interrupt(AInterrupt, MaxInstructions);
  end
  else
    Result := False;
end;

procedure TCustomHarness<TSystemMemory>.HandlePanic;
begin
  FCPU.Halt;

  if IsConsole then
    Writeln(' ** PANIC: ', TSystemState.TPanicCode(FMemory.CoreSystem.SystemState.PanicCode).ToString, ' ** ');

  DebugBreak;
end;

constructor TCustomHarness<TSystemMemory>.Create;
begin
  inherited;

  FMemory := TMemory<TSystemMemory>.Create(0, 0, 0);
  FCPU    := TCPU.Create(FMemory);

  FCPU.SysCallHandler := HandleSysCall;
  FCPU.PanicHandler   := HandlePanic;

  FCPUBatchSize := 16 * 1024;

  Initialize;
end;

destructor TCustomHarness<TSystemMemory>.Destroy;
begin
  Finalize;

  FCPU.Free;
  FMemory.Free;

  inherited;
end;

procedure TCustomHarness<TSystemMemory>.Start;
begin
  if FRunning then
    Exit;

  try
    FMemory.Reset;
    FCPU.Reset;

    FRunning := True;

    Started;

    TTicks.SetResolution(1);

    Execute;
  finally
    TTicks.ResetResolution;

    Stop;
  end;
end;

procedure TCustomHarness<TSystemMemory>.Stop;
begin
  if not FRunning then
    Exit;

  FRunning := False;

  Stopped;
end;

procedure TCustomHarness<TSystemMemory>.DebugBreak;
begin
  if IsConsole then
  begin
    Writeln; for var i := 0 to  7 do Write(TRegisters.ID(i).ToString, ':', IntToHex(FCPU.Registers.R[i], 0), #9);
    Writeln; for var i := 8 to 15 do Write(TRegisters.ID(i).ToString, ':', IntToHex(FCPU.Registers.R[i], 0), #9);

    Write(#13#10'pc:',    IntToHex(FCPU.Registers.PC),
              #9'flags:', FCPU.Registers.Flags.ToString,
              #9'FPS:',   FPS,
              #9'MIPS:',  MIPS:0:2,
              #9#8);

    if FCPU.HaltState  then Write(' HALT');
    if FCPU.YieldState then Write(' YIELD');
    if FCPU.PanicState then Write(' PANIC');

    Writeln;
  end;
end;

procedure TCustomHarness<TSystemMemory>.DebugPrint(const AString: AnsiString);
begin
  if IsConsole then
    Write(AString);
end;

class procedure TCustomHarness<TSystemMemory>.Run;
begin
  with Create do try
    Start;
  finally
    Free;
  end;
end;
{$ENDREGION}

end.
