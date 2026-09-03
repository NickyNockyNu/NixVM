{
  NixVM.Tools.Compiler.Lexer.pas
    Pascal lexer / tokenizer

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

unit NixVM.Tools.Compiler.Lexer;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  {$REGION 'Lexer'}
  TLexer = class
  type
    {$REGION 'Token'}
    TToken = record
    type
      {$REGION 'Token Kinds'}
      TKind = (
        // Special
        EOF,
        Unknown,

        // Literals
        IntegerLiteral,
        FloatLiteral,
        StringLiteral,
        CharLiteral,

        // Identifiers
        Identifier,

        // Program structure
        &Program,
        &Unit,
        &Uses,
        &Interface,
        &Implementation,
        &Initialization,

        Directive,

        // Declarations
        &Const,
        &Type,
        &Var,
        &Out,
        &Procedure,
        &Function,
        &Set,
        &In,

        // Property
        &Property,
        &Read,
        &Write,

        // Visiblilty
        &Public,
        &Private,

        // Method directives
        Syscall,
        Interrupt,
        &VarArgs,
        &Forward,

        // Self reference
        &Self,

        // Blocks & scopes
        &Begin,
        &End,
        &With,

        // Control flow
        &If,
        &Then,
        &Else,
        &Case,
        &Of,
        &While,
        &Do,
        &Repeat,
        &Until,
        &For,
        &To,
        &Downto,
        &Break,
        &Continue,
        &Exit,
        &Raise,

        // Types & structures
        &Record,
        &Array,
        &Packed,
        &Pointer,
        &String,
        &Integer,
        &Single,
        &Boolean,
        &Byte,
        &Word,
        &Cardinal,
        &ShortInt,
        &SmallInt,
        &Char,

        // Constants & boolean
        &True,
        &False,
        &Nil,

        // Operators as keywords
        &And,
        &Or,
        &Xor,
        &Not,
        &Div,
        &Mod,
        &Shl,
        &Shr,
        Sar,

        // Arithmetic
        Plus,          // +
        Minus,         // -
        Star,          // *
        Slash,         // /

        // Assignment
        Assign,        // :=
        PlusAssign,    // +=
        MinusAssign,   // -=
        MulAssign,     // *=
        DivAssign,     // /=

        // Relational / comparison
        Equal,         // =
        NotEqual,      // <>
        Less,          // <
        LessEqual,     // <=
        Greater,       // >
        GreaterEqual,  // >=

        // Delimiters & punctuation
        Comma,         // ,
        Semicolon,     // ;
        Colon,         // :
        Dot,           // .
        DotDot,        // ..
        Caret,         // ^
        At,            // @
        LParen,        // (
        RParen,        // )
        LBracket,      // [
        RBracket       // ]
      );
      {$ENDREGION}
    public
      Kind:       TKind;
      ValueStr:   String;
      ValueInt:   Cardinal;
      ValueFloat: Single;
      Line:       Integer;
      Col:        Integer;

      function ToString: String;
    end;
    {$ENDREGION}
  private
    FSource:    String;
    FFileName:  String;
    FSrcPos:    Integer;
    FSrcLen:    Integer;
    FCurLine:   Integer;
    FCurCol:    Integer;
    FErrors:    TStrings;
    FOwnsErrors: Boolean;

    class var FKeywords: TDictionary<String, TToken.TKind>;

    class constructor Create;
    class destructor  Destroy;

    function IsEOF: Boolean; inline;

    function PeekChar(AOffset: Integer = 0): Char; inline;
    function NextChar: Char; inline;

    procedure SkipWhitespaceAndComments;

    function  ScanNumber: TToken;
    function  ScanStringOrChar: TToken;
    function  ScanIdentifierOrKeyword: TToken;

    procedure Error(const AMsg: String; ALine, ACol: Integer);
  public
    constructor Create(const ASource: String; const AFileName: String = ''; AErrors: TStrings = nil);
    destructor  Destroy; override;

    function NextToken: TToken;
    function TokenizeAll: TList<TToken>;

    property Source: String read FSource;

    property FileName: String  read FFileName;
    property Line:     Integer read FCurLine;
    property Col:      Integer read FCurCol;

    property Errors: TStrings read FErrors;
  end;
  {$ENDREGION}

implementation

{$REGION 'Token'}
function TLexer.TToken.ToString: String;
begin
  case Kind of
    TToken.TKind.IntegerLiteral: Result := Format('Integer(%d)',  [ValueInt]);
    TToken.TKind.FloatLiteral:   Result := Format('Float(%f)',    [ValueFloat]);
    TToken.TKind.StringLiteral:  Result := Format('String("%s")', [ValueStr]);
    TToken.TKind.CharLiteral:    Result := Format('Char(''%s'')', [ValueStr]);
    TToken.TKind.Identifier:     Result := Format('Ident(%s)',    [ValueStr]);
  else
    Result := ValueStr;
  end;
end;
{$ENDREGION}

{$REGION 'Keywords Table'}
class constructor TLexer.Create;
begin
  FKeywords := TDictionary<String, TToken.TKind>.Create;

  FKeywords.Add('program',        TToken.TKind.Program);
  FKeywords.Add('unit',           TToken.TKind.Unit);
  FKeywords.Add('uses',           TToken.TKind.Uses);
  FKeywords.Add('interface',      TToken.TKind.Interface);
  FKeywords.Add('implementation', TToken.TKind.Implementation);
  FKeywords.Add('initialization', TToken.TKind.Initialization);

  FKeywords.Add('const',          TToken.TKind.Const);
  FKeywords.Add('type',           TToken.TKind.Type);
  FKeywords.Add('var',            TToken.TKind.Var);
  FKeywords.Add('out',            TToken.TKind.Out);
  FKeywords.Add('procedure',      TToken.TKind.Procedure);
  FKeywords.Add('function',       TToken.TKind.Function);
  FKeywords.Add('set',            TToken.TKind.Set);
  FKeywords.Add('in',             TToken.TKind.In);
  FKeywords.Add('property',       TToken.TKind.Property);
  FKeywords.Add('read',           TToken.TKind.Read);
  FKeywords.Add('write',          TToken.TKind.Write);
  FKeywords.Add('public',         TToken.TKind.Public);
  FKeywords.Add('private',        TToken.TKind.Private);

  FKeywords.Add('syscall',        TToken.TKind.SysCall);
  FKeywords.Add('interrupt',      TToken.TKind.Interrupt);
  FKeywords.Add('varargs',        TToken.TKind.VarArgs);
  FKeywords.Add('forward',        TToken.TKind.Forward);

  FKeywords.Add('self',           TToken.TKind.Self);

  FKeywords.Add('begin',          TToken.TKind.Begin);
  FKeywords.Add('end',            TToken.TKind.End);
  FKeywords.Add('with',           TToken.TKind.With);

  FKeywords.Add('if',             TToken.TKind.If);
  FKeywords.Add('then',           TToken.TKind.Then);
  FKeywords.Add('else',           TToken.TKind.Else);
  FKeywords.Add('case',           TToken.TKind.Case);
  FKeywords.Add('of',             TToken.TKind.Of);
  FKeywords.Add('while',          TToken.TKind.While);
  FKeywords.Add('do',             TToken.TKind.Do);
  FKeywords.Add('repeat',         TToken.TKind.Repeat);
  FKeywords.Add('until',          TToken.TKind.Until);
  FKeywords.Add('for',            TToken.TKind.For);
  FKeywords.Add('to',             TToken.TKind.To);
  FKeywords.Add('downto',         TToken.TKind.Downto);
  FKeywords.Add('break',          TToken.TKind.Break);
  FKeywords.Add('continue',       TToken.TKind.Continue);
  FKeywords.Add('exit',           TToken.TKind.Exit);
  FKeywords.Add('raise',          TToken.TKind.Raise);

  FKeywords.Add('record',         TToken.TKind.Record);
  FKeywords.Add('array',          TToken.TKind.Array);
  FKeywords.Add('packed',         TToken.TKind.Packed);
  FKeywords.Add('pointer',        TToken.TKind.Pointer);
  FKeywords.Add('string',         TToken.TKind.String);
  FKeywords.Add('integer',        TToken.TKind.Integer);
  FKeywords.Add('single',         TToken.TKind.Single);
  FKeywords.Add('boolean',        TToken.TKind.Boolean);
  FKeywords.Add('byte',           TToken.TKind.Byte);
  FKeywords.Add('word',           TToken.TKind.Word);
  FKeywords.Add('shortint',       TToken.TKind.ShortInt);
  FKeywords.Add('smallint',       TToken.TKind.SmallInt);
  FKeywords.Add('char',           TToken.TKind.Char);

  FKeywords.Add('true',           TToken.TKind.True);
  FKeywords.Add('false',          TToken.TKind.False);
  FKeywords.Add('nil',            TToken.TKind.Nil);

  FKeywords.Add('and',            TToken.TKind.And);
  FKeywords.Add('or',             TToken.TKind.Or);
  FKeywords.Add('xor',            TToken.TKind.Xor);
  FKeywords.Add('not',            TToken.TKind.Not);
  FKeywords.Add('div',            TToken.TKind.Div);
  FKeywords.Add('mod',            TToken.TKind.Mod);
  FKeywords.Add('shl',            TToken.TKind.Shl);
  FKeywords.Add('shr',            TToken.TKind.Shr);
  FKeywords.Add('sar',            TToken.TKind.Sar);
end;

class destructor TLexer.Destroy;
begin
  FKeywords.Free;
end;
{$ENDREGION}

{$REGION 'Lexer'}
constructor TLexer.Create(const ASource: String; const AFileName: String; AErrors: TStrings);
begin
  inherited Create;

  FSource     := ASource;
  FFileName   := AFileName;
  FSrcPos     := 1;
  FSrcLen     := Length(ASource);
  FCurLine    := 1;
  FCurCol     := 1;
  FOwnsErrors := (AErrors = nil);

  if FOwnsErrors then
    FErrors := TStringList.Create
  else
    FErrors := AErrors;
end;

destructor TLexer.Destroy;
begin
  if FOwnsErrors then
    FErrors.Free;

  inherited;
end;

function TLexer.IsEOF: Boolean;
begin
  Result := (FSrcPos > FSrcLen);
end;

function TLexer.PeekChar(AOffset: Integer): Char;
begin
  if FSrcPos + AOffset <= FSrcLen then
    Result := FSource[FSrcPos + AOffset]
  else
    Result := #0;
end;

function TLexer.NextChar: Char;
begin
  if FSrcPos <= FSrcLen then
  begin
    Result := FSource[FSrcPos];

    Inc(FSrcPos);
    Inc(FCurCol);
  end
  else
    Result := #0;
end;

procedure TLexer.Error(const AMsg: String; ALine, ACol: Integer);
begin
  if Length(FFileName) > 0 then
    FErrors.Add(Format('[%s] Line %d, Col %d: %s', [ExtractFileName(FFileName), ALine, ACol, AMsg]))
  else
    FErrors.Add(Format('Line %d, Col %d: %s', [ALine, ACol, AMsg]));
end;

procedure TLexer.SkipWhitespaceAndComments;
begin
  while not IsEOF do
  begin
    var C := PeekChar;

    if CharInSet(C, [' ', #9]) then
    begin
      NextChar;
      Continue;
    end;

    if CharInSet(C, [#10, #13]) then
    begin
      if (C = #13) and (PeekChar(1) = #10) then
        NextChar;

      NextChar;
      Inc(FCurLine);
      FCurCol := 1;

      Continue;
    end;

    if (C = '/') and (PeekChar(1) = '/') then
    begin
      while not IsEOF and not CharInSet(PeekChar, [#10, #13]) do
        NextChar;

      Continue;
    end;

    if C = '{' then
    begin
      if PeekChar(1) = '$' then
        Break;

      var StartLine := FCurLine;
      var StartCol  := FCurCol;

      NextChar;

      while not IsEOF and (PeekChar <> '}') do
      begin
        if CharInSet(PeekChar, [#10, #13]) then
        begin
          if (PeekChar = #13) and (PeekChar(1) = #10) then
            NextChar;

          NextChar;
          Inc(FCurLine);
          FCurCol := 1;
        end
        else
          NextChar;
      end;

      if IsEOF then
      begin
        Error('Unterminated block comment "{"', StartLine, StartCol);
        Break;
      end;

      NextChar;
      Continue;
    end;

    if (C = '(') and (PeekChar(1) = '*') then
    begin
      var StartLine := FCurLine;
      var StartCol  := FCurCol;

      NextChar;
      NextChar;

      while not IsEOF and not ((PeekChar = '*') and (PeekChar(1) = ')')) do
      begin
        if CharInSet(PeekChar, [#10, #13]) then
        begin
          if (PeekChar = #13) and (PeekChar(1) = #10) then
            NextChar;

          NextChar;
          Inc(FCurLine);
          FCurCol := 1;
        end
        else
          NextChar;
      end;

      if IsEOF then
      begin
        Error('Unterminated block comment "(*"', StartLine, StartCol);
        Break;
      end;

      NextChar;
      NextChar;
      Continue;
    end;

    Break;
  end;
end;

function TLexer.ScanNumber: TToken;
var
  NumStr:     String;
  IsFloat:    Boolean;
  Multiplier: Cardinal;
  Code:       Integer;
  SngVal:     Single;
  StartCol:   Integer;
begin
  Result      := Default(TToken);
  StartCol    := FCurCol;
  Result.Line := FCurLine;
  Result.Col  := StartCol;

  NumStr     := '';
  IsFloat    := False;
  Multiplier := 1;

  if PeekChar = '$' then
  begin
    NextChar;

    while CharInSet(PeekChar, ['0'..'9', 'a'..'f', 'A'..'F']) do
      NumStr := NumStr + NextChar;

    if Length(NumStr) = 0 then
    begin
      Error('Expected hex digits after "$"', FCurLine, StartCol);
      Result.Kind := TToken.TKind.Unknown;

      Exit;
    end;

    if CharInSet(PeekChar, ['k', 'K', 'm', 'M']) then
    begin
      if UpCase(PeekChar) = 'K' then
        Multiplier := 1024
      else
        Multiplier := 1024 * 1024;

      NextChar;
    end;

    Val('$' + NumStr, Result.ValueInt, Code);

    Result.ValueInt := Result.ValueInt * Multiplier;
    Result.Kind     := TToken.TKind.IntegerLiteral;
    Result.ValueStr := '$' + NumStr;

    Exit;
  end;

  if PeekChar = '%' then
  begin
    NextChar;

    while CharInSet(PeekChar, ['0', '1']) do
      NumStr := NumStr + NextChar;

    if Length(NumStr) = 0 then
    begin
      Error('Expected binary digits (0 or 1) after "%"', FCurLine, StartCol);
      Result.Kind := TToken.TKind.Unknown;

      Exit;
    end;

    if CharInSet(PeekChar, ['k', 'K', 'm', 'M']) then
    begin
      if UpCase(PeekChar) = 'K' then
        Multiplier := 1024
      else
        Multiplier := 1024 * 1024;

      NextChar;
    end;

    Result.ValueInt := 0;

    for var i := 1 to Length(NumStr) do
      Result.ValueInt := (Result.ValueInt shl 1) or Cardinal(Ord(NumStr[i]) - Ord('0'));

    Result.ValueInt := Result.ValueInt * Multiplier;
    Result.Kind     := TToken.TKind.IntegerLiteral;
    Result.ValueStr := '%' + NumStr;

    Exit;
  end;

  while CharInSet(PeekChar, ['0'..'9']) do
    NumStr := NumStr + NextChar;

  if (PeekChar = '.') and (PeekChar(1) <> '.') and CharInSet(PeekChar(1), ['0'..'9']) then
  begin
    IsFloat := True;
    NumStr  := NumStr + NextChar;

    while CharInSet(PeekChar, ['0'..'9']) do
      NumStr := NumStr + NextChar;

    if CharInSet(PeekChar, ['e', 'E']) then
    begin
      NumStr := NumStr + NextChar;

      if CharInSet(PeekChar, ['+', '-']) then
        NumStr := NumStr + NextChar;

      while CharInSet(PeekChar, ['0'..'9']) do
        NumStr := NumStr + NextChar;
    end;
  end;

  if CharInSet(PeekChar, ['k', 'K', 'm', 'M']) then
  begin
    if UpCase(PeekChar) = 'K' then
      Multiplier := 1024
    else
      Multiplier := 1024 * 1024;

    NextChar;
  end;

  if IsFloat then
  begin
    Val(NumStr, SngVal, Code);

    if Code = 0 then
    begin
      Result.Kind       := TToken.TKind.FloatLiteral;
      Result.ValueFloat := SngVal * Multiplier;
      Result.ValueStr   := NumStr;
    end
    else
    begin
      Error(Format('Malformed float literal "%s"', [NumStr]), FCurLine, StartCol);
      Result.Kind := TToken.TKind.Unknown;
    end;
  end
  else
  begin
    Val(NumStr, Result.ValueInt, Code);

    if Code = 0 then
    begin
      Result.Kind     := TToken.TKind.IntegerLiteral;
      Result.ValueInt := Result.ValueInt * Multiplier;
      Result.ValueStr := NumStr;
    end
    else
    begin
      Error(Format('Malformed integer literal "%s"', [NumStr]), FCurLine, StartCol);
      Result.Kind := TToken.TKind.Unknown;
    end;
  end;
end;

function TLexer.ScanStringOrChar: TToken;
var
  FullStr:  String;
  StartCol: Integer;
begin
  Result      := Default(TToken);
  StartCol    := FCurCol;
  Result.Line := FCurLine;
  Result.Col  := StartCol;
  FullStr     := '';

  while not IsEOF and ((PeekChar = '''') or (PeekChar = '#')) do
  begin
    if PeekChar = '''' then
    begin
      NextChar;

      while not IsEOF do
      begin
        var C := NextChar;

        if C = '''' then
        begin
          if PeekChar = '''' then
          begin
            FullStr := FullStr + '''';
            NextChar;
          end
          else
            Break;
        end
        else if CharInSet(C, [#10, #13]) then
        begin
          Error('Unterminated string literal', FCurLine, StartCol);
          Result.Kind := TToken.TKind.Unknown;

          Exit;
        end
        else
          FullStr := FullStr + C;
      end;
    end

    else if PeekChar = '#' then
    begin
      NextChar;

      var CodeStr := '';

      if PeekChar = '$' then
      begin
        CodeStr := '$';

        NextChar;

        while CharInSet(PeekChar, ['0'..'9', 'a'..'f', 'A'..'F']) do
          CodeStr := CodeStr + NextChar;
      end
      else
        while CharInSet(PeekChar, ['0'..'9']) do
          CodeStr := CodeStr + NextChar;

      var CharCode: Cardinal;
      var CodeErr:  Integer;

      Val(CodeStr, CharCode, CodeErr);

      if (CodeErr = 0) and (CharCode <= 255) then
        FullStr := FullStr + Char(CharCode)
      else
        Error(Format('Invalid character code "#%s"', [CodeStr]), FCurLine, StartCol);
    end;
  end;

  Result.ValueStr := FullStr;

  if Length(FullStr) = 1 then
    Result.Kind := TToken.TKind.CharLiteral
  else
    Result.Kind := TToken.TKind.StringLiteral;
end;

function TLexer.ScanIdentifierOrKeyword: TToken;
var
  IdentStr: String;
  KwKind:   TToken.TKind;
  StartCol: Integer;
begin
  Result      := Default(TToken);
  StartCol    := FCurCol;
  Result.Line := FCurLine;
  Result.Col  := StartCol;
  IdentStr    := '';

  while not IsEOF and CharInSet(PeekChar, ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
    IdentStr := IdentStr + NextChar;

  Result.ValueStr := IdentStr;

  if FKeywords.TryGetValue(LowerCase(IdentStr), KwKind) then
    Result.Kind := KwKind
  else
    Result.Kind := TToken.TKind.Identifier;
end;

function TLexer.NextToken: TToken;
begin
  SkipWhitespaceAndComments;

  if IsEOF then
  begin
    Result.Kind     := TToken.TKind.EOF;
    Result.ValueStr := '';
    Result.Line     := FCurLine;
    Result.Col      := FCurCol;

    Exit;
  end;

  var StartCol := FCurCol;
  var StartLine := FCurLine;
  var C := PeekChar;

  if (C = '{') and (PeekChar(1) = '$') then
  begin
    NextChar;
    NextChar;

    var DirStr := '';

    while not IsEOF and (PeekChar <> '}') do
    begin
      if CharInSet(PeekChar, [#10, #13]) then
      begin
        if (PeekChar = #13) and (PeekChar(1) = #10) then
          NextChar;

        NextChar;
        Inc(FCurLine);
        FCurCol := 1;
      end
      else
        DirStr := DirStr + NextChar;
    end;

    if not IsEOF then
      NextChar;

    Result          := Default(TToken);
    Result.Kind     := TToken.TKind.Directive;
    Result.ValueStr := Trim(DirStr);
    Result.Line     := StartLine;
    Result.Col      := StartCol;

    Exit;
  end;

  if (C = '$') or (C = '%') or CharInSet(C, ['0'..'9']) then
    Exit(ScanNumber);

  if (C = '''') or (C = '#') then
    Exit(ScanStringOrChar);

  if CharInSet(C, ['a'..'z', 'A'..'Z', '_']) then
    Exit(ScanIdentifierOrKeyword);

  NextChar;

  Result          := Default(TToken);
  Result.Line     := StartLine;
  Result.Col      := StartCol;
  Result.ValueStr := C;

  case C of
    '+':
      if PeekChar = '=' then
      begin
        NextChar;

        Result.Kind     := TToken.TKind.PlusAssign;
        Result.ValueStr := '+=';
      end
      else
        Result.Kind := TToken.TKind.Plus;

    '-':
      if PeekChar = '=' then
      begin
        NextChar;

        Result.Kind     := TToken.TKind.MinusAssign;
        Result.ValueStr := '-=';
      end
      else
        Result.Kind := TToken.TKind.Minus;

    '*':
      if PeekChar = '=' then
      begin
        NextChar;

        Result.Kind     := TToken.TKind.MulAssign;
        Result.ValueStr := '*='; end
      else
        Result.Kind := TToken.TKind.Star;

    '/':
      if PeekChar = '=' then
      begin
        NextChar;

        Result.Kind := TToken.TKind.DivAssign;
        Result.ValueStr := '/=';
      end
      else
        Result.Kind := TToken.TKind.Slash;

    ':':
      if PeekChar = '=' then
      begin
        NextChar;

        Result.Kind     := TToken.TKind.Assign;
        Result.ValueStr := ':=';
      end
      else
        Result.Kind := TToken.TKind.Colon;

    '=': Result.Kind := TToken.TKind.Equal;

    '<':
      if PeekChar = '>' then
      begin
        NextChar;

        Result.Kind     := TToken.TKind.NotEqual;
        Result.ValueStr := '<>';
      end
      else if PeekChar = '=' then
      begin
        NextChar;

        Result.Kind     := TToken.TKind.LessEqual;
        Result.ValueStr := '<=';
      end
      else
        Result.Kind := TToken.TKind.Less;

    '>':
      if PeekChar = '=' then
      begin
        NextChar;

        Result.Kind := TToken.TKind.GreaterEqual; Result.ValueStr := '>='; end
      else
        Result.Kind := TToken.TKind.Greater;

    '.':
      if PeekChar = '.' then
      begin
        NextChar;

        Result.Kind     := TToken.TKind.DotDot;
        Result.ValueStr := '..';
      end
      else
        Result.Kind := TToken.TKind.Dot;

    ',': Result.Kind := TToken.TKind.Comma;
    ';': Result.Kind := TToken.TKind.Semicolon;
    '^': Result.Kind := TToken.TKind.Caret;
    '@': Result.Kind := TToken.TKind.At;
    '(': Result.Kind := TToken.TKind.LParen;
    ')': Result.Kind := TToken.TKind.RParen;
    '[': Result.Kind := TToken.TKind.LBracket;
    ']': Result.Kind := TToken.TKind.RBracket;
  else
    Result.Kind := TToken.TKind.Unknown;

    Error(Format('Unexpected character "%s"', [C]), StartLine, StartCol);
  end;
end;

function TLexer.TokenizeAll: TList<TToken>;
begin
  Result := TList<TToken>.Create;

  try
    var Tok: TToken;

    repeat
      Tok := NextToken;
      Result.Add(Tok);
    until Tok.Kind = TToken.TKind.EOF;
  except
    Result.Free;
    raise;
  end;
end;
{$ENDREGION}

end.
