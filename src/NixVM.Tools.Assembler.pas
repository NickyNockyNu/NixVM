{
  NixVM.Tools.Assembler.pas
    Text Assembler

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

unit NixVM.Tools.Assembler;

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
  {$REGION 'Assembler'}
  TAssembler = class abstract
  type
    {$REGION 'Lexer Types'}
    TTokenKind = (
      EOF,
      NewLine,
      Comment,
      Identifier,
      Number,
      &String,
      Comma,
      Colon,
      Plus,
      Minus
    );

    TToken = record
      Kind:     TTokenKind;
      ValueStr: String;
      ValueNum: Cardinal;
      Line:     Integer;
      Col:      Integer;
    end;
    {$ENDREGION}
  private
    class function ParseNumber(const S: String; out AValue: Cardinal): Boolean; static;
  public
    class function Parse    (const ASource:   String; out AErrors: TStrings): TIRList; static;
    class function ParseFile(const AFileName: String; out AErrors: TStrings): TIRList; static;

    class function Assemble(const ASource: String; AMemory: TCustomMemory; AStartAddress: Cardinal; out AErrors: TStrings): Cardinal; static;
  end;
  {$ENDREGION}

implementation

{$REGION 'Number Parser'}
class function TAssembler.ParseNumber(const S: String; out AValue: Cardinal): Boolean;
var
  U:    String;
  Code: Integer;
begin
  Result := False;
  AValue := 0;

  if Length(S) = 0 then
    Exit;

  U := UpperCase(Trim(S));

  if (Length(U) > 2) and (U[1] = '0') and (U[2] = 'X') then
    U := '$' + Copy(U, 3, Length(U));

  if (Length(U) > 1) and (U[1] = '%') then
  begin
    AValue := 0;

    for var i := 2 to Length(U) do
    begin
      if not CharInSet(U[i], ['0', '1']) then
        Exit(False);

      AValue := (AValue shl 1) or Cardinal(Ord(U[i]) - Ord('0'));
    end;

    Exit(True);
  end
  else if (Length(U) > 2) and (U[1] = '0') and (U[2] = 'B') then
  begin
    AValue := 0;

    for var i := 3 to Length(U) do
    begin
      if not CharInSet(U[i], ['0', '1']) then
        Exit(False);

      AValue := (AValue shl 1) or Cardinal(Ord(U[i]) - Ord('0'));
    end;

    Exit(True);
  end;

  Val(U, AValue, Code);
  Result := (Code = 0);
end;
{$ENDREGION}

{$REGION 'Assembler Main'}
class function TAssembler.Parse(const ASource: String; out AErrors: TStrings): TIRList;
var
  IR:      TIRList;
  SrcPos:  Integer;
  SrcLen:  Integer;
  CurLine: Integer;
  CurCol:  Integer;
  Errors:  TStringList;

  function NextToken(out ATok: TToken): Boolean;
  var
    StartCol: Integer;
    C:        Char;
  begin
    ATok := Default(TToken);

    while SrcPos <= SrcLen do
    begin
      C := ASource[SrcPos];

      if CharInSet(C, [' ', #9]) then
      begin
        Inc(SrcPos);
        Inc(CurCol);

        Continue;
      end;

      if C = ';' then
      begin
        var CommentStr := '';

        Inc(SrcPos);
        Inc(CurCol);

        if (SrcPos <= SrcLen) and (ASource[SrcPos] = ' ') then
        begin
          Inc(SrcPos);
          Inc(CurCol);
        end;

        while (SrcPos <= SrcLen) and not CharInSet(ASource[SrcPos], [#10, #13]) do
        begin
          CommentStr := CommentStr + ASource[SrcPos];

          Inc(SrcPos);
          Inc(CurCol);
        end;

        ATok.Kind     := TTokenKind.Comment;
        ATok.ValueStr := CommentStr;

        Exit(True);
      end;

      if CharInSet(C, [#10, #13]) then
      begin
        ATok.Kind := TTokenKind.NewLine;
        ATok.Line := CurLine;
        ATok.Col  := CurCol;

        if (C = #13) and (SrcPos + 1 <= SrcLen) and (ASource[SrcPos + 1] = #10) then
          Inc(SrcPos);

        Inc(SrcPos);
        Inc(CurLine);

        CurCol := 1;

        Exit(True);
      end;

      Break;
    end;

    if SrcPos > SrcLen then
    begin
      ATok.Kind := TTokenKind.EOF;
      ATok.Line := CurLine;
      ATok.Col  := CurCol;

      Exit(False);
    end;

    StartCol  := CurCol;
    ATok.Line := CurLine;
    ATok.Col  := StartCol;
    C         := ASource[SrcPos];

    case C of
      ',': begin ATok.Kind := TTokenKind.Comma; ATok.ValueStr := ','; Inc(SrcPos); Inc(CurCol); Exit(True); end;
      ':': begin ATok.Kind := TTokenKind.Colon; ATok.ValueStr := ':'; Inc(SrcPos); Inc(CurCol); Exit(True); end;
      '+': begin ATok.Kind := TTokenKind.Plus;  ATok.ValueStr := '+'; Inc(SrcPos); Inc(CurCol); Exit(True); end;
      '-': begin ATok.Kind := TTokenKind.Minus; ATok.ValueStr := '-'; Inc(SrcPos); Inc(CurCol); Exit(True); end;
    end;

    if CharInSet(C, ['"', '''']) then
    begin
      var QuoteChar := C;
      var StrVal := '';

      Inc(SrcPos);
      Inc(CurCol);

      while SrcPos <= SrcLen do
      begin
        C := ASource[SrcPos];

        if C = QuoteChar then
        begin
          Inc(SrcPos);
          Inc(CurCol);

          Break;
        end
        else if (C = '\') and (SrcPos + 1 <= SrcLen) then
        begin
          Inc(SrcPos);
          Inc(CurCol);

          case ASource[SrcPos] of
            'n':  StrVal := StrVal + #10;
            'r':  StrVal := StrVal + #13;
            't':  StrVal := StrVal + #9;
            '0':  StrVal := StrVal + #0;
            '\':  StrVal := StrVal + '\';
            '"':  StrVal := StrVal + '"';
            '''': StrVal := StrVal + '''';
          else
            StrVal := StrVal + ASource[SrcPos];
          end;
        end
        else
          StrVal := StrVal + C;

        Inc(SrcPos);
        Inc(CurCol);
      end;

      ATok.Kind     := TTokenKind.String;
      ATok.ValueStr := StrVal;

      Exit(True);
    end;

    if CharInSet(C, ['0'..'9', '$', '%']) or ((C = '-') and (SrcPos + 1 <= SrcLen) and CharInSet(ASource[SrcPos + 1], ['0'..'9', '$'])) then
    begin
      var NumStr := '';

      while (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['0'..'9', 'a'..'f', 'A'..'F', 'x', 'X', '$', '%', '-']) do
      begin
        NumStr := NumStr + ASource[SrcPos];

        Inc(SrcPos);
        Inc(CurCol);
      end;

      var NumVal: Cardinal;

      if ParseNumber(NumStr, NumVal) then
      begin
        ATok.Kind     := TTokenKind.Number;
        ATok.ValueStr := NumStr;
        ATok.ValueNum := NumVal;

        Exit(True);
      end;

      ATok.Kind     := TTokenKind.Identifier;
      ATok.ValueStr := NumStr;

      Exit(True);
    end;

    if CharInSet(C, ['a'..'z', 'A'..'Z', '_', '@', '.']) then
    begin
      var IdentStr := '';

      while (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['a'..'z', 'A'..'Z', '0'..'9', '_', '@', '.']) do
      begin
        IdentStr := IdentStr + ASource[SrcPos];

        Inc(SrcPos);
        Inc(CurCol);
      end;

      ATok.Kind     := TTokenKind.Identifier;
      ATok.ValueStr := IdentStr;

      Exit(True);
    end;

    Errors.Add(Format('Line %d, Col %d: Unexpected character "%s"', [CurLine, CurCol, C]));

    Inc(SrcPos);
    Inc(CurCol);

    Exit(False);
  end;

  function ParseRegister(const ATok: TToken; out AReg: TRegisters.ID): Boolean;
  begin
    AReg := TRegisters.ID.FromString(ATok.ValueStr, Result);
  end;

  procedure Error(const AMsg: String; const ATok: TToken);
  begin
    Errors.Add(Format('Line %d, Col %d: %s', [ATok.Line, ATok.Col, AMsg]));
  end;

var
  Tok:         TToken;
  LineHasItem: Boolean;

  function PeekToken: TToken;
  var
    SavedPos, SavedLine, SavedCol: Integer;
  begin
    SavedPos  := SrcPos;
    SavedLine := CurLine;
    SavedCol  := CurCol;

    NextToken(Result);

    SrcPos  := SavedPos;
    CurLine := SavedLine;
    CurCol  := SavedCol;
  end;

begin
  IR          := TIRList.Create;
  Errors      := TStringList.Create;
  SrcPos      := 1;
  SrcLen      := Length(ASource);
  CurLine     := 1;
  CurCol      := 1;
  LineHasItem := False;

  while NextToken(Tok) do
  begin
    if Tok.Kind = TTokenKind.NewLine then
    begin
      if not LineHasItem and (IR.Count > 0) then
        IR.AddBlankLine;

      LineHasItem := False;
      Continue;
    end;

    if Tok.Kind = TTokenKind.Comment then
    begin
      if LineHasItem and (IR.Count > 0) then
      begin
        var LastItem := IR.Last;

        LastItem.Comment := Tok.ValueStr;
        IR.Items[IR.Count - 1] := LastItem;
      end
      else
      begin
        IR.AddComment(Tok.ValueStr);
        LineHasItem := True;
      end;

      Continue;
    end;

    if Tok.Kind <> TTokenKind.Identifier then
    begin
      Error('Expected instruction, label, or directive', Tok);
      Continue;
    end;

    var Peek := PeekToken;

    if Peek.Kind = TTokenKind.Colon then
    begin
      IR.AddLabel(TLabelString(Tok.ValueStr));
      NextToken(Tok);

      LineHasItem := True;

      Continue;
    end;

    var LowerIdent := LowerCase(Tok.ValueStr);

    if (LowerIdent = 'db') or (LowerIdent = 'byte') then
    begin
      var ByteList: TList<Byte> := TList<Byte>.Create;
      try
        repeat
          if not NextToken(Tok) then
            Break;

          if Tok.Kind = TTokenKind.String then
          begin
            for var i := 1 to Length(Tok.ValueStr) do
              ByteList.Add(Ord(Tok.ValueStr[i]));
          end
          else if Tok.Kind = TTokenKind.Number then
            ByteList.Add(Byte(Tok.ValueNum and $FF))
          else
          begin
            Error('Expected byte value or string literal in db directive', Tok);
            Break;
          end;

          Peek := PeekToken;

          if Peek.Kind = TTokenKind.Comma then
            NextToken(Tok)
          else
            Break;
        until False;

        if ByteList.Count > 0 then
        begin
          IR.AddDataBytes(ByteList.ToArray);
          LineHasItem := True;
        end;
      finally
        ByteList.Free;
      end;

      Continue;
    end;

    if (LowerIdent = 'dw') or (LowerIdent = 'word') then
    begin
      var WordList: TList<Word> := TList<Word>.Create;

      try
        repeat
          if not NextToken(Tok) then
            Break;

          if Tok.Kind = TTokenKind.Number then
            WordList.Add(Word(Tok.ValueNum and $FFFF))
          else
          begin
            Error('Expected word integer in dw directive', Tok);
            Break;
          end;

          Peek := PeekToken;

          if Peek.Kind = TTokenKind.Comma then
            NextToken(Tok)
          else
            Break;
        until False;

        if WordList.Count > 0 then
        begin
          IR.AddDataWords(WordList.ToArray);
          LineHasItem := True;
        end;
      finally
        WordList.Free;
      end;

      Continue;
    end;

    if (LowerIdent = 'dd') or (LowerIdent = 'dword') then
    begin
      var DWordList: TList<Cardinal> := TList<Cardinal>.Create;

      try
        repeat
          if not NextToken(Tok) then
            Break;

          if Tok.Kind = TTokenKind.Number then
            DWordList.Add(Tok.ValueNum)
          else
          begin
            Error('Expected dword integer in dd directive', Tok);
            Break;
          end;

          Peek := PeekToken;

          if Peek.Kind = TTokenKind.Comma then
            NextToken(Tok)
          else
            Break;
        until False;

        if DWordList.Count > 0 then
        begin
          IR.AddDataDWords(DWordList.ToArray);
          LineHasItem := True;
        end;
      finally
        DWordList.Free;
      end;

      Continue;
    end;

    if (LowerIdent = 'ds') or (LowerIdent = 'string') then
    begin
      if NextToken(Tok) and (Tok.Kind = TTokenKind.String) then
      begin
        IR.AddDataString(AnsiString(Tok.ValueStr), True);
        LineHasItem := True;
      end
      else
        Error('Expected quoted string literal in ds directive', Tok);

      Continue;
    end;

    var ValidOp: Boolean;
    var OpCode := TCPUInstruction.TOpCode.FromString(LowerIdent, ValidOp);

    if not ValidOp then
    begin
      Error(Format('Unknown mnemonic or directive "%s"', [Tok.ValueStr]), Tok);
      Continue;
    end;

    case OpCode.Definition.Params of
      TCPUInstruction.TParameters.None:
      begin
        IR.AddInstr(OpCode);
        LineHasItem := True;
      end;

      TCPUInstruction.TParameters.R1:
      begin
        if not NextToken(Tok) then
        begin
          Error('Expected register parameter', Tok);
          Continue;
        end;

        var RegA: TRegisters.ID;

        if not ParseRegister(Tok, RegA) then
          Error(Format('Invalid register "%s"', [Tok.ValueStr]), Tok)
        else
        begin
          IR.AddInstrR1(OpCode, RegA);
          LineHasItem := True;
        end;
      end;

      TCPUInstruction.TParameters.Imm:
      begin
        if not NextToken(Tok) then
        begin
          Error('Expected immediate or label target', Tok);
          Continue;
        end;

        if Tok.Kind = TTokenKind.Number then
        begin
          IR.AddInstrImm(OpCode, Tok.ValueNum);
          LineHasItem := True;
        end
        else if Tok.Kind = TTokenKind.Identifier then
        begin
          IR.AddInstrImm(OpCode, TLabelString(Tok.ValueStr));
          LineHasItem := True;
        end
        else
          Error('Expected number or label', Tok);
      end;

      TCPUInstruction.TParameters.R1Imm:
      begin
        if not NextToken(Tok) then
        begin
          Error('Expected register', Tok);
          Continue;
        end;

        var RegA: TRegisters.ID;

        if not ParseRegister(Tok, RegA) then
        begin
          Error(Format('Invalid register "%s"', [Tok.ValueStr]), Tok);
          Continue;
        end;

        if not NextToken(Tok) or (Tok.Kind <> TTokenKind.Comma) then
        begin
          Error('Expected comma', Tok);
          Continue;
        end;

        if not NextToken(Tok) then
        begin
          Error('Expected target label or immediate', Tok);
          Continue;
        end;

        if Tok.Kind = TTokenKind.Number then
        begin
          IR.AddInstrR1Imm(OpCode, RegA, Tok.ValueNum);
          LineHasItem := True;
        end
        else if Tok.Kind = TTokenKind.Identifier then
        begin
          IR.AddInstrR1Imm(OpCode, RegA, TLabelString(Tok.ValueStr));
          LineHasItem := True;
        end
        else
          Error('Expected number or label', Tok);
      end;

      TCPUInstruction.TParameters.RImm:
      begin
        if not NextToken(Tok) then
        begin
          Error('Expected operand (register, number, or label)', Tok);
          Continue;
        end;

        var RegB: TRegisters.ID;

        if (Tok.Kind = TTokenKind.Identifier) and ParseRegister(Tok, RegB) then
        begin
          IR.AddInstrRImm(OpCode, RegB);
          LineHasItem := True;
        end
        else if Tok.Kind = TTokenKind.Number then
        begin
          IR.AddInstrRImm(OpCode, Tok.ValueNum);
          LineHasItem := True;
        end
        else if Tok.Kind = TTokenKind.Identifier then
        begin
          IR.AddInstrRImm(OpCode, TLabelString(Tok.ValueStr));
          LineHasItem := True;
        end
        else
          Error('Invalid operand for RImm instruction', Tok);
      end;

      TCPUInstruction.TParameters.R1R2:
      begin
        if not NextToken(Tok) then
        begin
          Error('Expected destination register', Tok);
          Continue;
        end;

        var RegA: TRegisters.ID;

        if not ParseRegister(Tok, RegA) then
        begin
          Error(Format('Invalid register "%s"', [Tok.ValueStr]), Tok);
          Continue;
        end;

        if not NextToken(Tok) or (Tok.Kind <> TTokenKind.Comma) then
        begin
          Error('Expected comma', Tok);
          Continue;
        end;

        if not NextToken(Tok) then
        begin
          Error('Expected second operand (register, immediate, or label)', Tok);
          Continue;
        end;

        var RegB: TRegisters.ID;

        if (Tok.Kind = TTokenKind.Identifier) and ParseRegister(Tok, RegB) then
        begin
          IR.AddInstrR1R2(OpCode, RegA, RegB);
          LineHasItem := True;
        end
        else if Tok.Kind = TTokenKind.Number then
        begin
          IR.AddInstrR1Imm(OpCode, RegA, Tok.ValueNum);
          LineHasItem := True;
        end
        else if Tok.Kind = TTokenKind.Identifier then
        begin
          IR.AddInstrR1Imm(OpCode, RegA, TLabelString(Tok.ValueStr));
          LineHasItem := True;
        end
        else
          Error('Invalid second operand for R1R2 instruction', Tok);
      end;

      TCPUInstruction.TParameters.R1R2Imm:
      begin
        if not NextToken(Tok) then
        begin
          Error('Expected destination register', Tok);
          Continue;
        end;

        var RegA: TRegisters.ID;

        if not ParseRegister(Tok, RegA) then
        begin
          Error('Invalid destination register', Tok);
          Continue;
        end;

        if not NextToken(Tok) or (Tok.Kind <> TTokenKind.Comma) then
        begin
          Error('Expected comma', Tok);
          Continue;
        end;

        if not NextToken(Tok) then
        begin
          Error('Expected base register or immediate', Tok);
          Continue;
        end;

        var RegB: TRegisters.ID;

        if not ParseRegister(Tok, RegB) then
        begin
          Error('Invalid base register', Tok);
          Continue;
        end;

        if not NextToken(Tok) or (Tok.Kind <> TTokenKind.Comma) then
        begin
          Error('Expected comma', Tok);
          Continue;
        end;

        if not NextToken(Tok) then
        begin
          Error('Expected offset value or label', Tok);
          Continue;
        end;

        if Tok.Kind = TTokenKind.Number then
        begin
          IR.AddInstrR1R2Imm(OpCode, RegA, RegB, Tok.ValueNum);
          LineHasItem := True;
        end
        else if Tok.Kind = TTokenKind.Identifier then
        begin
          IR.AddInstrR1R2Imm(OpCode, RegA, RegB, TLabelString(Tok.ValueStr));
          LineHasItem := True;
        end
        else
          Error('Invalid offset in 3-operand instruction', Tok);
      end;
    end;
  end;

  AErrors := Errors;
  Result  := IR;
end;

class function TAssembler.ParseFile(const AFileName: String; out AErrors: TStrings): TIRList;
var
  SL: TStringList;
begin
  if not FileExists(AFileName) then
  begin
    AErrors := TStringList.Create;
    AErrors.Add(Format('File not found: "%s"', [AFileName]));

    Exit(TIRList.Create);
  end;

  SL := TStringList.Create;

  try
    SL.LoadFromFile(AFileName);

    Result := Parse(SL.Text, AErrors);
  finally
    SL.Free;
  end;
end;

class function TAssembler.Assemble(const ASource: String; AMemory: TCustomMemory; AStartAddress: Cardinal; out AErrors: TStrings): Cardinal;
var
  IR: TIRList;
begin
  IR := Parse(ASource, AErrors);

  try
    if (AErrors <> nil) and (AErrors.Count > 0) then
      Exit(0);

    if not IR.ResolveLabels(AStartAddress, AErrors) then
      Exit(0);

    Result := IR.Emit(AMemory, AStartAddress);
  finally
    IR.Free;
  end;
end;
{$ENDREGION}

end.
