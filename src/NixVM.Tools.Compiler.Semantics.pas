{
  NixVM.Tools.Compiler.Semantics.pas
    Semantic analyzer, symbol table and type checker

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

unit NixVM.Tools.Compiler.Semantics;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,

  NixVM.Tools.Compiler.AST;

type
  {$REGION 'Type'}
  TType = class
  type
    {$REGION 'Kind'}
    TKind = (
      &Integer,
      &Single,
      &Boolean,
      &Byte,
      &ShortInt,
      &Word,
      &SmallInt,
      &Cardinal,
      &Char,
      &String,
      &Pointer,
      &Array,
      &Record,
      &Set,
      Enum,
      &Procedure,
      &Function,
      NilType,
      VoidType,
      DynamicArray
    );
    {$ENDREGION}

    {$REGION 'RecordField'}
    TRecordField = record
      Name:   String;
      &Type:  TType;
      Offset: Cardinal;
    end;
    {$ENDREGION}

    {$REGION 'EnumElement'}
    TEnumElement = record
      Name:  String;
      Value: Integer;
    end;
    {$ENDREGION}

    {$REGION 'Property'}
    TProperty = record
      Name:          String;
      PropType:      TType;
      ReadSpec:      String;
      WriteSpec:     String;
      Visibility:    TVisibility;
      ReadOffset:    Cardinal;
      WriteOffset:   Cardinal;
      IsDirectRead:  Boolean;
      IsDirectWrite: Boolean;
    end;
    {$ENDREGION}
  private
    FKind:         TKind;
    FName:         String;
    FSize:         Cardinal;
    FElementType:  TType;
    FRecordFields: TList<TRecordField>;
    FSubrangeLow:  Integer;
    FSubrangeHigh: Integer;
    FReturnType:   TType;
    FMethods:      TObjectDictionary<String, TASTRoutineDecl>;
    FEnumElements: TList<TEnumElement>;
    FProperties:   TList<TProperty>;
  public
    constructor Create(AKind: TKind; const AName: String; ASize: Cardinal); overload;
    constructor CreateArray(AElementType: TType; ALow, AHigh: Integer); overload;
    constructor CreateRecord(const AName: String); overload;

    destructor  Destroy; override;

    function IsNumeric:      Boolean; inline;
    function IsInteger:      Boolean; inline;
    function IsFloat:        Boolean; inline;
    function IsBoolean:      Boolean; inline;
    function IsString:       Boolean; inline;
    function IsSigned:       Boolean; inline;
    function IsSet:          Boolean; inline;
    function IsDynamicArray: Boolean; inline;

    function FindField   (const AFieldName: String; out AField: TRecordField): Boolean;
    function FindProperty(const APropName:  String; out AProp:  TProperty):    Boolean;

    property Kind:         TKind               read FKind         write FKind;
    property Name:         String              read FName         write FName;
    property Size:         Cardinal            read FSize         write FSize;
    property ElementType:  TType               read FElementType  write FElementType;
    property RecordFields: TList<TRecordField> read FRecordFields;
    property SubrangeLow:  Integer             read FSubrangeLow  write FSubrangeLow;
    property SubrangeHigh: Integer             read FSubrangeHigh write FSubrangeHigh;
    property ReturnType:   TType               read FReturnType   write FReturnType;
    property EnumElements: TList<TEnumElement> read FEnumElements;

    property Methods:    TObjectDictionary<String, TASTRoutineDecl> read FMethods;
    property Properties: TList<TProperty>                           read FProperties;
  end;
  {$ENDREGION}

  {$REGION 'Symbol'}
  TScope = class;

  TSymbol = class
  type
    {$REGION 'Kind'}
    TKind = (
      Variable,
      Constant,
      &Type,
      &Procedure,
      &Function,
      Parameter
    );
    {$ENDREGION}

    {$REGION 'Storage'}
    TStorage = (
      Global,
      Local,
      Parameter
    );
    {$ENDREGION}
  private
    FName:         String;
    FKind:         TKind;
    FSymbolType:   TType;
    FLocalScope:   TScope;
    FStorage:      TStorage;
    FStackOffset:  Integer;
    FGlobalLabel:  String;
    FIsVarParam:   Boolean;
    FParamIndex:   Integer;
    FConstantExpr: TASTLiteral;
    FDeclaration:  TASTRoutineDecl;
    FIsSysCall:    Boolean;
    FSysCallID:    Cardinal;
    FConstVal:     TConstValue;
    FIsInterrupt:  Boolean;
    FIsVarArgs:    Boolean;
  public
    constructor Create(const AName: String; AKind: TKind; ASymbolType: TType);
    destructor  Destroy; override;

    property Name:         String          read FName         write FName;
    property Kind:         TKind           read FKind         write FKind;
    property SymbolType:   TType           read FSymbolType   write FSymbolType;
    property LocalScope:   TScope          read FLocalScope   write FLocalScope;
    property Storage:      TStorage        read FStorage      write FStorage;
    property StackOffset:  Integer         read FStackOffset  write FStackOffset;
    property GlobalLabel:  String          read FGlobalLabel  write FGlobalLabel;
    property IsVarParam:   Boolean         read FIsVarParam   write FIsVarParam;
    property ParamIndex:   Integer         read FParamIndex   write FParamIndex;
    property ConstantExpr: TASTLiteral     read FConstantExpr write FConstantExpr;
    property Declaration:  TASTRoutineDecl read FDeclaration  write FDeclaration;
    property IsSysCall:    Boolean         read FIsSysCall    write FIsSysCall;
    property SysCallID:    Cardinal        read FSysCallID    write FSysCallID;
    property ConstVal:     TConstValue     read FConstVal     write FConstVal;
    property IsInterrupt:  Boolean         read FIsInterrupt  write FIsInterrupt;
    property IsVarArgs:    Boolean         read FIsVarArgs    write FIsVarArgs;
  end;
  {$ENDREGION}

  {$REGION 'Scope'}
  TScope = class
  private
    FParent:     TScope;
    FSymbols:    TObjectDictionary<String, TSymbol>;
    FLocalSize:  Cardinal;
  public
    constructor Create(AParent: TScope = nil);
    destructor  Destroy; override;

    function Define(ASymbol: TSymbol): Boolean;

    function Resolve     (const AName: String): TSymbol;
    function ResolveLocal(const AName: String): TSymbol;

    property Parent:    TScope   read FParent;
    property LocalSize: Cardinal read FLocalSize write FLocalSize;
  end;
  {$ENDREGION}

  {$REGION 'Semantic Analyzer'}
  TSemanticAnalyzer = class
  type
    TWithContext = record
      RecordType: TType;
    end;
  private
    FGlobalScope:  TScope;
    FCurrentScope: TScope;
    FErrors:       TStrings;
    FOwnsErrors:   Boolean;
    FBuiltinTypes: TObjectDictionary<String, TType>;
    FWithStack:    TList<TWithContext>;

    procedure InitBuiltinTypes;

    procedure Error(const AMsg: String; ANode: TASTNode);

    function ResolveType(AAstType: TASTType): TType;

    function  FoldExpression(var AExpr: TASTExpression): Boolean;
    procedure FoldExpressionList(AList: TObjectList<TASTExpression>);

    procedure AnalyzeProgram    (AProgram: TASTProgram);
    procedure AnalyzeDeclaration(ADecl:    TASTDeclaration);
    procedure AnalyzeRoutine    (ARoutine: TASTRoutineDecl);

    procedure AnalyzeStatement(AStmt:   TASTStatement);
    procedure AnalyzeBlock    (ABlock:  TASTBlock);
    procedure AnalyzeWith     (AWith:   TASTWith);
    procedure AnalyzeAssign   (AAssign: TASTAssign);
    procedure AnalyzeIf       (AIf:     TASTIf);
    procedure AnalyzeWhile    (AWhile:  TASTWhile);
    procedure AnalyzeRepeat   (ARepeat: TASTRepeat);
    procedure AnalyzeFor      (AFor:    TASTFor);
    procedure AnalyzeForIn    (AForIn:  TASTForIn);
    procedure AnalyzeProcCall (ACall:   TASTProcCall);

    function AnalyzeExpression  (AExpr:     TASTExpression):   TType;
    function AnalyzeIfExpression(AIfExpr:   TASTIfExpression): TType;
    function AnalyzeBinary      (ABinary:   TASTBinary):       TType;
    function AnalyzeUnary       (AUnary:    TASTUnary):        TType;
    function AnalyzeLiteral     (ALiteral:  TASTLiteral):      TType;
    function AnalyzeIdentifier  (AIdent:    TASTIdentifier):   TType;
    function AnalyzeMemberAccess(AMember:   TASTMemberAccess): TType;
    function AnalyzeArrayAccess (AArrayAcc: TASTArrayAccess):  TType;
    function AnalyzeCallExpr    (ACall:     TASTCallExpr):     TType;

    function CheckTypeCompatibility(TargetType, SourceType: TType): Boolean;
  public
    constructor Create(AErrors: TStrings = nil);
    destructor  Destroy; override;

    function EvaluateConstValue(AExpr: TASTExpression; out AValue: TConstValue): Boolean;

    procedure ImportUnitInterface(AUnit: TASTUnit);

    function Analyze    (AProgram: TASTProgram): Boolean;
    function AnalyzeUnit(AUnit:    TASTUnit):    Boolean;

    property GlobalScope: TScope   read FGlobalScope;
    property Errors:      TStrings read FErrors;
  end;
  {$ENDREGION}

  {$REGION 'TreeShaker'}
  TTreeShaker = class
  type
    TPropSpec = record
      ReadRoutine:  String;
      WriteRoutine: String;
    end;
  private
    FProgram:     TASTProgram;
    FUnits:       TList<TASTUnit>;
    FRoutineMap:  TDictionary<String, TASTRoutineDecl>;
    FVarMap:      TDictionary<String, TASTVarDecl>;
    FPropertyMap: TDictionary<String, TPropSpec>;
    FWithStack:   TList<String>;

    procedure MarkExpression(AExpr:    TASTExpression);
    procedure MarkStatement (AStmt:    TASTStatement);
    procedure MarkBlock     (ABlock:   TASTBlock);
    procedure MarkRoutine   (ARoutine: TASTRoutineDecl);
  public
    constructor Create(AProgram: TASTProgram; AUnits: TList<TASTUnit>);
    destructor  Destroy; override;

    procedure Execute;
  end;
  {$ENDREGION}

implementation

{$REGION 'Type'}
constructor TType.Create(AKind: TKind; const AName: String; ASize: Cardinal);
begin
  inherited Create;

  FKind         := AKind;
  FName         := AName;
  FSize         := ASize;
  FElementType  := nil;
  FReturnType   := nil;
  FRecordFields := TList<TRecordField>.Create;
  FSubrangeLow  := 0;
  FSubrangeHigh := 0;
  FMethods      := TObjectDictionary<String, TASTRoutineDecl>.Create;
  FEnumElements := TList<TEnumElement>.Create;
  FProperties   := TList<TProperty>.Create;
end;

constructor TType.CreateArray(AElementType: TType; ALow, AHigh: Integer);
begin
  inherited Create;

  FKind         := TKind.Array;
  FElementType  := AElementType;
  FSubrangeLow  := ALow;
  FSubrangeHigh := AHigh;
  FRecordFields := TList<TRecordField>.Create;

  var ElementCount := (AHigh - ALow) + 1;

  if ElementCount < 0 then
    ElementCount := 0;

  if Assigned(AElementType) then
    FSize := Cardinal(ElementCount) * AElementType.Size
  else
    FSize := 0;

  FName := Format('array[%d..%d] of %s', [ALow, AHigh, AElementType.Name]);
end;

constructor TType.CreateRecord(const AName: String);
begin
  inherited Create;

  FKind         := TKind.Record;
  FName         := AName;
  FSize         := 0;
  FElementType  := nil;
  FRecordFields := TList<TRecordField>.Create;
  FMethods      := TObjectDictionary<String, TASTRoutineDecl>.Create;
  FProperties   := TList<TProperty>.Create;
end;

destructor TType.Destroy;
begin
  FRecordFields.Free;

  if Assigned(FProperties) then
    FProperties.Free;

  if Assigned(FMethods) then
    FMethods.Free;

  if Assigned(FEnumElements) then
    FEnumElements.Free;

  inherited;
end;

function TType.IsNumeric: Boolean;
begin
  Result := FKind in [TKind.Integer, TKind.Single, TKind.Byte, TKind.Word, TKind.Cardinal];
end;

function TType.IsInteger: Boolean;
begin
  Result := FKind in [TKind.Integer, TKind.Cardinal, TKind.SmallInt, TKind.Word, TKind.ShortInt, TKind.Byte, TKind.Enum, TKind.Char];
end;

function TType.IsFloat: Boolean;
begin
  Result := FKind = TKind.Single;
end;

function TType.IsBoolean: Boolean;
begin
  Result := FKind = TKind.Boolean;
end;

function TType.IsString: Boolean;
begin
  Result := FKind in [TKind.String, TKind.Char];
end;

function TType.IsSigned: Boolean;
begin
  Result := FKind in [TKind.Integer, TKind.SmallInt, TKind.ShortInt];
end;

function TType.IsSet: Boolean;
begin
  Result := FKind = TKind.Set;
end;

function TType.IsDynamicArray: Boolean;
begin
  Result := FKind = TKind.DynamicArray;
end;

function TType.FindField(const AFieldName: String; out AField: TRecordField): Boolean;
begin
  for var Field in FRecordFields do
    if SameText(Field.Name, AFieldName) then
    begin
      AField := Field;
      Exit(True);
    end;

  Result := False;
end;

function TType.FindProperty(const APropName: String; out AProp: TProperty): Boolean;
begin
  for var Prop in FProperties do
    if SameText(Prop.Name, APropName) then
    begin
      AProp := Prop;
      Exit(True);
    end;

  Result := False;
end;
{$ENDREGION}

{$REGION 'Symbol'}
constructor TSymbol.Create(const AName: String; AKind: TKind; ASymbolType: TType);
begin
  inherited Create;

  FName         := AName;
  FKind         := AKind;
  FSymbolType   := ASymbolType;
  FStorage      := TStorage.Global;
  FStackOffset  := 0;
  FIsVarParam   := False;
  FParamIndex   := 0;
  FConstantExpr := nil;
  FDeclaration  := nil;
end;

destructor TSymbol.Destroy;
begin
  if Assigned(FLocalScope) then
    FLocalScope.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'Scope'}
constructor TScope.Create(AParent: TScope);
begin
  inherited Create;

  FParent    := AParent;
  FSymbols   := TObjectDictionary<String, TSymbol>.Create([doOwnsValues]);
  FLocalSize := 0;
end;

destructor TScope.Destroy;
begin
  FSymbols.Free;

  inherited;
end;

function TScope.Define(ASymbol: TSymbol): Boolean;
begin
  var Key := LowerCase(ASymbol.Name);

  if FSymbols.ContainsKey(Key) then
    Exit(False);

  FSymbols.Add(Key, ASymbol);
  Result := True;
end;

function TScope.ResolveLocal(const AName: String): TSymbol;
begin
  FSymbols.TryGetValue(LowerCase(AName), Result);
end;

function TScope.Resolve(const AName: String): TSymbol;
begin
  if FSymbols.TryGetValue(LowerCase(AName), Result) then
    Exit;

  if Assigned(FParent) then
    Result := FParent.Resolve(AName)
  else
    Result := nil;
end;
{$ENDREGION}

{$REGION 'SemanticAnalyzer'}
constructor TSemanticAnalyzer.Create(AErrors: TStrings);
begin
  inherited Create;

  FOwnsErrors := (AErrors = nil);

  if FOwnsErrors then
    FErrors := TStringList.Create
  else
    FErrors := AErrors;

  FBuiltinTypes := TObjectDictionary<String, TType>.Create([doOwnsValues]);
  FGlobalScope  := TScope.Create(nil);
  FCurrentScope := FGlobalScope;

  FWithStack := TList<TWithContext>.Create;

  InitBuiltinTypes;
end;

destructor TSemanticAnalyzer.Destroy;
begin
  FGlobalScope.Free;
  FBuiltinTypes.Free;
  FWithStack.Free;

  if FOwnsErrors then
    FErrors.Free;

  inherited;
end;

procedure TSemanticAnalyzer.InitBuiltinTypes;
var
  ProcType : TType;
  FuncInt:   TType;
  FuncStr:   TType;
  FuncChar:  TType;
  FuncBool:  TType;
  FuncFloat: TType;
begin
  FBuiltinTypes.Add('integer',  TType.Create(TType.TKind.Integer,  'Integer',  4));
  FBuiltinTypes.Add('single',   TType.Create(TType.TKind.Single,   'Single',   4));
  FBuiltinTypes.Add('boolean',  TType.Create(TType.TKind.Boolean,  'Boolean',  4));
  FBuiltinTypes.Add('byte',     TType.Create(TType.TKind.Byte,     'Byte',     1));
  FBuiltinTypes.Add('word',     TType.Create(TType.TKind.Word,     'Word',     2));
  FBuiltinTypes.Add('cardinal', TType.Create(TType.TKind.Cardinal, 'Cardinal', 4));
  FBuiltinTypes.Add('char',     TType.Create(TType.TKind.Char,     'Char',     1));
  FBuiltinTypes.Add('string',   TType.Create(TType.TKind.String,   'String',   4));
  FBuiltinTypes.Add('pointer',  TType.Create(TType.TKind.Pointer,  'Pointer',  4));
  FBuiltinTypes.Add('nil',      TType.Create(TType.TKind.NilType,  'Nil',      4));
  FBuiltinTypes.Add('void',     TType.Create(TType.TKind.VoidType, 'Void',     0));
  FBuiltinTypes.Add('shortint', TType.Create(TType.TKind.ShortInt, 'ShortInt', 1));
  FBuiltinTypes.Add('smallint', TType.Create(TType.TKind.SmallInt, 'SmallInt', 2));

  for var Pair in FBuiltinTypes do
    FGlobalScope.Define(TSymbol.Create(Pair.Value.Name, TSymbol.TKind.Type, Pair.Value));

  ProcType := TType.Create(TType.TKind.Procedure, 'Procedure', 0);
  ProcType.ReturnType := FBuiltinTypes['void'];

  FuncInt := TType.Create(TType.TKind.Function, 'Function', 0);
  FuncInt.ReturnType := FBuiltinTypes['integer'];

  FuncStr := TType.Create(TType.TKind.Function, 'Function', 0);
  FuncStr.ReturnType := FBuiltinTypes['string'];

  FuncChar := TType.Create(TType.TKind.Function, 'Function', 0);
  FuncChar.ReturnType := FBuiltinTypes['char'];

  FuncBool := TType.Create(TType.TKind.Function, 'Function', 0);
  FuncBool.ReturnType := FBuiltinTypes['boolean'];

  FuncFloat := TType.Create(TType.TKind.Function, 'Function', 0);
  FuncFloat.ReturnType := FBuiltinTypes['single'];


  FGlobalScope.Define(TSymbol.Create('println', TSymbol.TKind.Procedure, ProcType));
  FGlobalScope.Define(TSymbol.Create('print',   TSymbol.TKind.Procedure, ProcType));

  FGlobalScope.Define(TSymbol.Create('halt',    TSymbol.TKind.Procedure, ProcType));
  FGlobalScope.Define(TSymbol.Create('yield',   TSymbol.TKind.Procedure, ProcType));
  FGlobalScope.Define(TSymbol.Create('inc',     TSymbol.TKind.Procedure, ProcType));
  FGlobalScope.Define(TSymbol.Create('dec',     TSymbol.TKind.Procedure, ProcType));

  FGlobalScope.Define(TSymbol.Create('length', TSymbol.TKind.Function, FuncInt));
  FGlobalScope.Define(TSymbol.Create('copy',   TSymbol.TKind.Function, FuncStr));
  FGlobalScope.Define(TSymbol.Create('format', TSymbol.TKind.Function, FuncStr));

  FGlobalScope.Define(TSymbol.Create('sin',  TSymbol.TKind.Function, FuncFloat));
  FGlobalScope.Define(TSymbol.Create('cos',  TSymbol.TKind.Function, FuncFloat));
  FGlobalScope.Define(TSymbol.Create('tan',  TSymbol.TKind.Function, FuncFloat));
  FGlobalScope.Define(TSymbol.Create('atan', TSymbol.TKind.Function, FuncFloat));
  FGlobalScope.Define(TSymbol.Create('exp',  TSymbol.TKind.Function, FuncFloat));
  FGlobalScope.Define(TSymbol.Create('ln',   TSymbol.TKind.Function, FuncFloat));
  FGlobalScope.Define(TSymbol.Create('sqrt', TSymbol.TKind.Function, FuncFloat));

  FGlobalScope.Define(TSymbol.Create('round', TSymbol.TKind.Function, FuncInt));
  FGlobalScope.Define(TSymbol.Create('trunc', TSymbol.TKind.Function, FuncInt));

  FGlobalScope.Define(TSymbol.Create('low',      TSymbol.TKind.Function, FuncInt));
  FGlobalScope.Define(TSymbol.Create('high',     TSymbol.TKind.Function, FuncInt));
  FGlobalScope.Define(TSymbol.Create('ord',      TSymbol.TKind.Function, FuncInt));
  FGlobalScope.Define(TSymbol.Create('chr',      TSymbol.TKind.Function, FuncChar));
  FGlobalScope.Define(TSymbol.Create('succ',     TSymbol.TKind.Function, FuncInt));
  FGlobalScope.Define(TSymbol.Create('pred',     TSymbol.TKind.Function, FuncInt));
  FGlobalScope.Define(TSymbol.Create('assigned', TSymbol.TKind.Function, FuncBool));
end;

procedure TSemanticAnalyzer.Error(const AMsg: String; ANode: TASTNode);
begin
  if Assigned(ANode) then
    FErrors.Add(Format('Line %d, Col %d: %s', [ANode.Line, ANode.Col, AMsg]))
  else
    FErrors.Add(AMsg);
end;

function TSemanticAnalyzer.ResolveType(AAstType: TASTType): TType;
begin
  if AAstType = nil then
    Exit(FBuiltinTypes['void']);

  case AAstType.Kind of
    TASTType.TKind.Integer:  Exit(FBuiltinTypes['integer']);
    TASTType.TKind.Single:   Exit(FBuiltinTypes['single']);
    TASTType.TKind.Boolean:  Exit(FBuiltinTypes['boolean']);
    TASTType.TKind.Byte:     Exit(FBuiltinTypes['byte']);
    TASTType.TKind.Word:     Exit(FBuiltinTypes['word']);
    TASTType.TKind.Cardinal: Exit(FBuiltinTypes['cardinal']);
    TASTType.TKind.Char:     Exit(FBuiltinTypes['char']);
    TASTType.TKind.String:   Exit(FBuiltinTypes['string']);
    TASTType.TKind.ShortInt: Exit(FBuiltinTypes['shortint']);
    TASTType.TKind.SmallInt: Exit(FBuiltinTypes['smallint']);

    TASTType.TKind.DynamicArray:
    begin
      var ElemType := ResolveType(AAstType.ElementType);

      Result := TType.Create(TType.TKind.DynamicArray, 'array of ' + ElemType.Name, 4);
      Result.ElementType := ElemType;

      FBuiltinTypes.Add(Format('DynArr_%p', [Pointer(Result)]), Result);
    end;

    TASTType.TKind.Pointer:
    begin
      var TargetElemType: TType := nil;

      if AAstType.ElementType <> nil then
      begin
        if AAstType.ElementType.Kind = TASTType.TKind.NamedAlias then
        begin
          var Sym := FCurrentScope.Resolve(AAstType.ElementType.TypeName);

          if (Sym <> nil) and (Sym.Kind = TSymbol.TKind.Type) then
            TargetElemType := Sym.SymbolType
          else
            TargetElemType := TType.Create(TType.TKind.Record, AAstType.ElementType.TypeName, 0);
        end
        else
          TargetElemType := ResolveType(AAstType.ElementType);
      end;

      var PtrName: String;

      if TargetElemType <> nil then
        PtrName := '^' + TargetElemType.Name
      else
        PtrName := 'Pointer';

      Result := TType.Create(TType.TKind.Pointer, PtrName, 4);
      Result.ElementType := TargetElemType;

      FBuiltinTypes.Add(Format('Ptr_%p', [Pointer(Result)]), Result);
    end;

    TASTType.TKind.NamedAlias:
    begin
      var Sym := FCurrentScope.Resolve(AAstType.TypeName);

      if (Sym <> nil) and (Sym.Kind = TSymbol.TKind.Type) then
        Exit(Sym.SymbolType);

      Error(Format('Unknown type identifier "%s"', [AAstType.TypeName]), AAstType);
      Exit(FBuiltinTypes['integer']);
    end;

    TASTType.TKind.Array:
    begin
      var ElemType := ResolveType(AAstType.ElementType);
      var LowVal:  TConstValue;
      var HighVal: TConstValue;

      var LowBound  := AAstType.SubrangeLow;
      var HighBound := AAstType.SubrangeHigh;

      if (AAstType.LowBoundExpr <> nil) and EvaluateConstValue(AAstType.LowBoundExpr, LowVal) then
        LowBound := Integer(LowVal.ValueInt);

      if (AAstType.HighBoundExpr <> nil) and EvaluateConstValue(AAstType.HighBoundExpr, HighVal) then
        HighBound := Integer(HighVal.ValueInt);

      AAstType.SubrangeLow  := LowBound;
      AAstType.SubrangeHigh := HighBound;

      Result := TType.CreateArray(ElemType, LowBound, HighBound);
      FBuiltinTypes.Add(Format('Array_%p', [Pointer(Result)]), Result);
    end;

    TASTType.TKind.Record:
    begin
      Result := TType.CreateRecord('Record');
      var CurrentOffset: Cardinal := 0;

      for var FieldNode in AAstType.RecordFields do
      begin
        if FieldNode is TASTVarDecl then
        begin
          var VarDecl := TASTVarDecl(FieldNode);
          var FieldType := ResolveType(VarDecl.VarType);

          for var FName in VarDecl.Names do
          begin
            var RField: TType.TRecordField;

            RField.Name   := FName;
            RField.&Type  := FieldType;
            RField.Offset := CurrentOffset;

            Result.RecordFields.Add(RField);

            var AlignedSize := (FieldType.Size + 3) and not Cardinal(3);
            Inc(CurrentOffset, AlignedSize);
          end;
        end;
      end;

      Result.Size := CurrentOffset;
      FBuiltinTypes.Add(Format('Record_%p', [Pointer(Result)]), Result);
    end;

    TASTType.TKind.Set:
    begin
      var BaseType := ResolveType(AAstType.ElementType);

      Result := TType.Create(TType.TKind.Set, 'set of ' + BaseType.Name, 4);
      Result.ElementType := BaseType;

      FBuiltinTypes.Add(Format('Set_%p', [Pointer(Result)]), Result);
    end;

    TASTType.TKind.Enum:
    begin
      Result := TType.Create(TType.TKind.Enum, 'Enum', 1);
      FBuiltinTypes.Add(Format('Enum_%p', [Pointer(Result)]), Result);
    end;
  else
    Result := FBuiltinTypes['integer'];
  end;
end;

function TSemanticAnalyzer.EvaluateConstValue(AExpr: TASTExpression; out AValue: TConstValue): Boolean;
begin
  AValue := Default(TConstValue);

  if AExpr = nil then
    Exit(False);

  if AExpr is TASTRange then
    Exit(False);

  if AExpr is TASTArrayLiteral then
  begin
    var ArrLit := TASTArrayLiteral(AExpr);
    var Mask: Cardinal := 0;

    for var Elem in ArrLit.Elements do
    begin
      if Elem is TASTRange then
      begin
        var RangeNode := TASTRange(Elem);
        var LowVal, HighVal: TConstValue;

        if EvaluateConstValue(RangeNode.LowExpr, LowVal) and EvaluateConstValue(RangeNode.HighExpr, HighVal) then
        begin
          for var k := LowVal.ValueInt to HighVal.ValueInt do
            if k < 32 then
              Mask := Mask or (1 shl k);
        end
        else
          Exit(False);
      end
      else
      begin
        var ElemVal: TConstValue;

        if EvaluateConstValue(Elem, ElemVal) then
        begin
          if ElemVal.ValueInt < 32 then
            Mask := Mask or (1 shl ElemVal.ValueInt);
        end
        else
          Exit(False);
      end;
    end;

    AValue := TConstValue.MakeSet(Mask);
    Exit(True);
  end;

  if AExpr is TASTLiteral then
  begin
    var Lit := TASTLiteral(AExpr);

    case Lit.Kind of
      TASTLiteral.TKind.Integer: AValue := TConstValue.MakeInt  (Lit.ValueInt);
      TASTLiteral.TKind.Float:   AValue := TConstValue.MakeFloat(Lit.ValueFloat);
      TASTLiteral.TKind.String:  AValue := TConstValue.MakeStr  (Lit.ValueStr);
      TASTLiteral.TKind.Char:    AValue := TConstValue.MakeStr  (Lit.ValueStr);
      TASTLiteral.TKind.Boolean: AValue := TConstValue.MakeBool (Lit.ValueBool);
      TASTLiteral.TKind.Nil:     AValue := TConstValue.MakePtr  (0);
      TASTLiteral.TKind.Set:     AValue := TConstValue.MakeSet  (Lit.ValueInt);
    end;

    Exit(True);
  end;

  if AExpr is TASTIdentifier then
  begin
    var Sym := FCurrentScope.Resolve(TASTIdentifier(AExpr).Name);

    if (Sym <> nil) and (Sym.Kind = TSymbol.TKind.Constant) then
    begin
      AValue := Sym.ConstVal;
      Exit(True);
    end;

    Exit(False);
  end;

  if AExpr is TASTIfExpression then
  begin
    var IfExp := TASTIfExpression(AExpr);
    var CondVal: TConstValue;

    if EvaluateConstValue(IfExp.Condition, CondVal) and (CondVal.Kind = TConstValue.TKind.Boolean) then
    begin
      if CondVal.ValueBool then
        Exit(EvaluateConstValue(IfExp.ThenExpr, AValue))
      else
        Exit(EvaluateConstValue(IfExp.ElseExpr, AValue));
    end;

    Exit(False);
  end;

  if AExpr is TASTMemberAccess then
  begin
    var MemberAcc := TASTMemberAccess(AExpr);

    if MemberAcc.Expression is TASTIdentifier then
    begin
      var IdentName := TASTIdentifier(MemberAcc.Expression).Name;
      var Sym := FCurrentScope.Resolve(IdentName);

      if (Sym <> nil) and (Sym.Kind = TSymbol.TKind.Type) and (Sym.SymbolType.Kind = TType.TKind.Enum) then
        for var Elem in Sym.SymbolType.EnumElements do
          if SameText(Elem.Name, MemberAcc.MemberName) then
          begin
            AValue := TConstValue.MakeInt(Cardinal(Elem.Value));
            Exit(True);
          end;

      var QualifiedSym := FCurrentScope.Resolve(IdentName + '.' + MemberAcc.MemberName);

      if (QualifiedSym <> nil) and (QualifiedSym.Kind = TSymbol.TKind.Constant) then
      begin
        AValue := QualifiedSym.ConstVal;
        Exit(True);
      end;
    end;

    Exit(False);
  end;

  if AExpr is TASTCallExpr then
  begin
    var Call := TASTCallExpr(AExpr);
    var CalleeLower := Lowercase(Call.CalleeName);

    if (CalleeLower = 'sizeof') and (Call.Arguments.Count = 1) then
    begin
      var Arg := Call.Arguments[0];

      if Arg is TASTIdentifier then
      begin
        var Sym := FCurrentScope.Resolve(TASTIdentifier(Arg).Name);

        if Sym <> nil then
        begin
          if Sym.Kind = TSymbol.TKind.Type then
            AValue := TConstValue.MakeInt(Sym.SymbolType.Size)

          else if Sym.SymbolType <> nil then
            AValue := TConstValue.MakeInt(Sym.SymbolType.Size);

          Exit(True);
        end;
      end;
    end;

    if (CalleeLower = 'sin')  or (CalleeLower = 'cos')   or (CalleeLower = 'tan')   or
       (CalleeLower = 'atan') or (CalleeLower = 'exp')   or (CalleeLower = 'ln')    or
       (CalleeLower = 'sqrt') or (CalleeLower = 'round') or (CalleeLower = 'trunc') then
   begin
      if Call.Arguments.Count = 1 then
      begin
        var ArgVal: TConstValue;

        if EvaluateConstValue(Call.Arguments[0], ArgVal) then
        begin
          var FVal: Single;

          if ArgVal.Kind = TConstValue.TKind.Single then
            FVal := ArgVal.ValueFloat
          else if ArgVal.Kind = TConstValue.TKind.Integer then
            FVal := ArgVal.ValueInt
          else
            Exit(False);

               if CalleeLower = 'sin'   then AValue := TConstValue.MakeFloat(System.Sin(FVal))
          else if CalleeLower = 'cos'   then AValue := TConstValue.MakeFloat(System.Cos(FVal))
          else if CalleeLower = 'tan'   then AValue := TConstValue.MakeFloat(System.Tangent(FVal))
          else if CalleeLower = 'atan'  then AValue := TConstValue.MakeFloat(System.ArcTan(FVal))
          else if CalleeLower = 'exp'   then AValue := TConstValue.MakeFloat(System.Exp(FVal))
          else if CalleeLower = 'ln'    then begin if FVal > 0 then AValue := TConstValue.MakeFloat(System.Ln(FVal)) else Exit(False); end
          else if CalleeLower = 'sqrt'  then begin if FVal >= 0 then AValue := TConstValue.MakeFloat(System.Sqrt(FVal)) else Exit(False); end
          else if CalleeLower = 'round' then AValue := TConstValue.MakeInt(Cardinal(System.Round(FVal)))
          else if CalleeLower = 'trunc' then AValue := TConstValue.MakeInt(Cardinal(System.Trunc(FVal)));

          Exit(True);
        end;
      end;
   end;

    if (CalleeLower = 'low') or (CalleeLower = 'high') then
    begin
      if Call.Arguments.Count = 1 then
      begin
        var Arg := Call.Arguments[0];

        if Arg is TASTIdentifier then
        begin
          var Sym := FCurrentScope.Resolve(TASTIdentifier(Arg).Name);
          if (Sym <> nil) and (Sym.SymbolType <> nil) then
          begin
            if Sym.SymbolType.Kind = TType.TKind.Array then
            begin
              if CalleeLower = 'low' then
                AValue := TConstValue.MakeInt(Cardinal(Sym.SymbolType.SubrangeLow))
              else
                AValue := TConstValue.MakeInt(Cardinal(Sym.SymbolType.SubrangeHigh));

              Exit(True);
            end;

            if Sym.SymbolType.Kind = TType.TKind.Enum then
            begin
              if CalleeLower = 'low' then
                AValue := TConstValue.MakeInt(0)
              else
                AValue := TConstValue.MakeInt(Cardinal(Sym.SymbolType.EnumElements.Count - 1));

              Exit(True);
            end;
          end;
        end;
      end;

      Exit(False);
    end;

    if (CalleeLower = 'length') and (Call.Arguments.Count = 1) then
    begin
      var Arg := Call.Arguments[0];

      if Arg is TASTIdentifier then
      begin
        var Sym := FCurrentScope.Resolve(TASTIdentifier(Arg).Name);

        if (Sym <> nil) and (Sym.SymbolType <> nil) and (Sym.SymbolType.Kind = TType.TKind.Array) then
        begin
          var Count := (Sym.SymbolType.SubrangeHigh - Sym.SymbolType.SubrangeLow) + 1;

          if Count < 0 then
            Count := 0;

          AValue := TConstValue.MakeInt(Cardinal(Count));

          Exit(True);
        end;
      end;
    end;

    if (CalleeLower = 'ord') and (Call.Arguments.Count = 1) then
    begin
      var SubVal: TConstValue;

      if EvaluateConstValue(Call.Arguments[0], SubVal) then
      begin
        if SubVal.Kind = TConstValue.TKind.String then
        begin
          if Length(SubVal.ValueStr) > 0 then
            AValue := TConstValue.MakeInt(Ord(SubVal.ValueStr[1]))
          else
            AValue := TConstValue.MakeInt(0);
        end
        else
          AValue := TConstValue.MakeInt(SubVal.ValueInt);

        Exit(True);
      end;
    end;

    if (CalleeLower = 'chr') and (Call.Arguments.Count = 1) then
    begin
      var SubVal: TConstValue;

      if EvaluateConstValue(Call.Arguments[0], SubVal) then
      begin
        AValue := TConstValue.MakeStr(Char(SubVal.ValueInt and $FF));
        Exit(True);
      end;
    end;

    if (CalleeLower = 'succ') and (Call.Arguments.Count = 1) then
    begin
      var SubVal: TConstValue;

      if EvaluateConstValue(Call.Arguments[0], SubVal) then
      begin
        AValue := TConstValue.MakeInt(SubVal.ValueInt + 1);
        Exit(True);
      end;
    end;

    if (CalleeLower = 'pred') and (Call.Arguments.Count = 1) then
    begin
      var SubVal: TConstValue;

      if EvaluateConstValue(Call.Arguments[0], SubVal) then
      begin
        AValue := TConstValue.MakeInt(SubVal.ValueInt - 1);
        Exit(True);
      end;
    end;

    Exit(False);
  end;

  if AExpr is TASTTypeCast then
  begin
    var TypeCast := TASTTypeCast(AExpr);

    if EvaluateConstValue(TypeCast.Expression, AValue) then
    begin
      if (TypeCast.TargetType <> nil) and (TypeCast.TargetType.Kind = TASTType.TKind.Byte) then
        AValue.ValueInt := AValue.ValueInt and $FF

      else if (TypeCast.TargetType <> nil) and (TypeCast.TargetType.Kind = TASTType.TKind.Word) then
        AValue.ValueInt := AValue.ValueInt and $FFFF;

      Exit(True);
    end;

    Exit(False);
  end;

  if AExpr is TASTBinary then
  begin
    var Bin := TASTBinary(AExpr);
    var LeftVal, RightVal: TConstValue;

    if EvaluateConstValue(Bin.Left, LeftVal) and EvaluateConstValue(Bin.Right, RightVal) then
    begin
      if (LeftVal.Kind = TConstValue.TKind.String) and (RightVal.Kind = TConstValue.TKind.String) and (Bin.Op = TASTBinary.TOp.Add) then
      begin
        AValue := TConstValue.MakeStr(LeftVal.ValueStr + RightVal.ValueStr);
        Exit(True);
      end;

      if (LeftVal.Kind = TConstValue.TKind.Single) or (RightVal.Kind = TConstValue.TKind.Single) then
      begin
        var LF: Single;
        var RF: Single;

        if LeftVal.Kind  = TConstValue.TKind.Single then LF := LeftVal.ValueFloat  else LF := LeftVal.ValueInt;
        if RightVal.Kind = TConstValue.TKind.Single then RF := RightVal.ValueFloat else RF := RightVal.ValueInt;

        case Bin.Op of
          TASTBinary.TOp.Add:      AValue := TConstValue.MakeFloat(LF + RF);
          TASTBinary.TOp.Subtract: AValue := TConstValue.MakeFloat(LF - RF);
          TASTBinary.TOp.Multiply: AValue := TConstValue.MakeFloat(LF * RF);

          TASTBinary.TOp.Divide:
            if RF <> 0.0 then
              AValue := TConstValue.MakeFloat(LF / RF)
            else
            begin
              Error('Division by zero in constant expression', AExpr);
              Exit(False);
            end;
        else
          Exit(False);
        end;

        Exit(True);
      end;

      if (LeftVal.Kind in [TConstValue.TKind.Integer, TConstValue.TKind.Pointer, TConstValue.TKind.Boolean]) and (RightVal.Kind in [TConstValue.TKind.Integer, TConstValue.TKind.Pointer, TConstValue.TKind.Boolean]) then
      begin
        var L := LeftVal.ValueInt;
        var R := RightVal.ValueInt;

        case Bin.Op of
          TASTBinary.TOp.Add:       AValue := TConstValue.MakeInt(L + R);
          TASTBinary.TOp.Subtract:  AValue := TConstValue.MakeInt(L - R);
          TASTBinary.TOp.Multiply:  AValue := TConstValue.MakeInt(L * R);

          TASTBinary.TOp.IntDivide:
            if R <> 0 then
              AValue := TConstValue.MakeInt(L div R)
            else
            begin
              Error('Division by zero in constant expression', AExpr);
              Exit(False);
            end;

          TASTBinary.TOp.Modulo:
            if R <> 0 then
              AValue := TConstValue.MakeInt(L mod R)
            else
            begin
              Error('Division by zero in constant expression', AExpr);
              Exit(False);
            end;

          TASTBinary.TOp.Shl: AValue := TConstValue.MakeInt(L shl R);
          TASTBinary.TOp.Shr: AValue := TConstValue.MakeInt(L shr R);
          TASTBinary.TOp.Sar: AValue := TConstValue.MakeInt(SAR(L, R));

          TASTBinary.TOp.And: AValue := TConstValue.MakeInt(L and R);
          TASTBinary.TOp.Or:  AValue := TConstValue.MakeInt(L or R);
          TASTBinary.TOp.Xor: AValue := TConstValue.MakeInt(L xor R);

          TASTBinary.TOp.Equal:        AValue := TConstValue.MakeBool(L = R);
          TASTBinary.TOp.NotEqual:     AValue := TConstValue.MakeBool(L <> R);
          TASTBinary.TOp.Less:         AValue := TConstValue.MakeBool(Integer(L) < Integer(R));
          TASTBinary.TOp.LessEqual:    AValue := TConstValue.MakeBool(Integer(L) <= Integer(R));
          TASTBinary.TOp.Greater:      AValue := TConstValue.MakeBool(Integer(L) > Integer(R));
          TASTBinary.TOp.GreaterEqual: AValue := TConstValue.MakeBool(Integer(L) >= Integer(R));
        else
          Exit(False);
        end;

        Exit(True);
      end;
    end;

    Exit(False);
  end;

  if AExpr is TASTUnary then
  begin
    var Un := TASTUnary(AExpr);
    var SubVal: TConstValue;

    if EvaluateConstValue(Un.Operand, SubVal) then
    begin
      case Un.Op of
        TASTUnary.TOp.Negate:
          if SubVal.Kind = TConstValue.TKind.Single then
            AValue := TConstValue.MakeFloat(-SubVal.ValueFloat)
          else
            AValue := TConstValue.MakeInt(Cardinal(-Int32(SubVal.ValueInt)));

        TASTUnary.TOp.Not:
          if SubVal.Kind = TConstValue.TKind.Boolean then
            AValue := TConstValue.MakeBool(not SubVal.ValueBool)
          else
            AValue := TConstValue.MakeInt(not SubVal.ValueInt);
      else
        Exit(False);
      end;

      Exit(True);
    end;

    Exit(False);
  end;

  Result := False;
end;

function TSemanticAnalyzer.FoldExpression(var AExpr: TASTExpression): Boolean;
var
  ConstVal: TConstValue;
  OldLine:  Integer;
  OldCol:   Integer;
  OldExpr:  TASTExpression;
begin
  Result := False;

  if AExpr = nil then
    Exit;

  if AExpr is TASTLiteral then
    Exit(True);

  if AExpr is TASTBinary then
  begin
    var Bin := TASTBinary(AExpr);

    var L := Bin.Left;
    var R := Bin.Right;

    if FoldExpression(L) then Bin.Left := L;
    if FoldExpression(R) then Bin.Right := R;
  end
  else if AExpr is TASTUnary then
  begin
    var Un := TASTUnary(AExpr);
    var Op := Un.Operand;

    if FoldExpression(Op) then Un.Operand := Op;
  end
  else if AExpr is TASTIfExpression then
  begin
    var IfExp := TASTIfExpression(AExpr);

    var C := IfExp.Condition;
    var T := IfExp.ThenExpr;
    var E := IfExp.ElseExpr;

    if FoldExpression(C) then IfExp.Condition := C;
    if FoldExpression(T) then IfExp.ThenExpr  := T;
    if FoldExpression(E) then IfExp.ElseExpr  := E;
  end;

  if EvaluateConstValue(AExpr, ConstVal) then
  begin
    OldLine := AExpr.Line;
    OldCol  := AExpr.Col;
    OldExpr := AExpr;

    case ConstVal.Kind of
      TConstValue.TKind.Integer: AExpr := TASTLiteral.CreateInt  (ConstVal.ValueInt,   OldLine, OldCol);
      TConstValue.TKind.Single:  AExpr := TASTLiteral.CreateFloat(ConstVal.ValueFloat, OldLine, OldCol);
      TConstValue.TKind.Boolean: AExpr := TASTLiteral.CreateBool (ConstVal.ValueBool,  OldLine, OldCol);
      TConstValue.TKind.Pointer: AExpr := TASTLiteral.CreateInt  (ConstVal.ValueInt,   OldLine, OldCol);
      TConstValue.TKind.Set:     AExpr := TASTLiteral.CreateSet  (ConstVal.ValueInt,   OldLine, OldCol);

      TConstValue.TKind.String:
        if Length(ConstVal.ValueStr) = 1 then
          AExpr := TASTLiteral.CreateChar(ConstVal.ValueStr[1], OldLine, OldCol)
        else
          AExpr := TASTLiteral.CreateStr(ConstVal.ValueStr, OldLine, OldCol);
    else
      Exit(False);
    end;

    OldExpr.Free;
    Result := True;
  end;
end;

procedure TSemanticAnalyzer.FoldExpressionList(AList: TObjectList<TASTExpression>);
begin
  if AList = nil then
    Exit;

  for var i := 0 to AList.Count - 1 do
  begin
    var Expr := AList[i];

    if not (Expr is TASTLiteral) and FoldExpression(Expr) then
    begin
      AList.OwnsObjects := False;
      AList[i] := Expr;
      AList.OwnsObjects := True;
    end;
  end;
end;

function TSemanticAnalyzer.CheckTypeCompatibility(TargetType, SourceType: TType): Boolean;
begin
  if (TargetType = nil) or (SourceType = nil) then
    Exit(False);

  if TargetType.Kind = SourceType.Kind then
    Exit(True);

  if TargetType.IsSet and SourceType.IsSet then
    Exit(True);

  if TargetType.IsSet and (SourceType.Kind = TType.TKind.Integer) then
    Exit(True);

  if SourceType.IsSet and (TargetType.Kind = TType.TKind.Integer) then
    Exit(True);

  if (TargetType.Kind = TType.TKind.Single) and SourceType.IsInteger then
    Exit(True);

  if TargetType.IsInteger and SourceType.IsInteger then
    Exit(True);

  if (SourceType.Kind = TType.TKind.NilType) and (TargetType.Kind in [TType.TKind.Pointer, TType.TKind.String]) then
    Exit(True);

  if (TargetType.Kind = TType.TKind.String) and (SourceType.Kind = TType.TKind.Char) then
    Exit(True);

  if (TargetType.Kind = TType.TKind.Char) and (SourceType.Kind = TType.TKind.String) then
    Exit(True);

  if (TargetType.Kind = TType.TKind.Char) and (SourceType.Kind = TType.TKind.Byte) then
    Exit(True);

  if (TargetType.Kind = TType.TKind.Byte) and (SourceType.Kind = TType.TKind.Char) then
    Exit(True);

  if TargetType.IsDynamicArray and SourceType.IsDynamicArray then
    Exit(CheckTypeCompatibility(TargetType.ElementType, SourceType.ElementType));

  if TargetType.IsDynamicArray and (SourceType.Kind = TType.TKind.NilType) then
    Exit(True);

  Result := False;
end;

function TSemanticAnalyzer.AnalyzeLiteral(ALiteral: TASTLiteral): TType;
begin
  case ALiteral.Kind of
    TASTLiteral.TKind.Integer: Result := FBuiltinTypes['integer'];
    TASTLiteral.TKind.Float:   Result := FBuiltinTypes['single'];
    TASTLiteral.TKind.String:  Result := FBuiltinTypes['string'];
    TASTLiteral.TKind.Char:    Result := FBuiltinTypes['char'];
    TASTLiteral.TKind.Boolean: Result := FBuiltinTypes['boolean'];
    TASTLiteral.TKind.Nil:     Result := FBuiltinTypes['nil'];
    TASTLiteral.TKind.Set:
    begin
      Result := TType.Create(TType.TKind.Set, 'Set', 4);
      FBuiltinTypes.Add(Format('SetLit_%p', [Pointer(Result)]), Result);
    end;
  else
    Result := FBuiltinTypes['integer'];
  end;
end;

function TSemanticAnalyzer.AnalyzeIdentifier(AIdent: TASTIdentifier): TType;
begin
  for var i := FWithStack.Count - 1 downto 0 do
  begin
    var RecType := FWithStack[i].RecordType;

    if RecType <> nil then
    begin
      var Field: TType.TRecordField;

      if RecType.FindField(AIdent.Name, Field) then
        Exit(Field.&Type);

      var Prop: TType.TProperty;

      if RecType.FindProperty(AIdent.Name, Prop) then
        Exit(Prop.PropType);

      var MethodDecl: TASTRoutineDecl;

      if (RecType.Methods <> nil) and RecType.Methods.TryGetValue(LowerCase(AIdent.Name), MethodDecl) then
      begin
        if MethodDecl.IsFunction and Assigned(MethodDecl.ReturnType) then
          Exit(ResolveType(MethodDecl.ReturnType))
        else
          Exit(FBuiltinTypes['void']);
      end;
    end;
  end;

  var LocalSym := FCurrentScope.ResolveLocal(AIdent.Name);

  if LocalSym <> nil then
  begin
    if LocalSym.Kind = TSymbol.TKind.Function then
    begin
      if Assigned(LocalSym.SymbolType) and Assigned(LocalSym.SymbolType.ReturnType) then
        Exit(LocalSym.SymbolType.ReturnType)
      else
        Exit(FBuiltinTypes['void']);
    end;

    Exit(LocalSym.SymbolType);
  end;

  var SelfSym := FCurrentScope.Resolve('self');

  if (SelfSym <> nil) and (SelfSym.SymbolType <> nil) and (SelfSym.SymbolType.Kind = TType.TKind.Record) then
  begin
    var Field: TType.TRecordField;

    if SelfSym.SymbolType.FindField(AIdent.Name, Field) then
      Exit(Field.&Type);

    var Prop: TType.TProperty;

    if SelfSym.SymbolType.FindProperty(AIdent.Name, Prop) then
      Exit(Prop.PropType);

    var MethodDecl: TASTRoutineDecl;

    if (SelfSym.SymbolType.Methods <> nil) and SelfSym.SymbolType.Methods.TryGetValue(LowerCase(AIdent.Name), MethodDecl) then
    begin
      if MethodDecl.IsFunction and Assigned(MethodDecl.ReturnType) then
        Exit(ResolveType(MethodDecl.ReturnType))
      else
        Exit(FBuiltinTypes['void']);
    end;
  end;

  var GlobalSym := FCurrentScope.Resolve(AIdent.Name);

  if GlobalSym <> nil then
  begin
    if GlobalSym.Kind = TSymbol.TKind.Function then
    begin
      if Assigned(GlobalSym.SymbolType) and Assigned(GlobalSym.SymbolType.ReturnType) then
        Exit(GlobalSym.SymbolType.ReturnType)
      else
        Exit(FBuiltinTypes['void']);
    end;

    Exit(GlobalSym.SymbolType);
  end;

  Error(Format('Undeclared identifier "%s"', [AIdent.Name]), AIdent);
  Result := FBuiltinTypes['integer'];
end;

function TSemanticAnalyzer.AnalyzeMemberAccess(AMember: TASTMemberAccess): TType;
begin
  if AMember.Expression is TASTIdentifier then
  begin
    var IdentName := TASTIdentifier(AMember.Expression).Name;
    var Sym := FCurrentScope.Resolve(IdentName);

    if (Sym <> nil) and (Sym.Kind = TSymbol.TKind.Type) and (Sym.SymbolType <> nil) and (Sym.SymbolType.Kind = TType.TKind.Enum) then
    begin
      for var Elem in Sym.SymbolType.EnumElements do
        if SameText(Elem.Name, AMember.MemberName) then
          Exit(Sym.SymbolType);

      Error(Format('Enum "%s" has no element named "%s"', [Sym.Name, AMember.MemberName]), AMember);
      Exit(Sym.SymbolType);
    end;
  end;

  var BaseType := AnalyzeExpression(AMember.Expression);

  if (BaseType.Kind = TType.TKind.Pointer) and (BaseType.ElementType <> nil) then
    BaseType := BaseType.ElementType;

  if BaseType.Kind = TType.TKind.Record then
  begin
    var Prop: TType.TProperty;

    if BaseType.FindProperty(AMember.MemberName, Prop) then
    begin
      if Length(Prop.ReadSpec) = 0 then
        Error(Format('Property "%s" is write-only', [Prop.Name]), AMember);

      if Prop.IsDirectRead then
      begin
        AMember.FieldOffset := Prop.ReadOffset;
        Exit(Prop.PropType);
      end;

      var MethodDecl: TASTRoutineDecl;

      if (BaseType.Methods <> nil) and BaseType.Methods.TryGetValue(LowerCase(Prop.ReadSpec), MethodDecl) then
        if MethodDecl.IsFunction and Assigned(MethodDecl.ReturnType) then
          Exit(ResolveType(MethodDecl.ReturnType));

      Exit(Prop.PropType);
    end;

    var Field: TType.TRecordField;

    if BaseType.FindField(AMember.MemberName, Field) then
    begin
      AMember.FieldOffset := Field.Offset;
      Exit(Field.&Type);
    end;

    var MethodDecl: TASTRoutineDecl;

    if (BaseType.Methods <> nil) and BaseType.Methods.TryGetValue(LowerCase(AMember.MemberName), MethodDecl) then
    begin
      if MethodDecl.IsFunction and Assigned(MethodDecl.ReturnType) then
        Exit(ResolveType(MethodDecl.ReturnType))
      else
        Exit(FBuiltinTypes['void']);
    end;

    Error(Format('Record "%s" has no field, method, or property named "%s"', [BaseType.Name, AMember.MemberName]), AMember);
    Exit(FBuiltinTypes['integer']);
  end;

  Error('Cannot access member of non-record and non-enum type', AMember);
  Result := FBuiltinTypes['integer'];
end;

function TSemanticAnalyzer.AnalyzeArrayAccess(AArrayAcc: TASTArrayAccess): TType;
begin
  FoldExpressionList(AArrayAcc.IndexExprs);

  var CurrentType := AnalyzeExpression(AArrayAcc.ArrayExpr);

  for var i := 0 to AArrayAcc.IndexExprs.Count - 1 do
  begin
    var IdxExpr := AArrayAcc.IndexExprs[i];
    var IdxType := AnalyzeExpression(IdxExpr);

    if not IdxType.IsInteger then
      Error('Array index expression must evaluate to an integer', IdxExpr);

    if CurrentType.IsString then
    begin
      AArrayAcc.ElementSize := 1;
      AArrayAcc.LowBound    := 1;

      CurrentType := FBuiltinTypes['char'];
    end

    else if CurrentType.IsDynamicArray then
    begin
      AArrayAcc.LowBound := 0;

      if CurrentType.ElementType <> nil then
        AArrayAcc.ElementSize := CurrentType.ElementType.Size
      else
        AArrayAcc.ElementSize := 4;

      CurrentType := CurrentType.ElementType;
    end

    else if CurrentType.Kind = TType.TKind.Pointer then
    begin
      if Assigned(CurrentType.ElementType) then
      begin
        if (CurrentType.ElementType.Kind = TType.TKind.Array) and Assigned(CurrentType.ElementType.ElementType) then
        begin
          AArrayAcc.ElementSize := CurrentType.ElementType.ElementType.Size;
          AArrayAcc.LowBound    := CurrentType.ElementType.SubrangeLow;

          CurrentType := CurrentType.ElementType.ElementType;
        end
        else
        begin
          AArrayAcc.ElementSize := CurrentType.ElementType.Size;
          AArrayAcc.LowBound    := 0;

          CurrentType := CurrentType.ElementType;
        end;
      end
      else
      begin
        AArrayAcc.ElementSize := 1;
        AArrayAcc.LowBound    := 0;

        CurrentType := FBuiltinTypes['byte'];
      end;
    end

    else if CurrentType.Kind = TType.TKind.Array then
    begin
      AArrayAcc.LowBound := CurrentType.SubrangeLow;

      if Assigned(CurrentType.ElementType) then
      begin
        AArrayAcc.ElementSize := CurrentType.ElementType.Size;

        CurrentType := CurrentType.ElementType;
      end
      else
      begin
        AArrayAcc.ElementSize := 4;

        CurrentType := FBuiltinTypes['integer'];
      end;
    end
    else
    begin
      Error('Cannot index non-array and non-pointer type', AArrayAcc);
      Exit(FBuiltinTypes['integer']);
    end;
  end;

  Result := CurrentType;
end;

function TSemanticAnalyzer.AnalyzeCallExpr(ACall: TASTCallExpr): TType;
var
  CalleeLower: String;
begin
  FoldExpressionList(ACall.Arguments);

  CalleeLower := LowerCase(ACall.CalleeName);

  if ACall.BaseExpr = nil then
  begin
    for var i := FWithStack.Count - 1 downto 0 do
    begin
      var RecType := FWithStack[i].RecordType;

      if RecType <> nil then
      begin
        var MethodDecl: TASTRoutineDecl;

        if (RecType.Methods <> nil) and RecType.Methods.TryGetValue(LowerCase(ACall.CalleeName), MethodDecl) then
        begin
          for var Arg in ACall.Arguments do
            AnalyzeExpression(Arg);

          if MethodDecl.IsFunction and Assigned(MethodDecl.ReturnType) then
            Exit(ResolveType(MethodDecl.ReturnType))
          else
            Exit(FBuiltinTypes['void']);
        end;
      end;
    end;
  end;

  if ACall.BaseExpr <> nil then
  begin
    var BaseType := AnalyzeExpression(ACall.BaseExpr);

    if (BaseType.Kind = TType.TKind.Pointer) and (BaseType.ElementType <> nil) then
      BaseType := BaseType.ElementType;

    if BaseType.Kind = TType.TKind.Record then
    begin
      var MethodDecl: TASTRoutineDecl;

      if (BaseType.Methods <> nil) and BaseType.Methods.TryGetValue(LowerCase(ACall.CalleeName), MethodDecl) then
      begin
        for var Arg in ACall.Arguments do
          AnalyzeExpression(Arg);

        if MethodDecl.IsFunction and Assigned(MethodDecl.ReturnType) then
          Exit(ResolveType(MethodDecl.ReturnType))
        else
          Exit(FBuiltinTypes['void']);
      end;

      Error(Format('Record "%s" has no method named "%s"', [BaseType.Name, ACall.CalleeName]), ACall);
      Exit(FBuiltinTypes['void']);
    end;
  end;

  if (CalleeLower = 'sin')  or (CalleeLower = 'cos')   or (CalleeLower = 'tan')   or
     (CalleeLower = 'atan') or (CalleeLower = 'exp')   or (CalleeLower = 'ln')    or
     (CalleeLower = 'sqrt') or (CalleeLower = 'round') or (CalleeLower = 'trunc') then
  begin
    if ACall.Arguments.Count <> 1 then
      Error(Format('Function "%s" expects exactly 1 argument', [ACall.CalleeName]), ACall)
    else
    begin
      var ArgType := AnalyzeExpression(ACall.Arguments[0]);

      if not ArgType.IsNumeric then
        Error(Format('Argument to "%s" must be a numeric expression', [ACall.CalleeName]), ACall.Arguments[0]);
    end;

    if (CalleeLower = 'round') or (CalleeLower = 'trunc') then
      Exit(FBuiltinTypes['integer'])
    else
      Exit(FBuiltinTypes['single']);
  end;

  if CalleeLower = 'length' then
  begin
    if ACall.Arguments.Count <> 1 then
      Error('Length expects exactly 1 argument', ACall)
    else
    begin
      var ArgType := AnalyzeExpression(ACall.Arguments[0]);

      if (not ArgType.IsString) and (not ArgType.IsDynamicArray) and (ArgType.Kind <> TType.TKind.Array) then
        Error('Argument to Length must be an array or string', ACall.Arguments[0]);
    end;

    Exit(FBuiltinTypes['integer']);
  end;

  if CalleeLower = 'setlength' then
  begin
    if ACall.Arguments.Count <> 2 then
      Error('SetLength expects exactly 2 arguments (Array, NewLength)', ACall)
    else
    begin
      var TargetType := AnalyzeExpression(ACall.Arguments[0]);
      var LenType    := AnalyzeExpression(ACall.Arguments[1]);

      if (not TargetType.IsDynamicArray) and (not TargetType.IsString) then
        Error('First argument to SetLength must be a dynamic array or string', ACall.Arguments[0]);

      if not LenType.IsInteger then
        Error('Second argument to SetLength must be an integer expression', ACall.Arguments[1]);
    end;

    Exit(FBuiltinTypes['void']);
  end;

  if CalleeLower = 'copy' then
  begin
    if ACall.Arguments.Count <> 3 then
      Error('Copy expects 3 arguments: (String, StartIndex, Count)', ACall)
    else
    begin
      var SType := AnalyzeExpression(ACall.Arguments[0]);
      var IdxType := AnalyzeExpression(ACall.Arguments[1]);
      var CntType := AnalyzeExpression(ACall.Arguments[2]);

      if not SType.IsString    then Error('First argument to Copy must be a string',    ACall.Arguments[0]);
      if not IdxType.IsInteger then Error('Second argument to Copy must be an integer', ACall.Arguments[1]);
      if not CntType.IsInteger then Error('Third argument to Copy must be an integer',  ACall.Arguments[2]);
    end;

    Exit(FBuiltinTypes['string']);
  end;

  if CalleeLower = 'format' then
  begin
    for var Arg in ACall.Arguments do
      AnalyzeExpression(Arg);

    Exit(FBuiltinTypes['string']);
  end;

  if (CalleeLower = 'inc') or (CalleeLower = 'dec') then
  begin
    if (ACall.Arguments.Count < 1) or (ACall.Arguments.Count > 2) then
      Error(Format('Procedure "%s" expects 1 or 2 arguments', [ACall.CalleeName]), ACall)
    else
    begin
      var TargetType := AnalyzeExpression(ACall.Arguments[0]);

      if (not TargetType.IsInteger) and (TargetType.Kind <> TType.TKind.Pointer) and (TargetType.Kind <> TType.TKind.Enum) then
        Error(Format('First argument to "%s" must be an ordinal variable or pointer', [ACall.CalleeName]), ACall.Arguments[0]);

      if ACall.Arguments.Count = 2 then
      begin
        var StepType := AnalyzeExpression(ACall.Arguments[1]);

        if not StepType.IsInteger then
          Error('Step count must be an integer expression', ACall.Arguments[1]);
      end;
    end;

    Exit(FBuiltinTypes['void']);
  end;

   if (CalleeLower = 'high') or (CalleeLower = 'low') then
  begin
    if ACall.Arguments.Count <> 1 then
      Error(Format('%s expects exactly 1 argument', [ACall.CalleeName]), ACall)
    else
    begin
      var ArgType := AnalyzeExpression(ACall.Arguments[0]);

      if (ArgType.Kind <> TType.TKind.Array) and (not ArgType.IsDynamicArray) and (not ArgType.IsString) and (ArgType.Kind <> TType.TKind.Enum) then
        Error(Format('Argument to %s must be an array, string, or enum', [ACall.CalleeName]), ACall.Arguments[0]);
    end;

    Exit(FBuiltinTypes['integer']);
  end;

  if CalleeLower = 'ord' then
  begin
    if ACall.Arguments.Count <> 1 then
      Error('Ord() expects exactly 1 argument', ACall)
    else
      AnalyzeExpression(ACall.Arguments[0]);

    Exit(FBuiltinTypes['integer']);
  end;

  if CalleeLower = 'chr' then
  begin
    if ACall.Arguments.Count <> 1 then
      Error('Chr() expects exactly 1 argument', ACall)
    else
    begin
      var ArgType := AnalyzeExpression(ACall.Arguments[0]);

      if not ArgType.IsInteger then
        Error('Argument to Chr() must be an integer', ACall.Arguments[0]);
    end;

    Exit(FBuiltinTypes['char']);
  end;

  if (CalleeLower = 'succ') or (CalleeLower = 'pred') then
  begin
    if ACall.Arguments.Count <> 1 then
      Error(Format('%s() expects exactly 1 argument', [ACall.CalleeName]), ACall);

    var ArgType := AnalyzeExpression(ACall.Arguments[0]);
    Exit(ArgType);
  end;

  if CalleeLower = 'assigned' then
  begin
    if ACall.Arguments.Count <> 1 then
      Error('Assigned() expects exactly 1 pointer/string argument', ACall)
    else
    begin
      var ArgType := AnalyzeExpression(ACall.Arguments[0]);

      if (ArgType.Kind <> TType.TKind.Pointer) and (not ArgType.IsString) then
        Error('Argument to Assigned() must be a pointer or string', ACall.Arguments[0]);
    end;

    Exit(FBuiltinTypes['boolean']);
  end;

  var Sym := FCurrentScope.Resolve(ACall.CalleeName);

  if Sym = nil then
  begin
    Error(Format('Undeclared routine or type "%s"', [ACall.CalleeName]), ACall);
    Exit(FBuiltinTypes['integer']);
  end;

  if Sym.Kind = TSymbol.TKind.Type then
  begin
    if ACall.Arguments.Count = 1 then
      AnalyzeExpression(ACall.Arguments[0])
    else
      Error('Typecast expects exactly 1 argument', ACall);

    Exit(Sym.SymbolType);
  end;

  if not (Sym.Kind in [TSymbol.TKind.Procedure, TSymbol.TKind.Function]) then
  begin
    Error(Format('"%s" is not a procedure, function, or typecast', [ACall.CalleeName]), ACall);
    Exit(FBuiltinTypes['integer']);
  end;

  if (Sym.Declaration <> nil) and not Sym.IsVarArgs then
    if ACall.Arguments.Count <> Sym.Declaration.Params.Count then
      Error(Format('Routine "%s" expects %d arguments, but got %d', [ACall.CalleeName, Sym.Declaration.Params.Count, ACall.Arguments.Count]), ACall);

  for var Arg in ACall.Arguments do
    AnalyzeExpression(Arg);

  if Assigned(Sym.SymbolType) then
    Result := Sym.SymbolType.ReturnType
  else
    Result := FBuiltinTypes['void'];
end;

function TSemanticAnalyzer.AnalyzeUnary(AUnary: TASTUnary): TType;
begin
  var OpType := AnalyzeExpression(AUnary.Operand);

  case AUnary.Op of
    TASTUnary.TOp.Negate:
    begin
      if not OpType.IsNumeric then
        Error('Unary "-" requires a numeric operand', AUnary);

      Result := OpType;
    end;

    TASTUnary.TOp.Not:
    begin
      if (not OpType.IsBoolean) and (not OpType.IsInteger) then
        Error('Operator "not" requires boolean or integer operand', AUnary);

      Result := OpType;
    end;

    TASTUnary.TOp.Dereference:
    begin
      if OpType.Kind <> TType.TKind.Pointer then
        Error('Operator "^" requires pointer operand', AUnary);

      if Assigned(OpType.ElementType) then
        Result := OpType.ElementType
      else
        Result := FBuiltinTypes['integer'];
    end;

    TASTUnary.TOp.AddressOf:
    begin
      Result := TType.Create(TType.TKind.Pointer, '^' + OpType.Name, 4);
      Result.ElementType := OpType;

      FBuiltinTypes.Add(Format('Ptr_%p', [Pointer(Result)]), Result);
    end;
  else
    Result := OpType;
  end;
end;

function TSemanticAnalyzer.AnalyzeBinary(ABinary: TASTBinary): TType;
begin
  var LeftType  := AnalyzeExpression(ABinary.Left);
  var RightType := AnalyzeExpression(ABinary.Right);

  if ABinary.Op = TASTBinary.TOp.In then
  begin
    if not RightType.IsSet then
      Error('Right operand of "in" must be a set', ABinary.Right);

    Exit(FBuiltinTypes['boolean']);
  end;

  if LeftType.IsSet and RightType.IsSet then
  begin
    case ABinary.Op of
      TASTBinary.TOp.Add,
      TASTBinary.TOp.Subtract,
      TASTBinary.TOp.Multiply,
      TASTBinary.TOp.Xor:
        Exit(LeftType);

      TASTBinary.TOp.Equal,
      TASTBinary.TOp.NotEqual,
      TASTBinary.TOp.LessEqual,
      TASTBinary.TOp.GreaterEqual:
        Exit(FBuiltinTypes['boolean']);
    end;
  end;

  if LeftType.IsSet and RightType.IsInteger then
    if (ABinary.Op = TASTBinary.TOp.Add) or (ABinary.Op = TASTBinary.TOp.Subtract) then
      Exit(LeftType);

  case ABinary.Op of
     TASTBinary.TOp.Add:
    begin
      if LeftType.IsString or RightType.IsString then
        Exit(FBuiltinTypes['string']);

      if LeftType.IsFloat or RightType.IsFloat then
        Exit(FBuiltinTypes['single']);

      Exit(FBuiltinTypes['integer']);
    end;

    TASTBinary.TOp.Subtract,
    TASTBinary.TOp.Multiply:
    begin
      if LeftType.IsFloat or RightType.IsFloat then
        Exit(FBuiltinTypes['single']);

      Exit(FBuiltinTypes['integer']);
    end;

    TASTBinary.TOp.Divide:
      Exit(FBuiltinTypes['single']);

    TASTBinary.TOp.IntDivide,
    TASTBinary.TOp.Modulo,
    TASTBinary.TOp.Shl,
    TASTBinary.TOp.Shr,
    TASTBinary.TOp.Sar:
    begin
      if (not LeftType.IsInteger) or (not RightType.IsInteger) then
        Error('Operator requires integer operands', ABinary);

      Exit(FBuiltinTypes['integer']);
    end;

    TASTBinary.TOp.And,
    TASTBinary.TOp.Or,
    TASTBinary.TOp.Xor:
    begin
      if LeftType.IsBoolean and RightType.IsBoolean then
        Exit(FBuiltinTypes['boolean']);

      Exit(FBuiltinTypes['integer']);
    end;

    TASTBinary.TOp.Equal,
    TASTBinary.TOp.NotEqual,
    TASTBinary.TOp.Less,
    TASTBinary.TOp.LessEqual,
    TASTBinary.TOp.Greater,
    TASTBinary.TOp.GreaterEqual:
    begin
      if not CheckTypeCompatibility(LeftType, RightType) and not CheckTypeCompatibility(RightType, LeftType) then
        Error('Incompatible types in comparison', ABinary);

      Exit(FBuiltinTypes['boolean']);
    end;
  else
    Result := LeftType;
  end;
end;

function TSemanticAnalyzer.AnalyzeExpression(AExpr: TASTExpression): TType;
begin
  if AExpr = nil then
    Exit(FBuiltinTypes['void']);

       if AExpr is TASTLiteral      then Result := AnalyzeLiteral     (TASTLiteral     (AExpr))
  else if AExpr is TASTIdentifier   then Result := AnalyzeIdentifier  (TASTIdentifier  (AExpr))
  else if AExpr is TASTBinary       then Result := AnalyzeBinary      (TASTBinary      (AExpr))
  else if AExpr is TASTUnary        then Result := AnalyzeUnary       (TASTUnary       (AExpr))
  else if AExpr is TASTMemberAccess then Result := AnalyzeMemberAccess(TASTMemberAccess(AExpr))
  else if AExpr is TASTArrayAccess  then Result := AnalyzeArrayAccess (TASTArrayAccess (AExpr))
  else if AExpr is TASTCallExpr     then Result := AnalyzeCallExpr    (TASTCallExpr    (AExpr))
  else if AExpr is TASTIfExpression then Result := AnalyzeIfExpression(TASTIfExpression(AExpr))

  else if AExpr is TASTTypeCast then
  begin
    var TypeCast := TASTTypeCast(AExpr);
    AnalyzeExpression(TypeCast.Expression);

    Result := ResolveType(TypeCast.TargetType);
  end

  else if AExpr is TASTArrayLiteral then
  begin
    var ElemType := FBuiltinTypes['integer'];
    var ArrLit := TASTArrayLiteral(AExpr);

    if ArrLit.Elements.Count > 0 then
      ElemType := AnalyzeExpression(ArrLit.Elements[0]);

    for var i := 1 to ArrLit.Elements.Count - 1 do
      AnalyzeExpression(ArrLit.Elements[i]);

    Result := TType.Create(TType.TKind.Set, 'set of ' + ElemType.Name, 4);
    Result.ElementType := ElemType;

    FBuiltinTypes.Add(Format('SetLit_%p', [Pointer(Result)]), Result);
  end

  else
    Result := FBuiltinTypes['integer'];

  if Assigned(Result) then
  begin
    case Result.Kind of
      TType.TKind.Single:   AExpr.ResolvedType := TASTType.Create(TASTType.TKind.Single);
      TType.TKind.Integer:  AExpr.ResolvedType := TASTType.Create(TASTType.TKind.Integer);
      TType.TKind.Boolean:  AExpr.ResolvedType := TASTType.Create(TASTType.TKind.Boolean);
      TType.TKind.Byte:     AExpr.ResolvedType := TASTType.Create(TASTType.TKind.Byte);
      TType.TKind.Word:     AExpr.ResolvedType := TASTType.Create(TASTType.TKind.Word);
      TType.TKind.Cardinal: AExpr.ResolvedType := TASTType.Create(TASTType.TKind.Cardinal);
      TType.TKind.String:   AExpr.ResolvedType := TASTType.Create(TASTType.TKind.String);
      TType.TKind.ShortInt: AExpr.ResolvedType := TASTType.Create(TASTType.TKind.ShortInt);
      TType.TKind.SmallInt: AExpr.ResolvedType := TASTType.Create(TASTType.TKind.SmallInt);
      TType.TKind.Enum:     AExpr.ResolvedType := TASTType.Create(TASTType.TKind.Enum);
      TType.TKind.Set:      AExpr.ResolvedType := TASTType.Create(TASTType.TKind.Set);

      TType.TKind.DynamicArray:
      begin
        AExpr.ResolvedType := TASTType.Create(TASTType.TKind.DynamicArray);
        AExpr.ResolvedType.TypeName := Result.Name;
      end;

      TType.TKind.Pointer:
      begin
        AExpr.ResolvedType := TASTType.Create(TASTType.TKind.Pointer);

        if Result.ElementType <> nil then
          AExpr.ResolvedType.TypeName := Result.ElementType.Name;
      end;

      TType.TKind.Record:
      begin
        AExpr.ResolvedType := TASTType.Create(TASTType.TKind.Record);
        AExpr.ResolvedType.TypeName := Result.Name;
      end;

      TType.TKind.Array:
      begin
        AExpr.ResolvedType := TASTType.Create(TASTType.TKind.Array);
        AExpr.ResolvedType.TypeName := Result.Name;
      end;
    else
      AExpr.ResolvedType := TASTType.Create(TASTType.TKind.Integer);
    end;
  end;
end;

function TSemanticAnalyzer.AnalyzeIfExpression(AIfExpr: TASTIfExpression): TType;
begin
  var Cond := AIfExpr.Condition;

  FoldExpression(Cond);
  AIfExpr.Condition := Cond;

  var CondType := AnalyzeExpression(AIfExpr.Condition);

  if not CondType.IsBoolean then
    Error('If-expression condition must be a Boolean expression', AIfExpr.Condition);

  var ThenExp := AIfExpr.ThenExpr;

  FoldExpression(ThenExp);
  AIfExpr.ThenExpr := ThenExp;

  var ElseExp := AIfExpr.ElseExpr;

  FoldExpression(ElseExp);
  AIfExpr.ElseExpr := ElseExp;

  var ThenType := AnalyzeExpression(AIfExpr.ThenExpr);
  var ElseType := AnalyzeExpression(AIfExpr.ElseExpr);

  if not CheckTypeCompatibility(ThenType, ElseType) and not CheckTypeCompatibility(ElseType, ThenType) then
    Error(Format('Incompatible branch types in if-expression ("%s" and "%s")', [ThenType.Name, ElseType.Name]), AIfExpr);

  if ThenType.IsFloat or ElseType.IsFloat then
    Result := FBuiltinTypes['single']
  else
    Result := ThenType;
end;

procedure TSemanticAnalyzer.AnalyzeAssign(AAssign: TASTAssign);
begin
  var Expr := AAssign.Expression;

  if not (Expr is TASTLiteral) and FoldExpression(Expr) then
    AAssign.Expression := Expr;

  if AAssign.Target is TASTMemberAccess then
  begin
    var MemberAcc := TASTMemberAccess(AAssign.Target);
    var BaseType  := AnalyzeExpression(MemberAcc.Expression);

    if (BaseType.Kind = TType.TKind.Pointer) and (BaseType.ElementType <> nil) then
      BaseType := BaseType.ElementType;

    if BaseType.Kind = TType.TKind.Record then
    begin
      var Prop: TType.TProperty;

      if BaseType.FindProperty(MemberAcc.MemberName, Prop) then
        if Length(Prop.WriteSpec) = 0 then
          Error(Format('Property "%s" is read-only', [Prop.Name]), AAssign.Target);
    end;
  end;

  var TargetType := AnalyzeExpression(AAssign.Target);
  var ValueType  := AnalyzeExpression(AAssign.Expression);

  if not CheckTypeCompatibility(TargetType, ValueType) then
    Error(Format('Cannot assign type "%s" to "%s"', [ValueType.Name, TargetType.Name]), AAssign);
end;

procedure TSemanticAnalyzer.AnalyzeIf(AIf: TASTIf);
begin
  var Cond := AIf.Condition;

  if not (Cond is TASTLiteral) and FoldExpression(Cond) then
    AIf.Condition := Cond;

  var CondType := AnalyzeExpression(AIf.Condition);

  if not CondType.IsBoolean then
    Error('If condition must be a Boolean expression', AIf.Condition);

  AnalyzeStatement(AIf.ThenStmt);

  if Assigned(AIf.ElseStmt) then
    AnalyzeStatement(AIf.ElseStmt);
end;

procedure TSemanticAnalyzer.AnalyzeWhile(AWhile: TASTWhile);
begin
  var Cond := AWhile.Condition;
  FoldExpression(Cond);
  AWhile.Condition := Cond;

  var CondType := AnalyzeExpression(AWhile.Condition);

  if not CondType.IsBoolean then
    Error('While condition must be a Boolean expression', AWhile.Condition);

  AnalyzeStatement(AWhile.Body);
end;

procedure TSemanticAnalyzer.AnalyzeRepeat(ARepeat: TASTRepeat);
begin
  var Cond := ARepeat.Condition;
  FoldExpression(Cond);
  ARepeat.Condition := Cond;

  for var Stmt in ARepeat.Statements do
    AnalyzeStatement(Stmt);

  var CondType := AnalyzeExpression(ARepeat.Condition);

  if not CondType.IsBoolean then
    Error('Repeat condition must be a Boolean expression', ARepeat.Condition);
end;

procedure TSemanticAnalyzer.AnalyzeFor(AFor: TASTFor);
var
  LoopVarSym: TSymbol;
  VarType:    TType;
  StartType:  TType;
  StopType:   TType;
begin
  var StartExp := AFor.StartExpr;
  var StopExp  := AFor.StopExpr;

  FoldExpression(StartExp);
  FoldExpression(StopExp);

  AFor.StartExpr := StartExp;
  AFor.StopExpr  := StopExp;

  StartType := AnalyzeExpression(AFor.StartExpr);
  StopType  := AnalyzeExpression(AFor.StopExpr);

  if (not StartType.IsInteger) or (not StopType.IsInteger) then
    Error('For loop range expressions must evaluate to integers', AFor);

  if AFor.IsInlineVar then
  begin
    if AFor.ExplicitType <> nil then
      VarType := ResolveType(AFor.ExplicitType)
    else
      VarType := StartType;

    LoopVarSym := FCurrentScope.ResolveLocal(AFor.LoopVar);

    if LoopVarSym = nil then
    begin
      var AlignedSize := (VarType.Size + 3) and not Cardinal(3);

      FCurrentScope.LocalSize := FCurrentScope.LocalSize + AlignedSize;

      LoopVarSym := TSymbol.Create(AFor.LoopVar, TSymbol.TKind.Variable, VarType);

      LoopVarSym.Storage     := TSymbol.TStorage.Local;
      LoopVarSym.StackOffset := -Integer(FCurrentScope.LocalSize);

      FCurrentScope.Define(LoopVarSym);
    end
    else
    begin
      if not CheckTypeCompatibility(LoopVarSym.SymbolType, VarType) then
        Error(Format('Inline loop variable "%s" conflicts with previous declaration of type "%s"', [AFor.LoopVar, LoopVarSym.SymbolType.Name]), AFor);
    end;

    AnalyzeStatement(AFor.Body);

    Exit;
  end;

  LoopVarSym := FCurrentScope.Resolve(AFor.LoopVar);

  if LoopVarSym = nil then
    Error(Format('Undeclared loop variable "%s"', [AFor.LoopVar]), AFor)
  else if not LoopVarSym.SymbolType.IsInteger then
    Error('Loop counter variable must be an integer', AFor);

  AnalyzeStatement(AFor.Body);
end;

procedure TSemanticAnalyzer.AnalyzeForIn(AForIn: TASTForIn);
var
  LoopVarSym: TSymbol;
  VarType:    TType;
  CollType:   TType;
begin
  CollType := AnalyzeExpression(AForIn.Collection);

  if AForIn.IsInlineVar then
  begin
    if AForIn.ExplicitType <> nil then
      VarType := ResolveType(AForIn.ExplicitType)
    else
    begin
      if CollType.Kind = TType.TKind.Array then
        VarType := CollType.ElementType
      else if CollType.IsDynamicArray then
        VarType := CollType.ElementType
      else if CollType.IsSet then
        VarType := FBuiltinTypes['integer']
      else if CollType.IsString then
        VarType := FBuiltinTypes['char']
      else
        VarType := FBuiltinTypes['integer'];
    end;

    LoopVarSym := FCurrentScope.ResolveLocal(AForIn.LoopVar);

    if LoopVarSym = nil then
    begin
      var AlignedSize := (VarType.Size + 3) and not Cardinal(3);

      FCurrentScope.LocalSize := FCurrentScope.LocalSize + AlignedSize;

      LoopVarSym := TSymbol.Create(AForIn.LoopVar, TSymbol.TKind.Variable, VarType);

      LoopVarSym.Storage     := TSymbol.TStorage.Local;
      LoopVarSym.StackOffset := -Integer(FCurrentScope.LocalSize);

      FCurrentScope.Define(LoopVarSym);
    end
    else
    begin
      if not CheckTypeCompatibility(LoopVarSym.SymbolType, VarType) then
        Error(Format('Inline loop variable "%s" conflicts with previous declaration of type "%s"', [AForIn.LoopVar, LoopVarSym.SymbolType.Name]), AForIn);
    end;

    AnalyzeStatement(AForIn.Body);

    Exit;
  end;

  LoopVarSym := FCurrentScope.Resolve(AForIn.LoopVar);

  if LoopVarSym = nil then
  begin
    Error(Format('Undeclared loop variable "%s"', [AForIn.LoopVar]), AForIn);
    Exit;
  end;

  if CollType.Kind = TType.TKind.Array then
  begin
    if CollType.ElementType <> nil then
      if not CheckTypeCompatibility(LoopVarSym.SymbolType, CollType.ElementType) then
        Error(Format('Incompatible loop variable type for array element (cannot assign "%s" to "%s")', [CollType.ElementType.Name, LoopVarSym.SymbolType.Name]), AForIn);
  end

  else if CollType.IsDynamicArray then
  begin
    if CollType.ElementType <> nil then
      if not CheckTypeCompatibility(LoopVarSym.SymbolType, CollType.ElementType) then
        Error(Format('Incompatible loop variable type for dynamic array (cannot assign "%s" to "%s")', [CollType.ElementType.Name, LoopVarSym.SymbolType.Name]), AForIn);
  end

  else if CollType.IsSet then
  begin
    if (not LoopVarSym.SymbolType.IsInteger) and (LoopVarSym.SymbolType.Kind <> TType.TKind.Enum) then
      Error('Loop variable for set iteration must be an integer, char, or enum', AForIn);
  end

  else if CollType.IsString then
  begin
    if (LoopVarSym.SymbolType.Kind <> TType.TKind.Char) and (LoopVarSym.SymbolType.Kind <> TType.TKind.Byte) then
      Error('Loop variable for string iteration must be of type Char or Byte', AForIn);
  end

  else
    Error('Expression in "for..in" must be an array, set, or string', AForIn.Collection);

  AnalyzeStatement(AForIn.Body);
end;

procedure TSemanticAnalyzer.AnalyzeProcCall(ACall: TASTProcCall);
begin
  AnalyzeCallExpr(ACall.CallExpr);
end;

procedure TSemanticAnalyzer.AnalyzeBlock(ABlock: TASTBlock);
begin
  for var Stmt in ABlock.Statements do
    AnalyzeStatement(Stmt);
end;

procedure TSemanticAnalyzer.AnalyzeWith(AWith: TASTWith);
var
  PushedCount: Integer;
begin
  PushedCount := 0;

  for var Expr in AWith.Expressions do
  begin
    var BaseType := AnalyzeExpression(Expr);

    if (BaseType.Kind = TType.TKind.Pointer) and (BaseType.ElementType <> nil) then
      BaseType := BaseType.ElementType;

    if BaseType.Kind <> TType.TKind.Record then
    begin
      Error('Expression in "with" statement must be a record or pointer to record', Expr);
      Continue;
    end;

    var Ctx: TWithContext;

    Ctx.RecordType := BaseType;
    FWithStack.Add(Ctx);
    Inc(PushedCount);
  end;

  try
    AnalyzeStatement(AWith.Body);
  finally
    for var i := 1 to PushedCount do
      FWithStack.Delete(FWithStack.Count - 1);
  end;
end;

procedure TSemanticAnalyzer.AnalyzeStatement(AStmt: TASTStatement);
begin
  if AStmt = nil then
    Exit;

       if AStmt is TASTBlock    then AnalyzeBlock   (TASTBlock   (AStmt))
  else if AStmt is TASTWith     then AnalyzeWith    (TASTWith    (AStmt))
  else if AStmt is TASTAssign   then AnalyzeAssign  (TASTAssign  (AStmt))
  else if AStmt is TASTIf       then AnalyzeIf      (TASTIf      (AStmt))
  else if AStmt is TASTWhile    then AnalyzeWhile   (TASTWhile   (AStmt))
  else if AStmt is TASTRepeat   then AnalyzeRepeat  (TASTRepeat  (AStmt))
  else if AStmt is TASTFor      then AnalyzeFor     (TASTFor     (AStmt))
  else if AStmt is TASTForIn    then AnalyzeForIn   (TASTForIn   (AStmt))
  else if AStmt is TASTProcCall then AnalyzeProcCall(TASTProcCall(AStmt))
  else if AStmt is TASTCase then
  begin
    var CaseStmt := TASTCase(AStmt);
    var SelType := AnalyzeExpression(CaseStmt.Selector);

    if not SelType.IsInteger and not SelType.IsBoolean and (SelType.Kind <> TType.TKind.Char) then
      Error('Case selector must evaluate to an ordinal type (Integer, Char, Boolean, Enum)', CaseStmt.Selector);

    for var Branch in CaseStmt.Branches do
      AnalyzeStatement(Branch.Statement);

    if Assigned(CaseStmt.ElseStmt) then
      AnalyzeStatement(CaseStmt.ElseStmt);
  end;
end;

procedure TSemanticAnalyzer.AnalyzeDeclaration(ADecl: TASTDeclaration);
begin
   if ADecl is TASTConstDecl then
  begin
    var ConstDecl := TASTConstDecl(ADecl);
    var ValType: TType;

    var ValExpr := ConstDecl.Value;
    FoldExpression(ValExpr);
    ConstDecl.Value := ValExpr;

    if ConstDecl.ConstType <> nil then
      ValType := ResolveType(ConstDecl.ConstType)
    else
    begin
      var ConstVal: TConstValue;

      if EvaluateConstValue(ConstDecl.Value, ConstVal) and (ConstVal.Kind = TConstValue.TKind.Set) then
      begin
        ValType := TType.Create(TType.TKind.Set, 'Set', 4);
        FBuiltinTypes.Add(Format('SetConst_%p', [Pointer(ValType)]), ValType);
      end
      else
        ValType := AnalyzeExpression(ConstDecl.Value);
    end;

    var Sym := TSymbol.Create(ConstDecl.Name, TSymbol.TKind.Constant, ValType);

    var ConstVal: TConstValue;

    if EvaluateConstValue(ConstDecl.Value, ConstVal) then
      Sym.ConstVal := ConstVal
    else
      Error(Format('Constant expression for "%s" must be a compile-time constant', [ConstDecl.Name]), ConstDecl);

    if not FCurrentScope.Define(Sym) then
      Error(Format('Duplicate identifier "%s"', [ConstDecl.Name]), ConstDecl);
  end

  else if ADecl is TASTTypeDecl then
  begin
    var TypeDecl := TASTTypeDecl(ADecl);
    var DeclType := ResolveType(TypeDecl.DeclType);

    DeclType.Name := TypeDecl.Name;

    if TypeDecl.DeclType.Kind = TASTType.TKind.Enum then
      for var Elem in TypeDecl.DeclType.EnumElements do
      begin
        var E: TType.TEnumElement;

        E.Name  := Elem.Name;
        E.Value := Elem.Value;

        DeclType.EnumElements.Add(E);

        var EnumSym := TSymbol.Create(Elem.Name, TSymbol.TKind.Constant, DeclType);
        EnumSym.ConstVal := TConstValue.MakeInt(Cardinal(Elem.Value));

        FCurrentScope.Define(EnumSym);
      end;

    for var MNode in TypeDecl.DeclType.RecordMethods do
      if MNode is TASTRoutineDecl then
        DeclType.Methods.AddOrSetValue(LowerCase(TASTRoutineDecl(MNode).Name), TASTRoutineDecl(MNode));

    for var PNode in TypeDecl.DeclType.RecordProperties do
      if PNode is TASTProperty then
      begin
        var ASTProp := TASTProperty(PNode);
        var PInfo: TType.TProperty;

        PInfo.Name          := ASTProp.Name;
        PInfo.PropType      := ResolveType(ASTProp.PropertyType);
        PInfo.ReadSpec      := ASTProp.ReadSpec;
        PInfo.WriteSpec     := ASTProp.WriteSpec;
        PInfo.Visibility    := ASTProp.Visibility;
        PInfo.IsDirectRead  := False;
        PInfo.IsDirectWrite := False;
        PInfo.ReadOffset    := 0;
        PInfo.WriteOffset   := 0;

        var RField: TType.TRecordField;

        if DeclType.FindField(ASTProp.ReadSpec, RField) then
        begin
          PInfo.IsDirectRead := True;
          PInfo.ReadOffset   := RField.Offset;
        end;

        var WField: TType.TRecordField;

        if DeclType.FindField(ASTProp.WriteSpec, WField) then
        begin
          PInfo.IsDirectWrite := True;
          PInfo.WriteOffset   := WField.Offset;
        end;

        DeclType.Properties.Add(PInfo);
      end;

    for var Pair in FBuiltinTypes do
      if (Pair.Value.Kind = TType.TKind.Pointer) and (Pair.Value.ElementType <> nil) and SameText(Pair.Value.ElementType.Name, TypeDecl.Name) then
        Pair.Value.ElementType := DeclType;

    var Sym := TSymbol.Create(TypeDecl.Name, TSymbol.TKind.Type, DeclType);

    if not FCurrentScope.Define(Sym) then
      Error(Format('Duplicate type identifier "%s"', [TypeDecl.Name]), TypeDecl);
  end

  else if ADecl is TASTVarDecl then
  begin
    var VarDecl := TASTVarDecl(ADecl);
    var VType   := ResolveType(VarDecl.VarType);

     if VarDecl.InitialValue <> nil then
    begin
      var InitVal := VarDecl.InitialValue;
      FoldExpression(InitVal);
      VarDecl.InitialValue := InitVal;
    end;

    for var Name in VarDecl.Names do
    begin
      var Sym := TSymbol.Create(Name, TSymbol.TKind.Variable, VType);

      if FCurrentScope = FGlobalScope then
      begin
        Sym.Storage     := TSymbol.TStorage.Global;
        Sym.GlobalLabel := '_var_' + LowerCase(Name);
      end
      else
      begin
        Sym.Storage := TSymbol.TStorage.Local;

        var AlignedSize := (VType.Size + 3) and not Cardinal(3);
        Inc(FCurrentScope.FLocalSize, AlignedSize);

        Sym.StackOffset := -Integer(FCurrentScope.FLocalSize);
      end;

      if not FCurrentScope.Define(Sym) then
        Error(Format('Duplicate variable identifier "%s"', [Name]), VarDecl);
    end;
  end;
end;

procedure TSemanticAnalyzer.AnalyzeRoutine(ARoutine: TASTRoutineDecl);
var
  RetType:     TType;
  RoutineKind: TSymbol.TKind;
  ExistingSym: TSymbol;
  RoutineName: String;
begin
  RoutineName := ARoutine.Name;

  if ARoutine.IsRecordMethod and (Length(ARoutine.ParentTypeName) > 0) then
    RoutineName := ARoutine.ParentTypeName + '_' + ARoutine.Name;

  ExistingSym := FCurrentScope.Resolve(RoutineName);

  if (ExistingSym <> nil) and (ExistingSym.Declaration <> nil) and
     (ExistingSym.Declaration.IsForward or (ExistingSym.Declaration.Body = nil)) and
     (not ExistingSym.IsSysCall) then
  begin
    ExistingSym.Declaration.IsForward := False;

    if (ARoutine.Params.Count = 0) and (ExistingSym.Declaration.Params.Count > 0) then
      for var P in ExistingSym.Declaration.Params do
        ARoutine.Params.Add(TASTParamDecl.Create(P.Name, P.ParamType.Clone, P.Modifier, ARoutine.Line, ARoutine.Col));

    if (ARoutine.ReturnType = nil) and (ExistingSym.Declaration.ReturnType <> nil) then
      ARoutine.ReturnType := ExistingSym.Declaration.ReturnType.Clone;

    ExistingSym.Declaration := ARoutine;
  end
  else
  begin
    RoutineKind := TSymbol.TKind.Procedure;

    if ARoutine.IsFunction then
    begin
      RoutineKind := TSymbol.TKind.Function;
      RetType     := ResolveType(ARoutine.ReturnType);
    end
    else
      RetType := FBuiltinTypes['void'];

    var RoutineType := TType.Create(TType.TKind.Procedure, ARoutine.Name, 0);

    RoutineType.ReturnType := RetType;

    var RoutineSym := TSymbol.Create(RoutineName, RoutineKind, RoutineType);

    RoutineSym.Declaration := ARoutine;
    RoutineSym.IsSysCall   := ARoutine.IsSysCall;
    RoutineSym.SysCallID   := ARoutine.SysCallID;
    RoutineSym.IsInterrupt := ARoutine.IsInterrupt;
    RoutineSym.IsVarArgs   := ARoutine.IsVarArgs;

    if not FCurrentScope.Define(RoutineSym) then
      Error(Format('Duplicate routine identifier "%s"', [RoutineName]), ARoutine);

    ExistingSym := RoutineSym;
  end;

  if ARoutine.IsForward or (ARoutine.Body = nil) then
    Exit;

  if ARoutine.IsSysCall then
  begin
    if ARoutine.Params.Count > 13 then
      Error(Format('SysCalls cannot have more than 13 parameters, but "%s" has %d', [ARoutine.Name, ARoutine.Params.Count]), ARoutine);

    var SysVal: TConstValue;

    if (ARoutine.SysCallExpr <> nil) and EvaluateConstValue(ARoutine.SysCallExpr, SysVal) then
    begin
      ExistingSym.SysCallID := SysVal.ValueInt;
      ARoutine.SysCallID    := SysVal.ValueInt;
    end

    else if ARoutine.SysCallID > 0 then
      ExistingSym.SysCallID := ARoutine.SysCallID

    else
      Error('SysCall ID must evaluate to a compile-time integer constant', ARoutine);

    Exit;
  end;

  var RoutineScope := TScope.Create(FCurrentScope);
  ExistingSym.LocalScope := RoutineScope;
  FCurrentScope := RoutineScope;

  try
    var RegParamCount := 0;

    if ARoutine.IsRecordMethod and (Length(ARoutine.ParentTypeName) > 0) then
    begin
      var ParentTypeSym := FGlobalScope.Resolve(ARoutine.ParentTypeName);

      if ParentTypeSym <> nil then
      begin
        var SelfSym := TSymbol.Create('self', TSymbol.TKind.Parameter, ParentTypeSym.SymbolType);

        SelfSym.Storage    := TSymbol.TStorage.Parameter;
        SelfSym.ParamIndex := 0;
        SelfSym.IsVarParam := True;

        Inc(FCurrentScope.FLocalSize, 4);

        SelfSym.StackOffset := -Integer(FCurrentScope.FLocalSize);

        FCurrentScope.Define(SelfSym);

        RegParamCount := 1;
      end;
    end;

    var StackParamOffset: Integer := 8;

    for var i := 0 to ARoutine.Params.Count - 1 do
    begin
      var PDecl := ARoutine.Params[i];
      var PType := ResolveType(PDecl.ParamType);
      var PSym := TSymbol.Create(PDecl.Name, TSymbol.TKind.Parameter, PType);

      PSym.Storage    := TSymbol.TStorage.Parameter;
      PSym.ParamIndex := i + RegParamCount;
      PSym.IsVarParam := (PDecl.Modifier in [TASTParamDecl.TModifier.Var, TASTParamDecl.TModifier.Out]);

      if PSym.ParamIndex < 4 then
      begin
        Inc(FCurrentScope.FLocalSize, 4);
        PSym.StackOffset := -Integer(FCurrentScope.FLocalSize);
      end
      else
      begin
        PSym.StackOffset := StackParamOffset;
        Inc(StackParamOffset, 4);
      end;

      if not FCurrentScope.Define(PSym) then
        Error(Format('Duplicate parameter "%s"', [PDecl.Name]), PDecl);
    end;

    if ARoutine.IsFunction then
    begin
      var ResultSym := TSymbol.Create('result', TSymbol.TKind.Variable, ResolveType(ARoutine.ReturnType));

      ResultSym.Storage := TSymbol.TStorage.Local;
      Inc(FCurrentScope.FLocalSize, 4);
      ResultSym.StackOffset := -Integer(FCurrentScope.FLocalSize);
      FCurrentScope.Define(ResultSym);

      var FuncNameSym := TSymbol.Create(ARoutine.Name, TSymbol.TKind.Variable, ResolveType(ARoutine.ReturnType));

      FuncNameSym.Storage     := TSymbol.TStorage.Local;
      FuncNameSym.StackOffset := ResultSym.StackOffset;

      FCurrentScope.Define(FuncNameSym);
    end;

    for var Decl in ARoutine.Declarations do
      AnalyzeDeclaration(Decl);

    if Assigned(ARoutine.Body) then
      AnalyzeBlock(ARoutine.Body);
  finally
    FCurrentScope := FCurrentScope.Parent;
  end;
end;

procedure TSemanticAnalyzer.AnalyzeProgram(AProgram: TASTProgram);
begin
  for var Decl in AProgram.Declarations do
    if Decl is TASTRoutineDecl then
      AnalyzeRoutine(TASTRoutineDecl(Decl))
    else
      AnalyzeDeclaration(Decl);

  for var Decl in AProgram.Declarations do
    if Decl is TASTTypeDecl then
    begin
      var TDecl := TASTTypeDecl(Decl);

      for var MNode in TDecl.DeclType.RecordMethods do
        if (MNode is TASTRoutineDecl) and (TASTRoutineDecl(MNode).Body <> nil) then
          AnalyzeRoutine(TASTRoutineDecl(MNode));
    end;

  if Assigned(AProgram.Body) then
    AnalyzeBlock(AProgram.Body);
end;

procedure TSemanticAnalyzer.ImportUnitInterface(AUnit: TASTUnit);
begin
  if AUnit = nil then
    Exit;

  for var Decl in AUnit.InterfaceDecls do
    AnalyzeDeclaration(Decl);
end;

function TSemanticAnalyzer.Analyze(AProgram: TASTProgram): Boolean;
begin
  FErrors.Clear;

  if AProgram = nil then
    Exit(False);

  AnalyzeProgram(AProgram);

  for var Decl in AProgram.Declarations do
    if (Decl is TASTRoutineDecl) and TASTRoutineDecl(Decl).IsForward then
      Error(Format('Forward-declared routine "%s" was never implemented', [TASTRoutineDecl(Decl).Name]), Decl);

  Result := (FErrors.Count = 0);
end;

function TSemanticAnalyzer.AnalyzeUnit(AUnit: TASTUnit): Boolean;
begin
  if AUnit = nil then
    Exit(False);

  for var Decl in AUnit.InterfaceDecls do
    if Decl is TASTRoutineDecl then
    begin
      var RDecl := TASTRoutineDecl(Decl);
      var RetType: TType := FBuiltinTypes['void'];
      var RKind := TSymbol.TKind.Procedure;

      if RDecl.IsFunction then
      begin
        RKind   := TSymbol.TKind.Function;
        RetType := ResolveType(RDecl.ReturnType);
      end;

      var RType := TType.Create(TType.TKind.Procedure, RDecl.Name, 0);

      RType.ReturnType := RetType;

      var RSym := TSymbol.Create(RDecl.Name, RKind, RType);

      RSym.Declaration := RDecl;
      RSym.IsSysCall   := RDecl.IsSysCall;
      RSym.SysCallID   := RDecl.SysCallID;

      FCurrentScope.Define(RSym);
    end
    else
      AnalyzeDeclaration(Decl);

  for var Decl in AUnit.ImplementationDecls do
    if Decl is TASTRoutineDecl then
      AnalyzeRoutine(TASTRoutineDecl(Decl))
    else
      AnalyzeDeclaration(Decl);

  if Assigned(AUnit.InitializationBlock) then
    AnalyzeBlock(AUnit.InitializationBlock);

  for var Decl in AUnit.InterfaceDecls do
    if (Decl is TASTRoutineDecl) and (not TASTRoutineDecl(Decl).IsSysCall) then
    begin
      var Sym := FCurrentScope.Resolve(TASTRoutineDecl(Decl).Name);

      if (Sym = nil) or (Sym.Declaration = nil) or (Sym.Declaration.Body = nil) then
        Error(Format('Unsatisfied interface declaration for "%s"', [TASTRoutineDecl(Decl).Name]), Decl);
    end;

  for var Decl in AUnit.ImplementationDecls do
    if (Decl is TASTRoutineDecl) and TASTRoutineDecl(Decl).IsForward then
      Error(Format('Forward-declared routine "%s" was never implemented', [TASTRoutineDecl(Decl).Name]), Decl);

  Result := (FErrors.Count = 0);
end;
{$ENDREGION}

{$REGION 'TreeShaker'}
constructor TTreeShaker.Create(AProgram: TASTProgram; AUnits: TList<TASTUnit>);
  procedure RegisterDecls(ADecls: TObjectList<TASTDeclaration>);
  begin
    for var Decl in ADecls do
    begin
      if Decl is TASTRoutineDecl then
      begin
        var R := TASTRoutineDecl(Decl);

        if (R.Body <> nil) and (not R.IsForward) then
        begin
          var MangledName := R.Name;

          if R.IsRecordMethod and (Length(R.ParentTypeName) > 0) then
            MangledName := R.ParentTypeName + '_' + R.Name;

          FRoutineMap.AddOrSetValue(LowerCase(MangledName), R);
        end;
      end
      else if Decl is TASTTypeDecl then
      begin
        var TD := TASTTypeDecl(Decl);

        for var MNode in TD.DeclType.RecordMethods do
          if MNode is TASTRoutineDecl then
          begin
            var R := TASTRoutineDecl(MNode);

            if (R.Body <> nil) and (not R.IsForward) then
            begin
              var MangledName := TD.Name + '_' + R.Name;

              FRoutineMap.AddOrSetValue(LowerCase(MangledName), R);
            end;
          end;

        for var PNode in TD.DeclType.RecordProperties do
          if PNode is TASTProperty then
          begin
            var Prop := TASTProperty(PNode);
            var Spec: TPropSpec;

            Spec.ReadRoutine  := TD.Name + '_' + Prop.ReadSpec;
            Spec.WriteRoutine := TD.Name + '_' + Prop.WriteSpec;

            FPropertyMap.AddOrSetValue(LowerCase(TD.Name + '_' + Prop.Name), Spec);
          end;
      end

      else if Decl is TASTVarDecl then
        for var Name in TASTVarDecl(Decl).Names do
          FVarMap.AddOrSetValue(LowerCase(Name), TASTVarDecl(Decl));
    end;
  end;

begin
  inherited Create;

  FProgram     := AProgram;
  FUnits       := AUnits;
  FRoutineMap  := TDictionary<String, TASTRoutineDecl>.Create;
  FVarMap      := TDictionary<String, TASTVarDecl>.Create;
  FPropertyMap := TDictionary<String, TPropSpec>.Create;
  FWithStack   := TList<String>.Create;

  if FUnits <> nil then
    for var U in FUnits do
    begin
      RegisterDecls(U.InterfaceDecls);
      RegisterDecls(U.ImplementationDecls);
    end;

  RegisterDecls(FProgram.Declarations);
end;

destructor TTreeShaker.Destroy;
begin
  FWithStack.Free;
  FPropertyMap.Free;
  FRoutineMap.Free;
  FVarMap.Free;

  inherited;
end;

procedure TTreeShaker.MarkRoutine(ARoutine: TASTRoutineDecl);
begin
  if (ARoutine = nil) or ARoutine.IsUsed then
    Exit;

  ARoutine.IsUsed := True;

  if Assigned(ARoutine.Body) then
    MarkBlock(ARoutine.Body);
end;

procedure TTreeShaker.MarkExpression(AExpr: TASTExpression);
begin
  if AExpr = nil then
    Exit;

  if AExpr is TASTIdentifier then
  begin
    var IdentName := TASTIdentifier(AExpr).Name;

    for var i := FWithStack.Count - 1 downto 0 do
    begin
      var TypeName := FWithStack[i];
      var Key := LowerCase(TypeName + '_' + IdentName);

      var PropSpec: TPropSpec;

      if FPropertyMap.TryGetValue(Key, PropSpec) then
      begin
        var GetterRoutine: TASTRoutineDecl;

        if FRoutineMap.TryGetValue(LowerCase(PropSpec.ReadRoutine), GetterRoutine) then
          MarkRoutine(GetterRoutine);
      end;

      var MethodRoutine: TASTRoutineDecl;

      if FRoutineMap.TryGetValue(Key, MethodRoutine) then
        MarkRoutine(MethodRoutine);
    end;

    var VarDecl: TASTVarDecl;

    if FVarMap.TryGetValue(LowerCase(IdentName), VarDecl) then
      VarDecl.IsUsed := True;

    var Routine: TASTRoutineDecl;

    if FRoutineMap.TryGetValue(LowerCase(IdentName), Routine) then
      MarkRoutine(Routine);
  end

  else if AExpr is TASTIfExpression then
  begin
    var IfExp := TASTIfExpression(AExpr);

    MarkExpression(IfExp.Condition);
    MarkExpression(IfExp.ThenExpr);
    MarkExpression(IfExp.ElseExpr);
  end

  else if AExpr is TASTCallExpr then
  begin
    var Call := TASTCallExpr(AExpr);
    var Routine: TASTRoutineDecl := nil;
    var Callee := Call.CalleeName;

    if Call.BaseExpr <> nil then
    begin
      var BaseType := Call.BaseExpr.ResolvedType;

      if (BaseType <> nil) and (BaseType.Kind = TASTType.TKind.Pointer) and (BaseType.ElementType <> nil) then
        BaseType := BaseType.ElementType;

      if BaseType <> nil then
        Callee := BaseType.TypeName + '_' + Call.CalleeName;
    end

    else
      for var i := FWithStack.Count - 1 downto 0 do
      begin
        var TypeName := FWithStack[i];
        var CandidateKey := LowerCase(TypeName + '_' + Call.CalleeName);

        if FRoutineMap.ContainsKey(CandidateKey) then
        begin
          Callee := CandidateKey;
          Break;
        end;
      end;

    if FRoutineMap.TryGetValue(LowerCase(Callee), Routine) then
      MarkRoutine(Routine);

    if Call.BaseExpr <> nil then
      MarkExpression(Call.BaseExpr);

    for var Arg in Call.Arguments do
      MarkExpression(Arg);
  end

  else if AExpr is TASTMemberAccess then
  begin
    var MemAcc := TASTMemberAccess(AExpr);

    if (MemAcc.Expression.ResolvedType <> nil) then
    begin
      var BaseType := MemAcc.Expression.ResolvedType;

      if (BaseType.Kind = TASTType.TKind.Pointer) and (BaseType.ElementType <> nil) then
        BaseType := BaseType.ElementType;

      var Key := LowerCase(BaseType.TypeName + '_' + MemAcc.MemberName);

      var PropSpec: TPropSpec;

      if FPropertyMap.TryGetValue(Key, PropSpec) then
      begin
        var GetterRoutine: TASTRoutineDecl;

        if FRoutineMap.TryGetValue(LowerCase(PropSpec.ReadRoutine), GetterRoutine) then
          MarkRoutine(GetterRoutine);
      end;

      var MethodRoutine: TASTRoutineDecl;

      if FRoutineMap.TryGetValue(Key, MethodRoutine) then
        MarkRoutine(MethodRoutine);
    end;

    MarkExpression(MemAcc.Expression);
  end

  else if AExpr is TASTBinary then
  begin
    MarkExpression(TASTBinary(AExpr).Left);
    MarkExpression(TASTBinary(AExpr).Right);
  end

  else if AExpr is TASTUnary then
  begin
    var Un := TASTUnary(AExpr);

    if (Un.Op = TASTUnary.TOp.AddressOf) and (Un.Operand is TASTIdentifier) then
    begin
      var Routine: TASTRoutineDecl;

      if FRoutineMap.TryGetValue(LowerCase(TASTIdentifier(Un.Operand).Name), Routine) then
        MarkRoutine(Routine);
    end;

    MarkExpression(Un.Operand);
  end

  else if AExpr is TASTArrayAccess then
  begin
    MarkExpression(TASTArrayAccess(AExpr).ArrayExpr);

    for var Idx in TASTArrayAccess(AExpr).IndexExprs do
      MarkExpression(Idx);
  end

  else if AExpr is TASTArrayLiteral then
    for var Elem in TASTArrayLiteral(AExpr).Elements do
      MarkExpression(Elem)

  else if AExpr is TASTTypeCast then
    MarkExpression(TASTTypeCast(AExpr).Expression);
end;

procedure TTreeShaker.MarkStatement(AStmt: TASTStatement);
begin
  if AStmt = nil then Exit;

  if AStmt is TASTBlock then
    MarkBlock(TASTBlock(AStmt))

  else if AStmt is TASTWith then
  begin
    var WithStmt := TASTWith(AStmt);
    var PushedCount := 0;

    for var Expr in WithStmt.Expressions do
    begin
      MarkExpression(Expr);

      var BaseType := Expr.ResolvedType;

      if (BaseType <> nil) and (BaseType.Kind = TASTType.TKind.Pointer) and (BaseType.ElementType <> nil) then
        BaseType := BaseType.ElementType;

      if BaseType <> nil then
      begin
        FWithStack.Add(BaseType.TypeName);
        Inc(PushedCount);
      end;
    end;

    try
      MarkStatement(WithStmt.Body);
    finally
      for var i := 1 to PushedCount do
        FWithStack.Delete(FWithStack.Count - 1);
    end;
  end

  else if AStmt is TASTAssign then
  begin
    var Assign := TASTAssign(AStmt);

    if Assign.Target is TASTMemberAccess then
    begin
      var MemAcc := TASTMemberAccess(Assign.Target);

      if (MemAcc.Expression.ResolvedType <> nil) then
      begin
        var BaseType := MemAcc.Expression.ResolvedType;

        if (BaseType.Kind = TASTType.TKind.Pointer) and (BaseType.ElementType <> nil) then
          BaseType := BaseType.ElementType;

        var Key := LowerCase(BaseType.TypeName + '_' + MemAcc.MemberName);
        var PropSpec: TPropSpec;

        if FPropertyMap.TryGetValue(Key, PropSpec) then
        begin
          var SetterRoutine: TASTRoutineDecl;

          if FRoutineMap.TryGetValue(LowerCase(PropSpec.WriteRoutine), SetterRoutine) then
            MarkRoutine(SetterRoutine);
        end;
      end;
    end

    else if Assign.Target is TASTIdentifier then
    begin
      var TargetName := TASTIdentifier(Assign.Target).Name;

      for var i := FWithStack.Count - 1 downto 0 do
      begin
        var TypeName := FWithStack[i];
        var Key := LowerCase(TypeName + '_' + TargetName);
        var PropSpec: TPropSpec;

        if FPropertyMap.TryGetValue(Key, PropSpec) then
        begin
          var SetterRoutine: TASTRoutineDecl;

          if FRoutineMap.TryGetValue(LowerCase(PropSpec.WriteRoutine), SetterRoutine) then
            MarkRoutine(SetterRoutine);
        end;
      end;
    end;

    MarkExpression(Assign.Target);
    MarkExpression(Assign.Expression);
  end

  else if AStmt is TASTIf then
  begin
    MarkExpression(TASTIf(AStmt).Condition);
    MarkStatement(TASTIf(AStmt).ThenStmt);

    if Assigned(TASTIf(AStmt).ElseStmt) then
      MarkStatement(TASTIf(AStmt).ElseStmt);
  end

  else if AStmt is TASTWhile then
  begin
    MarkExpression(TASTWhile(AStmt).Condition);
    MarkStatement(TASTWhile(AStmt).Body);
  end

  else if AStmt is TASTRepeat then
  begin
    for var S in TASTRepeat(AStmt).Statements do
      MarkStatement(S);

    MarkExpression(TASTRepeat(AStmt).Condition);
  end

  else if AStmt is TASTFor then
  begin
    MarkExpression(TASTFor(AStmt).StartExpr);
    MarkExpression(TASTFor(AStmt).StopExpr);
    MarkStatement(TASTFor(AStmt).Body);
  end

  else if AStmt is TASTForIn then
  begin
    var ForInStmt := TASTForIn(AStmt);
    var VarDecl: TASTVarDecl;

    if FVarMap.TryGetValue(LowerCase(ForInStmt.LoopVar), VarDecl) then
      VarDecl.IsUsed := True;

    MarkExpression(ForInStmt.Collection);
    MarkStatement(ForInStmt.Body);
  end

  else if AStmt is TASTProcCall then
    MarkExpression(TASTProcCall(AStmt).CallExpr)

  else if AStmt is TASTCase then
  begin
    var CaseStmt := TASTCase(AStmt);
    MarkExpression(CaseStmt.Selector);

    for var Branch in CaseStmt.Branches do
      MarkStatement(Branch.Statement);

    if Assigned(CaseStmt.ElseStmt) then
      MarkStatement(CaseStmt.ElseStmt);
  end;
end;

procedure TTreeShaker.MarkBlock(ABlock: TASTBlock);
begin
  for var Stmt in ABlock.Statements do
    MarkStatement(Stmt);
end;

procedure TTreeShaker.Execute;
begin
  if Assigned(FProgram.Body) then
    MarkBlock(FProgram.Body);

  if FUnits <> nil then
    for var U in FUnits do
      if Assigned(U.InitializationBlock) then
        MarkBlock(U.InitializationBlock);

  for var Pair in FRoutineMap do
    if Pair.Value.IsInterrupt then
      MarkRoutine(Pair.Value);
end;
{$ENDREGION}

end.
