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
  public
    {$REGION 'Version'}
    class function HarnessName:  String; virtual;
    class function HarnessMajor: Word;   virtual;
    class function HarnessMinor: Word;   virtual;
    {$ENDREGION}
  private
    FMemory: TMemory<TSystemMemory>;
    FCPU:    TCPU;

    FRunning: Boolean;

    FStopOnHalt: Boolean;

    FElapsedTimer: TStopwatch;
    FFrameTimer:   TStopwatch;
    FUpdateTimer:  TStopwatch;

    FFrameCount: Cardinal;

    FFramesPerSecond:       Cardinal;
    FInstructionsPerSecond: Cardinal;

    FCPUBatchSize:  Cardinal;
    FCPUBatchCount: Cardinal;

    FROMFile: String;

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

    function LoadROM(const AROMFile: String): Boolean;
  public
    constructor Create(const AROMFile: String = '');
    destructor  Destroy; override;

    procedure Start;
    procedure Stop;

    procedure DebugBreak; virtual;
    procedure DebugPrint(const AString: AnsiString); virtual;

    property Memory: TMemory<TSystemMemory> read FMemory;
    property CPU:    TCPU                   read FCPU;

    property Running: Boolean read FRunning;

    property StopOnHalt: Boolean read FStopOnHalt write FStopOnHalt;

    property Elapsed: Double read GetElapsed;

    property FPS:  Cardinal read GetFPS;
    property IPS:  Cardinal read GetIPS;
    property MIPS: Double   read GetMIPS;

    property CPUBatchSize:  Cardinal read FCPUBatchSize write FCPUBatchSize;
    property CPUBatchCount: Cardinal read FCPUBatchCount;

    property ROMFile: String read FROMFile;
  public
    class function GenTargetInc: String;

    class procedure Run(const AROMFile: String = '');
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Core.ROM,
  NixVM.Core.Strings;

{$REGION 'CustomHarness'}
{$REGION 'Version'}
class function TCustomHarness<TSystemMemory>.HarnessName: String;
var
  i: Integer;
begin
  Result := Copy(ClassName, 1, 32);

  if Result[1] = 'T' then
    Result := Copy(Result, 2, Length(Result));

  i := Pos('<', Result);

  if i > 0 then
    Result := Copy(Result, 1, i - 1);
end;

class function TCustomHarness<TSystemMemory>.HarnessMajor: Word;
begin
  Result := 1;
end;

class function TCustomHarness<TSystemMemory>.HarnessMinor: Word;
begin
  Result := 0;
end;
{$ENDREGION}

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

    if FStopOnHalt and FCPU.HaltState then
      Stop;

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
  if Length(FROMFile) > 0  then
  begin
    if not LoadROM(FROMFile) then
      FCPU.Halt;
  end

  else if ParamCount >= 1 then
  begin
    if not LoadROM(ParamStr(1)) then
      CPU.Halt;
  end

  else
  begin
    DebugPrint('No ROM.'#13#10);
    CPU.Halt;
  end;
end;

procedure TCustomHarness<TSystemMemory>.Finalize;
begin
  ExitCode := FMemory.CoreSystem^.SystemState.UserCode;
end;

procedure TCustomHarness<TSystemMemory>.Started;
begin

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

function TCustomHarness<TSystemMemory>.LoadROM(const AROMFile: String): Boolean;
var
  F:         file;
  OldMode:   Byte;
  Header:    TROMHeader;
  BytesRead: Integer;
begin
  Result   := False;
  OldMode  := FileMode;
  FileMode := 0;
  FROMFile := '';

  AssignFile(F, AROMFile);

  try
    {$I-}Reset(F, 1);{$I+}

    if IOResult <> 0 then
    begin
      DebugPrint('Unable to open file "' + AnsiString(AROMFile) + '"'#13#10);

      Exit;
    end;

    try
      BlockRead(F, Header, SizeOf(TROMHeader), BytesRead);

      if (BytesRead <> SizeOf(TROMHeader)) or not Header.IsValid then
      begin
        DebugPrint('Not a valid NixVM ROM'#13#10);

        Exit;
      end;

      if Header.UserAddress <> FMemory.UserAddress then
      begin
        DebugPrint('Incompatable memory layout'#13#10);

        Exit;
      end;

      if Length(Header.Harness.Name) > 0 then
      begin
        if Lowercase(Header.Harness.Name) <> Lowercase(HarnessName) then
        begin
          DebugPrint(AnsiString('Requires harness: "' + Header.Harness.Name + '" is "' + HarnessName + '"'#13#10));

          Exit;
        end;

        if (Header.Harness.Major > HarnessMajor) or ((Header.Harness.Major = HarnessMajor) and (Header.Harness.Minor > HarnessMinor)) then
        begin
          DebugPrint(AnsiString('Requires harness version:' + IntToStr(Header.Harness.Major) + '.' + IntToStr(Header.Harness.Minor) + #13#10));

          Exit;
        end;
      end;

      if Header.UserSize = 0 then
        Header.UserSize := FileSize(F) - SizeOf(TROMHeader);

      //if Header.HeapSize  = 0 then Header.HeapSize  := 64 * 1024;
      //if Header.StackSize = 0 then Header.StackSize := 16 * 1024;

      FMemory.Resize(Header.UserSize, Header.HeapSize, Header.StackSize);
      FMemory.Reset;

      if Header.UserSize > 0 then
      begin
        BlockRead(F, FMemory[FMemory.UserAddress]^, Header.UserSize, BytesRead);

        if Cardinal(BytesRead) <> Header.UserSize then
        begin
          DebugPrint('Unable to read data'#13#10);

          Exit(False);
        end;
      end;

      FROMFile := AROMFile;
      Result   := True;

      FCPU.Reset;
    finally
      CloseFile(F);
    end;
  finally
    FileMode := OldMode;
  end;
end;

constructor TCustomHarness<TSystemMemory>.Create(const AROMFile: String = '');
begin
  inherited Create;

  FMemory := TMemory<TSystemMemory>.Create(0, 0, 0);
  FCPU    := TCPU.Create(FMemory);

  FCPU.SysCallHandler := HandleSysCall;
  FCPU.PanicHandler   := HandlePanic;

  FCPUBatchSize := 16 * 1024;

  FROMFile := AROMFile;

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

class function TCustomHarness<TSystemMemory>.GenTargetInc: String;
var
  ExpectedUserAddr: Cardinal;
begin
  ExpectedUserAddr := (SizeOf(TCoreSystemMemory) + SizeOf(TSystemMemory) + 3) and not Cardinal(3);

  Result :=
    '; Auto-generated target specification for ' + QualifiedClassName + #13#10 +
    '.target "' + HarnessName + '", ' + IntToStr(HarnessMajor) + ', ' + IntToStr(HarnessMinor) + #13#10 +
    '.base $' + IntToHex(ExpectedUserAddr, 0) + #13#10;
end;

class procedure TCustomHarness<TSystemMemory>.Run(const AROMFile: String = '');
begin
  with Create(AROMFile) do try
    Start;
  finally
    Free;
  end;
end;
{$ENDREGION}

end.
