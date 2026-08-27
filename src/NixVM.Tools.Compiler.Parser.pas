{
  NixVM.Tools.Compiler.Parser.pas
    Recursive Descent Parser

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

unit NixVM.Tools.Compiler.Parser;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.TypInfo,

  NixVM.Core.ROM,

  NixVM.Tools.Compiler.Lexer,
  NixVM.Tools.Compiler.AST;

type
  {$REGION 'Parser'}
  TParser = class
  private
    FLexer:       TLexer;
    FCurTok:      TLexer.TToken;
    FPeekTok:     TLexer.TToken;
    FErrors:      TStrings;
    FOwnsErrors:  Boolean;
    FOwnsLexer:   Boolean;
    FConstants:   TDictionary<String, TConstValue>;
    FHeader:      TROMHeader;

    procedure NextToken;
    function  PeekToken: TLexer.TToken;

    function  Check(AKind: TLexer.TToken.TKind): Boolean;
    function  Match(AKind: TLexer.TToken.TKind): Boolean;
    function  Expect(AKind: TLexer.TToken.TKind; const AMsg: String = ''): Boolean;

    procedure Error(const AMsg: String; ALine: Integer = 0; ACol: Integer = 0); overload;
    procedure Error(const AMsg: String; const ATok: TLexer.TToken); overload;
    //procedure Error(const AMsg: String; ANode: TASTNode); overload;

    function EvaluateConstant(AExpr: TASTExpression): TConstValue;

    procedure ProcessDirective(const ADirText: String; const ATok: TLexer.TToken);

    {$REGION 'Types'}
    function ParseType:       TASTType;
    function ParseRecordType: TASTType;
    function ParseArrayType:  TASTType;
    {$ENDREGION}

    {$REGION 'Expressions'}
    function ParseExpression:     TASTExpression;
    function ParseComparison:     TASTExpression;
    function ParseAdditive:       TASTExpression;
    function ParseMultiplicative: TASTExpression;
    function ParseUnary:          TASTExpression;
    function ParsePostfix:        TASTExpression;
    function ParsePrimary:        TASTExpression;
    {$ENDREGION}

    {$REGION 'Statements'}
    function ParseStatement:        TASTStatement;
    function ParseBlock:            TASTBlock;
    function ParseIf:               TASTStatement;
    function ParseWhile:            TASTStatement;
    function ParseRepeat:           TASTStatement;
    function ParseFor:              TASTStatement;
    function ParseCase:             TASTStatement;
    function ParseAssignmentOrCall: TASTStatement;
    {$ENDREGION}

    {$REGION 'Declarations'}
    procedure ParseConstSection(ADecls: TObjectList<TASTDeclaration>);
    procedure ParseTypeSection (ADecls: TObjectList<TASTDeclaration>);
    procedure ParseVarSection  (ADecls: TObjectList<TASTDeclaration>);

    function  ParseRoutine(AIsFunction: Boolean; ARequireBody: Boolean = True): TASTRoutineDecl;
    {$ENDREGION}
  public
    constructor Create(ALexer: TLexer;                                      AErrors: TStrings = nil); overload;
    constructor Create(const ASource: String; const AFileName: String = ''; AErrors: TStrings = nil); overload;

    destructor  Destroy; override;

    function Parse:        TASTCompilationUnit;
    function ParseProgram: TASTProgram;
    function ParseUnit:    TASTUnit;

    property Lexer:  TLexer   read FLexer;
    property Errors: TStrings read FErrors;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Tools.Assembler;

{$REGION 'Parser'}
constructor TParser.Create(ALexer: TLexer; AErrors: TStrings);
begin
  inherited Create;

  FConstants  := TDictionary<String, TConstValue>.Create;
  FLexer      := ALexer;
  FOwnsLexer  := False;
  FOwnsErrors := (AErrors = nil);

  FHeader.Reset;

  if FOwnsErrors then
    FErrors := TStringList.Create
  else
    FErrors := AErrors;

  NextToken;
  NextToken;
end;

constructor TParser.Create(const ASource: String; const AFileName: String; AErrors: TStrings);
begin
  inherited Create;

  FConstants  := TDictionary<String, TConstValue>.Create;
  FOwnsErrors := (AErrors = nil);

  FHeader.Reset;

  if FOwnsErrors then
    FErrors := TStringList.Create
  else
    FErrors := AErrors;

  FLexer     := TLexer.Create(ASource, AFileName, FErrors);
  FOwnsLexer := True;

  NextToken;
  NextToken;
end;

destructor TParser.Destroy;
begin
  FConstants.Free;

  if FOwnsLexer then
    FLexer.Free;

  if FOwnsErrors then
    FErrors.Free;

  inherited;
end;

procedure TParser.NextToken;
begin
  FCurTok  := FPeekTok;
  FPeekTok := FLexer.NextToken;

  while FCurTok.Kind = TLexer.TToken.TKind.Directive do
  begin
    ProcessDirective(FCurTok.ValueStr, FCurTok);

    FCurTok  := FPeekTok;
    FPeekTok := FLexer.NextToken;
  end;
end;

function TParser.PeekToken: TLexer.TToken;
begin
  Result := FPeekTok;
end;

function TParser.Check(AKind: TLexer.TToken.TKind): Boolean;
begin
  Result := FCurTok.Kind = AKind;
end;

function TParser.Match(AKind: TLexer.TToken.TKind): Boolean;
begin
  if Check(AKind) then
  begin
    NextToken;
    Result := True;
  end
  else
    Result := False;
end;

function TParser.Expect(AKind: TLexer.TToken.TKind; const AMsg: String): Boolean;
begin
  if Check(AKind) then
  begin
    NextToken;
    Result := True;
  end
  else
  begin
    if Length(AMsg) > 0 then
      Error(AMsg, FCurTok)
    else
      Error(Format('Expected token "%s", but got "%s"', [GetEnumName(TypeInfo(TLexer.TToken.TKind), Ord(AKind)), FCurTok.ToString]), FCurTok);

    Result := False;
  end;
end;

procedure TParser.Error(const AMsg: String; ALine, ACol: Integer);
begin
  if Length(FLexer.FileName) > 0 then
    FErrors.Add(Format('[%s] Line %d, Col %d: %s', [ExtractFileName(FLexer.FileName), ALine, ACol, AMsg]))
  else
    FErrors.Add(Format('Line %d, Col %d: %s', [ALine, ACol, AMsg]));
end;

procedure TParser.Error(const AMsg: String; const ATok: TLexer.TToken);
begin
  Error(AMsg, ATok.Line, ATok.Col);
end;

function TParser.EvaluateConstant(AExpr: TASTExpression): TConstValue;
begin
  Result := Default(TConstValue);

  if AExpr = nil then
    Exit;

  if AExpr is TASTLiteral then
  begin
    var Lit := TASTLiteral(AExpr);

    case Lit.Kind of
      TASTLiteral.TKind.Integer: Exit(TConstValue.MakeInt  (Lit.ValueInt));
      TASTLiteral.TKind.Float:   Exit(TConstValue.MakeFloat(Lit.ValueFloat));
      TASTLiteral.TKind.String:  Exit(TConstValue.MakeStr  (Lit.ValueStr));
      TASTLiteral.TKind.Char:    Exit(TConstValue.MakeStr  (Lit.ValueStr));
      TASTLiteral.TKind.Boolean: Exit(TConstValue.MakeBool (Lit.ValueBool));
      TASTLiteral.TKind.Nil:     Exit(TConstValue.MakePtr  (0));
    end;
  end;

  if AExpr is TASTIdentifier then
  begin
    var ConstName := LowerCase(TASTIdentifier(AExpr).Name);

    if FConstants.TryGetValue(ConstName, Result) then
      Exit;

    Error(Format('Unknown constant identifier "%s"', [TASTIdentifier(AExpr).Name]), AExpr.Line, AExpr.Col);
    Exit;
  end;

  if AExpr is TASTMemberAccess then
  begin
    var MemberAcc := TASTMemberAccess(AExpr);

    if MemberAcc.Expression is TASTIdentifier then
    begin
      var ScopedName := LowerCase(TASTIdentifier(MemberAcc.Expression).Name + '.' + MemberAcc.MemberName);

      if FConstants.TryGetValue(ScopedName, Result) then
        Exit;
    end;
  end;

  if AExpr is TASTBinary then
  begin
    var Bin := TASTBinary(AExpr);

    var LeftVal  := EvaluateConstant(Bin.Left);
    var RightVal := EvaluateConstant(Bin.Right);

    if (LeftVal.Kind = TConstValue.TKind.String) and (RightVal.Kind = TConstValue.TKind.String) and (Bin.Op = TASTBinary.TOp.Add) then
      Exit(TConstValue.MakeStr(LeftVal.ValueStr + RightVal.ValueStr));

    if (LeftVal.Kind = TConstValue.TKind.Single) or (RightVal.Kind = TConstValue.TKind.Single) then
    begin
      var LF: Single;
      var RF: Single;

      if LeftVal.Kind  = TConstValue.TKind.Single then LF := LeftVal.ValueFloat  else LF := LeftVal.ValueInt;
      if RightVal.Kind = TConstValue.TKind.Single then RF := RightVal.ValueFloat else RF := RightVal.ValueInt;

      case Bin.Op of
        TASTBinary.TOp.Add:      Exit(TConstValue.MakeFloat(LF + RF));
        TASTBinary.TOp.Subtract: Exit(TConstValue.MakeFloat(LF - RF));
        TASTBinary.TOp.Multiply: Exit(TConstValue.MakeFloat(LF * RF));

        TASTBinary.TOp.Divide:
          if RF <> 0.0 then
            Exit(TConstValue.MakeFloat(LF / RF))
          else
            Exit;
      end;
    end;

    if (LeftVal.Kind in [TConstValue.TKind.Integer, TConstValue.TKind.Pointer]) and (RightVal.Kind in [TConstValue.TKind.Integer, TConstValue.TKind.Pointer]) then
    begin
      var L := LeftVal.ValueInt;
      var R := RightVal.ValueInt;

      case Bin.Op of
        TASTBinary.TOp.Add:       Exit(TConstValue.MakeInt(L + R));
        TASTBinary.TOp.Subtract:  Exit(TConstValue.MakeInt(L - R));
        TASTBinary.TOp.Multiply:  Exit(TConstValue.MakeInt(L * R));
        TASTBinary.TOp.IntDivide: if R <> 0 then Exit(TConstValue.MakeInt(L div R)) else Exit;
        TASTBinary.TOp.Modulo:    if R <> 0 then Exit(TConstValue.MakeInt(L mod R)) else Exit;
        TASTBinary.TOp.Shl:       Exit(TConstValue.MakeInt(L shl R));
        TASTBinary.TOp.Shr:       Exit(TConstValue.MakeInt(L shr R));
        TASTBinary.TOp.And:       Exit(TConstValue.MakeInt(L and R));
        TASTBinary.TOp.Or:        Exit(TConstValue.MakeInt(L or  R));
        TASTBinary.TOp.Xor:       Exit(TConstValue.MakeInt(L xor R));
      end;
    end;
  end;

  if AExpr is TASTUnary then
  begin
    var Un := TASTUnary(AExpr);
    var Val := EvaluateConstant(Un.Operand);

    case Un.Op of
      TASTUnary.TOp.Negate:
      begin
        if Val.Kind = TConstValue.TKind.Single  then Exit(TConstValue.MakeFloat(-Val.ValueFloat));
        if Val.Kind = TConstValue.TKind.Integer then Exit(TConstValue.MakeInt(Cardinal(-Int32(Val.ValueInt))));
      end;
      TASTUnary.TOp.Not:
      begin
        if Val.Kind = TConstValue.TKind.Boolean then Exit(TConstValue.MakeBool(not Val.ValueBool));
        if Val.Kind = TConstValue.TKind.Integer then Exit(TConstValue.MakeInt(not Val.ValueInt));
      end;
    end;
  end;

  Error('Expression must be a compile-time constant', AExpr.Line, AExpr.Col);
end;

procedure TParser.ProcessDirective(const ADirText: String; const ATok: TLexer.TToken);
var
  DirName:  String;
  DirParam: String;
  SpacePos: Integer;
begin
  var Text := Trim(ADirText);

  if Length(Text) = 0 then
    Exit;

  SpacePos := Pos(' ', Text);

  if SpacePos > 0 then
  begin
    DirName  := UpperCase(Trim(Copy(Text, 1, SpacePos - 1)));
    DirParam := Trim(Copy(Text, SpacePos + 1, Length(Text)));
  end
  else
  begin
    DirName  := UpperCase(Text);
    DirParam := '';
  end;

  if (DirName = 'HEAP') or (DirName = 'HEAPSIZE') then
  begin
    var Val: Cardinal;

    if TAssembler.ParseNumber(DirParam, Val) then
      FHeader.HeapSize := Val
    else
      Error(Format('Invalid size "%s" in {$HEAP} directive', [DirParam]), ATok);
  end

  else if (DirName = 'STACK') or (DirName = 'STACKSIZE') then
  begin
    var Val: Cardinal;

    if TAssembler.ParseNumber(DirParam, Val) then
      FHeader.StackSize := Val
    else
      Error(Format('Invalid size "%s" in {$STACK} directive', [DirParam]), ATok);
  end

  else if (DirName = 'BASE') or (DirName = 'ORG') then
  begin
    var Val: Cardinal;

    if TAssembler.ParseNumber(DirParam, Val) then
      FHeader.UserAddress := Val
    else
      Error(Format('Invalid base address "%s" in {$BASE} directive', [DirParam]), ATok);
  end

  else
    Error(Format('Unknown compiler directive "{$%s}"', [DirName]), ATok);
end;

function TParser.Parse: TASTCompilationUnit;
begin
  if Check(TLexer.TToken.TKind.Unit) then
    Result := ParseUnit
  else
    Result := ParseProgram;
end;

function TParser.ParseUnit: TASTUnit;
var
  UnitTok: TLexer.TToken;
begin
  UnitTok := FCurTok;
  Expect(TLexer.TToken.TKind.Unit);

  var UnitName := 'Unit';

  if Check(TLexer.TToken.TKind.Identifier) then
  begin
    UnitName := FCurTok.ValueStr;
    NextToken;
  end;

  Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after unit name');

  Result := TASTUnit.Create(UnitName);

  Expect(TLexer.TToken.TKind.Interface, 'Expected "interface" section');

  if Match(TLexer.TToken.TKind.Uses) then
  begin
    repeat
      if Check(TLexer.TToken.TKind.Identifier) then
      begin
        Result.InterfaceUses.Add(FCurTok.ValueStr);
        NextToken;
      end
      else
        Break;
    until not Match(TLexer.TToken.TKind.Comma);

    Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after uses clause');
  end;

  while not Check(TLexer.TToken.TKind.Implementation) and not Check(TLexer.TToken.TKind.EOF) do
  begin
    if Check(TLexer.TToken.TKind.Const) then
      ParseConstSection(Result.InterfaceDecls)

    else if Check(TLexer.TToken.TKind.Type) then
      ParseTypeSection(Result.InterfaceDecls)

    else if Check(TLexer.TToken.TKind.Var) then
      ParseVarSection(Result.InterfaceDecls)

    else if Check(TLexer.TToken.TKind.Procedure) then
      Result.InterfaceDecls.Add(ParseRoutine(False, False))

    else if Check(TLexer.TToken.TKind.Function) then
      Result.InterfaceDecls.Add(ParseRoutine(True, False))

    else
    begin
      Error(Format('Unexpected token "%s" in interface section', [FCurTok.ToString]), FCurTok);
      NextToken;
    end;
  end;

  Expect(TLexer.TToken.TKind.Implementation, 'Expected "implementation" section');

  if Match(TLexer.TToken.TKind.Uses) then
  begin
    repeat
      if Check(TLexer.TToken.TKind.Identifier) then
      begin
        Result.ImplementationUses.Add(FCurTok.ValueStr);
        NextToken;
      end
      else
        Break;
    until not Match(TLexer.TToken.TKind.Comma);

    Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after uses clause');
  end;

  while not Check(TLexer.TToken.TKind.End) and not Check(TLexer.TToken.TKind.Initialization) and not Check(TLexer.TToken.TKind.EOF) do
  begin
    if Check(TLexer.TToken.TKind.Const) then
      ParseConstSection(Result.ImplementationDecls)

    else if Check(TLexer.TToken.TKind.Type) then
      ParseTypeSection(Result.ImplementationDecls)

    else if Check(TLexer.TToken.TKind.Var) then
      ParseVarSection(Result.ImplementationDecls)

    else if Check(TLexer.TToken.TKind.Procedure) then
      Result.ImplementationDecls.Add(ParseRoutine(False, True))

    else if Check(TLexer.TToken.TKind.Function) then
      Result.ImplementationDecls.Add(ParseRoutine(True, True))

    else
    begin
      Error(Format('Unexpected token "%s" in implementation section', [FCurTok.ToString]), FCurTok);
      NextToken;
    end;
  end;

  if Match(TLexer.TToken.TKind.Initialization) then
  begin
    var InitBlock := TASTBlock.Create(FCurTok.Line, FCurTok.Col);

    while not Check(TLexer.TToken.TKind.End) and not Check(TLexer.TToken.TKind.EOF) do
    begin
      var Stmt := ParseStatement;

      if Assigned(Stmt) then
        InitBlock.Statements.Add(Stmt);

      Match(TLexer.TToken.TKind.Semicolon);
    end;

    Result.InitializationBlock := InitBlock;
  end;

  Expect(TLexer.TToken.TKind.End, 'Expected "end" closing unit');
  Expect(TLexer.TToken.TKind.Dot, 'Expected "." after final end of unit');
end;

function TParser.ParseProgram: TASTProgram;
var
  ProgName:    String;
  ProgMajor:   Word;
  ProgMinor:   Word;
  TargetName:  String;
  TargetMajor: Word;
  TargetMinor: Word;

  procedure ParseVersionTuple(out AMajor, AMinor: Word);
  begin
    AMajor := 1;
    AMinor := 0;

    if Match(TLexer.TToken.TKind.LParen) then
    begin
      if FCurTok.Kind = TLexer.TToken.TKind.FloatLiteral then
      begin
        var Parts := FCurTok.ValueStr.Split(['.']);

        if Length(Parts) > 0 then AMajor := StrToIntDef(Parts[0], 1);
        if Length(Parts) > 1 then AMinor := StrToIntDef(Parts[1], 0);

        NextToken;
      end
      else if FCurTok.Kind = TLexer.TToken.TKind.IntegerLiteral then
      begin
        AMajor := FCurTok.ValueInt;
        NextToken;

        if Match(TLexer.TToken.TKind.Comma) and (FCurTok.Kind = TLexer.TToken.TKind.IntegerLiteral) then
        begin
          AMinor := FCurTok.ValueInt;
          NextToken;
        end;
      end;

      Expect(TLexer.TToken.TKind.RParen, 'Expected ")" closing version');
    end;
  end;
begin
  ProgName    := 'Program';
  ProgMajor   := 1;
  ProgMinor   := 0;
  TargetName  := '';
  TargetMajor := 1;
  TargetMinor := 0;

  if Match(TLexer.TToken.TKind.Program) then
  begin
    if Check(TLexer.TToken.TKind.Identifier) then
    begin
      ProgName := FCurTok.ValueStr;
      NextToken;
    end;

    ParseVersionTuple(ProgMajor, ProgMinor);

    if Check(TLexer.TToken.TKind.Identifier) and (SameText(FCurTok.ValueStr, 'targets') or SameText(FCurTok.ValueStr, 'target') or SameText(FCurTok.ValueStr, 'for')) then
    begin
      NextToken;

      if Check(TLexer.TToken.TKind.Identifier) or Check(TLexer.TToken.TKind.StringLiteral) then
      begin
        TargetName := FCurTok.ValueStr;
        NextToken;
      end;

      ParseVersionTuple(TargetMajor, TargetMinor);
    end;

    Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after program header');
  end;

  Result := TASTProgram.Create(ProgName);

  Result.Header           := FHeader;
  Result.Header.ROM.Name  := ProgName;
  Result.Header.ROM.Major := ProgMajor;
  Result.Header.ROM.Minor := ProgMinor;

  if Length(TargetName) > 0 then
  begin
    Result.Header.Harness.Name  := TargetName;
    Result.Header.Harness.Major := TargetMajor;
    Result.Header.Harness.Minor := TargetMinor;
  end;

  if Match(TLexer.TToken.TKind.Uses) then
  begin
    repeat
      if Check(TLexer.TToken.TKind.Identifier) then
      begin
        Result.UsesUnits.Add(FCurTok.ValueStr);
        NextToken;
      end
      else
      begin
        Error('Expected unit identifier in uses clause', FCurTok);
        Break;
      end;
    until not Match(TLexer.TToken.TKind.Comma);

    Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after uses clause');
  end;

  while not Check(TLexer.TToken.TKind.Begin) and not Check(TLexer.TToken.TKind.EOF) do
  begin
    if Check(TLexer.TToken.TKind.Const) then
      ParseConstSection(Result.Declarations)

    else if Check(TLexer.TToken.TKind.Type) then
      ParseTypeSection(Result.Declarations)

    else if Check(TLexer.TToken.TKind.Var) then
      ParseVarSection(Result.Declarations)

    else if Check(TLexer.TToken.TKind.Procedure) then
      Result.Declarations.Add(ParseRoutine(False))

    else if Check(TLexer.TToken.TKind.Function) then
      Result.Declarations.Add(ParseRoutine(True))

    else
    begin
      Error(Format('Unexpected token "%s" in declarations', [FCurTok.ToString]), FCurTok);
      NextToken;
    end;
  end;

  Result.Body := ParseBlock;

  Expect(TLexer.TToken.TKind.Dot, 'Expected "." after final end of program');
end;
{$ENDREGION}

{$REGION 'Types'}
function TParser.ParseRecordType: TASTType;
var
  StartTok:          TLexer.TToken;
  CurrentVisibility: TVisibility;
begin
  StartTok          := FCurTok;
  CurrentVisibility := TVisibility.Public;

  Expect(TLexer.TToken.TKind.Record);
  Result := TASTType.Create(TASTType.TKind.Record, StartTok.Line, StartTok.Col);

  while not Check(TLexer.TToken.TKind.End) and not Check(TLexer.TToken.TKind.EOF) do
  begin
    if Match(TLexer.TToken.TKind.Private) then
    begin
      CurrentVisibility := TVisibility.Private;
      Continue;
    end;

    if Match(TLexer.TToken.TKind.Public) then
    begin
      CurrentVisibility := TVisibility.Public;
      Continue;
    end;

    if Match(TLexer.TToken.TKind.Property) then
    begin
      var PropTok := FCurTok;

      if not Expect(TLexer.TToken.TKind.Identifier, 'Expected property identifier') then
        Continue;

      var PropName := PropTok.ValueStr;
      Expect(TLexer.TToken.TKind.Colon, 'Expected ":" and property type');
      var PropType := ParseType;

      var ReadSpec  := '';
      var WriteSpec := '';

      if Match(TLexer.TToken.TKind.Read) then
      begin
        if Check(TLexer.TToken.TKind.Identifier) then
        begin
          ReadSpec := FCurTok.ValueStr;
          NextToken;
        end
        else
          Error('Expected field or method identifier after "read"', FCurTok);
      end;

      if Match(TLexer.TToken.TKind.Write) then
      begin
        if Check(TLexer.TToken.TKind.Identifier) then
        begin
          WriteSpec := FCurTok.ValueStr;
          NextToken;
        end
        else
          Error('Expected field or method identifier after "write"', FCurTok);
      end;

      Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after property declaration');

      var PropNode := TASTProperty.Create(PropName, PropType, ReadSpec, WriteSpec, CurrentVisibility, PropTok.Line, PropTok.Col);
      Result.RecordProperties.Add(PropNode);

      Continue;
    end;

    if Check(TLexer.TToken.TKind.Procedure) or Check(TLexer.TToken.TKind.Function) then
    begin
      var IsFunc := Check(TLexer.TToken.TKind.Function);
      var MethodDecl := ParseRoutine(IsFunc, False);
      MethodDecl.IsRecordMethod := True;

      if Check(TLexer.TToken.TKind.Begin) or Check(TLexer.TToken.TKind.Var) then
      begin
        while Check(TLexer.TToken.TKind.Var) or Check(TLexer.TToken.TKind.Const) do
          if Check(TLexer.TToken.TKind.Var) then
            ParseVarSection(MethodDecl.Declarations)
          else
            ParseConstSection(MethodDecl.Declarations);

        MethodDecl.Body := ParseBlock;
        Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after inline method');
      end;

      Result.RecordMethods.Add(MethodDecl);
      Continue;
    end;

    var FieldNames := TList<String>.Create;

    try
      repeat
        if Check(TLexer.TToken.TKind.Identifier) then
        begin
          FieldNames.Add(FCurTok.ValueStr);
          NextToken;
        end
        else
        begin
          Error('Expected field identifier or member in record declaration', FCurTok);
          Break;
        end;
      until not Match(TLexer.TToken.TKind.Comma);

      Expect(TLexer.TToken.TKind.Colon, 'Expected ":" after field names');
      var FieldType := ParseType;

      var VarDecl := TASTVarDecl.Create(FieldType, nil, StartTok.Line, StartTok.Col);

      for var Name in FieldNames do
        VarDecl.Names.Add(Name);

      Result.RecordFields.Add(VarDecl);
      Match(TLexer.TToken.TKind.Semicolon);
    finally
      FieldNames.Free;
    end;
  end;

  Expect(TLexer.TToken.TKind.End, 'Expected "end" closing record definition');
end;

function TParser.ParseArrayType: TASTType;
var
  StartTok: TLexer.TToken;
  LowVals, HighVals: TList<Integer>;
begin
  StartTok := FCurTok;

  Expect(TLexer.TToken.TKind.Array);
  Expect(TLexer.TToken.TKind.LBracket, 'Expected "[" after array');

  LowVals  := TList<Integer>.Create;
  HighVals := TList<Integer>.Create;
  try
    repeat
      var LowTok := FCurTok;
      var LowBound: Integer := 0;

      if Expect(TLexer.TToken.TKind.IntegerLiteral, 'Expected integer lower bound for array') then
        LowBound := Integer(LowTok.ValueInt);

      Expect(TLexer.TToken.TKind.DotDot, 'Expected ".." in array subrange');

      var HighTok := FCurTok;
      var HighBound: Integer := 0;

      if Expect(TLexer.TToken.TKind.IntegerLiteral, 'Expected integer upper bound for array') then
        HighBound := Integer(HighTok.ValueInt);

      LowVals.Add(LowBound);
      HighVals.Add(HighBound);
    until not Match(TLexer.TToken.TKind.Comma);

    Expect(TLexer.TToken.TKind.RBracket, 'Expected "]" closing array dimensions');
    Expect(TLexer.TToken.TKind.Of, 'Expected "of" after array dimensions');

    var FinalElemType := ParseType;

    Result := FinalElemType;

    for var i := LowVals.Count - 1 downto 0 do
    begin
      var ArrType := TASTType.Create(TASTType.TKind.Array, StartTok.Line, StartTok.Col);

      ArrType.SubrangeLow  := LowVals[i];
      ArrType.SubrangeHigh := HighVals[i];
      ArrType.ElementType  := Result;

      Result := ArrType;
    end;
  finally
    LowVals.Free;
    HighVals.Free;
  end;
end;

function TParser.ParseType: TASTType;
var
  Tok: TLexer.TToken;
begin
  Tok := FCurTok;

  if Match(TLexer.TToken.TKind.LParen) then
  begin
    Result := TASTType.Create(TASTType.TKind.Enum, Tok.Line, Tok.Col);
    var CurrentVal: Integer := 0;

    repeat
      if Check(TLexer.TToken.TKind.Identifier) then
      begin
        var Elem: TASTType.TEnumElement;
        Elem.Name := FCurTok.ValueStr;

        NextToken;

        if Match(TLexer.TToken.TKind.Equal) then
        begin
          var ValExpr := ParseExpression;
          var ConstVal := EvaluateConstant(ValExpr);

          CurrentVal := Integer(ConstVal.ValueInt);

          ValExpr.Free;
        end;

        Elem.Value := CurrentVal;
        Result.EnumElements.Add(Elem);

        Inc(CurrentVal);
      end
      else
      begin
        Error('Expected enum element identifier', FCurTok);
        Break;
      end;
    until not Match(TLexer.TToken.TKind.Comma);

    Expect(TLexer.TToken.TKind.RParen, 'Expected ")" closing enumerated type');
    Exit;
  end;

  if Match(TLexer.TToken.TKind.Integer)  then Exit(TASTType.Create(TASTType.TKind.Integer,  Tok.Line, Tok.Col));
  if Match(TLexer.TToken.TKind.Single)   then Exit(TASTType.Create(TASTType.TKind.Single,   Tok.Line, Tok.Col));
  if Match(TLexer.TToken.TKind.Boolean)  then Exit(TASTType.Create(TASTType.TKind.Boolean,  Tok.Line, Tok.Col));
  if Match(TLexer.TToken.TKind.Byte)     then Exit(TASTType.Create(TASTType.TKind.Byte,     Tok.Line, Tok.Col));
  if Match(TLexer.TToken.TKind.Word)     then Exit(TASTType.Create(TASTType.TKind.Word,     Tok.Line, Tok.Col));
  if Match(TLexer.TToken.TKind.Cardinal) then Exit(TASTType.Create(TASTType.TKind.Cardinal, Tok.Line, Tok.Col));
  if Match(TLexer.TToken.TKind.Char)     then Exit(TASTType.Create(TASTType.TKind.Char,     Tok.Line, Tok.Col));
  if Match(TLexer.TToken.TKind.String)   then Exit(TASTType.Create(TASTType.TKind.String,   Tok.Line, Tok.Col));
  if Match(TLexer.TToken.TKind.Pointer)  then Exit(TASTType.Create(TASTType.TKind.Pointer,  Tok.Line, Tok.Col));
  if Match(TLexer.TToken.TKind.ShortInt) then Exit(TASTType.Create(TASTType.TKind.ShortInt, Tok.Line, Tok.Col));
  if Match(TLexer.TToken.TKind.SmallInt) then Exit(TASTType.Create(TASTType.TKind.SmallInt, Tok.Line, Tok.Col));

  if Check(TLexer.TToken.TKind.Record) then
    Exit(ParseRecordType);

  if Check(TLexer.TToken.TKind.Array) then
    Exit(ParseArrayType);

  if Match(TLexer.TToken.TKind.Caret) then
  begin
    Result := TASTType.Create(TASTType.TKind.Pointer, Tok.Line, Tok.Col);
    Result.ElementType := ParseType;
    Exit;
  end;

  if Check(TLexer.TToken.TKind.Identifier) then
  begin
    var TypeName := FCurTok.ValueStr;
    NextToken;
    Exit(TASTType.Create(TypeName, Tok.Line, Tok.Col));
  end;

  if Match(TLexer.TToken.TKind.Set) then
  begin
    Expect(TLexer.TToken.TKind.Of, 'Expected "of" after "set"');

    Result := TASTType.Create(TASTType.TKind.Set, Tok.Line, Tok.Col);
    Result.ElementType := ParseType;

    Exit;
  end;

  Error('Expected type name or type definition', Tok);
  Result := TASTType.Create(TASTType.TKind.Integer, Tok.Line, Tok.Col);
end;
{$ENDREGION}

{$REGION 'Expressions'}
function TParser.ParsePrimary: TASTExpression;
var
  Tok: TLexer.TToken;
begin
  Tok := FCurTok;

  if (FCurTok.Kind in [TLexer.TToken.TKind.Integer,
                       TLexer.TToken.TKind.Single,
                       TLexer.TToken.TKind.Boolean,
                       TLexer.TToken.TKind.Byte,
                       TLexer.TToken.TKind.Word,
                       TLexer.TToken.TKind.Cardinal,
                       TLexer.TToken.TKind.Char,
                       TLexer.TToken.TKind.String,
                       TLexer.TToken.TKind.Pointer]) and
     (PeekToken.Kind = TLexer.TToken.TKind.LParen) then
  begin
    var CastType := ParseType;
    NextToken;

    var CastExpr := ParseExpression;
    Expect(TLexer.TToken.TKind.RParen, 'Expected ")" closing typecast');

    Exit(TASTTypeCast.Create(CastType, CastExpr, Tok.Line, Tok.Col));
  end;

  if Check(TLexer.TToken.TKind.IntegerLiteral) then
  begin
    NextToken;
    Exit(TASTLiteral.CreateInt(Tok.ValueInt, Tok.Line, Tok.Col));
  end;

  if Check(TLexer.TToken.TKind.FloatLiteral) then
  begin
    NextToken;
    Exit(TASTLiteral.CreateFloat(Tok.ValueFloat, Tok.Line, Tok.Col));
  end;

  if Check(TLexer.TToken.TKind.StringLiteral) then
  begin
    NextToken;
    Exit(TASTLiteral.CreateStr(Tok.ValueStr, Tok.Line, Tok.Col));
  end;

  if Check(TLexer.TToken.TKind.CharLiteral) then
  begin
    NextToken;
    Exit(TASTLiteral.CreateChar(Tok.ValueStr[1], Tok.Line, Tok.Col));
  end;

  if Match(TLexer.TToken.TKind.LBracket) then
  begin
    var ArrayLit := TASTArrayLiteral.Create(Tok.Line, Tok.Col);

    if not Check(TLexer.TToken.TKind.RBracket) then
      repeat
        ArrayLit.Elements.Add(ParseExpression);
      until not Match(TLexer.TToken.TKind.Comma);

    Expect(TLexer.TToken.TKind.RBracket, 'Expected "]" closing array literal');
    Exit(ArrayLit);
  end;

  if Match(TLexer.TToken.TKind.True) then
    Exit(TASTLiteral.CreateBool(True, Tok.Line, Tok.Col));

  if Match(TLexer.TToken.TKind.False) then
    Exit(TASTLiteral.CreateBool(False, Tok.Line, Tok.Col));

  if Match(TLexer.TToken.TKind.Nil) then
    Exit(TASTLiteral.CreateNil(Tok.Line, Tok.Col));

  if Check(TLexer.TToken.TKind.Identifier) then
  begin
    var IdentName := FCurTok.ValueStr;
    NextToken;

    if Match(TLexer.TToken.TKind.LParen) then
    begin
      var CallExpr := TASTCallExpr.Create(IdentName, Tok.Line, Tok.Col);

      if not Check(TLexer.TToken.TKind.RParen) then
        repeat
          CallExpr.Arguments.Add(ParseExpression);
        until not Match(TLexer.TToken.TKind.Comma);

      Expect(TLexer.TToken.TKind.RParen, 'Expected ")" closing function arguments');
      Exit(CallExpr);
    end;

    Exit(TASTIdentifier.Create(IdentName, Tok.Line, Tok.Col));
  end;

  if Match(TLexer.TToken.TKind.LParen) then
  begin
    Result := ParseExpression;
    Expect(TLexer.TToken.TKind.RParen, 'Expected ")" after expression');

    Exit;
  end;

  Error(Format('Unexpected token "%s" in expression', [Tok.ToString]), Tok);
  Result := TASTLiteral.CreateInt(0, Tok.Line, Tok.Col);
end;

function TParser.ParsePostfix: TASTExpression;
begin
  Result := ParsePrimary;

  while True do
  begin
    var Tok := FCurTok;

    if Match(TLexer.TToken.TKind.Dot) then
    begin
      if Check(TLexer.TToken.TKind.Identifier) then
      begin
        var MemberName := FCurTok.ValueStr;
        NextToken;
        Result := TASTMemberAccess.Create(Result, MemberName, Tok.Line, Tok.Col);
      end
      else
      begin
        Error('Expected field identifier after "."', FCurTok);
        Break;
      end;
    end

    else if Match(TLexer.TToken.TKind.LBracket) then
    begin
      var ArrayAcc := TASTArrayAccess.Create(Result, Tok.Line, Tok.Col);

      repeat
        ArrayAcc.IndexExprs.Add(ParseExpression);
      until not Match(TLexer.TToken.TKind.Comma);

      Expect(TLexer.TToken.TKind.RBracket, 'Expected "]" closing array indices');
      Result := ArrayAcc;
    end

    else if Match(TLexer.TToken.TKind.Caret) then
      Result := TASTUnary.Create(TASTUnary.TOp.Dereference, Result, Tok.Line, Tok.Col)

    else
      Break;
  end;
end;

function TParser.ParseUnary: TASTExpression;
var
  Tok: TLexer.TToken;
begin
  Tok := FCurTok;

  if Match(TLexer.TToken.TKind.Minus) then
    Exit(TASTUnary.Create(TASTUnary.TOp.Negate, ParseUnary, Tok.Line, Tok.Col));

  if Match(TLexer.TToken.TKind.Plus) then
    Exit(ParseUnary);

  if Match(TLexer.TToken.TKind.Not) then
    Exit(TASTUnary.Create(TASTUnary.TOp.Not, ParseUnary, Tok.Line, Tok.Col));

  if Match(TLexer.TToken.TKind.At) then
    Exit(TASTUnary.Create(TASTUnary.TOp.AddressOf, ParseUnary, Tok.Line, Tok.Col));

  Result := ParsePostfix;
end;

function TParser.ParseMultiplicative: TASTExpression;
begin
  Result := ParseUnary;

  while True do
  begin
    var Tok := FCurTok;

         if Match(TLexer.TToken.TKind.Star)  then Result := TASTBinary.Create(Result, TASTBinary.TOp.Multiply,  ParseUnary, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.Slash) then Result := TASTBinary.Create(Result, TASTBinary.TOp.Divide,    ParseUnary, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.Div)   then Result := TASTBinary.Create(Result, TASTBinary.TOp.IntDivide, ParseUnary, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.Mod)   then Result := TASTBinary.Create(Result, TASTBinary.TOp.Modulo,    ParseUnary, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.And)   then Result := TASTBinary.Create(Result, TASTBinary.TOp.And,       ParseUnary, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.Shl)   then Result := TASTBinary.Create(Result, TASTBinary.TOp.Shl,       ParseUnary, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.Shr)   then Result := TASTBinary.Create(Result, TASTBinary.TOp.Shr,       ParseUnary, Tok.Line, Tok.Col)
    else Break;
  end;
end;

function TParser.ParseAdditive: TASTExpression;
begin
  Result := ParseMultiplicative;

  while True do
  begin
    var Tok := FCurTok;

         if Match(TLexer.TToken.TKind.Plus)  then Result := TASTBinary.Create(Result, TASTBinary.TOp.Add,      ParseMultiplicative, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.Minus) then Result := TASTBinary.Create(Result, TASTBinary.TOp.Subtract, ParseMultiplicative, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.Or)    then Result := TASTBinary.Create(Result, TASTBinary.TOp.Or,       ParseMultiplicative, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.Xor)   then Result := TASTBinary.Create(Result, TASTBinary.TOp.Xor,      ParseMultiplicative, Tok.Line, Tok.Col)
    else Break;
  end;
end;

function TParser.ParseComparison: TASTExpression;
begin
  Result := ParseAdditive;

  while True do
  begin
    var Tok := FCurTok;

         if Match(TLexer.TToken.TKind.Equal)        then Result := TASTBinary.Create(Result, TASTBinary.TOp.Equal,        ParseAdditive, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.NotEqual)     then Result := TASTBinary.Create(Result, TASTBinary.TOp.NotEqual,     ParseAdditive, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.Less)         then Result := TASTBinary.Create(Result, TASTBinary.TOp.Less,         ParseAdditive, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.LessEqual)    then Result := TASTBinary.Create(Result, TASTBinary.TOp.LessEqual,    ParseAdditive, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.Greater)      then Result := TASTBinary.Create(Result, TASTBinary.TOp.Greater,      ParseAdditive, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.GreaterEqual) then Result := TASTBinary.Create(Result, TASTBinary.TOp.GreaterEqual, ParseAdditive, Tok.Line, Tok.Col)
    else if Match(TLexer.TToken.TKind.In)           then Result := TASTBinary.Create(Result, TASTBinary.TOp.In,           ParseAdditive, Tok.Line, Tok.Col)
    else Break;
  end;
end;

function TParser.ParseExpression: TASTExpression;
begin
  Result := ParseComparison;
end;
{$ENDREGION}

{$REGION 'Statements'}
function TParser.ParseBlock: TASTBlock;
var
  StartTok: TLexer.TToken;
begin
  StartTok := FCurTok;
  Expect(TLexer.TToken.TKind.Begin, 'Expected "begin"');

  Result := TASTBlock.Create(StartTok.Line, StartTok.Col);

  while not Check(TLexer.TToken.TKind.End) and not Check(TLexer.TToken.TKind.EOF) do
  begin
    if Match(TLexer.TToken.TKind.Semicolon) then
      Continue;

    var SavedPos := FCurTok;
    var Stmt := ParseStatement;

    if Assigned(Stmt) then
      Result.Statements.Add(Stmt)
    else if (FCurTok.Line = SavedPos.Line) and (FCurTok.Col = SavedPos.Col) then
      NextToken;

    Match(TLexer.TToken.TKind.Semicolon);
  end;

  Expect(TLexer.TToken.TKind.End, 'Expected "end" closing statement block');
end;

function TParser.ParseIf: TASTStatement;
var
  StartTok: TLexer.TToken;
  Cond:     TASTExpression;
  ThenStmt: TASTStatement;
  ElseStmt: TASTStatement;
begin
  StartTok := FCurTok;
  Expect(TLexer.TToken.TKind.If);

  Cond := ParseExpression;
  Expect(TLexer.TToken.TKind.Then, 'Expected "then" after if condition');

  ThenStmt := ParseStatement;
  ElseStmt := nil;

  if Match(TLexer.TToken.TKind.Else) then
    ElseStmt := ParseStatement;

  Result := TASTIf.Create(Cond, ThenStmt, ElseStmt, StartTok.Line, StartTok.Col);
end;

function TParser.ParseWhile: TASTStatement;
var
  StartTok: TLexer.TToken;
  Cond:     TASTExpression;
  Body:     TASTStatement;
begin
  StartTok := FCurTok;
  Expect(TLexer.TToken.TKind.While);

  Cond := ParseExpression;
  Expect(TLexer.TToken.TKind.Do, 'Expected "do" after while condition');

  Body   := ParseStatement;
  Result := TASTWhile.Create(Cond, Body, StartTok.Line, StartTok.Col);
end;

function TParser.ParseRepeat: TASTStatement;
var
  StartTok:   TLexer.TToken;
  RepeatStmt: TASTRepeat;
begin
  StartTok := FCurTok;
  Expect(TLexer.TToken.TKind.Repeat);

  RepeatStmt := TASTRepeat.Create(nil, StartTok.Line, StartTok.Col);

  while not Check(TLexer.TToken.TKind.Until) and not Check(TLexer.TToken.TKind.EOF) do
  begin
    var Stmt := ParseStatement;

    if Assigned(Stmt) then
      RepeatStmt.Statements.Add(Stmt);

    Match(TLexer.TToken.TKind.Semicolon);
  end;

  Expect(TLexer.TToken.TKind.Until, 'Expected "until" after repeat body');
  RepeatStmt.Condition := ParseExpression;

  Result := RepeatStmt;
end;

function TParser.ParseFor: TASTStatement;
var
  StartTok: TLexer.TToken;
  LoopVar:  String;
  StartExp: TASTExpression;
  StopExp:  TASTExpression;
  &Downto:  Boolean;
  Body:     TASTStatement;
begin
  StartTok := FCurTok;
  Expect(TLexer.TToken.TKind.For);

  var VarTok := FCurTok;
  if not Expect(TLexer.TToken.TKind.Identifier, 'Expected loop variable identifier after for') then
    Exit(nil);

  LoopVar := VarTok.ValueStr;
  Expect(TLexer.TToken.TKind.Assign, 'Expected ":=" after loop variable');

  StartExp := ParseExpression;

  if Match(TLexer.TToken.TKind.To) then
    &Downto := False

  else if Match(TLexer.TToken.TKind.&Downto) then
    &Downto := True

  else
  begin
    Error('Expected "to" or "downto" in for loop', FCurTok);
    &Downto := False;
  end;

  StopExp := ParseExpression;
  Expect(TLexer.TToken.TKind.Do, 'Expected "do" after for range');

  Body   := ParseStatement;
  Result := TASTFor.Create(LoopVar, StartExp, StopExp, &Downto, Body, StartTok.Line, StartTok.Col);
end;

function TParser.ParseCase: TASTStatement;
var
  StartTok:  TLexer.TToken;
  Selector:  TASTExpression;
  CaseStmt:  TASTCase;
begin
  StartTok := FCurTok;
  Expect(TLexer.TToken.TKind.Case);

  Selector := ParseExpression;
  Expect(TLexer.TToken.TKind.Of, 'Expected "of" after case selector expression');

  CaseStmt := TASTCase.Create(Selector, nil, StartTok.Line, StartTok.Col);

  while not Check(TLexer.TToken.TKind.End) and not Check(TLexer.TToken.TKind.Else) and not Check(TLexer.TToken.TKind.EOF) do
  begin
    var Branch := TASTCaseBranch.Create(FCurTok.Line, FCurTok.Col);

    repeat
      var ValExpr := ParseExpression;
      var LowConst := EvaluateConstant(ValExpr);
      ValExpr.Free;

      var MatchVal: TASTCaseBranch.TMatchValue;

      if Match(TLexer.TToken.TKind.DotDot) then
      begin
        var HighExpr := ParseExpression;
        var HighConst := EvaluateConstant(HighExpr);
        HighExpr.Free;

        MatchVal.Kind    := TASTCaseBranch.TMatchValue.TKind.RangeValue;
        MatchVal.LowVal  := Integer(LowConst.ValueInt);
        MatchVal.HighVal := Integer(HighConst.ValueInt);
      end
      else
      begin
        MatchVal.Kind    := TASTCaseBranch.TMatchValue.TKind.SingleValue;
        MatchVal.LowVal  := Integer(LowConst.ValueInt);
        MatchVal.HighVal := Integer(LowConst.ValueInt);
      end;

      Branch.Values.Add(MatchVal);

    until not Match(TLexer.TToken.TKind.Comma);

    Expect(TLexer.TToken.TKind.Colon, 'Expected ":" after case labels');
    Branch.Statement := ParseStatement;
    Match(TLexer.TToken.TKind.Semicolon);

    CaseStmt.Branches.Add(Branch);
  end;

  if Match(TLexer.TToken.TKind.Else) then
  begin
    var ElseBlock := TASTBlock.Create(FCurTok.Line, FCurTok.Col);

    while not Check(TLexer.TToken.TKind.End) and not Check(TLexer.TToken.TKind.EOF) do
    begin
      var Stmt := ParseStatement;

      if Assigned(Stmt) then
        ElseBlock.Statements.Add(Stmt);

      Match(TLexer.TToken.TKind.Semicolon);
    end;

    CaseStmt.ElseStmt := ElseBlock;
  end;

  Expect(TLexer.TToken.TKind.End, 'Expected "end" closing case statement');
  Result := CaseStmt;
end;

function TParser.ParseAssignmentOrCall: TASTStatement;
var
  StartTok: TLexer.TToken;
  Target:   TASTExpression;
begin
  StartTok := FCurTok;
  Target   := ParsePostfix;

  if Check(TLexer.TToken.TKind.Assign) or
     Check(TLexer.TToken.TKind.PlusAssign) or
     Check(TLexer.TToken.TKind.MinusAssign) or
     Check(TLexer.TToken.TKind.MulAssign) or
     Check(TLexer.TToken.TKind.DivAssign) then
  begin
    var OpTok := FCurTok;
    var AssignOp: TASTAssign.TOp;

    case OpTok.Kind of
      TLexer.TToken.TKind.Assign:      AssignOp := TASTAssign.TOp.Assign;
      TLexer.TToken.TKind.PlusAssign:  AssignOp := TASTAssign.TOp.PlusAssign;
      TLexer.TToken.TKind.MinusAssign: AssignOp := TASTAssign.TOp.MinusAssign;
      TLexer.TToken.TKind.MulAssign:   AssignOp := TASTAssign.TOp.MulAssign;
      TLexer.TToken.TKind.DivAssign:   AssignOp := TASTAssign.TOp.DivAssign;
    else
      AssignOp := TASTAssign.TOp.Assign;
    end;

    NextToken;
    var ValueExpr := ParseExpression;

    Exit(TASTAssign.Create(Target, AssignOp, ValueExpr, StartTok.Line, StartTok.Col));
  end;

  if Target is TASTCallExpr then
    Exit(TASTProcCall.Create(TASTCallExpr(Target), StartTok.Line, StartTok.Col));

  if Target is TASTIdentifier then
  begin
    var Call := TASTCallExpr.Create(TASTIdentifier(Target).Name, StartTok.Line, StartTok.Col);
    Target.Free;

    Exit(TASTProcCall.Create(Call, StartTok.Line, StartTok.Col));
  end;

  Error('Invalid statement', StartTok);
  Target.Free;
  Result := nil;
end;

function TParser.ParseStatement: TASTStatement;
var
  Tok: TLexer.TToken;
begin
  Tok := FCurTok;

  if Check(TLexer.TToken.TKind.Begin) then
    Exit(ParseBlock);

  if Check(TLexer.TToken.TKind.If) then
    Exit(ParseIf);

  if Check(TLexer.TToken.TKind.While) then
    Exit(ParseWhile);

  if Check(TLexer.TToken.TKind.Repeat) then
    Exit(ParseRepeat);

  if Check(TLexer.TToken.TKind.For) then
    Exit(ParseFor);

  if Check(TLexer.TToken.TKind.Case) then
    Exit(ParseCase);

  if Match(TLexer.TToken.TKind.Exit) then
    Exit(TASTExit.Create(Tok.Line, Tok.Col));

  if Match(TLexer.TToken.TKind.Break) then
    Exit(TASTBreak.Create(Tok.Line, Tok.Col));

  if Match(TLexer.TToken.TKind.Continue) then
    Exit(TASTContinue.Create(Tok.Line, Tok.Col));

  if Check(TLexer.TToken.TKind.Semicolon) or Check(TLexer.TToken.TKind.End) then
    Exit(nil);

  Result := ParseAssignmentOrCall;
end;
{$ENDREGION}

{$REGION 'Declarations'}
procedure TParser.ParseConstSection(ADecls: TObjectList<TASTDeclaration>);
begin
  Expect(TLexer.TToken.TKind.Const);

  while Check(TLexer.TToken.TKind.Identifier) do
  begin
    var StartTok := FCurTok;
    var ConstName := FCurTok.ValueStr;

    NextToken;

    var ConstType: TASTType := nil;

    if Match(TLexer.TToken.TKind.Colon) then
      ConstType := ParseType;

    Expect(TLexer.TToken.TKind.Equal, 'Expected "=" in const declaration');

    var ValueExpr := ParseExpression;

    Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after const declaration');

    ADecls.Add(TASTConstDecl.Create(ConstName, ValueExpr, Default(TConstValue), ConstType, StartTok.Line, StartTok.Col));
  end;
end;

procedure TParser.ParseTypeSection(ADecls: TObjectList<TASTDeclaration>);
begin
  Expect(TLexer.TToken.TKind.Type);

  while Check(TLexer.TToken.TKind.Identifier) do
  begin
    var StartTok := FCurTok;
    var TypeName := FCurTok.ValueStr;

    NextToken;

    Expect(TLexer.TToken.TKind.Equal, 'Expected "=" in type declaration');
    var DeclType := ParseType;
    Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after type declaration');

    if DeclType.Kind = TASTType.TKind.Enum then
      for var Elem in DeclType.EnumElements do
      begin
        FConstants.AddOrSetValue(LowerCase(Elem.Name), TConstValue.MakeInt(Cardinal(Elem.Value)));

        var ScopedName := LowerCase(TypeName + '.' + Elem.Name);
        FConstants.AddOrSetValue(ScopedName, TConstValue.MakeInt(Cardinal(Elem.Value)));
      end;

    for var MethodNode in DeclType.RecordMethods do
      if MethodNode is TASTRoutineDecl then
      begin
        TASTRoutineDecl(MethodNode).ParentTypeName := TypeName;
        TASTRoutineDecl(MethodNode).IsRecordMethod := True;
      end;

    ADecls.Add(TASTTypeDecl.Create(TypeName, DeclType, StartTok.Line, StartTok.Col));
  end;
end;

procedure TParser.ParseVarSection(ADecls: TObjectList<TASTDeclaration>);
begin
  Expect(TLexer.TToken.TKind.Var);

  while Check(TLexer.TToken.TKind.Identifier) do
  begin
    var StartTok := FCurTok;
    var VarNames := TList<String>.Create;

    try
      repeat
        if Check(TLexer.TToken.TKind.Identifier) then
        begin
          VarNames.Add(FCurTok.ValueStr);
          NextToken;
        end
        else
        begin
          Error('Expected variable identifier', FCurTok);
          Break;
        end;

        if not Match(TLexer.TToken.TKind.Comma) then
          Break;
      until False;

      Expect(TLexer.TToken.TKind.Colon, 'Expected ":" after variable names');
      var VarType := ParseType;

      var InitVal: TASTExpression := nil;

      if Match(TLexer.TToken.TKind.Equal) then
        InitVal := ParseExpression;

      Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after variable declaration');

      var VarDecl := TASTVarDecl.Create(VarType, InitVal, StartTok.Line, StartTok.Col);

      for var Name in VarNames do
        VarDecl.Names.Add(Name);

      ADecls.Add(VarDecl);
    finally
      VarNames.Free;
    end;
  end;
end;

function TParser.ParseRoutine(AIsFunction: Boolean; ARequireBody: Boolean = True): TASTRoutineDecl;
var
  StartTok:   TLexer.TToken;
  NameTok:    TLexer.TToken;
  ParentName: String;
  MethodName: String;
begin
  StartTok := FCurTok;

  if AIsFunction then
    Expect(TLexer.TToken.TKind.Function)
  else
    Expect(TLexer.TToken.TKind.Procedure);

  NameTok := FCurTok;

  if not Expect(TLexer.TToken.TKind.Identifier, 'Expected routine name identifier') then
    Exit(nil);

  ParentName := '';
  MethodName := NameTok.ValueStr;

  if Match(TLexer.TToken.TKind.Dot) then
  begin
    ParentName := NameTok.ValueStr;

    if Check(TLexer.TToken.TKind.Identifier) then
    begin
      MethodName := FCurTok.ValueStr;
      NextToken;
    end
    else
      Error('Expected method name identifier after "."', FCurTok);
  end;

  Result := TASTRoutineDecl.Create(MethodName, AIsFunction, nil, StartTok.Line, StartTok.Col);

  Result.ParentTypeName := ParentName;
  Result.IsRecordMethod := (Length(ParentName) > 0);

  if Match(TLexer.TToken.TKind.LParen) then
  begin
    if not Check(TLexer.TToken.TKind.RParen) then
      repeat
        var Modifier := TASTParamDecl.TModifier.Value;

             if Match(TLexer.TToken.TKind.Var)   then Modifier := TASTParamDecl.TModifier.Var
        else if Match(TLexer.TToken.TKind.Const) then Modifier := TASTParamDecl.TModifier.Const
        else if Match(TLexer.TToken.TKind.Out)   then Modifier := TASTParamDecl.TModifier.Out;

        var ParamNames := TList<String>.Create;
        try
          repeat
            if Check(TLexer.TToken.TKind.Identifier) then
            begin
              ParamNames.Add(FCurTok.ValueStr);
              NextToken;
            end
            else
            begin
              Error('Expected parameter identifier', FCurTok);
              Break;
            end;
          until not Match(TLexer.TToken.TKind.Comma);

          Expect(TLexer.TToken.TKind.Colon, 'Expected ":" after parameter names');
          var ParamType := ParseType;

          for var PName in ParamNames do
            Result.Params.Add(TASTParamDecl.Create(PName, ParamType.Clone, Modifier, StartTok.Line, StartTok.Col));

          ParamType.Free;
        finally
          ParamNames.Free;
        end;
      until not Match(TLexer.TToken.TKind.Semicolon);

    Expect(TLexer.TToken.TKind.RParen, 'Expected ")" after parameter list');
  end;

  if AIsFunction then
  begin
    Expect(TLexer.TToken.TKind.Colon, 'Expected ":" and return type for function');
    Result.ReturnType := ParseType;
  end;

  Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after routine header');

  if Match(TLexer.TToken.TKind.Interrupt) then
  begin
    Result.IsInterrupt := True;
    Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after interrupt directive');
  end
  else
  begin
    if Match(TLexer.TToken.TKind.VarArgs) then
    begin
      Result.IsVarArgs := True;
      Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after varargs directive');
    end;

    if Match(TLexer.TToken.TKind.SysCall) then
    begin
      Result.IsSysCall := True;
      Result.SysCallExpr := ParseExpression;

      Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after syscall declaration');

      if Match(TLexer.TToken.TKind.VarArgs) then
      begin
        Result.IsVarArgs := True;
        Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after varargs directive');
      end;

      Exit;
    end

    else if Result.IsVarArgs then
      Error('"varargs" directive is only valid on syscall declarations', FCurTok);
  end;

  if not ARequireBody then
    Exit;

  while True do
  begin
    if Check(TLexer.TToken.TKind.Const) then
      ParseConstSection(Result.Declarations)

    else if Check(TLexer.TToken.TKind.Type) then
      ParseTypeSection(Result.Declarations)

    else if Check(TLexer.TToken.TKind.Var) then
      ParseVarSection(Result.Declarations)

    else
      Break;
  end;

  Result.Body := ParseBlock;
  Expect(TLexer.TToken.TKind.Semicolon, 'Expected ";" after routine end');
end;
{$ENDREGION}

end.
