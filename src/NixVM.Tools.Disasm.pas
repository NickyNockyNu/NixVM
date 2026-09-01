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
  System.IOUtils,

  NixVM.Core.Registers,
  NixVM.Core.Instructions,
  NixVM.Core.Memory,
  NixVM.Core.ROM,
  NixVM.Core.System,

  NixVM.Tools.IR;

type
  {$REGION 'Disassembler'}
  TDisassembler = class
  private type
    {$REGION 'Symbol'}
    TSymbolKind = (CodeLabel, Subroutine, DataPointer);

    TSymbolInfo = record
      Name: TLabelString;
      Kind: TSymbolKind;
    end;
    {$ENDREGION}
  private
    FIR:             TIRList;
    FErrors:         TStrings;
    FEmitDirectives: Boolean;
    FIsRawBinary:    Boolean;

    class function TryReadPrintableString(AMemory: TCustomMemory; AAddr, AMaxAddr: Cardinal; out ABytes: TBytes): Boolean; static;
  public
    ROMHeader: TROMHeader;

    constructor Create;
    destructor  Destroy; override;

    function Disassemble(      AMemory: TCustomMemory; AStartAddress, ALength: Cardinal): Boolean; overload;
    function Disassemble(const ABytes:  TBytes;        AStartAddress: Cardinal = 0):      Boolean; overload;
    function Disassemble(      AStream: TStream):                                         Boolean; overload;

    function DisassembleRaw(const ABytes:  TBytes;  ABaseAddress: Cardinal = $4E0): Boolean; overload;
    function DisassembleRaw(      AStream: TStream; ABaseAddress: Cardinal = $4E0): Boolean; overload;

    function DisassembleFile   (const AFileName: String):                                Boolean;
    function DisassembleRawFile(const AFileName: String; ABaseAddress: Cardinal = $4E0): Boolean;

    function SaveToFile(const AFileName: String): Boolean;

    function ToString: String; override;

    class function DisassembleMemory(AMemory: TCustomMemory; AStartAddress, ALength: Cardinal; AErrors: TStrings = nil): TIRList; static;
    class function DisassembleBytes(const ABytes: TBytes; AStartAddress: Cardinal = 0): TIRList; static;

    property IR:             TIRList    read FIR;
    property Errors:         TStrings   read FErrors;
    property EmitDirectives: Boolean    read FEmitDirectives write FEmitDirectives;
    property IsRawBinary:    Boolean    read FIsRawBinary;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Core.Strings;

{$REGION 'Disassembler'}
constructor TDisassembler.Create;
begin
  inherited Create;

  FIR             := TIRList.Create;
  FErrors         := TStringList.Create;
  FEmitDirectives := True;
  FIsRawBinary    := False;

  ROMHeader.Reset;
end;

destructor TDisassembler.Destroy;
begin
  FIR.Free;
  FErrors.Free;

  inherited;
end;

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
          if PrintableCount >= 1 then
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

class function TDisassembler.DisassembleMemory(AMemory: TCustomMemory; AStartAddress, ALength: Cardinal; AErrors: TStrings): TIRList;
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

      if Instr.OpCode.Definition.Params in [TCPUInstruction.TParameters.Imm,
                                           TCPUInstruction.TParameters.R1Imm,
                                           TCPUInstruction.TParameters.R1R2Imm,
                                           TCPUInstruction.TParameters.RnImm] then
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
              if Instr.RegB <> TRegisters.ID.BP then
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
      var RawWord   := AMemory.ReadWord(CurrAddr);
      var Instr: TCPUInstruction := RawWord;

      Inc(CurrAddr, 2);

      var Item := Default(TIRItem);

      Item.Kind    := TIRItem.TKind.Instruction;
      Item.Address := InstrAddr;
      Item.OpCode  := Instr.OpCode;
      Item.RegA    := Instr.RegA;
      Item.RegB    := Instr.RegB;

      if Instr.RegB = TRegisters.ID.Imm then
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

      if Instr.OpCode.Definition.Params in [TCPUInstruction.TParameters.Imm,
                                           TCPUInstruction.TParameters.R1Imm,
                                           TCPUInstruction.TParameters.R1R2Imm,
                                           TCPUInstruction.TParameters.RnImm] then
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

      if (Instr.OpCode = TCPUInstruction.TOpCode.syscall) and (Instr.RegB = TRegisters.ID.Imm) then
        Item.Comment := TSysCalls.ID(Item.Imm.Value).ToString

      else if (Instr.OpCode = TCPUInstruction.TOpCode.int) and (Instr.RegB = TRegisters.ID.Imm) then
        Item.Comment := TInterrupts.ID(Item.Imm.Value and $F).ToString;

      Result.Add(Item);

      if Instr.OpCode in [TCPUInstruction.TOpCode.ret, TCPUInstruction.TOpCode.iret, TCPUInstruction.TOpCode.halt] then
        InCode := False;
    end;
  finally
    SymbolMap.Free;
  end;
end;

class function TDisassembler.DisassembleBytes(const ABytes: TBytes; AStartAddress: Cardinal): TIRList;
var
  Errors: TStrings;
  Mem:    TCustomMemory;
  Total:  Cardinal;
begin
  if Length(ABytes) = 0 then
    Exit(TIRList.Create);

  Errors := nil;
  Total  := AStartAddress + Cardinal(Length(ABytes));
  Mem    := TCustomMemory.Create(Total);

  try
    Mem.WriteData(AStartAddress, ABytes[0], Length(ABytes));
    Result := DisassembleMemory(Mem, AStartAddress, Length(ABytes), Errors);
  finally
    Mem.Free;
  end;
end;

function TDisassembler.Disassemble(AMemory: TCustomMemory; AStartAddress, ALength: Cardinal): Boolean;
begin
  if Assigned(FIR) then
    FIR.Free;

  FErrors.Clear;

  FIR := DisassembleMemory(AMemory, AStartAddress, ALength, FErrors);
  Result := FErrors.Count = 0;
end;

function TDisassembler.Disassemble(const ABytes: TBytes; AStartAddress: Cardinal): Boolean;
begin
  if Assigned(FIR) then
    FIR.Free;

  FErrors.Clear;

  FIR := DisassembleBytes(ABytes, AStartAddress);
  Result := FErrors.Count = 0;
end;

function TDisassembler.Disassemble(AStream: TStream): Boolean;
var
  Header:   TROMHeader;
  Bytes:    TBytes;
  UserSize: Cardinal;
begin
  FErrors.Clear;

  if AStream.Size < SizeOf(TROMHeader) then
  begin
    FErrors.Add('Stream is too small to be a valid ROM');
    Exit(False);
  end;

  AStream.Position := 0;
  AStream.ReadBuffer(Header, SizeOf(TROMHeader));

  if not Header.IsValid then
  begin
    FErrors.Add('Invalid ROM signature');
    Exit(False);
  end;

  ROMHeader    := Header;
  FIsRawBinary := False;

  UserSize := Header.UserSize;

  if UserSize = 0 then
    UserSize := AStream.Size - SizeOf(TROMHeader);

  SetLength(Bytes, UserSize);

  if UserSize > 0 then
    AStream.ReadBuffer(Bytes[0], UserSize);

  Result := Disassemble(Bytes, Header.UserAddress);
end;

function TDisassembler.DisassembleRaw(const ABytes: TBytes; ABaseAddress: Cardinal): Boolean;
begin
  FIsRawBinary := True;

  ROMHeader.Reset;
  ROMHeader.UserAddress := ABaseAddress;
  ROMHeader.UserSize    := Length(ABytes);

  Result := Disassemble(ABytes, ABaseAddress);
end;

function TDisassembler.DisassembleRaw(AStream: TStream; ABaseAddress: Cardinal): Boolean;
var
  Bytes: TBytes;
begin
  FErrors.Clear;

  FIsRawBinary := True;

  ROMHeader.Reset;
  ROMHeader.UserAddress := ABaseAddress;
  ROMHeader.UserSize    := AStream.Size;

  SetLength(Bytes, AStream.Size);

  if AStream.Size > 0 then
  begin
    AStream.Position := 0;
    AStream.ReadBuffer(Bytes[0], AStream.Size);
  end;

  Result := Disassemble(Bytes, ABaseAddress);
end;

function TDisassembler.DisassembleRawFile(const AFileName: String; ABaseAddress: Cardinal): Boolean;
var
  FS: TFileStream;
begin
  FErrors.Clear;

  if not FileExists(AFileName) then
  begin
    FErrors.Add(Format('File not found: "%s"', [AFileName]));
    Exit(False);
  end;

  try
    FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);

    try
      Result := DisassembleRaw(FS, ABaseAddress);
    finally
      FS.Free;
    end;
  except
    on E: Exception do
    begin
      FErrors.Add(Format('Error reading file "%s": %s', [AFileName, E.Message]));
      Result := False;
    end;
  end;
end;

function TDisassembler.DisassembleFile(const AFileName: String): Boolean;
var
  FS:       TFileStream;
  MagicSig: TROMHeader.TSignature;
begin
  FErrors.Clear;

  if not FileExists(AFileName) then
  begin
    FErrors.Add(Format('File not found: "%s"', [AFileName]));
    Exit(False);
  end;

  try
    FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);

    try
      if FS.Size < SizeOf(TROMHeader) then
      begin
        FErrors.Add('To small to be an nvm file');
        Exit(False);
      end;

      FS.Position := 0;
      FS.ReadBuffer(MagicSig[0], SizeOf(MagicSig));
      FS.Position := 0;

      if MagicSig <> TROMHeader.Magic then
      begin
        FErrors.Add('Not a valid nvm file');
        Exit(False);
      end;

      Exit(Disassemble(FS));
    finally
      FS.Free;
    end;
  except
    on E: Exception do
    begin
      FErrors.Add(Format('Error reading file "%s": %s', [AFileName, E.Message]));
      Result := False;
    end;
  end;
end;

function TDisassembler.SaveToFile(const AFileName: String): Boolean;
begin
  Result := False;
  FErrors.Clear;

  try
    TFile.WriteAllText(AFileName, ToString);
    Result := True;
  except
    on E: Exception do
      FErrors.Add(Format('Failed to save assembly to "%s": %s', [AFileName, E.Message]));
  end;
end;

function TDisassembler.ToString: String;
var
  SB: TStringBuilder;
begin
  if not Assigned(FIR) then
    Exit('');

  SB := TStringBuilder.Create;
  try
    if FEmitDirectives then
    begin
      if not FIsRawBinary then
      begin
        if Length(ROMHeader.Harness.Name) > 0 then
          SB.AppendLine(Format('.target "%s", %d, %d', [ROMHeader.Harness.Name, ROMHeader.Harness.Major, ROMHeader.Harness.Minor]));

        if Length(ROMHeader.ROM.Name) > 0 then
          SB.AppendLine(Format('.name   "%s"', [ROMHeader.ROM.Name]));

        SB.AppendLine(Format('.version %d, %d', [ROMHeader.ROM.Major, ROMHeader.ROM.Minor]));
      end;

      SB.AppendLine(Format('.base   $%x', [ROMHeader.UserAddress]));

      if not FIsRawBinary then
      begin
        SB.AppendLine(Format('.heap   %d', [ROMHeader.HeapSize]));
        SB.AppendLine(Format('.stack  %d', [ROMHeader.StackSize]));
      end;

      SB.AppendLine;
    end;

    SB.Append(FIR.ToString);

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;
{$ENDREGION}

end.
