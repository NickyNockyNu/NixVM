{
  NixVM.Core.CPU.pas
    Central Processor Unit

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

unit NixVM.Core.CPU;

{$INCLUDE 'NixVM.Options.inc'}
{.$DEFINE CHECK_MEM_BOUNDS}
{.$DEFINE DEBUG}

interface

uses
  NixVM.Core.Registers,
  NixVM.Core.Instructions,
  NixVM.Core.System,
  NixVM.Core.Memory;

type
  {$REGION 'CPU'}
  TCPU = class
  type
    TPanicHandler = procedure of object;
  private
    FMemory: TMemory;

    FHalt:  Boolean;
    FYield: Boolean;
    FPanic: Boolean;

    FStepCount: Integer;

    FCurrentCPUInstruction: TCPUInstruction;

    FSysCallHandler: TSysCalls.THandler;
    FPanicHandler:   TPanicHandler;

    function NextWord:  Word;     inline;
    function NextDWord: Cardinal; inline;

    procedure CheckPC; inline;
    {$IF DEFINED(CHECK_MEM_BOUNDS)}
    procedure CheckAddress(AAddress: Cardinal; APanicCode: TSystemState.TPanicCode); inline;
    {$ENDIF}

    procedure FPUError;
  protected
    procedure InternalPanic; virtual;
  public
    constructor Create(AMemory: TMemory);

    procedure Reset;

    procedure Step; inline;
    procedure Execute(AMaxInstructions: Integer; AAbortOp: TCPUInstruction.TOpCode = TCPUInstruction.TOpCode.HALT); inline;

    procedure Push(AValue: Cardinal);
    function  Pop: Cardinal;

    procedure SaveState;
    procedure RestoreState;

    procedure Panic(APanicCode: TSystemState.TPanicCode; AUserCode: Cardinal = 0);
    procedure Halt;

    function SysCall  (ASysCallID:   TSysCalls.ID;   AMaxInstructions: Integer = 0): Boolean;
    function Interrupt(AInterruptID: TInterrupts.ID; AMaxInstructions: Integer = 0): Boolean;

    property Memory: TMemory read FMemory;

    property HaltState:  Boolean read FHalt;
    property YieldState: Boolean read FYield;
    property PanicState: Boolean read FPanic;

    property SysCallHandler: TSysCalls.THandler read FSysCallHandler write FSysCallHandler;
    property PanicHandler:   TPanicHandler      read FPanicHandler   write FPanicHandler;

    property StepCount: Integer read FStepCount write FStepCount;
  public
    Registers: TRegisters;

  private
    {$REGION 'Instructions'}
    procedure DoHALT;  inline;
    procedure DoYIELD; inline;
    procedure DoRAISE; inline;

    procedure DoMOV;   inline;
    procedure DoSWAP;  inline;
    procedure DoCMP;   inline;
    procedure DoLEA;   inline;
    procedure DoZEXTB; inline;
    procedure DoZEXTW; inline;

    procedure DoADD; inline;
    procedure DoSUB; inline;
    procedure DoMUL; inline;
    procedure DoDIV; inline;
    procedure DoMOD; inline;

    procedure DoIMUL;  inline;
    procedure DoIDIV;  inline;
    procedure DoIMOD;  inline;
    procedure DoISAR;  inline;
    procedure DoINEG;  inline;
    procedure DoIEXTB; inline;
    procedure DoIEXTW; inline;

    procedure DoAND; inline;
    procedure DoOR;  inline;
    procedure DoXOR; inline;
    procedure DoSHL; inline;
    procedure DoSHR; inline;
    procedure DoNOT; inline;

    procedure DoLDB; inline;
    procedure DoLDW; inline;
    procedure DoLD;  inline;
    procedure DoSTB;  inline;
    procedure DoSTW;  inline;
    procedure DoST;   inline;
    procedure DoLDIB; inline;
    procedure DoLDIW; inline;
    procedure DoLDI;  inline;
    procedure DoSTIB; inline;
    procedure DoSTIW; inline;
    procedure DoSTI;  inline;
    procedure DoSTSB; inline;
    procedure DoSTSW; inline;
    procedure DoSTS;  inline;
    procedure DoLDOB; inline;
    procedure DoLDOW; inline;
    procedure DoLDO;  inline;
    procedure DoSTOB; inline;
    procedure DoSTOW; inline;
    procedure DoSTO;  inline;

    procedure DoJNZ;
    procedure DoJE;
    procedure DoJL;
    procedure DoJLE;
    procedure DoJG;
    procedure DoJGE;
    procedure DoJB;
    procedure DoJAE;
    procedure DoJMP;
    procedure DoLOOP;

    procedure DoCALL;
    procedure DoSYSCALL;
    procedure DoINT;
    procedure DoRET;
    procedure DoIRET;

    procedure DoENTER;
    procedure DoLEAVE;
    procedure DoZENTER;

    procedure DoPUSH;
    procedure DoPOP;
    procedure DoPUSHF;
    procedure DoPOPF;
    procedure DoPUSHR;
    procedure DoPOPR;

    procedure DoFADD;
    procedure DoFSUB;
    procedure DoFMUL;
    procedure DoFDIV;

    procedure DoITOF;
    procedure DoFTOI;
    procedure DoFRND;

    procedure DoFSIN;
    procedure DoFCOS;
    procedure DoFTAN;
    procedure DoFATAN;
    procedure DoFLN;
    procedure DoFEXP;
    procedure DoFSQRT;
    procedure DoFCE;
    procedure DoFCMP;

    procedure DoSETE;  inline;
    procedure DoSETNE; inline;
    procedure DoSETL;  inline;
    procedure DoSETLE; inline;
    procedure DoSETG;  inline;
    procedure DoSETGE; inline;

    procedure DoBSET;  inline;
    procedure DoBCLR;  inline;
    procedure DoBTST;  inline;
    procedure DoBSETF; inline;
    procedure DoBCLRF; inline;
    procedure DoBTSTF; inline;

    procedure DoNOP; inline;
    {$ENDREGION}
  end;
  {$ENDREGION}

function SingleToDWord(AValue: Single):   Cardinal; inline;
function DWordToSingle(AValue: Cardinal): Single;   inline;

implementation

function SingleToDWord(AValue: Single): Cardinal;
begin
  Result := PCardinal(@AValue)^;
end;

function DWordToSingle(AValue: Cardinal): Single;
begin
  Result := PSingle(@AValue)^;
end;

{$REGION 'CPU'}
function TCPU.NextWord: Word;
begin
  Result := FMemory.ReadWord(Registers.PC);
  Inc(Registers.PC, SizeOf(Result));
end;

function TCPU.NextDWord: Cardinal;
begin
  Result := FMemory.ReadDWord(Registers.PC);
  Inc(Registers.PC, SizeOf(Result));
end;

procedure TCPU.CheckPC;
begin
  if not FMemory.IsAddressExecutable(Registers.PC) then
    Panic(TSystemState.TPanicCode.AccessViolationExec, Registers.PC);
end;

{$IF DEFINED(CHECK_MEM_BOUNDS)}
procedure TCPU.CheckAddress(AAddress: Cardinal; APanicCode: TSystemState.TPanicCode);
begin
  if AAddress >= FMemory.Size then
    Panic(APanicCode, AAddress);
end;
{$ENDIF}

procedure TCPU.FPUError;
begin
  Registers.Flags.FPUException := True;

  Interrupt(TInterrupts.ID.FPUError);
end;

procedure TCPU.InternalPanic;
begin
  if Assigned(FPanicHandler) then
    FPanicHandler
  else
  begin
    SysCall(TSysCalls.ID.DebugBreak);
    Self.Halt;
  end;
end;

constructor TCPU.Create(AMemory: TMemory);
begin
  inherited Create;

  FMemory := AMemory;
end;

procedure TCPU.Reset;
begin
  FHalt  := False;
  FYield := False;
  FPanic := False;

  Registers := Default(TRegisters);

  Registers.PC    := FMemory.UserAddress;
  Registers.SP    := FMemory.Stack.Address;
  Registers.Flags := TRegisters.TFlags.Default;

  FStepCount := 0;
end;

procedure TCPU.Step;
begin
  FYield := False;

  Inc(FStepCount);

  FCurrentCPUInstruction := NextWord;

{$IF DEFINED(DEBUG)}
  Writeln(FCurrentCPUInstruction.ToString);
{$ENDIF}

  if FCurrentCPUInstruction.RegB = TRegisters.ID.Imm then
    Registers.r[TRegisters.ID.Imm] := NextDWord;

  case FCurrentCPUInstruction.OpCode of
    {$REGION 'Instruction dispatch'}
    TCPUInstruction.TOpCode.HALT:   DoHALT;
    TCPUInstruction.TOpCode.YIELD:  DoYIELD;
    TCPUInstruction.TOpCode.&RAISE: DoRAISE;

    TCPUInstruction.TOpCode.MOV:   DoMOV;
    TCPUInstruction.TOpCode.SWAP:  DoSWAP;
    TCPUInstruction.TOpCode.CMP:   DoCMP;
    TCPUInstruction.TOpCode.LEA:   DoLEA;
    TCPUInstruction.TOpCode.ZEXTB: DoZEXTB;
    TCPUInstruction.TOpCode.ZEXTW: DoZEXTW;

    TCPUInstruction.TOpCode.ADD: DoADD;
    TCPUInstruction.TOpCode.SUB: DoSUB;
    TCPUInstruction.TOpCode.MUL: DoMUL;
    TCPUInstruction.TOpCode.DIV: DoDIV;
    TCPUInstruction.TOpCode.MOD: DoMOD;

    TCPUInstruction.TOpCode.IMUL:  DoIMUL;
    TCPUInstruction.TOpCode.IDIV:  DoIDIV;
    TCPUInstruction.TOpCode.IMOD:  DoIMOD;
    TCPUInstruction.TOpCode.ISAR:  DoISAR;
    TCPUInstruction.TOpCode.INEG:  DoINEG;
    TCPUInstruction.TOpCode.IEXTB: DoIEXTB;
    TCPUInstruction.TOpCode.IEXTW: DoIEXTW;

    TCPUInstruction.TOpCode.AND: DoAND;
    TCPUInstruction.TOpCode.OR:  DoOR;
    TCPUInstruction.TOpCode.XOR: DoXOR;
    TCPUInstruction.TOpCode.SHL: DoSHL;
    TCPUInstruction.TOpCode.SHR: DoSHR;
    TCPUInstruction.TOpCode.NOT: DoNOT;

    TCPUInstruction.TOpCode.LDB:  DoLDB;
    TCPUInstruction.TOpCode.LDW:  DoLDW;
    TCPUInstruction.TOpCode.LD:   DoLD;
    TCPUInstruction.TOpCode.STB:  DoSTB;
    TCPUInstruction.TOpCode.STW:  DoSTW;
    TCPUInstruction.TOpCode.ST:   DoST;
    TCPUInstruction.TOpCode.LDIB: DoLDIB;
    TCPUInstruction.TOpCode.LDIW: DoLDIW;
    TCPUInstruction.TOpCode.LDI:  DoLDI;
    TCPUInstruction.TOpCode.STIB: DoSTIB;
    TCPUInstruction.TOpCode.STIW: DoSTIW;
    TCPUInstruction.TOpCode.STI:  DoSTI;
    TCPUInstruction.TOpCode.STSB: DoSTSB;
    TCPUInstruction.TOpCode.STSW: DoSTSW;
    TCPUInstruction.TOpCode.STS:  DoSTS;
    TCPUInstruction.TOpCode.LDOB: DoLDOB;
    TCPUInstruction.TOpCode.LDOW: DoLDOW;
    TCPUInstruction.TOpCode.LDO:  DoLDO;
    TCPUInstruction.TOpCode.STOB: DoSTOB;
    TCPUInstruction.TOpCode.STOW: DoSTOW;
    TCPUInstruction.TOpCode.STO:  DoSTO;

    TCPUInstruction.TOpCode.JNZ:  DoJNZ;
    TCPUInstruction.TOpCode.JE:   DoJE;
    TCPUInstruction.TOpCode.JL:   DoJL;
    TCPUInstruction.TOpCode.JLE:  DoJLE;
    TCPUInstruction.TOpCode.JG:   DoJG;
    TCPUInstruction.TOpCode.JGE:  DoJGE;
    TCPUInstruction.TOpCode.JB:   DoJB;
    TCPUInstruction.TOpCode.JAE:  DoJAE;
    TCPUInstruction.TOpCode.JMP:  DoJMP;
    TCPUInstruction.TOpCode.LOOP: DoLOOP;

    TCPUInstruction.TOpCode.CALL:    DoCALL;
    TCPUInstruction.TOpCode.SYSCALL: DoSYSCALL;
    TCPUInstruction.TOpCode.INT:     DoINT;
    TCPUInstruction.TOpCode.RET:     DoRET;
    TCPUInstruction.TOpCode.IRET:    DoIRET;

    TCPUInstruction.TOpCode.ENTER:  DoENTER;
    TCPUInstruction.TOpCode.LEAVE:  DoLEAVE;
    TCPUInstruction.TOpCode.ZENTER: DoZENTER;

    TCPUInstruction.TOpCode.PUSH:  DoPUSH;
    TCPUInstruction.TOpCode.POP:   DoPOP;
    TCPUInstruction.TOpCode.PUSHF: DoPUSHF;
    TCPUInstruction.TOpCode.POPF:  DoPOPF;
    TCPUInstruction.TOpCode.PUSHR: DoPUSHR;
    TCPUInstruction.TOpCode.POPR:  DoPOPR;

    TCPUInstruction.TOpCode.FADD: DoFADD;
    TCPUInstruction.TOpCode.FSUB: DoFSUB;
    TCPUInstruction.TOpCode.FMUL: DoFMUL;
    TCPUInstruction.TOpCode.FDIV: DoFDIV;

    TCPUInstruction.TOpCode.ITOF:  DoITOF;
    TCPUInstruction.TOpCode.FTOI:  DoFTOI;
    TCPUInstruction.TOpCode.FRND:  DoFRND;
    TCPUInstruction.TOpCode.FSIN:  DoFSIN;
    TCPUInstruction.TOpCode.FCOS:  DoFCOS;
    TCPUInstruction.TOpCode.FTAN:  DoFTAN;
    TCPUInstruction.TOpCode.FATAN: DoFATAN;
    TCPUInstruction.TOpCode.FEXP:  DoFEXP;
    TCPUInstruction.TOpCode.FLN:   DoFLN;
    TCPUInstruction.TOpCode.FSQRT: DoFSQRT;
    TCPUInstruction.TOpCode.FCE:   DoFCE;
    TCPUInstruction.TOpCode.FCMP:  DoFCMP;

    TCPUInstruction.TOpCode.SETE:  DoSETE;
    TCPUInstruction.TOpCode.SETNE: DoSETNE;
    TCPUInstruction.TOpCode.SETL:  DoSETL;
    TCPUInstruction.TOpCode.SETLE: DoSETLE;
    TCPUInstruction.TOpCode.SETG:  DoSETG;
    TCPUInstruction.TOpCode.SETGE: DoSETGE;

    TCPUInstruction.TOpCode.BSET:  DoBSET;
    TCPUInstruction.TOpCode.BCLR:  DoBCLR;
    TCPUInstruction.TOpCode.BTST:  DoBTST;
    TCPUInstruction.TOpCode.BSETF: DoBSETF;
    TCPUInstruction.TOpCode.BCLRF: DoBCLRF;
    TCPUInstruction.TOpCode.BTSTF: DoBTSTF;

    TCPUInstruction.TOpCode.NOP: DoNOP;
    {$ENDREGION}
  else
    Panic(TSystemState.TPanicCode.InvalidOperation, FCurrentCPUInstruction.OpCode);
  end;

{$IF DEFINED(DEBUG)}
  SysCall(TSysCalls.ID.DebugBreak);
  Readln;
{$ENDIF}
end;

procedure TCPU.Execute(AMaxInstructions: Integer; AAbortOp: TCPUInstruction.TOpCode);
var
  Count: Integer;
begin
  if AMaxInstructions <= 0 then
    Exit;

  Count := 0;

  while Count < AMaxInstructions do
  begin
    Step;
    Inc(Count);

    if FHalt or FYield or (FCurrentCPUInstruction.OpCode = AAbortOp) then
      Break;
  end;
end;

procedure TCPU.Push(AValue: Cardinal);
begin
  if Registers.SP < (FMemory.Stack.Address - FMemory.Stack.Size) + SizeOf(Cardinal) then
  begin
    Panic(TSystemState.TPanicCode.StackOverflow);
    Exit;
  end;

  Dec(Registers.SP, SizeOf(Cardinal));

  FMemory.WriteDWord(Registers.SP, AValue);
end;

function TCPU.Pop: Cardinal;
begin
  if Registers.SP >= FMemory.Stack.Address then
  begin
    Panic(TSystemState.TPanicCode.StackUnderflow);
    Exit(0);
  end;

  Result := FMemory.ReadDWord(Registers.SP);

  Inc(Registers.SP, SizeOf(Cardinal));
end;

procedure TCPU.SaveState;
begin
  FMemory.CoreSystem.SystemState.Registers := Registers;
end;

procedure TCPU.RestoreState;
begin
  Registers := FMemory.CoreSystem.SystemState.Registers;
end;

procedure TCPU.Panic(APanicCode: TSystemState.TPanicCode; AUserCode: Cardinal);
var
  HandlerAddr: Cardinal;
begin
  SaveState;

  FMemory.CoreSystem.SystemState.PanicCode := APanicCode;
  FMemory.CoreSystem.SystemState.UserCode  := AUserCode;

  if FPanic then
  begin
    InternalPanic;
    Exit;
  end;

  FPanic := True;

  HandlerAddr := FMemory.CoreSystem.Interrupts.Vectors[TInterrupts.ID.Panic];

  if (HandlerAddr = 0) or not FMemory.IsAddressExecutable(HandlerAddr) then
    InternalPanic
  else
    Interrupt(TInterrupts.ID.Panic);
end;

function TCPU.SysCall(ASysCallID: TSysCalls.ID; AMaxInstructions: Integer): Boolean;
var
  TargetPC: Cardinal;
begin
  if ASysCallID < 256 then
  begin
    TargetPC := FMemory.CoreSystem.SysCalls.Vectors[ASysCallID];

    if not FMemory.IsAddressExecutable(TargetPC) then
    begin
      if Assigned(FSysCallHandler) then
        Exit(FSysCallHandler(ASysCallID))
      else
        Exit(False);
    end;

    Push(Registers.PC);

    Registers.PC := TargetPC;

    Result := True;

    if AMaxInstructions > 0 then
      Execute(AMaxInstructions, TCPUInstruction.TOpCode.RET);
  end
  else if Assigned(FSysCallHandler) then
    Result := FSysCallHandler(ASysCallID)
  else
    Result := False;
end;

procedure TCPU.Halt;
begin
  FHalt := True;
end;

function TCPU.Interrupt(AInterruptID: TInterrupts.ID; AMaxInstructions: Integer): Boolean;
var
  TargetPC: Cardinal;
begin
  if (not Registers.Flags.InterruptsEnabled) and (AInterruptID <> TInterrupts.ID.Panic) and (AInterruptID <> TInterrupts.ID.NMI) then
    Exit(False);

  TargetPC := FMemory.CoreSystem.Interrupts.Vectors[AInterruptID];

  if not FMemory.IsAddressExecutable(TargetPC) then
    Exit(False);

  Push(Registers.Flags);
  Push(Registers.PC);

  Registers.Flags.InterruptsEnabled := False;

  Registers.PC := TargetPC;

  Result := True;

  if AMaxInstructions > 0 then
    Execute(AMaxInstructions, TCPUInstruction.TOpCode.IRET);
end;
{$ENDREGION}

{$REGION 'Instructions'}
procedure TCPU.DoHALT;
begin
  Self.Halt;
end;

procedure TCPU.DoYIELD;
begin
  FYield := True;
end;

procedure TCPU.DoRAISE;
begin
  Panic(TSystemState.TPanicCode.Exception, Registers.r[FCurrentCPUInstruction.RegB]);
end;

procedure TCPU.DoMOV;
begin
  Registers.r[FCurrentCPUInstruction.RegA] := Registers.r[FCurrentCPUInstruction.RegB];
end;

procedure TCPU.DoSWAP;
var
  Temp: Cardinal;
begin
  Temp := Registers.r[FCurrentCPUInstruction.RegA];

  Registers.r[FCurrentCPUInstruction.RegA] := Registers.r[FCurrentCPUInstruction.RegB];
  Registers.r[FCurrentCPUInstruction.RegB] := Temp;
end;

procedure TCPU.DoCMP;
var
  Save: Cardinal;
begin
  Save := Registers.r[FCurrentCPUInstruction.RegA];
  DoSUB;
  Registers.r[FCurrentCPUInstruction.RegA] := Save;
end;

procedure TCPU.DoLEA;
begin
  Registers.r[FCurrentCPUInstruction.RegA] := Registers.r[FCurrentCPUInstruction.RegB] + NextDWord;

  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoZEXTB;
begin
  Registers.r[FCurrentCPUInstruction.RegA] := Registers.r[FCurrentCPUInstruction.RegB] and $FF;
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoZEXTW;
begin
  Registers.r[FCurrentCPUInstruction.RegA] := Registers.r[FCurrentCPUInstruction.RegB] and $FFFF;
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

{$REGION 'Arithmetic'}
procedure TCPU.DoADD;
var
  Left, Right: Cardinal;
  Result32:    Cardinal;
  Result64:    UInt64;
begin
  Left  := Registers.r[FCurrentCPUInstruction.RegA];
  Right := Registers.r[FCurrentCPUInstruction.RegB];

  Result64 := Left + Right;
  Result32 := Result64 and $FFFFFFFF;

  Registers.r[FCurrentCPUInstruction.RegA] := Result32;

  Registers.Flags.UpdateZN(Result32);

  Registers.Flags.Carry    := (Result64 > $FFFFFFFF);
  Registers.Flags.Overflow := ((Left xor Result32) and (Right xor Result32) and $80000000) <> 0;
end;

procedure TCPU.DoSUB;
var
  Left, Right: Cardinal;
  Result32:    Cardinal;
  Result64:    UInt64;
begin
  Left  := Registers.r[FCurrentCPUInstruction.RegA];
  Right := Registers.r[FCurrentCPUInstruction.RegB];

  Result64 := Left - Right;
  Result32 := Result64 and $FFFFFFFF;

  Registers.r[FCurrentCPUInstruction.RegA] := Result32;

  Registers.Flags.UpdateZN(Result32);

  //Registers.Flags.Carry    := Int64(Result64) < 0;
  Registers.Flags.Carry := Left < Right;
  Registers.Flags.Overflow := ((Left xor Right) and (Left xor Result32) and $80000000) <> 0;
end;

procedure TCPU.DoMUL;
var
  Left, Right: Cardinal;
  Result32:    Cardinal;
  Result64:    UInt64;
begin
  Left  := Registers.r[FCurrentCPUInstruction.RegA];
  Right := Registers.r[FCurrentCPUInstruction.RegB];

  Result64 := UInt64(Left) * Right;
  Result32 := Result64 and $FFFFFFFF;

  Registers.r[FCurrentCPUInstruction.RegA] := Result32;

  Registers.Flags.UpdateZN(Result32);

  Registers.Flags.Carry    := (Result64 > $FFFFFFFF);
  Registers.Flags.Overflow := Registers.Flags.Carry;
end;

procedure TCPU.DoDIV;
var
  Left:  Cardinal;
  Right: Cardinal;
begin
  Right := Registers.r[FCurrentCPUInstruction.RegB];

  if Right = 0 then
  begin
    Registers.r[FCurrentCPUInstruction.RegA] := 0;

    Registers.Flags.Carry := True;
    Registers.Flags.Zero  := True;

    if Registers.Flags.DivZPanicEnabled then
      Panic(TSystemState.TPanicCode.DivideByZero);

    Exit;
  end;

  Left  := Registers.r[FCurrentCPUInstruction.RegA];

  Registers.r[FCurrentCPUInstruction.RegA] := Left div Right;
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoMOD;
var
  Left:  Cardinal;
  Right: Cardinal;
begin
  Right := Registers.r[FCurrentCPUInstruction.RegB];

  if Right = 0 then
  begin
    Registers.r[FCurrentCPUInstruction.RegA] := 0;

    Registers.Flags.Carry := True;
    Registers.Flags.Zero  := True;

    if Registers.Flags.DivZPanicEnabled then
      Panic(TSystemState.TPanicCode.DivideByZero);

    Exit;
  end;

  Left  := Registers.r[FCurrentCPUInstruction.RegA];

  Registers.r[FCurrentCPUInstruction.RegA] := Left mod Right;
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;
{$ENDREGION}

{$REGION 'Signed/Integer Arithmetic'}
procedure TCPU.DoIMUL;
var
  Left, Right: Integer;
  Result32:    Integer;
  Result64:    Int64;
begin
  Left  := Integer(Registers.r[FCurrentCPUInstruction.RegA]);
  Right := Integer(Registers.r[FCurrentCPUInstruction.RegB]);

  Result64 := Int64(Left) * Right;
  Result32 := Result64 and $FFFFFFFF;

  Registers.r[FCurrentCPUInstruction.RegA] := Cardinal(Result32);

  Registers.Flags.UpdateZN(Cardinal(Result32));

  Registers.Flags.Overflow := (Result64 < -(Int64(MaxInt) + 1)) or (Result64 > MaxInt);
  Registers.Flags.Carry    := Registers.Flags.Overflow;
end;

procedure TCPU.DoIDIV;
var
  Left:  Integer;
  Right: Integer;
begin
  Left  := Integer(Registers.r[FCurrentCPUInstruction.RegA]);
  Right := Integer(Registers.r[FCurrentCPUInstruction.RegB]);

  if (Right = 0) or ((Left = Low(Integer)) and (Right = -1)) then
  begin
    Registers.r[FCurrentCPUInstruction.RegA] := 0;

    Registers.Flags.Carry := True;
    Registers.Flags.Zero  := True;

    if Registers.Flags.DivZPanicEnabled then
      Panic(TSystemState.TPanicCode.DivideByZero);

    Exit;
  end;

  Registers.r[FCurrentCPUInstruction.RegA] := Cardinal(Left div Right);
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoIMOD;
var
  Left:  Integer;
  Right: Integer;
begin
  Right := Integer(Registers.r[FCurrentCPUInstruction.RegB]);

  if Right = 0 then
  begin
    Registers.r[FCurrentCPUInstruction.RegA] := 0;

    Registers.Flags.Carry := True;
    Registers.Flags.Zero  := True;

    if Registers.Flags.DivZPanicEnabled then
      Panic(TSystemState.TPanicCode.DivideByZero);

    Exit;
  end;

  Left := Integer(Registers.r[FCurrentCPUInstruction.RegA]);

  if (Left = Low(Integer)) and (Right = -1) then
  begin
    Registers.r[FCurrentCPUInstruction.RegA] := 0;
    Registers.Flags.UpdateZN(0);

    Exit;
  end;

  Registers.r[FCurrentCPUInstruction.RegA] := Cardinal(Left mod Right);
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoISAR;
var
  ShiftCount: Cardinal;
  Value:      Int64;
begin
  ShiftCount := Registers.r[FCurrentCPUInstruction.RegB];

  if ShiftCount = 0 then
    Exit;

  Value := Integer(Registers.r[FCurrentCPUInstruction.RegA]);

  if ShiftCount < 32 then
  begin
    if Value < 0 then
      Registers.r[FCurrentCPUInstruction.RegA] := Cardinal((Value shr ShiftCount) or ($FFFFFFFF shl (32 - ShiftCount)))
    else
      Registers.r[FCurrentCPUInstruction.RegA] := Cardinal(Value shr ShiftCount);
  end
  else
  begin
    if Value < 0 then
      Registers.r[FCurrentCPUInstruction.RegA] := $FFFFFFFF
    else
      Registers.r[FCurrentCPUInstruction.RegA] := 0;
  end;

  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoINEG;
var
  Value: Cardinal;
begin
  Value := Registers.r[FCurrentCPUInstruction.RegB];
  Registers.r[FCurrentCPUInstruction.RegA] := Cardinal(-Int32(Value));

  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);

  Registers.Flags.Overflow := (Value = $80000000);
  Registers.Flags.Carry    := (Value <> 0);
end;

procedure TCPU.DoIEXTB;
begin
  Registers.r[FCurrentCPUInstruction.RegA] := Cardinal(Int32(Int8(Registers.r[FCurrentCPUInstruction.RegB])));
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoIEXTW;
begin
  Registers.r[FCurrentCPUInstruction.RegA] := Cardinal(Int32(Int16(Registers.r[FCurrentCPUInstruction.RegB])));
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;
{$ENDREGION}

{$REGION 'Bitwise'}
procedure TCPU.DoAND;
begin
  Registers.r[FCurrentCPUInstruction.RegA] := Registers.r[FCurrentCPUInstruction.RegA] and Registers.r[FCurrentCPUInstruction.RegB];
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoOR;
begin
  Registers.r[FCurrentCPUInstruction.RegA] := Registers.r[FCurrentCPUInstruction.RegA] or Registers.r[FCurrentCPUInstruction.RegB];
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoXOR;
begin
  Registers.r[FCurrentCPUInstruction.RegA] := Registers.r[FCurrentCPUInstruction.RegA] xor Registers.r[FCurrentCPUInstruction.RegB];
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoSHL;
var
  ShiftCount: Word;
begin
  ShiftCount := Registers.r[FCurrentCPUInstruction.RegB];

  if ShiftCount < 32 then
    Registers.r[FCurrentCPUInstruction.RegA] := (Registers.r[FCurrentCPUInstruction.RegA] shl ShiftCount) and $FFFFFFFF
  else
    Registers.r[FCurrentCPUInstruction.RegA] := 0;

  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoSHR;
var
  ShiftCount: Word;
begin
  ShiftCount := Registers.r[FCurrentCPUInstruction.RegB];

  if ShiftCount < 32 then
    Registers.r[FCurrentCPUInstruction.RegA] := (Registers.r[FCurrentCPUInstruction.RegA] shr ShiftCount) and $FFFFFFFF
  else
    Registers.r[FCurrentCPUInstruction.RegA] := 0;

  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoNOT;
begin
  Registers.r[FCurrentCPUInstruction.RegA] := not Registers.r[FCurrentCPUInstruction.RegB];
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;
{$ENDREGION}

{$REGION 'Load/Store'}
procedure TCPU.DoLDB;
begin
  {$IF DEFINED(CHECK_MEM_BOUNDS)}CheckAddress(Registers.r[FCurrentCPUInstruction.RegB], TSystemState.TPanicCode.AccessViolationRead);{$ENDIF}
  Registers.R[FCurrentCPUInstruction.RegA] := FMemory.ReadByte(Registers.r[FCurrentCPUInstruction.RegB]);
end;

procedure TCPU.DoLDW;
begin
  {$IF DEFINED(CHECK_MEM_BOUNDS)}CheckAddress(Registers.r[FCurrentCPUInstruction.RegB] + 1, TSystemState.TPanicCode.AccessViolationRead);{$ENDIF}
  Registers.R[FCurrentCPUInstruction.RegA] := FMemory.ReadWord(Registers.r[FCurrentCPUInstruction.RegB]);
end;

procedure TCPU.DoLD;
begin
  {$IF DEFINED(CHECK_MEM_BOUNDS)}CheckAddress(Registers.r[FCurrentCPUInstruction.RegB] + 3, TSystemState.TPanicCode.AccessViolationRead);{$ENDIF}
  Registers.R[FCurrentCPUInstruction.RegA] := FMemory.ReadDWord(Registers.r[FCurrentCPUInstruction.RegB]);
end;

procedure TCPU.DoSTB;
begin
  {$IF DEFINED(CHECK_MEM_BOUNDS)}CheckAddress(Registers.r[FCurrentCPUInstruction.RegA], TSystemState.TPanicCode.AccessViolationWrite);{$ENDIF}
  FMemory.WriteByte(Registers.r[FCurrentCPUInstruction.RegA], Registers.R[FCurrentCPUInstruction.RegB] and $FF);
end;

procedure TCPU.DoSTW;
begin
  {$IF DEFINED(CHECK_MEM_BOUNDS)}CheckAddress(Registers.r[FCurrentCPUInstruction.RegA] + 1, TSystemState.TPanicCode.AccessViolationWrite);{$ENDIF}
  FMemory.WriteWord(Registers.r[FCurrentCPUInstruction.RegA], Registers.R[FCurrentCPUInstruction.RegB] and $FFFF);
end;

procedure TCPU.DoST;
begin
  {$IF DEFINED(CHECK_MEM_BOUNDS)}CheckAddress(Registers.r[FCurrentCPUInstruction.RegA] + 3, TSystemState.TPanicCode.AccessViolationWrite);{$ENDIF}
  FMemory.WriteDWord(Registers.r[FCurrentCPUInstruction.RegA], Registers.R[FCurrentCPUInstruction.RegB]);
end;

procedure TCPU.DoLDIB;
begin
  DoLDB;
  Inc(Registers.r[FCurrentCPUInstruction.RegB]);
end;

procedure TCPU.DoLDIW;
begin
  DoLDW;
  Inc(Registers.r[FCurrentCPUInstruction.RegB], 2);
end;

procedure TCPU.DoLDI;
begin
  DoLD;
  Inc(Registers.r[FCurrentCPUInstruction.RegB], 4);
end;

procedure TCPU.DoSTIB;
begin
  DoSTB;
  Inc(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoSTIW;
begin
  DoSTW;
  Inc(Registers.r[FCurrentCPUInstruction.RegA], 2);
end;

procedure TCPU.DoSTI;
begin
  DoST;
  Inc(Registers.r[FCurrentCPUInstruction.RegA], 4);
end;

procedure TCPU.DoSTSB;
begin
  {$IF DEFINED(CHECK_MEM_BOUNDS)}
    CheckAddress(Registers.r[FCurrentCPUInstruction.RegA], TSystemState.TPanicCode.AccessViolationWrite);
    CheckAddress(Registers.r[FCurrentCPUInstruction.RegB], TSystemState.TPanicCode.AccessViolationRead);
  {$ENDIF}

  FMemory.WriteByte(Registers.r[FCurrentCPUInstruction.RegA], FMemory.ReadByte(Registers.r[FCurrentCPUInstruction.RegB]));

  Inc(Registers.r[FCurrentCPUInstruction.RegA]);
  Inc(Registers.r[FCurrentCPUInstruction.RegB]);
end;

procedure TCPU.DoSTSW;
begin
  {$IF DEFINED(CHECK_MEM_BOUNDS)}
    CheckAddress(Registers.r[FCurrentCPUInstruction.RegA] + 1, TSystemState.TPanicCode.AccessViolationWrite);
    CheckAddress(Registers.r[FCurrentCPUInstruction.RegB] + 1, TSystemState.TPanicCode.AccessViolationRead);
  {$ENDIF}

  FMemory.WriteWord(Registers.r[FCurrentCPUInstruction.RegA], FMemory.ReadWord(Registers.r[FCurrentCPUInstruction.RegB]));

  Inc(Registers.r[FCurrentCPUInstruction.RegA], 2);
  Inc(Registers.r[FCurrentCPUInstruction.RegB], 2);
end;

procedure TCPU.DoSTS;
begin
  {$IF DEFINED(CHECK_MEM_BOUNDS)}
    CheckAddress(Registers.r[FCurrentCPUInstruction.RegA] + 3, TSystemState.TPanicCode.AccessViolationWrite);
    CheckAddress(Registers.r[FCurrentCPUInstruction.RegB] + 3, TSystemState.TPanicCode.AccessViolationRead);
  {$ENDIF}

  FMemory.WriteDWord(Registers.r[FCurrentCPUInstruction.RegA], FMemory.ReadDWord(Registers.r[FCurrentCPUInstruction.RegB]));

  Inc(Registers.r[FCurrentCPUInstruction.RegA], 4);
  Inc(Registers.r[FCurrentCPUInstruction.RegB], 4);
end;

procedure TCPU.DoLDOB;
var
  TargetAddr: Cardinal;
begin
  TargetAddr := Registers.R[FCurrentCPUInstruction.RegB] + NextDWord;

  {$IF DEFINED(CHECK_MEM_BOUNDS)}
    CheckAddress(TargetAddr, TSystemState.TPanicCode.AccessViolationRead);
  {$ENDIF}

  Registers.R[FCurrentCPUInstruction.RegA] := FMemory.ReadByte(TargetAddr);
end;

procedure TCPU.DoLDOW;
var
  TargetAddr: Cardinal;
begin
  TargetAddr := Registers.R[FCurrentCPUInstruction.RegB] + NextDWord;

  {$IF DEFINED(CHECK_MEM_BOUNDS)}
    CheckAddress(TargetAddr + 1, TSystemState.TPanicCode.AccessViolationRead);
  {$ENDIF}

  Registers.R[FCurrentCPUInstruction.RegA] := FMemory.ReadWord(TargetAddr);
end;

procedure TCPU.DoLDO;
var
  TargetAddr: Cardinal;
begin
  TargetAddr := Registers.R[FCurrentCPUInstruction.RegB] + NextDWord;

  {$IF DEFINED(CHECK_MEM_BOUNDS)}
    CheckAddress(TargetAddr + 3, TSystemState.TPanicCode.AccessViolationRead);
  {$ENDIF}

  Registers.R[FCurrentCPUInstruction.RegA] := FMemory.ReadDWord(TargetAddr);
end;

procedure TCPU.DoSTOB;
var
  TargetAddr: Cardinal;
begin
  TargetAddr := Registers.R[FCurrentCPUInstruction.RegA] + NextDWord;

  {$IF DEFINED(CHECK_MEM_BOUNDS)}
    CheckAddress(TargetAddr, TSystemState.TPanicCode.AccessViolationWrite);
  {$ENDIF}

  FMemory.WriteByte(TargetAddr, Registers.R[FCurrentCPUInstruction.RegB] and $FF);
end;

procedure TCPU.DoSTOW;
var
  TargetAddr: Cardinal;
begin
  TargetAddr := Registers.R[FCurrentCPUInstruction.RegA] + NextDWord;

  {$IF DEFINED(CHECK_MEM_BOUNDS)}
    CheckAddress(TargetAddr + 1, TSystemState.TPanicCode.AccessViolationWrite);
  {$ENDIF}

  FMemory.WriteWord(TargetAddr, Registers.R[FCurrentCPUInstruction.RegB] and $FFFF);
end;

procedure TCPU.DoSTO;
var
  TargetAddr: Cardinal;
begin
  TargetAddr := Registers.R[FCurrentCPUInstruction.RegA] + NextDWord;

  {$IF DEFINED(CHECK_MEM_BOUNDS)}
    CheckAddress(TargetAddr + 3, TSystemState.TPanicCode.AccessViolationWrite);
  {$ENDIF}

  FMemory.WriteDWord(TargetAddr, Registers.R[FCurrentCPUInstruction.RegB]);
end;
{$ENDREGION}

{$REGION 'Jump'}
procedure TCPU.DoJNZ;
var
  TargetAddress: Cardinal;
begin
  TargetAddress := NextDWord;

  if not Registers.Flags.Zero then
  begin
    Registers.PC := TargetAddress;
    CheckPC;
  end;
end;

procedure TCPU.DoJE;
var
  TargetAddress: Cardinal;
begin
  TargetAddress := NextDWord;

  if Registers.Flags.Zero then
  begin
    Registers.PC := TargetAddress;
    CheckPC;
  end;
end;

procedure TCPU.DoJL;
var
  TargetAddress: Cardinal;
begin
  TargetAddress := NextDWord;

  if Registers.Flags.Negative <> Registers.Flags.Overflow then
  begin
    Registers.PC := TargetAddress;
    CheckPC;
  end;
end;

procedure TCPU.DoJLE;
var
  TargetAddress: Cardinal;
begin
  TargetAddress := NextDWord;

  if Registers.Flags.Zero or (Registers.Flags.Negative <> Registers.Flags.Overflow) then
  begin
    Registers.PC := TargetAddress;
    CheckPC;
  end;
end;

procedure TCPU.DoJG;
var
  TargetAddress: Cardinal;
begin
  TargetAddress := NextDWord;

  if not (Registers.Flags.Negative <> Registers.Flags.Overflow) and not Registers.Flags.Zero then
  begin
    Registers.PC := TargetAddress;
    CheckPC;
  end;
end;

procedure TCPU.DoJGE;
var
  TargetAddress: Cardinal;
begin
  TargetAddress := NextDWord;

  if Registers.Flags.Negative = Registers.Flags.Overflow then
  begin
    Registers.PC := TargetAddress;
    CheckPC;
  end;
end;

procedure TCPU.DoJB;
var
  TargetAddress: Cardinal;
begin
  TargetAddress := NextDWord;

  if Registers.Flags.Carry then
  begin
    Registers.PC := TargetAddress;
    CheckPC;
  end;
end;

procedure TCPU.DoJAE;
var
  TargetAddress: Cardinal;
begin
  TargetAddress := NextDWord;

  if not Registers.Flags.Carry then
  begin
    Registers.PC := TargetAddress;
    CheckPC;
  end;
end;

procedure TCPU.DoJMP;
begin
  Registers.PC := Registers.r[FCurrentCPUInstruction.RegB];
  CheckPC;
end;

procedure TCPU.DoLOOP;
var
  TargetAddress: Cardinal;
begin
  TargetAddress := NextDWord;

  Dec(Registers.r[FCurrentCPUInstruction.RegA]);

  if Registers.r[FCurrentCPUInstruction.RegA] > 0 then
  begin
    Registers.PC := TargetAddress;
    CheckPC;
  end;
end;
{$ENDREGION}

{$REGION 'Call/Return'}
procedure TCPU.DoCALL;
begin
  Push(Registers.PC);
  Registers.PC := Registers.r[FCurrentCPUInstruction.RegB];

  CheckPC;
end;

procedure TCPU.DoSYSCALL;
begin
  SysCall(Registers.r[FCurrentCPUInstruction.RegB]);
end;

procedure TCPU.DoINT;
begin
  Interrupt(Registers.r[FCurrentCPUInstruction.RegB] and $F);
end;

procedure TCPU.DoRET;
begin
  Registers.PC := Pop;
  CheckPC;
end;

procedure TCPU.DoIRET;
begin
  Registers.PC    := Pop;
  Registers.Flags := TRegisters.TFlags(Pop and $FF);
  CheckPC;
end;

procedure TCPU.DoENTER;
var
  ParamCount: Cardinal;
  FrameSize:  Cardinal;
begin
  Push(Registers.BP);
  Registers.BP := Registers.SP;

  ParamCount := FCurrentCPUInstruction.RegA;
  FrameSize  := NextDWord;

  for var i := 0 to Integer(ParamCount) - 1 do
    FMemory.WriteDWord(Registers.BP - Cardinal((i + 1) * 4), Registers.R[i]);

  Registers.SP := Registers.BP - FrameSize;
end;

procedure TCPU.DoZENTER;
var
  ParamCount: Cardinal;
  FrameSize:  Cardinal;
begin
  Push(Registers.BP);
  Registers.BP := Registers.SP;

  ParamCount := FCurrentCPUInstruction.RegA;
  FrameSize  := NextDWord;

  if FrameSize > 0 then
  begin
    Registers.SP := Registers.BP - FrameSize;
    FMemory.Fill(Registers.SP, FrameSize, 0);
  end;

  for var i := 0 to Integer(ParamCount) - 1 do
    FMemory.WriteDWord(Registers.BP - Cardinal((i + 1) * 4), Registers.R[i]);
end;

procedure TCPU.DoLEAVE;
begin
  Registers.SP := Registers.BP;
  Registers.BP := Pop;
end;
{$ENDREGION}

{$REGION 'Push/Pop'}
procedure TCPU.DoPUSH;
begin
  Push(Registers.R[FCurrentCPUInstruction.RegB]);
end;

procedure TCPU.DoPOP;
begin
  Registers.R[FCurrentCPUInstruction.RegA] := Pop;
end;

procedure TCPU.DoPUSHF;
begin
  Push(Registers.Flags);
end;

procedure TCPU.DoPOPF;
begin
  Registers.Flags := TRegisters.TFlags(Pop and $FF);
end;

procedure TCPU.DoPUSHR;
var
  Count: Cardinal;
begin
  Count := FCurrentCPUInstruction.RegA;

  if Count > 16 then
    Count := 16;

  for var i := Integer(Count) - 1 downto 0 do
    Push(Registers.R[i]);
end;

procedure TCPU.DoPOPR;
var
  Count: Cardinal;
begin
  Count := FCurrentCPUInstruction.RegA;

  if Count > 16 then
    Count := 16;

  for var i := 0 to Integer(Count) - 1 do
    Registers.R[i] := Pop;
end;
{$ENDREGION}

{$REGION 'Floating point'}
procedure TCPU.DoFADD;
var
  F1, F2: Single;
begin
  F1 := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegA]);
  F2 := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegB]);

  Registers.r[FCurrentCPUInstruction.RegA] := SingleToDWord(F1 + F2);

  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoFSUB;
var
  F1, F2: Single;
begin
  F1 := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegA]);
  F2 := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegB]);

  Registers.r[FCurrentCPUInstruction.RegA] := SingleToDWord(F1 - F2);

  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoFMUL;
var
  F1, F2: Single;
begin
  F1 := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegA]);
  F2 := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegB]);

  Registers.r[FCurrentCPUInstruction.RegA] := SingleToDWord(F1 * F2);

  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoFDIV;
var
  Right:  Cardinal;
  F1, F2: Single;
begin
  Right := Registers.r[FCurrentCPUInstruction.RegB];

  if (Right and $7FFFFFFF) = 0 then
  begin
    Registers.r[FCurrentCPUInstruction.RegA] := $7F800000;

    if Registers.Flags.DivZPanicEnabled then
      FPUError;

    Exit;
  end;

  F1 := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegA]);
  F2 := DWordToSingle(Right);

  Registers.r[FCurrentCPUInstruction.RegA] := SingleToDWord(F1 / F2);

  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoITOF;
var
  I: Integer;
  F: Single;
begin
  I := Integer(Registers.r[FCurrentCPUInstruction.RegB]);
  F := I;

  Registers.r[FCurrentCPUInstruction.RegA] := SingleToDWord(F);

  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoFTOI;
var
  F: Single;
  I: Integer;
begin
  F := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegB]);
  I := Trunc(F);

  Registers.r[FCurrentCPUInstruction.RegA] := Cardinal(I);

  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoFRND;
var
  F: Single;
  I: Integer;
begin
  F := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegB]);
  I := Round(F);

  Registers.r[FCurrentCPUInstruction.RegA] := Cardinal(I);

  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoFSIN;
var
  F: Single;
begin
  F := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegB]);
  Registers.r[FCurrentCPUInstruction.RegA] := SingleToDWord(Sin(F));
end;

procedure TCPU.DoFCOS;
var
  F: Single;
begin
  F := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegB]);
  Registers.r[FCurrentCPUInstruction.RegA] := SingleToDWord(Cos(F));
end;

procedure TCPU.DoFTAN;
var
  F: Single;
begin
  F := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegB]);
  Registers.r[FCurrentCPUInstruction.RegA] := SingleToDWord(Tangent(F));
end;

procedure TCPU.DoFATAN;
var
  F: Single;
begin
  F := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegB]);
  Registers.r[FCurrentCPUInstruction.RegA] := SingleToDWord(ArcTan(F));
end;

procedure TCPU.DoFLN;
var
  Right: Cardinal;
  F:     Single;
begin
  Right := Registers.r[FCurrentCPUInstruction.RegB];

  if ((Right and $7FFFFFFF) = 0) or ((Right and $80000000) <> 0) then
  begin
    Registers.r[FCurrentCPUInstruction.RegA] := $7FC00000;

    if Registers.Flags.DivZPanicEnabled then
      FPUError;

    Exit;
  end;

  F := DWordToSingle(Right);
  Registers.r[FCurrentCPUInstruction.RegA] := SingleToDWord(Ln(F));

  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoFEXP;
var
  F: Single;
begin
  F := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegB]);
  Registers.r[FCurrentCPUInstruction.RegA] := SingleToDWord(Exp(F));
end;

procedure TCPU.DoFSQRT;
var
  Right: Cardinal;
  F:     Single;
begin
  Right := Registers.r[FCurrentCPUInstruction.RegB];

  if ((Right and $80000000) <> 0) and ((Right and $7FFFFFFF) <> 0) then
  begin
    Registers.r[FCurrentCPUInstruction.RegA] := $7FC00000;

    if Registers.Flags.DivZPanicEnabled then
      FPUError;

    Exit;
  end;

  F := DWordToSingle(Right);
  Registers.r[FCurrentCPUInstruction.RegA] := SingleToDWord(Sqrt(F));

  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoFCE;
begin
  Registers.Flags.FPUException := False;
end;

procedure TCPU.DoFCMP;
var
  F1, F2: Single;
begin
  F1 := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegA]);
  F2 := DWordToSingle(Registers.r[FCurrentCPUInstruction.RegB]);

  Registers.Flags.Zero     := (F1 = F2);
  Registers.Flags.Negative := (F1 < F2);

  Registers.Flags.Overflow := False;
  Registers.Flags.Carry    := False;
end;
{$ENDREGION}

{$REGION 'Set condition'}
procedure TCPU.DoSETE;
begin
  if Registers.Flags.Zero then Registers.r[FCurrentCPUInstruction.RegA] := 1 else Registers.r[FCurrentCPUInstruction.RegA] := 0;
end;

procedure TCPU.DoSETNE;
begin
  if not Registers.Flags.Zero then Registers.r[FCurrentCPUInstruction.RegA] := 1 else Registers.r[FCurrentCPUInstruction.RegA] := 0;
end;

procedure TCPU.DoSETL;
begin
  if Registers.Flags.Negative <> Registers.Flags.Overflow then Registers.r[FCurrentCPUInstruction.RegA] := 1 else Registers.r[FCurrentCPUInstruction.RegA] := 0;
end;

procedure TCPU.DoSETLE;
begin
  if Registers.Flags.Zero or (Registers.Flags.Negative <> Registers.Flags.Overflow) then Registers.r[FCurrentCPUInstruction.RegA] := 1 else Registers.r[FCurrentCPUInstruction.RegA] := 0;
end;

procedure TCPU.DoSETG;
begin
  if not Registers.Flags.Zero and (Registers.Flags.Negative = Registers.Flags.Overflow) then Registers.r[FCurrentCPUInstruction.RegA] := 1 else Registers.r[FCurrentCPUInstruction.RegA] := 0;
end;

procedure TCPU.DoSETGE;
begin
  if Registers.Flags.Negative = Registers.Flags.Overflow then Registers.r[FCurrentCPUInstruction.RegA] := 1 else Registers.r[FCurrentCPUInstruction.RegA] := 0;
end;
{$ENDREGION}

{$REGION 'Bit set/clear/test'}
procedure TCPU.DoBSET;
begin
  Registers.r[FCurrentCPUInstruction.RegA] := Registers.r[FCurrentCPUInstruction.RegA] or Registers.r[FCurrentCPUInstruction.RegB];
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoBCLR;
begin
  Registers.r[FCurrentCPUInstruction.RegA] := Registers.r[FCurrentCPUInstruction.RegA] and not Registers.r[FCurrentCPUInstruction.RegB];
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA]);
end;

procedure TCPU.DoBTST;
begin
  Registers.Flags.UpdateZN(Registers.r[FCurrentCPUInstruction.RegA] and Registers.r[FCurrentCPUInstruction.RegB]);
end;

procedure TCPU.DoBSETF;
begin
  Registers.Flags := TRegisters.TFlags(Byte(Registers.Flags) or (Registers.r[FCurrentCPUInstruction.RegB] and $FF));
end;

procedure TCPU.DoBCLRF;
begin
  Registers.Flags := TRegisters.TFlags(Byte(Registers.Flags) and not (Registers.r[FCurrentCPUInstruction.RegB] and $FF));
end;

procedure TCPU.DoBTSTF;
begin
  Registers.Flags.UpdateZN(Byte(Registers.Flags) and (Registers.r[FCurrentCPUInstruction.RegB] and $FF));
end;
{$ENDREGION}

procedure TCPU.DoNOP;
begin
  {}
end;
{$ENDREGION}

end.
