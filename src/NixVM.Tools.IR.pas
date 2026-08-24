{
  NixVM.Tools.IR.pas
    Intermediate Representation (IR) builder, label resolver, and emitter

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

unit NixVM.Tools.IR;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,

  NixVM.Core.Registers,
  NixVM.Core.Instructions,
  NixVM.Core.Memory;

type
  TLabelString = String[31];

  {$REGION 'IRItem'}
  PIRItem = ^TIRItem;
  TIRItem = record
  type
    {$REGION 'Kind'}
    TKind = (
      None,
      Instruction,
      &Label,
      DataBytes,
      DataWords,
      DataDWords,
      DataString
    );
    {$ENDREGION}

    TValue = record
      Value:  Cardinal;
      &Label: TLabelString;
    end;
  public
    function ToString: String;

    function Size: Cardinal;
  public
    Address:    Cardinal;
    Comment:    String;
    SourceLine: Integer;

    case Kind: TKind of
      TKind.Instruction: (
        OpCode: TCPUInstruction.TOpCode;
        RegA:   TRegisters.ID;
        RegB:   TRegisters.ID;

        Imm:    TValue;
        Offset: TValue;
      );

      TKind.&Label: (
        Name: TLabelString;
      );

      TKind.DataBytes,
      TKind.DataWords,
      TKind.DataDWords,
      TKind.DataString: (
        DataPtr:  Pointer;
        DataSize: Cardinal;
      );
  end;
  {$ENDREGION}

  {$REGION 'TIRList'}
  TIRList = class(TList<TIRItem>)
  private
    FDataPool: TList<TBytes>;

    function StoreData(const AData: Pointer; ASize: Cardinal): Pointer; overload;
    function StoreData(const ABytes: TBytes): Pointer; overload;
  public
    constructor Create;
    destructor  Destroy; override;

    procedure Clear;

    function AddBlankLine: Integer;

    function AddComment(const AComment: String): Integer;

    function AddLabel(const AName: TLabelString): Integer;

    function AddInstr(AOpCode: TCPUInstruction.TOpCode): Integer;

    function AddInstrR1(AOpCode: TCPUInstruction.TOpCode; ARegA: TRegisters.ID): Integer;

    function AddInstrR1R2(AOpCode: TCPUInstruction.TOpCode; ARegA, ARegB: TRegisters.ID): Integer;

    function AddInstrR1Imm(AOpCode: TCPUInstruction.TOpCode; ARegA: TRegisters.ID;       AImmVal:   Cardinal):     Integer; overload;
    function AddInstrR1Imm(AOpCode: TCPUInstruction.TOpCode; ARegA: TRegisters.ID; const AImmLabel: TLabelString): Integer; overload;

    function AddInstrImm(AOpCode: TCPUInstruction.TOpCode;       AImmVal:   Cardinal):     Integer; overload;
    function AddInstrImm(AOpCode: TCPUInstruction.TOpCode; const AImmLabel: TLabelString): Integer; overload;

    function AddInstrRImm(AOpCode: TCPUInstruction.TOpCode;       ARegB:     TRegisters.ID): Integer; overload;
    function AddInstrRImm(AOpCode: TCPUInstruction.TOpCode;       AImmVal:   Cardinal):      Integer; overload;
    function AddInstrRImm(AOpCode: TCPUInstruction.TOpCode; const AImmLabel: TLabelString):  Integer; overload;

    function AddInstrR1R2Imm(AOpCode: TCPUInstruction.TOpCode; ARegA, ARegB: TRegisters.ID;       AOffsetVal:   Cardinal):     Integer; overload;
    function AddInstrR1R2Imm(AOpCode: TCPUInstruction.TOpCode; ARegA, ARegB: TRegisters.ID; const AOffsetLabel: TLabelString): Integer; overload;

    function AddDataBytes (const ABytes:  array of Byte):     Integer;
    function AddDataWords (const AWords:  array of Word):     Integer;
    function AddDataDWords(const ADWords: array of Cardinal): Integer;

    function AddDataString(const AString: AnsiString; ANullTerminated: Boolean = True): Integer;

    function ComputeAddresses(AStartAddress: Cardinal = 0):                          Cardinal;
    function ResolveLabels   (AStartAddress: Cardinal = 0; AErrors: TStrings = nil): Boolean;

    function Emit(AMemory: TCustomMemory; AAddress: Cardinal): Cardinal; overload;
    function Emit(AStream: TStream):                           Cardinal; overload;

    function EmitToBytes: TBytes;

    function ToString: String; override;
  end;
  {$ENDREGION}

implementation

{$REGION 'IRItem'}
function TIRItem.ToString: String;
var
  Mnemonic: String;

  function FormatValue(const AVal: TValue; AHex: Boolean = False): String;
  begin
    if Length(AVal.&Label) > 0 then
      Result := String(AVal.&Label)
    else if AHex then
      Result := '$' + IntToHex(AVal.Value, 0)
    else
      Result := IntToStr(Integer(AVal.Value));
  end;
begin
  case Kind of
    TKind.None: ;

    TKind.&Label:
      Result := String(Name) + ':';

    TKind.Instruction:
    begin
      Mnemonic := OpCode.ToString;

      case OpCode.Definition.Params of
        TCPUInstruction.TParameters.None:
          Result := Mnemonic;

        TCPUInstruction.TParameters.R1:
          Result := Mnemonic + #9 + RegA.ToString;

        TCPUInstruction.TParameters.Imm:
          Result := Mnemonic + #9 + FormatValue(Offset, True);

        TCPUInstruction.TParameters.R1Imm:
          Result := Mnemonic + #9 + RegA.ToString + ', ' + FormatValue(Offset, True);

        TCPUInstruction.TParameters.R1R2:
        begin
          if RegB = TRegisters.ID.Imm then
            Result := Mnemonic + #9 + RegA.ToString + ', ' + FormatValue(Imm)
          else
            Result := Mnemonic + #9 + RegA.ToString + ', ' + RegB.ToString;
        end;

        TCPUInstruction.TParameters.RImm:
        begin
          if RegB = TRegisters.ID.Imm then
            Result := Mnemonic + #9 + FormatValue(Imm, True)
          else
            Result := Mnemonic + #9 + RegB.ToString;
        end;

        TCPUInstruction.TParameters.R1R2Imm:
        begin
          if RegB = TRegisters.ID.Imm then
            Result := Mnemonic + #9 + RegA.ToString + ', ' + FormatValue(Imm) + ', ' + FormatValue(Offset)
          else
            Result := Mnemonic + #9 + RegA.ToString + ', ' + RegB.ToString + ', ' + FormatValue(Offset);
        end;
      else
        Result := Mnemonic;
      end;
    end;

    TKind.DataBytes:
    begin
      Result := 'db ';

      var P := PByte(DataPtr);

      for var i := 0 to DataSize - 1 do
      begin
        if i > 0 then
          Result := Result + ', ';

        Result := Result + '$' + IntToHex(P^, 2);

        Inc(P);
      end;
    end;

    TKind.DataWords:
    begin
      Result := 'dw ';

      var P := PWord(DataPtr);

      for var i := 0 to (DataSize div 2) - 1 do
      begin
        if i > 0 then
          Result := Result + ', ';

        Result := Result + '$' + IntToHex(P^, 4);

        Inc(P);
      end;
    end;

    TKind.DataDWords:
    begin
      Result := 'dd ';

      var P := PCardinal(DataPtr);

      for var i := 0 to (DataSize div 4) - 1 do
      begin
        if i > 0 then
          Result := Result + ', ';

        Result := Result + '$' + IntToHex(P^, 8);

        Inc(P);
      end;
    end;

    TKind.DataString:
    begin
      // TODO: Split string special characters. eg `Hello'#9'World'#13#10 -> "Hello", 9, "World", 13, 10

      var S: AnsiString;
      SetString(S, PAnsiChar(DataPtr), DataSize);

      if (Length(S) > 0) and (S[Length(S)] = #0) then
        SetLength(S, Length(S) - 1);

      Result := 'ds "' + String(S) + '"';
    end;
  else
    Result := '';
  end;

  if Length(Comment) > 0 then
    Result := Result + ' ; ' + Comment;
end;

function TIRItem.Size: Cardinal;
begin
  case Kind of
    TKind.Instruction:
    begin
      Result := 2;

      if RegB = TRegisters.ID.Imm then
        Inc(Result, 4);

      if OpCode.Definition.Params in [TCPUInstruction.TParameters.Imm, TCPUInstruction.TParameters.R1Imm, TCPUInstruction.TParameters.R1R2Imm] then
        Inc(Result, 4);
    end;

    TKind.&Label:
      Result := 0;

    TKind.DataBytes,
    TKind.DataWords,
    TKind.DataDWords,
    TKind.DataString:
      Result := DataSize;
  else
    Result := 0;
  end;
end;
{$ENDREGION}

{$REGION 'TIRList'}
constructor TIRList.Create;
begin
  inherited Create;
  FDataPool := TList<TBytes>.Create;
end;

destructor TIRList.Destroy;
begin
  FDataPool.Free;
  inherited;
end;

procedure TIRList.Clear;
begin
  inherited Clear;
  FDataPool.Clear;
end;

function TIRList.StoreData(const AData: Pointer; ASize: Cardinal): Pointer;
var
  Buffer: TBytes;
begin
  if (AData = nil) or (ASize = 0) then
    Exit(nil);

  SetLength(Buffer, ASize);
  System.Move(AData^, Buffer[0], ASize);

  FDataPool.Add(Buffer);
  Result := @FDataPool.Last[0];
end;

function TIRList.StoreData(const ABytes: TBytes): Pointer;
begin
  if Length(ABytes) = 0 then
    Exit(nil);

  FDataPool.Add(Copy(ABytes));
  Result := @FDataPool.Last[0];
end;

function TIRList.AddBlankLine: Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind    := TIRItem.TKind.None;
  Item.Comment := '';

  Result := Add(Item);
end;

function TIRList.AddComment(const AComment: String): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind    := TIRItem.TKind.None;
  Item.Comment := AComment;

  Result := Add(Item);
end;

function TIRList.AddLabel(const AName: TLabelString): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind := TIRItem.TKind.&Label;
  Item.Name := AName;

  Result := Add(Item);
end;

function TIRList.AddInstr(AOpCode: TCPUInstruction.TOpCode): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind   := TIRItem.TKind.Instruction;
  Item.OpCode := AOpCode;

  Result := Add(Item);
end;

function TIRList.AddInstrR1(AOpCode: TCPUInstruction.TOpCode; ARegA: TRegisters.ID): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind   := TIRItem.TKind.Instruction;
  Item.OpCode := AOpCode;
  Item.RegA   := ARegA;

  Result := Add(Item);
end;

function TIRList.AddInstrR1R2(AOpCode: TCPUInstruction.TOpCode; ARegA, ARegB: TRegisters.ID): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind   := TIRItem.TKind.Instruction;
  Item.OpCode := AOpCode;
  Item.RegA   := ARegA;
  Item.RegB   := ARegB;

  Result := Add(Item);
end;

function TIRList.AddInstrR1Imm(AOpCode: TCPUInstruction.TOpCode; ARegA: TRegisters.ID; AImmVal: Cardinal): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind      := TIRItem.TKind.Instruction;
  Item.OpCode    := AOpCode;
  Item.RegA      := ARegA;
  Item.RegB      := TRegisters.ID.Imm;
  Item.Imm.Value := AImmVal;

  Result := Add(Item);
end;

function TIRList.AddInstrR1Imm(AOpCode: TCPUInstruction.TOpCode; ARegA: TRegisters.ID; const AImmLabel: TLabelString): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind       := TIRItem.TKind.Instruction;
  Item.OpCode     := AOpCode;
  Item.RegA       := ARegA;
  Item.RegB       := TRegisters.ID.Imm;
  Item.Imm.&Label := AImmLabel;

  Result := Add(Item);
end;

function TIRList.AddInstrImm(AOpCode: TCPUInstruction.TOpCode; AImmVal: Cardinal): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind         := TIRItem.TKind.Instruction;
  Item.OpCode       := AOpCode;
  Item.Offset.Value := AImmVal;

  Result := Add(Item);
end;

function TIRList.AddInstrImm(AOpCode: TCPUInstruction.TOpCode; const AImmLabel: TLabelString): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind          := TIRItem.TKind.Instruction;
  Item.OpCode        := AOpCode;
  Item.Offset.&Label := AImmLabel;

  Result := Add(Item);
end;

function TIRList.AddInstrRImm(AOpCode: TCPUInstruction.TOpCode; ARegB: TRegisters.ID): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind   := TIRItem.TKind.Instruction;
  Item.OpCode := AOpCode;
  Item.RegB   := ARegB;

  Result := Add(Item);
end;

function TIRList.AddInstrRImm(AOpCode: TCPUInstruction.TOpCode; AImmVal: Cardinal): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind      := TIRItem.TKind.Instruction;
  Item.OpCode    := AOpCode;
  Item.RegB      := TRegisters.ID.Imm;
  Item.Imm.Value := AImmVal;

  Result := Add(Item);
end;

function TIRList.AddInstrRImm(AOpCode: TCPUInstruction.TOpCode; const AImmLabel: TLabelString): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind       := TIRItem.TKind.Instruction;
  Item.OpCode     := AOpCode;
  Item.RegB       := TRegisters.ID.Imm;
  Item.Imm.&Label := AImmLabel;

  Result := Add(Item);
end;

function TIRList.AddInstrR1R2Imm(AOpCode: TCPUInstruction.TOpCode; ARegA, ARegB: TRegisters.ID; AOffsetVal: Cardinal): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind         := TIRItem.TKind.Instruction;
  Item.OpCode       := AOpCode;
  Item.RegA         := ARegA;
  Item.RegB         := ARegB;
  Item.Offset.Value := AOffsetVal;

  Result := Add(Item);
end;

function TIRList.AddInstrR1R2Imm(AOpCode: TCPUInstruction.TOpCode; ARegA, ARegB: TRegisters.ID; const AOffsetLabel: TLabelString): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind          := TIRItem.TKind.Instruction;
  Item.OpCode        := AOpCode;
  Item.RegA          := ARegA;
  Item.RegB          := ARegB;
  Item.Offset.&Label := AOffsetLabel;

  Result := Add(Item);
end;

function TIRList.AddDataBytes(const ABytes: array of Byte): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind     := TIRItem.TKind.DataBytes;
  Item.DataSize := Length(ABytes);

  if Item.DataSize > 0 then
    Item.DataPtr := StoreData(@ABytes[0], Item.DataSize);

  Result := Add(Item);
end;

function TIRList.AddDataWords(const AWords: array of Word): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind     := TIRItem.TKind.DataWords;
  Item.DataSize := Length(AWords) * SizeOf(Word);

  if Item.DataSize > 0 then
    Item.DataPtr := StoreData(@AWords[0], Item.DataSize);

  Result := Add(Item);
end;

function TIRList.AddDataDWords(const ADWords: array of Cardinal): Integer;
var
  Item: TIRItem;
begin
  Item := Default(TIRItem);

  Item.Kind     := TIRItem.TKind.DataDWords;
  Item.DataSize := Length(ADWords) * SizeOf(Cardinal);

  if Item.DataSize > 0 then
    Item.DataPtr := StoreData(@ADWords[0], Item.DataSize);

  Result := Add(Item);
end;

function TIRList.AddDataString(const AString: AnsiString; ANullTerminated: Boolean): Integer;
var
  Item: TIRItem;
  Len:  Integer;
begin
  Len := Length(AString);
  if ANullTerminated then
    Inc(Len);

  Item := Default(TIRItem);

  Item.Kind     := TIRItem.TKind.DataString;
  Item.DataSize := Len;

  if Len > 0 then
    Item.DataPtr := StoreData(PAnsiChar(AString), Len);

  Result := Add(Item);
end;

function TIRList.ComputeAddresses(AStartAddress: Cardinal): Cardinal;
var
  CurrAddr: Cardinal;
begin
  CurrAddr := AStartAddress;

  for var i := 0 to Count - 1 do
  begin
    var Item := Items[i];
    Item.Address := CurrAddr;
    Inc(CurrAddr, Item.Size);
    Items[i] := Item;
  end;

  Result := CurrAddr - AStartAddress;
end;

function TIRList.ResolveLabels(AStartAddress: Cardinal; AErrors: TStrings): Boolean;
var
  LabelMap:     TDictionary<TLabelString, Cardinal>;
  CurrentScope: TLabelString;

  function Qualify(const AName, AScope: TLabelString): TLabelString; inline;
  begin
    if (Length(AName) > 0) and (AName[1] = '.') then
      Result := AScope + AName
    else
      Result := AName;
  end;
begin
  Result := True;
  ComputeAddresses(AStartAddress);

  LabelMap     := TDictionary<TLabelString, Cardinal>.Create;
  CurrentScope := '';

  try
    for var i := 0 to Count - 1 do
    begin
      if Items[i].Kind = TIRItem.TKind.&Label then
      begin
        var RawName := Items[i].Name;

        if (Length(RawName) > 0) and (RawName[1] <> '.') then
          CurrentScope := RawName;

        var FullName := Qualify(RawName, CurrentScope);

        if LabelMap.ContainsKey(FullName) then
        begin
          if Assigned(AErrors) then
            AErrors.Add(Format('Duplicate label "%s" at address $%x', [FullName, Items[i].Address]));

          Result := False;
        end
        else
          LabelMap.Add(FullName, Items[i].Address);
      end;
    end;

    CurrentScope := '';

    for var i := 0 to Count - 1 do
    begin
      if Items[i].Kind = TIRItem.TKind.&Label then
      begin
        if (Length(Items[i].Name) > 0) and (Items[i].Name[1] <> '.') then
          CurrentScope := Items[i].Name;
      end
      else if Items[i].Kind = TIRItem.TKind.Instruction then
      begin
        var Item     := Items[i];
        var Modified := False;

        if Length(Item.Imm.&Label) > 0 then
        begin
          var FullName := Qualify(Item.Imm.&Label, CurrentScope);
          var TargetAddr: Cardinal;

          if LabelMap.TryGetValue(FullName, TargetAddr) then
          begin
            Item.Imm.Value := TargetAddr;
            Modified := True;
          end
          else
          begin
            if Assigned(AErrors) then
              AErrors.Add(Format('Undefined label "%s" at address $%x', [FullName, Item.Address]));

            Result := False;
          end;
        end;

        if Length(Item.Offset.&Label) > 0 then
        begin
          var FullName := Qualify(Item.Offset.&Label, CurrentScope);
          var TargetAddr: Cardinal;

          if LabelMap.TryGetValue(FullName, TargetAddr) then
          begin
            Item.Offset.Value := TargetAddr;
            Modified := True;
          end
          else
          begin
            if Assigned(AErrors) then
              AErrors.Add(Format('Undefined offset label "%s" at address $%x', [FullName, Item.Address]));

            Result := False;
          end;
        end;

        if Modified then
          Items[i] := Item;
      end;
    end;
  finally
    LabelMap.Free;
  end;
end;

function TIRList.Emit(AMemory: TCustomMemory; AAddress: Cardinal): Cardinal;
var
  CurrAddr: Cardinal;
begin
  CurrAddr := AAddress;

  for var i := 0 to Count - 1 do
  begin
    var Item := Items[i];

    case Item.Kind of
      TIRItem.TKind.Instruction:
      begin
        var Instr: TCPUInstruction;

        Instr.OpCode := Item.OpCode;
        Instr.RegA   := Item.RegA;
        Instr.RegB   := Item.RegB;

        AMemory.WriteWord(CurrAddr, Word(Instr));

        Inc(CurrAddr, 2);

        if Item.RegB = TRegisters.ID.Imm then
        begin
          AMemory.WriteDWord(CurrAddr, Item.Imm.Value);
          Inc(CurrAddr, 4);
        end;

        if Item.OpCode.Definition.Params in [TCPUInstruction.TParameters.Imm, TCPUInstruction.TParameters.R1Imm, TCPUInstruction.TParameters.R1R2Imm] then
        begin
          AMemory.WriteDWord(CurrAddr, Item.Offset.Value);
          Inc(CurrAddr, 4);
        end;
      end;

      TIRItem.TKind.DataBytes,
      TIRItem.TKind.DataWords,
      TIRItem.TKind.DataDWords,
      TIRItem.TKind.DataString:
      begin
        if (Item.DataPtr <> nil) and (Item.DataSize > 0) then
        begin
          AMemory.WriteData(CurrAddr, Item.DataPtr^, Item.DataSize);
          Inc(CurrAddr, Item.DataSize);
        end;
      end;
    end;
  end;

  Result := CurrAddr - AAddress;
end;

function TIRList.Emit(AStream: TStream): Cardinal;
var
  TotalSize: Cardinal;
  Mem: TCustomMemory;
begin
  TotalSize := ComputeAddresses(0);

  if TotalSize = 0 then
    Exit(0);

  Mem := TCustomMemory.Create(TotalSize);

  try
    Emit(Mem, 0);

    AStream.WriteBuffer(Mem.Data^, TotalSize);

    Result := TotalSize;
  finally
    Mem.Free;
  end;
end;

function TIRList.EmitToBytes: TBytes;
var
  Stream: TBytesStream;
begin
  Stream := TBytesStream.Create;

  try
    Emit(Stream);

    Result := Stream.Bytes;

    SetLength(Result, Stream.Size);
  finally
    Stream.Free;
  end;
end;

function TIRList.ToString: String;
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;

  try
    for var i := 0 to Count - 1 do
    begin
      var Line := Items[i].ToString;

      if (Items[i].Kind <> TIRItem.TKind.&Label) and (Length(Line) > 0) then
        SB.Append(#9);

      SB.AppendLine(Line);
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;
{$ENDREGION}

end.
