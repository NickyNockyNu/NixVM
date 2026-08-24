{
  NixVM.Registers.pas
    NixVM - CPU registers
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

unit NixVM.Registers;

{$INCLUDE 'NixVM.Options.inc'}

interface

type
  PRegisters = ^TRegisters;
  TRegisters = packed record
  type
    {$REGION 'ID'}
    ID = 0..15;

    IDHelper = record helper for ID
    const
      Ret = 0;

      Param1 = 0;
      Param2 = 1;
      Param3 = 2;
      Param4 = 3;

      Imm = 13;

      BP = 14;
      SP = 15;
    public
      function ToString: String;
      class function FromString(const AString: String; out AValid: Boolean): ID; static;
    end;
    {$ENDREGION}

    {$REGION 'Flags'}
    TFlags = type Byte;

    TFlagsHelper = record helper for TFlags
    const
      ZeroMask              = 1 shl 0;
      NegativeMask          = 1 shl 1;
      CarryMask             = 1 shl 2;
      OverflowMask          = 1 shl 3;
      FPUExceptionMask      = 1 shl 4;
      InterruptsEnabledMask = 1 shl 5;
      DivZPanicEnabledMask  = 1 shl 6;

      Default = InterruptsEnabledMask or DivZPanicEnabledMask;
    private
      function  GetFlag(AMask: Integer):         Boolean;  inline;
      procedure SetFlag(AMask: Integer; AEnable: Boolean); inline;
    public
      procedure UpdateZN(ATest: Cardinal); inline;

      function ToString: String;

      property Zero:     Boolean index ZeroMask     read GetFlag write SetFlag;
      property Negative: Boolean index NegativeMask read GetFlag write SetFlag;
      property Carry:    Boolean index CarryMask    read GetFlag write SetFlag;
      property Overflow: Boolean index OverflowMask read GetFlag write SetFlag;

      property FPUException:  Boolean index FPUExceptionMask  read GetFlag write SetFlag;

      property InterruptsEnabled: Boolean index InterruptsEnabledMask read GetFlag write SetFlag;
      property DivZPanicEnabled:  Boolean index DivZPanicEnabledMask  read GetFlag write SetFlag;
    end;
    {$ENDREGION}
  public
    class function  Encode(                  RegA, RegB: ID): Byte; inline; static;
    class procedure Decode(AValue: Byte; out RegA, RegB: ID);       inline; static;
  public
    PC:      Cardinal;
    Flags:   TFlags;
    Padding: packed array[0..2] of Byte;
    case Integer of
      0: (R: array[ID] of Cardinal);
      1: (R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14, R15: Cardinal);
      2: (P1, P2, P3, P4, _4, _5, _6, _7, _8, _9, _10, _11, _12, Imm, BP,  SP:  Cardinal);
      3: (Ret: Cardinal);
  end;

implementation

uses
  NixVM.Strings;

{$REGION 'ID'}
function TRegisters.IDHelper.ToString: String;
begin
  case Self of
    Imm: Result := 'imm';
    BP:  Result := 'bp';
    SP:  Result := 'sp';
  else
    Result := 'r' + IntToStr(Self);
  end;
end;

class function TRegisters.IDHelper.FromString(const AString: String; out AValid: Boolean): ID;
var
  U: String;
begin
  U := Lowercase(TrimWhitespace(AString));

  AValid := True;

       if (U = 'r0' ) or (U = 'p1') or (U = 'result') then Result := 0
  else if (U = 'r1' ) or (U = 'p2')                   then Result := 1
  else if (U = 'r2' ) or (U = 'p3')                   then Result := 2
  else if (U = 'r3' ) or (U = 'p4')                   then Result := 3
  else if (U = 'r4' )                                 then Result := 4
  else if (U = 'r5' )                                 then Result := 5
  else if (U = 'r6' )                                 then Result := 6
  else if (U = 'r7' )                                 then Result := 7
  else if (U = 'r8' )                                 then Result := 8
  else if (U = 'r9' )                                 then Result := 9
  else if (U = 'r10')                                 then Result := 10
  else if (U = 'r11')                                 then Result := 11
  else if (U = 'r12')                                 then Result := 12
  else if (U = 'r13') or (U = 'imm')                  then Result := 13
  else if (U = 'r14') or (U = 'bp')                   then Result := 14
  else if (U = 'r15') or (U = 'sp')                   then Result := 15

  else
  begin
    Result := 0;
    AValid := False;
  end;
end;
{$ENDREGION}

{$REGION 'Flags'}
function TRegisters.TFLagsHelper.GetFlag(AMask: Integer): Boolean;
begin
  Result := (Self and AMask) <> 0;
end;

procedure TRegisters.TFLagsHelper.SetFlag(AMask: Integer; AEnable: Boolean);
begin
  if AEnable then
    Self := Self or AMask
  else
    Self := Self and not AMask;
end;

procedure TRegisters.TFLagsHelper.UpdateZN(ATest: Cardinal);
var
  F: Byte;
begin
  F := Byte(Self) and not (ZeroMask or NegativeMask);

  if ATest = 0 then
    F := F or ZeroMask;

  if Integer(ATest) < 0 then
    F := F or NegativeMask;

  Self := TFlags(F);
end;

function TRegisters.TFlagsHelper.ToString: String;
begin
  Result := '--------';

  if Zero              then Result[8] := 'Z';
  if Negative          then Result[7] := 'N';
  if Carry             then Result[6] := 'C';
  if Overflow          then Result[5] := 'O';
  if FPUException      then Result[4] := 'F';
  if InterruptsEnabled then Result[3] := 'I';
  if DivZPanicEnabled  then Result[2] := 'D';
end;

class function TRegisters.Encode(RegA, RegB: ID): Byte;
begin
  Result := ((RegA and $0F) shl 4) or (RegB and $0F);
end;

class procedure TRegisters.Decode(AValue: Byte; out RegA, RegB: ID);
begin
  RegA := (AValue shr 4) and $0F;
  RegB :=  AValue        and $0F;
end;
{$ENDREGION}

end.
