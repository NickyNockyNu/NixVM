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
  {$REGION 'Disassembler'}
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
    class function TryReadPrintableString(AMemory: TCustomMemory; AAddr, AMaxAddr: Cardinal; out ABytes: TBytes): Boolean;
  public
    class function Disassemble(AMemory:      TCustomMemory; AStartAddress, ALength: Cardinal): TIRList; overload;
    class function Disassemble(const ABytes: TBytes;        AStartAddress: Cardinal = 0):      TIRList; overload;

    class function DisassembleToString(AMemory: TCustomMemory; AStartAddress, ALength: Cardinal): String;
  end;
  {$ENDREGION}

implementation

{$REGION 'Disassembler'}
class function TDisassembler.TryReadPrintableString(AMemory: TCustomMemory; AAddr, AMaxAddr: Cardinal; out ABytes: TBytes): Boolean;
var
  Curr:           Cardinal;
  B:              Byte;
  Buffer:         TList<Byte>;
  PrintableCount: Integer;
begin
  Result         := False;
  ABytes         := nil;
  PrintableCount := 0;

  if AAddr >= AMaxAddr then
    Exit;

  Buffer := TList<Byte>.Create;
  try
    Curr := AAddr;

    while Curr < AMaxAddr do
    begin
      B := AMemory.ReadByte(Curr);
      Inc(Curr);

      if B in [32..126] then
        Inc(PrintableCount);

      if (B in [32..126, 0, 8, 9, 10, 13]) then
      begin
        Buffer.Add(B);

        if B = 0 then
        begin
          if PrintableCount > 0 then
          begin
            ABytes := Buffer.ToArray;
            Result := True;
          end;

          Break;
        end;
      end
      else
        Break;
    end;
  finally
    Buffer.Free;
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
      TSymbolKind.Subroutine:  Info.Name := TLabelString('sub_'  + IntToHex(AAddr, 8));
      TSymbolKind.CodeLabel:   Info.Name := TLabelString('@loc_' + IntToHex(AAddr, 8));
      TSymbolKind.DataPointer: Info.Name := TLabelString('data_' + IntToHex(AAddr, 8));
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
          else if (Target >= AStartAddress) and (Target < EndAddr) then
              AddSymbol(Target, TSymbolKind.DataPointer);

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
        var ZeroCount: Cardinal := 0;
        var ScanAddr:  Cardinal := CurrAddr;

        while (ScanAddr < EndAddr) and (AMemory.ReadByte(ScanAddr) = 0) do
        begin
          if (ZeroCount > 0) and SymbolMap.ContainsKey(ScanAddr) then
            Break;

          Inc(ZeroCount);
          Inc(ScanAddr);
        end;

        if ZeroCount >= 8 then
        begin
          Result.AddDataReserved(ZeroCount);
          Inc(CurrAddr, ZeroCount);

          Continue;
        end;

        var StrBytes: TBytes;

        if TryReadPrintableString(AMemory, CurrAddr, EndAddr, StrBytes) then
        begin
          Result.AddDataString(StrBytes);
          Inc(CurrAddr, Length(StrBytes));

          Continue;
        end;

        var RawBytes: TList<Byte> := TList<Byte>.Create;

        try
          while (CurrAddr < EndAddr) and (RawBytes.Count < 16) do
          begin
            if (RawBytes.Count > 0) and SymbolMap.ContainsKey(CurrAddr) then
              Break;

            RawBytes.Add(AMemory.ReadByte(CurrAddr));
            Inc(CurrAddr);
          end;

          if RawBytes.Count > 0 then
            Result.AddDataBytes(RawBytes.ToArray);
        finally
          RawBytes.Free;
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
          begin
            Item.Imm.&Label := TargetSym.Name;
            Item.Imm.Value  := 0;
          end;

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
          begin
            Item.Offset.&Label := TargetSym.Name;
            Item.Offset.Value  := 0;
          end;

          Inc(CurrAddr, 4);
        end;
      end;

      Result.Add(Item);

      if (Instr.OpCode = TCPUInstruction.TOpCode.ret)  or (Instr.OpCode = TCPUInstruction.TOpCode.iret) or (Instr.OpCode = TCPUInstruction.TOpCode.halt) then
        InCode := False;
    end;
  finally
    SymbolMap.Free;
  end;
end;

class function TDisassembler.Disassemble(const ABytes: TBytes; AStartAddress: Cardinal): TIRList;
var
  Mem:          TCustomMemory;
  TotalMemSize: Cardinal;
begin
  if Length(ABytes) = 0 then
    Exit(TIRList.Create);

  TotalMemSize := AStartAddress + Cardinal(Length(ABytes));

  Mem := TCustomMemory.Create(TotalMemSize);

  try
    Mem.WriteData(AStartAddress, ABytes[0], Length(ABytes));

    Result := Disassemble(Mem, AStartAddress, Length(ABytes));
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
