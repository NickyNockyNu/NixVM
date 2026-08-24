{
  NixVM.Tools.Disasm.pas
    Binary Disassembler

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

unit NixVM.Tools.Disasm;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,

  NixVM.Core.Registers,
  NixVM.Core.Instructions,
  NixVM.Core.Memory,

  NixVM.Tools.IR;

type
  TDisassembler = class abstract
  private type
    {$REGION 'Symbol'}
    TSymbolKind = (CodeLabel, Subroutine, DataPointer);

    TSymbolInfo = record
      Name: TLabelString;
      Kind: TSymbolKind;
    end;
    {$ENDREGION}
  private
    class function TryReadPrintableString(AMemory: TCustomMemory; AAddr, AMaxAddr: Cardinal; out AString: AnsiString; out ATotalBytes: Cardinal): Boolean; static;
  public
    class function Disassemble(AMemory:      TCustomMemory; AStartAddress, ALength: Cardinal): TIRList; overload;
    class function Disassemble(const ABytes: TBytes;        AStartAddress: Cardinal = 0):      TIRList; overload;

    class function DisassembleToString(AMemory: TCustomMemory; AStartAddress, ALength: Cardinal): String;
  end;

implementation

{$REGION 'TDisassembler'}
class function TDisassembler.TryReadPrintableString(AMemory: TCustomMemory; AAddr, AMaxAddr: Cardinal; out AString: AnsiString; out ATotalBytes: Cardinal): Boolean;
var
  Curr:  Cardinal;
  B:     Byte;
  Chars: TList<AnsiChar>;
begin
  Result  := False;
  AString := '';

  ATotalBytes := 0;

  if AAddr >= AMaxAddr then
    Exit;

  Chars := TList<AnsiChar>.Create;

  try
    Curr := AAddr;

    while Curr < AMaxAddr do
    begin
      B := AMemory.ReadByte(Curr);
      Inc(Curr);

      if B = 0 then
      begin
        if Chars.Count > 0 then
        begin
          SetString(AString, PAnsiChar(@Chars.ToArray[0]), Chars.Count);

          ATotalBytes := (Curr - AAddr);

          Result := True;
        end;

        Break;
      end;

      if (B in [32..126, 9, 10, 13]) then
        Chars.Add(AnsiChar(B))
      else
        Break;
    end;
  finally
    Chars.Free;
  end;
end;

class function TDisassembler.Disassemble(AMemory: TCustomMemory; AStartAddress, ALength: Cardinal): TIRList;
var
  SymbolMap: TDictionary<Cardinal, TSymbolInfo>;
  CurrAddr:  Cardinal;
  EndAddr:   Cardinal;
  InCode:    Boolean;

  procedure AddSymbol(AAddr: Cardinal; AKind: TSymbolKind);
  var
    Info: TSymbolInfo;
  begin
    if (AAddr < AStartAddress) or (AAddr >= EndAddr) or SymbolMap.ContainsKey(AAddr) then
      Exit;

    Info.Kind := AKind;

    case AKind of
      TSymbolKind.Subroutine:  Info.Name := TLabelString('@sub_'  + IntToHex(AAddr, 8));
      TSymbolKind.CodeLabel:   Info.Name := TLabelString('@loc_'  + IntToHex(AAddr, 8));
      TSymbolKind.DataPointer: Info.Name := TLabelString('_data_' + IntToHex(AAddr, 8));
    end;

    SymbolMap.Add(AAddr, Info);
  end;

begin
  Result    := TIRList.Create;
  SymbolMap := TDictionary<Cardinal, TSymbolInfo>.Create;

  try
    EndAddr := AStartAddress + ALength;

    if EndAddr > AMemory.Size then
      EndAddr := AMemory.Size;

    CurrAddr := AStartAddress;

    while CurrAddr < EndAddr do
    begin
      var RawWord := AMemory.ReadWord(CurrAddr);
      var Instr: TCPUInstruction := RawWord;

      Inc(CurrAddr, 2);

      if Instr.RegB = TRegisters.ID.Imm then
      begin
        if CurrAddr + 4 <= EndAddr then
        begin
          var Target := AMemory.ReadDWord(CurrAddr);

          if Instr.OpCode = TCPUInstruction.TOpCode.call then
            AddSymbol(Target, TSymbolKind.Subroutine)
          else if Instr.OpCode = TCPUInstruction.TOpCode.jmp then
            AddSymbol(Target, TSymbolKind.CodeLabel)
          else if (Instr.OpCode = TCPUInstruction.TOpCode.mov) or (Instr.OpCode = TCPUInstruction.TOpCode.lea) then
          begin
            if (Target >= AStartAddress) and (Target < EndAddr) then
              AddSymbol(Target, TSymbolKind.DataPointer);
          end;

          Inc(CurrAddr, 4);
        end;
      end;

      if Instr.OpCode.Definition.Params in [TCPUInstruction.TParameters.Imm, TCPUInstruction.TParameters.R1Imm, TCPUInstruction.TParameters.R1R2Imm] then
      begin
        if CurrAddr + 4 <= EndAddr then
        begin
          var Target := AMemory.ReadDWord(CurrAddr);

          case Instr.OpCode of
            TCPUInstruction.TOpCode.jnz,
            TCPUInstruction.TOpCode.je,
            TCPUInstruction.TOpCode.jl,
            TCPUInstruction.TOpCode.jle,
            TCPUInstruction.TOpCode.jg,
            TCPUInstruction.TOpCode.jge,
            TCPUInstruction.TOpCode.jb,
            TCPUInstruction.TOpCode.jae,
            TCPUInstruction.TOpCode.loop:
              AddSymbol(Target, TSymbolKind.CodeLabel);

            TCPUInstruction.TOpCode.ldo,
            TCPUInstruction.TOpCode.ldob,
            TCPUInstruction.TOpCode.ldow:
              AddSymbol(Target, TSymbolKind.DataPointer);
          end;

          Inc(CurrAddr, 4);
        end;
      end;
    end;

    CurrAddr := AStartAddress;
    InCode   := True;

    while CurrAddr < EndAddr do
    begin
      var SymInfo: TSymbolInfo;
      var HasSymbol := SymbolMap.TryGetValue(CurrAddr, SymInfo);

      if HasSymbol then
      begin
        Result.AddBlankLine;
        Result.AddLabel(SymInfo.Name);

        if SymInfo.Kind = TSymbolKind.DataPointer then
          InCode := False
        else
          InCode := True;
      end;

      if not InCode then
      begin
        var StrVal: AnsiString;
        var StrBytes: Cardinal;

        if TryReadPrintableString(AMemory, CurrAddr, EndAddr, StrVal, StrBytes) then
        begin
          Result.AddDataString(StrVal, True);
          Inc(CurrAddr, StrBytes);
        end
        else
        begin
          var B := AMemory.ReadByte(CurrAddr);

          Result.AddDataBytes([B]);
          Inc(CurrAddr, 1);
        end;

        Continue;
      end;

      var InstrAddr := CurrAddr;
      var RawWord := AMemory.ReadWord(CurrAddr);
      var Instr: TCPUInstruction := RawWord;

      Inc(CurrAddr, 2);

      var Item := Default(TIRItem);

      Item.Kind    := TIRItem.TKind.Instruction;
      Item.Address := InstrAddr;
      Item.OpCode  := Instr.OpCode;
      Item.RegA    := Instr.RegA;
      Item.RegB    := Instr.RegB;

      if Instr.RegB = TRegisters.ID.Imm then
      begin
        if CurrAddr + 4 <= EndAddr then
        begin
          Item.Imm.Value := AMemory.ReadDWord(CurrAddr);

          var TargetSym: TSymbolInfo;

          if SymbolMap.TryGetValue(Item.Imm.Value, TargetSym) then
            Item.Imm.&Label := TargetSym.Name;

          Inc(CurrAddr, 4);
        end;
      end;

      if Instr.OpCode.Definition.Params in [TCPUInstruction.TParameters.Imm, TCPUInstruction.TParameters.R1Imm, TCPUInstruction.TParameters.R1R2Imm] then
      begin
        if CurrAddr + 4 <= EndAddr then
        begin
          Item.Offset.Value := AMemory.ReadDWord(CurrAddr);

          var TargetSym: TSymbolInfo;

          if SymbolMap.TryGetValue(Item.Offset.Value, TargetSym) then
            Item.Offset.&Label := TargetSym.Name;

          Inc(CurrAddr, 4);
        end;
      end;

      Result.Add(Item);

      if (Instr.OpCode = TCPUInstruction.TOpCode.ret)  or
         (Instr.OpCode = TCPUInstruction.TOpCode.iret) or
         (Instr.OpCode = TCPUInstruction.TOpCode.halt) then
      begin
        InCode := False;
      end;
    end;

  finally
    SymbolMap.Free;
  end;
end;

class function TDisassembler.Disassemble(const ABytes: TBytes; AStartAddress: Cardinal): TIRList;
var
  Mem: TCustomMemory;
begin
  if Length(ABytes) = 0 then
    Exit(TIRList.Create);

  Mem := TCustomMemory.Create(Length(ABytes));
  try
    Mem.WriteData(0, ABytes[0], Length(ABytes));
    Result := Disassemble(Mem, 0, Length(ABytes));

    if AStartAddress > 0 then
      Result.ComputeAddresses(AStartAddress);
  finally
    Mem.Free;
  end;
end;

class function TDisassembler.DisassembleToString(AMemory: TCustomMemory; AStartAddress, ALength: Cardinal): String;
var
  List: TIRList;
begin
  List := Disassemble(AMemory, AStartAddress, ALength);
  try
    Result := List.ToString;
  finally
    List.Free;
  end;
end;
{$ENDREGION}

end.
