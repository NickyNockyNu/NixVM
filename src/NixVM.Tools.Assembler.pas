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
  System.IOUtils,

  NixVM.Core.System,
  NixVM.Core.Registers,
  NixVM.Core.Instructions,
  NixVM.Core.Memory,
  NixVM.Core.ROM,

  NixVM.Tools.Compiler.Optimiser,
  NixVM.Tools.IR;

type
  {$REGION 'Assembler'}
  TAssembler = class
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
    FIR:     TIRList;
    FErrors: TStrings;

    FBasePath: String;

    FOptimise: Boolean;

    FSizeBeforeOpt: Integer;
    FSizeAfterOpt:  Integer;
  public
    ROMHeader: TROMHeader;

    constructor Create;
    destructor  Destroy; override;

    function Assemble    (const ASource:   String): Boolean;
    function AssembleFile(const AFileName: String): Boolean;

    function Link(AMemory: TMemory;        AResize:     Boolean = True): Boolean; overload;
    function Link(AStream: TStream;        AWithHeader: Boolean = True): Boolean; overload;
    function Link(const AFileName: String; AWithHeader: Boolean = True): Boolean; overload;

    class function Parse(const ASource: String; out AErrors: TStrings; const AFileName: String = ''; const ABasePath: String = ''; AIncludeStack: TStrings = nil; ASharedErrors: TStringList = nil; AROMHeader: PROMHeader = nil): TIRList;
    class function ParseFile(const AFileName: String; out AErrors: TStrings; AROMHeader: PROMHeader = nil): TIRList; static;

    property IR:     TIRList  read FIR;
    property Errors: TStrings read FErrors;

    property BasePath: String read FBasePath write FBasePath;

    property Optimise: Boolean read FOptimise write FOptimise;

    property SizeBeforeOpt: Integer read FSizeBeforeOpt;
    property SizeAfterOpt:  Integer read FSizeAfterOpt;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Core.Strings;

{$REGION 'Assembler'}
constructor TAssembler.Create;
begin
  inherited;

  FErrors := TStringList.Create;
  ROMHeader.Reset;

  FOptimise := False;
end;

destructor TAssembler.Destroy;
begin
  if Assigned(FIR) then
    FIR.Free;

  FErrors.Free;
  inherited;
end;

function TAssembler.Assemble(const ASource: String): Boolean;
begin
  if Assigned(FIR) then
    FIR.Free;

  FIR := Parse(ASource, FErrors, '', FBasePath, nil, nil, @ROMHeader);

  FSizeBeforeOpt := FIR.Size;

  if FOptimise then
    TPeepholeOptimiser.Optimise(FIR);

  FSizeAfterOpt := FIR.Size;
  Result := FErrors.Count = 0;
end;

function TAssembler.AssembleFile(const AFileName: String): Boolean;
var
  SourceText:   String;
  FullFilePath: String;
begin
  if not FileExists(AFileName) then
  begin
    FErrors.Clear;
    FErrors.Add(Format('File not found: "%s"', [AFileName]));
    Exit(False);
  end;

  FullFilePath := TPath.GetFullPath(AFileName);
  FBasePath    := ExtractFilePath(FullFilePath);

  SourceText := TFile.ReadAllText(FullFilePath);
  Result     := Assemble(SourceText);
end;

function TAssembler.Link(AMemory: TMemory; AResize: Boolean): Boolean;
begin
  Result := False;
  FErrors.Clear;

  if not Assigned(FIR) then
    Exit;

  if AResize then
    AMemory.Resize(FIR.Size, ROMHeader.HeapSize, ROMHeader.StackSize)
  else
  begin
    ROMHeader.HeapSize  := AMemory.Heap.Size;
    ROMHeader.StackSize := AMemory.Stack.Size;
  end;

  if not FIR.ResolveLabels(AMemory.UserAddress, FErrors) then
    Exit;

  ROMHeader.UserAddress := AMemory.UserAddress;
  ROMHeader.UserSize    := FIR.Emit(AMemory, AMemory.UserAddress);
  Result := True;
end;

function TAssembler.Link(AStream: TStream; AWithHeader: Boolean): Boolean;
var
  CodeBytes: TBytes;
  BaseAddr:  Cardinal;
begin
  Result := False;
  FErrors.Clear;

  if not Assigned(FIR) then
    Exit;

  if ROMHeader.UserAddress > 0 then
    BaseAddr := ROMHeader.UserAddress
  else
    BaseAddr := (SizeOf(TCoreSystemMemory) + 3) and not Cardinal(3);

  if not FIR.ResolveLabels(BaseAddr, FErrors) then
    Exit;

  CodeBytes          := FIR.EmitToBytes;
  ROMHeader.UserSize := Length(CodeBytes);

  if AWithHeader then
    AStream.WriteBuffer(ROMHeader, SizeOf(TROMHeader));

  if Length(CodeBytes) > 0 then
    AStream.WriteBuffer(CodeBytes[0], Length(CodeBytes));

  Result := True;
end;

function TAssembler.Link(const AFileName: String; AWithHeader: Boolean): Boolean;
var
  FS: TFileStream;
begin
  try
    FS := TFileStream.Create(AFileName, fmCreate);
  except
    on E: EFCreateError do
    begin
      FErrors.Add(E.Message);
      Exit(False);
    end;
  end;

  try
    Result := Link(FS, AWithHeader);
  finally
    FS.Free;
  end;
end;

{$REGION 'Parse'}
class function TAssembler.Parse(const ASource: String; out AErrors: TStrings; const AFileName: String; const ABasePath: String; AIncludeStack: TStrings; ASharedErrors: TStringList; AROMHeader: PROMHeader): TIRList;
var
  IR:            TIRList;
  Constants:     TDictionary<String, Cardinal>;
  Errors:        TStringList;
  OwnsErrors:    Boolean;
  SrcPos:        Integer;
  SrcLen:        Integer;
  CurLine:       Integer;
  CurCol:        Integer;
  LineHasItem:   Boolean;
  EffectiveBase: String;
  Tok:           TToken;

  procedure Error(const AMsg: String; const ATok: TToken);
  begin
    if Length(AFileName) > 0 then
      Errors.Add(Format('[%s] Line %d, Col %d: %s', [ExtractFileName(AFileName), ATok.Line, ATok.Col, AMsg]))
    else
      Errors.Add(Format('Line %d, Col %d: %s', [ATok.Line, ATok.Col, AMsg]));
  end;

  {$REGION 'Tokenizer'}
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

    // Single-character delimiters (only match '-' if NOT followed by a digit or hex prefix)
    case C of
      ',': begin ATok.Kind := TTokenKind.Comma; ATok.ValueStr := ','; Inc(SrcPos); Inc(CurCol); Exit(True); end;
      ':': begin ATok.Kind := TTokenKind.Colon; ATok.ValueStr := ':'; Inc(SrcPos); Inc(CurCol); Exit(True); end;
      '+': begin ATok.Kind := TTokenKind.Plus;  ATok.ValueStr := '+'; Inc(SrcPos); Inc(CurCol); Exit(True); end;
      '-':
      begin
        if not ((SrcPos + 1 <= SrcLen) and CharInSet(ASource[SrcPos + 1], ['0'..'9', '$', '%'])) then
        begin
          ATok.Kind := TTokenKind.Minus;
          ATok.ValueStr := '-';

          Inc(SrcPos);
          Inc(CurCol);

          Exit(True);
        end;
      end;
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
          if (SrcPos + 1 <= SrcLen) and (ASource[SrcPos + 1] = QuoteChar) then
          begin
            StrVal := StrVal + QuoteChar;

            Inc(SrcPos, 2);
            Inc(CurCol, 2);

            Continue;
          end;

          Inc(SrcPos);
          Inc(CurCol);

          Break;
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

    if C = '$' then
    begin
      var HexStr: String := '$';

      Inc(SrcPos);
      Inc(CurCol);

      while (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['0'..'9', 'a'..'f', 'A'..'F']) do
      begin
        HexStr := HexStr + ASource[SrcPos];
        Inc(SrcPos);
        Inc(CurCol);
      end;

      if Length(HexStr) = 1 then
      begin
        Error('Expected hex digits after "$"', ATok);
        Exit(False);
      end;

      if (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['k', 'K', 'm', 'M']) then
      begin
        HexStr := HexStr + ASource[SrcPos];

        Inc(SrcPos);
        Inc(CurCol);

        if (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['a'..'z', 'A'..'Z', '0'..'9', '_']) then
        begin
          Error(Format('Invalid trailing character "%s" after number suffix', [ASource[SrcPos]]), ATok);
          Exit(False);
        end;
      end;

      var NumVal: Cardinal;
      if ParseNumber(HexStr, NumVal) then
      begin
        ATok.Kind     := TTokenKind.Number;
        ATok.ValueStr := HexStr;
        ATok.ValueNum := NumVal;

        Exit(True);
      end;
    end;

    if C = '%' then
    begin
      var BinStr: String := '%';

      Inc(SrcPos);
      Inc(CurCol);

      while (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['0', '1']) do
      begin
        BinStr := BinStr + ASource[SrcPos];

        Inc(SrcPos);
        Inc(CurCol);
      end;

      if Length(BinStr) = 1 then
      begin
        Error('Expected binary digits (0 or 1) after "%"', ATok);
        Exit(False);
      end;

      if (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['k', 'K', 'm', 'M']) then
      begin
        BinStr := BinStr + ASource[SrcPos];

        Inc(SrcPos);
        Inc(CurCol);

        if (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['a'..'z', 'A'..'Z', '0'..'9', '_']) then
        begin
          Error(Format('Invalid trailing character "%s" after number suffix', [ASource[SrcPos]]), ATok);
          Exit(False);
        end;
      end;

      var NumVal: Cardinal;
      if ParseNumber(BinStr, NumVal) then
      begin
        ATok.Kind     := TTokenKind.Number;
        ATok.ValueStr := BinStr;
        ATok.ValueNum := NumVal;

        Exit(True);
      end;
    end;

    if CharInSet(C, ['0'..'9']) or ((C = '-') and (SrcPos + 1 <= SrcLen) and CharInSet(ASource[SrcPos + 1], ['0'..'9', '$', '%'])) then
    begin
      var NumStr := '';

      if (C = '0') and (SrcPos + 1 <= SrcLen) and CharInSet(ASource[SrcPos + 1], ['x', 'X', 'b', 'B']) then
      begin
        var Prefix := ASource[SrcPos + 1];
        NumStr := '0' + Prefix;

        Inc(SrcPos, 2);
        Inc(CurCol, 2);

        if (Prefix = 'x') or (Prefix = 'X') then
        begin
          while (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['0'..'9', 'a'..'f', 'A'..'F']) do
          begin
            NumStr := NumStr + ASource[SrcPos];

            Inc(SrcPos);
            Inc(CurCol);
          end;
        end
        else
        begin
          while (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['0', '1']) do
          begin
            NumStr := NumStr + ASource[SrcPos];

            Inc(SrcPos);
            Inc(CurCol);
          end;
        end;
      end
      else
      begin
        if C = '-' then
        begin
          NumStr := '-';

          Inc(SrcPos);
          Inc(CurCol);
        end;

        if (SrcPos <= SrcLen) and (ASource[SrcPos] = '$') then
        begin
          NumStr := NumStr + '$';

          Inc(SrcPos);
          Inc(CurCol);

          while (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['0'..'9', 'a'..'f', 'A'..'F']) do
          begin
            NumStr := NumStr + ASource[SrcPos];

            Inc(SrcPos);
            Inc(CurCol);
          end;
        end
        else
        begin
          while (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['0'..'9']) do
          begin
            NumStr := NumStr + ASource[SrcPos];

            Inc(SrcPos);
            Inc(CurCol);
          end;

          if (SrcPos + 1 <= SrcLen) and (ASource[SrcPos] = '.') and CharInSet(ASource[SrcPos + 1], ['0'..'9']) then
          begin
            NumStr := NumStr + '.';

            Inc(SrcPos);
            Inc(CurCol);

            while (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['0'..'9']) do
            begin
              NumStr := NumStr + ASource[SrcPos];

              Inc(SrcPos);
              Inc(CurCol);
            end;
          end;
        end;
      end;

      if (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['k', 'K', 'm', 'M']) then
      begin
        NumStr := NumStr + ASource[SrcPos];

        Inc(SrcPos);
        Inc(CurCol);

        if (SrcPos <= SrcLen) and CharInSet(ASource[SrcPos], ['a'..'z', 'A'..'Z', '0'..'9', '_']) then
        begin
          Error(Format('Invalid trailing character "%s" after number suffix', [ASource[SrcPos]]), ATok);
          Exit(False);
        end;
      end;

      var NumVal: Cardinal;
      if ParseNumber(NumStr, NumVal) then
      begin
        ATok.Kind     := TTokenKind.Number;
        ATok.ValueStr := NumStr;
        ATok.ValueNum := NumVal;

        Exit(True);
      end
      else
      begin
        Error(Format('Malformed numeric literal "%s"', [NumStr]), ATok);
        Exit(False);
      end;
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
  {$ENDREGION}

  {$REGION 'Value getters'}
  function ParseRegister(const ATok: TToken; out AReg: TRegisters.ID): Boolean;
  begin
    AReg := TRegisters.ID.FromString(ATok.ValueStr, Result);
  end;

  function ResolveIdentOrNumber(const ATok: TToken; out AVal: Cardinal; out AIsConst: Boolean): Boolean;
  begin
    if ATok.Kind = TTokenKind.Number then
    begin
      AVal     := ATok.ValueNum;
      AIsConst := True;
      Exit(True);
    end;

    if ATok.Kind = TTokenKind.Identifier then
    begin
      if Constants.TryGetValue(LowerCase(ATok.ValueStr), AVal) then
      begin
        AIsConst := True;
        Exit(True);
      end;

      AIsConst := False;
      Exit(True);
    end;

    Result := False;
  end;

  function ParseOperand(out AVal: Cardinal; out ALabel: TLabelString; out AIsConst: Boolean): Boolean;
  var
    FirstTok: TToken;
  begin
    AVal     := 0;
    ALabel   := '';
    AIsConst := False;

    if not NextToken(FirstTok) then
      Exit(False);

    if FirstTok.Kind = TTokenKind.Minus then
    begin
      var NextTok: TToken;
      if NextToken(NextTok) then
      begin
        var SubVal: Cardinal;
        var SubIsConst: Boolean;
        if ResolveIdentOrNumber(NextTok, SubVal, SubIsConst) and SubIsConst then
        begin
          AVal     := Cardinal(-Int32(SubVal));
          AIsConst := True;

          Exit(True);
        end;
      end;

      Exit(False);
    end;

    if FirstTok.Kind = TTokenKind.Number then
    begin
      AVal     := FirstTok.ValueNum;
      AIsConst := True;

      Exit(True);
    end;

    if FirstTok.Kind = TTokenKind.Identifier then
    begin
      if Constants.TryGetValue(LowerCase(FirstTok.ValueStr), AVal) then
      begin
        AIsConst := True;

        Exit(True);
      end;

      ALabel := TLabelString(FirstTok.ValueStr);

      var Next := PeekToken;

      if (Next.Kind = TTokenKind.Plus) or (Next.Kind = TTokenKind.Minus) then
      begin
        var IsMinus := (Next.Kind = TTokenKind.Minus);
        NextToken(Next);

        var OffsetTok: TToken;

        if not NextToken(OffsetTok) then
        begin
          Error('Expected offset number or constant after +/-', Next);
          Exit(False);
        end;

        var OffsetVal: Cardinal;
        var OffsetIsConst: Boolean;

        if ResolveIdentOrNumber(OffsetTok, OffsetVal, OffsetIsConst) and OffsetIsConst then
        begin
          if IsMinus then
            AVal := Cardinal(-Int32(OffsetVal))
          else
            AVal := OffsetVal;
        end
        else
        begin
          Error(Format('Expected numeric constant for label offset, got "%s"', [OffsetTok.ValueStr]), OffsetTok);
          Exit(False);
        end;
      end;

      AIsConst := False;
      Exit(True);
    end;

    Result := False;
  end;
  {$ENDREGION}
begin
  IR         := TIRList.Create;
  Constants  := TDictionary<String, Cardinal>.Create;
  OwnsErrors := (ASharedErrors = nil);

  if OwnsErrors then
    Errors := TStringList.Create
  else
    Errors := ASharedErrors;

  EffectiveBase := ABasePath;

  if (Length(EffectiveBase) = 0) and (Length(AFileName) > 0) then
    EffectiveBase := ExtractFilePath(AFileName);

  SrcPos      := 1;
  SrcLen      := Length(ASource);
  CurLine     := 1;
  CurCol      := 1;
  LineHasItem := False;

  try
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
          var LastItem := IR.Items[IR.Count - 1];

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
        Error('Expected instruction, label, constant, or directive', Tok);
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

      if (Peek.Kind = TTokenKind.Identifier) and ((LowerCase(Peek.ValueStr) = '.equ') or (LowerCase(Peek.ValueStr) = '.const')) then
      begin
        var ConstName := LowerCase(Tok.ValueStr);
        NextToken(Tok);

        if not NextToken(Tok) then
        begin
          Error('Expected value after .equ', Tok);
          Continue;
        end;

        var ConstVal: Cardinal;
        var IsConst:  Boolean;

        if ResolveIdentOrNumber(Tok, ConstVal, IsConst) and IsConst then
          Constants.AddOrSetValue(ConstName, ConstVal)
        else
          Error(Format('Expected integer constant value for .equ "%s"', [ConstName]), Tok);

        LineHasItem := True;
        Continue;
      end;

      var LowerIdent := LowerCase(Tok.ValueStr);

      if (LowerIdent = '.db') or (LowerIdent = '.byte') then
      begin
        var ByteList: TList<Byte> := TList<Byte>.Create;
        try
          repeat
            if not NextToken(Tok) then
              Break;

            if Tok.Kind = TTokenKind.String then
              for var i := 1 to Length(Tok.ValueStr) do
                ByteList.Add(Ord(Tok.ValueStr[i]))
            else
            begin
              var Val: Cardinal;
              var IsConst: Boolean;

              if ResolveIdentOrNumber(Tok, Val, IsConst) and IsConst then
                ByteList.Add(Byte(Val and $FF))
              else
              begin
                Error('Expected byte value, constant, or string literal in .db directive', Tok);
                Break;
              end;
            end;

            Peek := PeekToken;
            if Peek.Kind = TTokenKind.Comma then
              NextToken(Tok)
            else
              Break;
          until False;

          if ByteList.Count > 0 then
            IR.AddDataBytes(ByteList.ToArray);
        finally
          ByteList.Free;
        end;

        LineHasItem := True;
        Continue;
      end;

      if (LowerIdent = '.dw') or (LowerIdent = '.word') then
      begin
        var WordList: TList<Word> := TList<Word>.Create;
        try
          repeat
            if not NextToken(Tok) then
              Break;

            var Val: Cardinal;
            var IsConst: Boolean;

            if ResolveIdentOrNumber(Tok, Val, IsConst) and IsConst then
              WordList.Add(Word(Val and $FFFF))
            else
            begin
              Error('Expected word integer or constant in .dw directive', Tok);
              Break;
            end;

            Peek := PeekToken;
            if Peek.Kind = TTokenKind.Comma then
              NextToken(Tok)
            else
              Break;
          until False;

          if WordList.Count > 0 then
            IR.AddDataWords(WordList.ToArray);
        finally
          WordList.Free;
        end;

        LineHasItem := True;
        Continue;
      end;

      if (LowerIdent = '.dd') or (LowerIdent = '.dword') then
      begin
        var DWordList: TList<Cardinal> := TList<Cardinal>.Create;
        try
          repeat
            if not NextToken(Tok) then
              Break;

            var Val: Cardinal;
            var IsConst: Boolean;

            if ResolveIdentOrNumber(Tok, Val, IsConst) and IsConst then
              DWordList.Add(Val)
            else
            begin
              Error('Expected dword integer or constant in .dd directive', Tok);
              Break;
            end;

            Peek := PeekToken;
            if Peek.Kind = TTokenKind.Comma then
              NextToken(Tok)
            else
              Break;
          until False;

          if DWordList.Count > 0 then
            IR.AddDataDWords(DWordList.ToArray);
        finally
          DWordList.Free;
        end;

        LineHasItem := True;
        Continue;
      end;

      if (LowerIdent = '.float') or (LowerIdent = '.single') then
      begin
        var FloatList: TList<Single> := TList<Single>.Create;
        try
          repeat
            if not NextToken(Tok) then
              Break;

            var Val: Cardinal;
            var IsConst: Boolean;

            if ResolveIdentOrNumber(Tok, Val, IsConst) and IsConst then
              FloatList.Add(PSingle(@Val)^)
            else
            begin
              Error('Expected floating point number or constant in .float directive', Tok);
              Break;
            end;

            Peek := PeekToken;
            if Peek.Kind = TTokenKind.Comma then
              NextToken(Tok)
            else
              Break;
          until False;

          if FloatList.Count > 0 then
            IR.AddDataFloats(FloatList.ToArray);
        finally
          FloatList.Free;
        end;

        LineHasItem := True;
        Continue;
      end;

      if (LowerIdent = '.ds') or (LowerIdent = '.dsz') or (LowerIdent = '.str') or (LowerIdent = '.strz') or (LowerIdent = '.ascii') or (LowerIdent = '.asciiz') then
      begin
        var IsAsciiZ := (LowerIdent = '.asciiz') or (LowerIdent = '.strz') or (LowerIdent = '.dsz');
        var ByteList := TList<Byte>.Create;
        try
          repeat
            if not NextToken(Tok) then
              Break;

            if Tok.Kind = TTokenKind.String then
              for var i := 1 to Length(Tok.ValueStr) do
                ByteList.Add(Ord(Tok.ValueStr[i]))
            else
            begin
              var Val: Cardinal;
              var IsConst: Boolean;

              if ResolveIdentOrNumber(Tok, Val, IsConst) and IsConst then
                ByteList.Add(Byte(Val and $FF))
              else
              begin
                Error('Expected string literal or byte number in string directive', Tok);
                Break;
              end;
            end;

            Peek := PeekToken;
            if Peek.Kind = TTokenKind.Comma then
              NextToken(Tok)
            else
              Break;
          until False;

          if IsAsciiZ and ((ByteList.Count = 0) or (ByteList.Last <> 0)) then
            ByteList.Add(0);

          if ByteList.Count > 0 then
            IR.AddDataString(ByteList.ToArray);
        finally
          ByteList.Free;
        end;

        LineHasItem := True;
        Continue;
      end;

      if (LowerIdent = '.res') or (LowerIdent = '.resb') then
      begin
        if not NextToken(Tok) then
        begin
          Error('Expected byte count in res directive', Tok);
          Continue;
        end;

        var Val: Cardinal;
        var IsConst: Boolean;

        if ResolveIdentOrNumber(Tok, Val, IsConst) and IsConst then
          IR.AddDataReserved(Val)
        else
          Error('Expected integer number or constant for byte count in res directive', Tok);

        LineHasItem := True;
        Continue;
      end;

      if LowerIdent = '.align' then
      begin
        if not NextToken(Tok) then
        begin
          Error('Expected alignment boundary in align directive', Tok);
          Continue;
        end;

        var Boundary: Cardinal;
        var IsConst:  Boolean;

        if not ResolveIdentOrNumber(Tok, Boundary, IsConst) or not IsConst or (Boundary = 0) then
        begin
          Error('Expected positive integer for alignment boundary', Tok);
          Continue;
        end;

        var PadByte: Byte := 0;
        Peek := PeekToken;

        if Peek.Kind = TTokenKind.Comma then
        begin
          NextToken(Tok);

          if NextToken(Tok) then
          begin
            var PadVal: Cardinal;

            if ResolveIdentOrNumber(Tok, PadVal, IsConst) and IsConst then
              PadByte := Byte(PadVal and $FF)
            else
              Error('Expected byte value for align padding', Tok);
          end;
        end;

        IR.AddAlign(Boundary, PadByte);
        LineHasItem := True;
        Continue;
      end;

      if (LowerIdent = '.base') or (LowerIdent = '.org') then
      begin
        var Val: Cardinal;
        var IsConst: Boolean;

        if not NextToken(Tok) or not ResolveIdentOrNumber(Tok, Val, IsConst) or not IsConst then
        begin
          Error('Expected base address integer or constant in .base directive', Tok);
          Continue;
        end;

        if Assigned(AROMHeader) then
          AROMHeader^.UserAddress := Val;

        LineHasItem := True;
        Continue;
      end;

      if (LowerIdent = '.heap') or (LowerIdent = '.heapsize') then
      begin
        var Val: Cardinal;
        var IsConst: Boolean;

        if not NextToken(Tok) or not ResolveIdentOrNumber(Tok, Val, IsConst) or not IsConst then
        begin
          Error('Expected integer size or constant in .heap directive', Tok);
          Continue;
        end;

        if Assigned(AROMHeader) then
          AROMHeader^.HeapSize := Val;

        LineHasItem := True;
        Continue;
      end;

      if (LowerIdent = '.stack') or (LowerIdent = '.stacksize') then
      begin
        var Val: Cardinal;
        var IsConst: Boolean;

        if not NextToken(Tok) or not ResolveIdentOrNumber(Tok, Val, IsConst) or not IsConst then
        begin
          Error('Expected integer size or constant in .stack directive', Tok);
          Continue;
        end;

        if Assigned(AROMHeader) then
          AROMHeader^.StackSize := Val;

        LineHasItem := True;
        Continue;
      end;

      if LowerIdent = '.name' then
      begin
        if not NextToken(Tok) or (Tok.Kind <> TTokenKind.String) then
        begin
          Error('Expected quoted string for .name directive', Tok);
          Continue;
        end;

        if Assigned(AROMHeader) then
          AROMHeader^.ROM.Name := Tok.ValueStr;

        LineHasItem := True;
        Continue;
      end;

      if LowerIdent = '.version' then
      begin
        var MajorVal, MinorVal: Cardinal;
        var IsConst: Boolean;

        if not NextToken(Tok) or not ResolveIdentOrNumber(Tok, MajorVal, IsConst) or not IsConst then
        begin
          Error('Expected major version number in .version directive', Tok);
          Continue;
        end;

        if not NextToken(Tok) or (Tok.Kind <> TTokenKind.Comma) then
        begin
          Error('Expected comma between major and minor version', Tok);
          Continue;
        end;

        if not NextToken(Tok) or not ResolveIdentOrNumber(Tok, MinorVal, IsConst) or not IsConst then
        begin
          Error('Expected minor version number in .version directive', Tok);
          Continue;
        end;

        if Assigned(AROMHeader) then
        begin
          AROMHeader^.ROM.Major := Word(MajorVal and $FFFF);
          AROMHeader^.ROM.Minor := Word(MinorVal and $FFFF);
        end;

        LineHasItem := True;
        Continue;
      end;

      if LowerIdent = '.target' then
      begin
        if not NextToken(Tok) or (Tok.Kind <> TTokenKind.String) then
        begin
          Error('Expected quoted target name string in .target directive', Tok);
          Continue;
        end;

        if Assigned(AROMHeader) then
          AROMHeader^.Harness.Name := Tok.ValueStr;

        Peek := PeekToken;

        if Peek.Kind = TTokenKind.Comma then
        begin
          NextToken(Tok);

          var MajorVal, MinorVal: Cardinal;
          var IsConst: Boolean;

          if NextToken(Tok) and ResolveIdentOrNumber(Tok, MajorVal, IsConst) and IsConst then
          begin
            if Assigned(AROMHeader) then
              AROMHeader^.Harness.Major := Word(MajorVal and $FFFF);

            Peek := PeekToken;
            if Peek.Kind = TTokenKind.Comma then
            begin
              NextToken(Tok);

              if NextToken(Tok) and ResolveIdentOrNumber(Tok, MinorVal, IsConst) and IsConst then
              begin
                if Assigned(AROMHeader) then
                  AROMHeader^.Harness.Minor := Word(MinorVal and $FFFF);
              end;
            end;
          end;
        end;

        LineHasItem := True;
        Continue;
      end;

      if (LowerIdent = '.embed') or (LowerIdent = '.includeb') then
      begin
        if not NextToken(Tok) then
        begin
          Error('Expected filename string in .embed directive', Tok);
          Continue;
        end;

        if Tok.Kind <> TTokenKind.String then
        begin
          Error('Expected quoted filename string in .embed directive', Tok);
          Continue;
        end;

        var RelFileName := Tok.ValueStr;
        var FullFilePath := RelFileName;

        if (Length(ABasePath) > 0) and not TPath.IsPathRooted(RelFileName) then
          FullFilePath := TPath.Combine(ABasePath, RelFileName);

        if not FileExists(FullFilePath) then
        begin
          Error(Format('Binary file not found: "%s"', [FullFilePath]), Tok);
          Continue;
        end;

        try
          var FileStream := TFileStream.Create(FullFilePath, fmOpenRead or fmShareDenyNone);
          try
            var FileBytes: TBytes;
            SetLength(FileBytes, FileStream.Size);

            if FileStream.Size > 0 then
              FileStream.ReadBuffer(FileBytes[0], FileStream.Size);

            IR.AddEmbed(RelFileName, FileBytes);
          finally
            FileStream.Free;
          end;
        except
          on E: Exception do
            Error(Format('Error reading binary file "%s": %s', [FullFilePath, E.Message]), Tok);
        end;

        LineHasItem := True;
        Continue;
      end;

      if LowerIdent = '.include' then
      begin
        if not NextToken(Tok) then
        begin
          Error('Expected filename string in .include directive', Tok);
          Continue;
        end;

        if Tok.Kind <> TTokenKind.String then
        begin
          Error('Expected quoted filename string in .include directive', Tok);
          Continue;
        end;

        var RelFileName := Tok.ValueStr;
        var FullFilePath := RelFileName;

        if (Length(EffectiveBase) > 0) and not TPath.IsPathRooted(RelFileName) then
          FullFilePath := TPath.Combine(EffectiveBase, RelFileName);

        if not FileExists(FullFilePath) then
        begin
          Error(Format('Include file not found: "%s"', [FullFilePath]), Tok);
          Continue;
        end;

        var IncStack  := AIncludeStack;
        var OwnsStack := False;

        if IncStack = nil then
        begin
          IncStack := TStringList.Create;
          OwnsStack := True;
        end;

        try
          var CanonicalPath := LowerCase(TPath.GetFullPath(FullFilePath));

          if IncStack.IndexOf(CanonicalPath) >= 0 then
          begin
            Error(Format('Circular include detected for "%s"', [FullFilePath]), Tok);
            Continue;
          end;

          IncStack.Add(CanonicalPath);
          try
            var SubSource := TFile.ReadAllText(FullFilePath);
            var DummyErrors: TStrings := nil;

            var SubIR := Parse(SubSource, DummyErrors, FullFilePath, ExtractFilePath(FullFilePath), IncStack, Errors, AROMHeader);
            try
              for var j := 0 to SubIR.Count - 1 do
                IR.Add(SubIR[j]);
            finally
              SubIR.Free;
            end;
          finally
            IncStack.Delete(IncStack.IndexOf(CanonicalPath));
          end;
        finally
          if OwnsStack then
            IncStack.Free;
        end;

        LineHasItem := True;
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
          IR.AddInstr(OpCode);

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
            IR.AddInstrR1(OpCode, RegA);
        end;

        TCPUInstruction.TParameters.Imm:
        begin
          var OpVal:   Cardinal;
          var OpLabel: TLabelString;
          var IsConst: Boolean;

          if ParseOperand(OpVal, OpLabel, IsConst) then
          begin
            if IsConst then
              IR.AddInstrImm(OpCode, OpVal)
            else
            begin
              var Idx  := IR.AddInstrImm(OpCode, OpLabel);
              var Item := IR.Items[Idx];

              Item.Offset.Delta := Integer(OpVal);

              IR.Items[Idx] := Item;
            end;
          end
          else
            Error('Expected immediate value or label target', Tok);
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

          var OpVal:   Cardinal;
          var OpLabel: TLabelString;
          var IsConst: Boolean;

          if ParseOperand(OpVal, OpLabel, IsConst) then
          begin
            if IsConst then
              IR.AddInstrR1Imm(OpCode, RegA, OpVal)
            else
            begin
              var Idx := IR.AddInstrR1Imm(OpCode, RegA, OpLabel);
              var Item := IR.Items[Idx];

              Item.Offset.Delta := Integer(OpVal);

              IR.Items[Idx] := Item;
            end;
          end
          else
            Error('Expected target label or immediate', Tok);
        end;

        TCPUInstruction.TParameters.RImm:
        begin
          var RegB: TRegisters.ID;
          Peek := PeekToken;

          if (Peek.Kind = TTokenKind.Identifier) and ParseRegister(Peek, RegB) then
          begin
            NextToken(Tok);
            IR.AddInstrRImm(OpCode, RegB);
          end
          else
          begin
            var OpVal:   Cardinal;
            var OpLabel: TLabelString;
            var IsConst: Boolean;

            if ParseOperand(OpVal, OpLabel, IsConst) then
            begin
              if IsConst then
                IR.AddInstrRImm(OpCode, OpVal)
              else
              begin
                var Idx := IR.AddInstrRImm(OpCode, OpLabel);
                var Item := IR.Items[Idx];

                Item.Imm.Delta := Integer(OpVal);

                IR.Items[Idx] := Item;
              end;
            end
            else
              Error('Invalid operand for RImm instruction', Tok);
          end;
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
            Error(Format('Invalid destination register "%s"', [Tok.ValueStr]), Tok);
            Continue;
          end;

          if not NextToken(Tok) or (Tok.Kind <> TTokenKind.Comma) then
          begin
            Error('Expected comma', Tok);
            Continue;
          end;

          var RegB: TRegisters.ID;
          Peek := PeekToken;

          if (Peek.Kind = TTokenKind.Identifier) and ParseRegister(Peek, RegB) then
          begin
            NextToken(Tok);
            IR.AddInstrR1R2(OpCode, RegA, RegB);
          end
          else
          begin
            var OpVal:   Cardinal;
            var OpLabel: TLabelString;
            var IsConst: Boolean;

            if ParseOperand(OpVal, OpLabel, IsConst) then
            begin
              if IsConst then
                IR.AddInstrR1Imm(OpCode, RegA, OpVal)
              else
              begin
                var Idx  := IR.AddInstrR1Imm(OpCode, RegA, OpLabel);
                var Item := IR.Items[Idx];

                Item.Imm.Delta := Integer(OpVal);

                IR.Items[Idx] := Item;
              end;
            end
            else
              Error('Invalid second operand for R1R2 instruction', Tok);
          end;
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
            Error(Format('Invalid destination register "%s"', [Tok.ValueStr]), Tok);
            Continue;
          end;

          if not NextToken(Tok) or (Tok.Kind <> TTokenKind.Comma) then
          begin
            Error('Expected comma', Tok);
            Continue;
          end;

          if not NextToken(Tok) then
          begin
            Error('Expected base register', Tok);
            Continue;
          end;

          var RegB: TRegisters.ID;
          if not ParseRegister(Tok, RegB) then
          begin
            Error(Format('Invalid base register "%s"', [Tok.ValueStr]), Tok);
            Continue;
          end;

          if not NextToken(Tok) or (Tok.Kind <> TTokenKind.Comma) then
          begin
            Error('Expected comma', Tok);
            Continue;
          end;

          var OpVal:   Cardinal;
          var OpLabel: TLabelString;
          var IsConst: Boolean;

          if ParseOperand(OpVal, OpLabel, IsConst) then
          begin
            if IsConst then
              IR.AddInstrR1R2Imm(OpCode, RegA, RegB, OpVal)
            else
            begin
              var Idx  := IR.AddInstrR1R2Imm(OpCode, RegA, RegB, OpLabel);
              var Item := IR.Items[Idx];

              Item.Offset.Delta := Integer(OpVal);

              IR.Items[Idx] := Item;
            end;
          end
          else
            Error('Invalid offset in 3-operand instruction', Tok);
        end;

        TCPUInstruction.TParameters.Rn:
        begin
          if not NextToken(Tok) then
          begin
            Error('Expected count operand', Tok);
            Continue;
          end;

          var Val: Cardinal;
          var IsConst: Boolean;

          if ResolveIdentOrNumber(Tok, Val, IsConst) and IsConst then
            IR.AddInstrRn(OpCode, Val)
          else
            Error('Expected integer constant (0..15) for Rn parameter', Tok);
        end;

        TCPUInstruction.TParameters.RnImm:
        begin
          if not NextToken(Tok) then
          begin
            Error('Expected count operand', Tok);
            Continue;
          end;

          var CountVal: Cardinal;
          var IsConst: Boolean;

          if not (ResolveIdentOrNumber(Tok, CountVal, IsConst) and IsConst) then
          begin
            Error('Expected integer constant (0..15) for count', Tok);
            Continue;
          end;

          if not NextToken(Tok) or (Tok.Kind <> TTokenKind.Comma) then
          begin
            Error('Expected comma', Tok);
            Continue;
          end;

          var OpVal:   Cardinal;
          var OpLabel: TLabelString;

          if ParseOperand(OpVal, OpLabel, IsConst) then
          begin
            if IsConst then
              IR.AddInstrRnImm(OpCode, CountVal, OpVal)
            else
            begin
              var Idx := IR.AddInstrRnImm(OpCode, CountVal, 0);
              var Item := IR.Items[Idx];

              Item.Offset.&Label := OpLabel;
              Item.Offset.Delta  := Integer(OpVal);

              IR.Items[Idx] := Item;
            end;
          end
          else
            Error('Expected immediate operand', Tok);
        end;
      end;

      LineHasItem := True;
    end;
  finally
    Constants.Free;
  end;

  AErrors := Errors;
  Result  := IR;
end;
{$ENDREGION}

class function TAssembler.ParseFile(const AFileName: String; out AErrors: TStrings; AROMHeader: PROMHeader): TIRList;
var
  SourceText: String;
begin
  if not FileExists(AFileName) then
  begin
    AErrors := TStringList.Create;
    AErrors.Add(Format('File not found: "%s"', [AFileName]));

    Exit(TIRList.Create);
  end;

  SourceText := TFile.ReadAllText(AFileName);
  Result     := Parse(SourceText, AErrors, AFileName, ExtractFilePath(AFileName), nil, nil, AROMHeader);
end;
{$ENDREGION}

end.
