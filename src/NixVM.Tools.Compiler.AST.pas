{
  NixVM.Tools.Compiler.AST.pas
    Abstract Syntax Tree nodes

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

unit NixVM.Tools.Compiler.AST;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,

  NixVM.Core.ROM;

type
  {$REGION 'Visibility'}
  TVisibility = (&Public, &Private);
  {$ENDREGION}

  {$REGION 'ConstValue'}
  TConstValue = record
  type
    {$REGION 'Kind'}
    TKind = (
      None,
      &Integer,
      &Single,
      &Boolean,
      &String,
      &Pointer
    );
    {$ENDREGION}
  public
    Kind:       TKind;
    ValueInt:   Cardinal;
    ValueFloat: Single;
    ValueBool:  Boolean;
    ValueStr:   String;

    class function MakeInt  (AVal: Cardinal): TConstValue; static;
    class function MakeFloat(AVal: Single):   TConstValue; static;
    class function MakeBool (AVal: Boolean):  TConstValue; static;
    class function MakeStr  (const AVal: String): TConstValue; static;
    class function MakePtr  (AVal: Cardinal): TConstValue; static;
  end;
  {$ENDREGION}

  {$REGION 'ASTNode'}
  TASTNode = class
  private
    FLine: Integer;
    FCol:  Integer;
  public
    constructor Create(ALine: Integer = 0; ACol: Integer = 0);

    property Line: Integer read FLine write FLine;
    property Col:  Integer read FCol  write FCol;
  end;
  {$ENDREGION}

  {$REGION 'ASTType'}
  TASTType = class(TASTNode)
  type
    {$REGION 'Type Kind'}
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
      Subrange,
      NamedAlias
    );
    {$ENDREGION}

    {$REGION 'Enum Element'}
    TEnumElement = record
      Name:  String;
      Value: Integer;
    end;
    {$ENDREGION}
  private
    FKind:             TKind;
    FTypeName:         String;
    FElementType:      TASTType;
    FRecordFields:     TObjectList<TASTNode>;
    FSubrangeLow:      Integer;
    FSubrangeHigh:     Integer;
    FRecordMethods:    TObjectList<TASTNode>;
    FEnumElements:     TList<TEnumElement>;
    FRecordProperties: TObjectList<TASTNode>;
  public
    constructor Create(AKind: TKind;        ALine: Integer = 0; ACol: Integer = 0); overload;
    constructor Create(const AName: String; ALine: Integer = 0; ACol: Integer = 0); overload;

    destructor  Destroy; override;

    function Size: Cardinal;

    function Clone: TASTType;

    function IsFloat:   Boolean; inline;
    function IsInteger: Boolean; inline;
    function IsNumeric: Boolean; inline;
    function IsBoolean: Boolean; inline;
    function IsString:  Boolean; inline;
    function IsSigned:  Boolean; inline;
    function IsSet:     Boolean; inline;

    property Kind:     TKind  read FKind write FKind;
    property TypeName: String read FTypeName write FTypeName;

    property ElementType: TASTType read FElementType write FElementType;

    property RecordFields: TObjectList<TASTNode> read FRecordFields;

    property SubrangeLow:  Integer read FSubrangeLow  write FSubrangeLow;
    property SubrangeHigh: Integer read FSubrangeHigh write FSubrangeHigh;

    property RecordMethods: TObjectList<TASTNode> read FRecordMethods;

    property EnumElements: TList<TEnumElement> read FEnumElements;

    property RecordProperties: TObjectList<TASTNode> read FRecordProperties;
  end;
  {$ENDREGION}

  {$REGION 'Expressions'}
  TASTExpression = class(TASTNode)
  private
    FResolvedType: TASTType;
  public
    property ResolvedType: TASTType read FResolvedType write FResolvedType;
  end;

  {$REGION 'Literal'}
  TASTLiteral = class(TASTExpression)
  type
    {$REGION 'Kind'}
    TKind = (
      &Integer,
      &Float,
      &String,
      &Char,
      &Boolean,
      &Nil
    );
    {$ENDREGION}
  private
    FKind:       TKind;
    FValueInt:   Cardinal;
    FValueFloat: Single;
    FValueStr:   String;
    FValueBool:  Boolean;
  public
    constructor CreateInt  (AValue: Cardinal;     ALine: Integer = 0; ACol: Integer = 0);
    constructor CreateFloat(AValue: Single;       ALine: Integer = 0; ACol: Integer = 0);
    constructor CreateStr  (const AValue: String; ALine: Integer = 0; ACol: Integer = 0);
    constructor CreateChar (AValue: Char;         ALine: Integer = 0; ACol: Integer = 0);
    constructor CreateBool (AValue: Boolean;      ALine: Integer = 0; ACol: Integer = 0);
    constructor CreateNil  (                      ALine: Integer = 0; ACol: Integer = 0);

    property Kind:       TKind    read FKind;
    property ValueInt:   Cardinal read FValueInt;
    property ValueFloat: Single   read FValueFloat;
    property ValueStr:   String   read FValueStr;
    property ValueBool:  Boolean  read FValueBool;
  end;
  {$ENDREGION}

  {$REGION 'Array literal'}
  TASTArrayLiteral = class(TASTExpression)
  private
    FElements: TObjectList<TASTExpression>;
  public
    constructor Create(ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Elements: TObjectList<TASTExpression> read FElements;
  end;
  {$ENDREGION}

  {$REGION 'Typecast'}
  TASTTypeCast = class(TASTExpression)
  private
    FTargetType: TASTType;
    FExpression: TASTExpression;
  public
    constructor Create(ATargetType: TASTType; AExpression: TASTExpression; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property TargetType: TASTType       read FTargetType write FTargetType;
    property Expression: TASTExpression read FExpression write FExpression;
  end;
  {$ENDREGION}

  {$REGION 'Identifier'}
  TASTIdentifier = class(TASTExpression)
  private
    FName: String;
  public
    constructor Create(const AName: String; ALine: Integer = 0; ACol: Integer = 0);

    property Name: String read FName write FName;
  end;
  {$ENDREGION}

  {$REGION 'Binary op'}
  TASTBinary = class(TASTExpression)
  type
    {$REGION 'Operator'}
    TOp = (
      Add,
      Subtract,
      Multiply,
      Divide,
      IntDivide,
      Modulo,
      &And,
      &Or,
      &Xor,
      &Shl,
      &Shr,
      Equal,
      NotEqual,
      Less,
      LessEqual,
      Greater,
      GreaterEqual,
      &In
    );
    {$ENDREGION}
  private
    FLeft:  TASTExpression;
    FRight: TASTExpression;
    FOp:    TOp;
  public
    constructor Create(ALeft: TASTExpression; AOp: TOp; ARight: TASTExpression; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Left:  TASTExpression read FLeft  write FLeft;
    property Right: TASTExpression read FRight write FRight;
    property Op:    TOp            read FOp    write FOp;
  end;
  {$ENDREGION}

  {$REGION 'Unary op'}
  TASTUnary = class(TASTExpression)
  type
    {$REGION 'Operator'}
    TOp = (
      Negate,
      &Not,
      AddressOf,
      Dereference
    );
    {$ENDREGION}
  private
    FOperand: TASTExpression;
    FOp:      TOp;
  public
    constructor Create(AOp: TOp; AOperand: TASTExpression; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Operand: TASTExpression read FOperand write FOperand;
    property Op:      TOp            read FOp      write FOp;
  end;
  {$ENDREGION}

  {$REGION 'Member access'}
  TASTMemberAccess = class(TASTExpression)
  private
    FExpression:  TASTExpression;
    FMemberName:  String;
    FFieldOffset: Cardinal;
  public
    constructor Create(AExpression: TASTExpression; const AMemberName: String; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Expression:  TASTExpression read FExpression  write FExpression;
    property MemberName:  String         read FMemberName  write FMemberName;
    property FieldOffset: Cardinal       read FFieldOffset write FFieldOffset;
  end;
  {$ENDREGION}

  {$REGION 'Array access'}
  TASTArrayAccess = class(TASTExpression)
  private
    FArrayExpr:   TASTExpression;
    FIndexExprs:  TObjectList<TASTExpression>;
    FElementSize: Cardinal;
    FLowBound:    Integer;
  public
    constructor Create(AArrayExpr: TASTExpression; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property ArrayExpr:   TASTExpression              read FArrayExpr   write FArrayExpr;
    property IndexExprs:  TObjectList<TASTExpression> read FIndexExprs;
    property ElementSize: Cardinal                    read FElementSize write FElementSize;
    property LowBound:    Integer                     read FLowBound    write FLowBound;
  end;
  {$ENDREGION}

  {$REGION 'Call'}
  TASTCallExpr = class(TASTExpression)
  private
    FCalleeName: String;
    FArguments:  TObjectList<TASTExpression>;
  public
    constructor Create(const ACalleeName: String; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property CalleeName: String                     read FCalleeName write FCalleeName;
    property Arguments:  TObjectList<TASTExpression> read FArguments;
  end;
  {$ENDREGION}
  {$ENDREGION}

  {$REGION 'Statements'}
  TASTStatement = class(TASTNode)

  end;

  {$REGION 'begin/end'}
  TASTBlock = class(TASTStatement)
  private
    FStatements: TObjectList<TASTStatement>;
  public
    constructor Create(ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Statements: TObjectList<TASTStatement> read FStatements;
  end;
  {$ENDREGION}

  {$REGION 'Assign'}
  TASTAssign = class(TASTStatement)
  type
    {$REGION 'Assign Operator'}
    TOp = (
      Assign,      // :=
      PlusAssign,  // +=
      MinusAssign, // -=
      MulAssign,   // *=
      DivAssign    // /=
    );
    {$ENDREGION}
  private
    FTarget:     TASTExpression;
    FExpression: TASTExpression;
    FOp:         TOp;
  public
    constructor Create(ATarget: TASTExpression; AOp: TOp; AExpression: TASTExpression; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Target:     TASTExpression read FTarget     write FTarget;
    property Expression: TASTExpression read FExpression write FExpression;
    property Op:         TOp            read FOp         write FOp;
  end;
  {$ENDREGION}

  {$REGION 'if'}
  TASTIf = class(TASTStatement)
  private
    FCondition: TASTExpression;
    FThenStmt:  TASTStatement;
    FElseStmt:  TASTStatement;
  public
    constructor Create(ACondition: TASTExpression; AThenStmt: TASTStatement; AElseStmt: TASTStatement = nil; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Condition: TASTExpression read FCondition write FCondition;
    property ThenStmt:  TASTStatement  read FThenStmt  write FThenStmt;
    property ElseStmt:  TASTStatement  read FElseStmt  write FElseStmt;
  end;
  {$ENDREGION}

  {$REGION 'while'}
  TASTWhile = class(TASTStatement)
  private
    FCondition: TASTExpression;
    FBody:      TASTStatement;
  public
    constructor Create(ACondition: TASTExpression; ABody: TASTStatement; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Condition: TASTExpression read FCondition write FCondition;
    property Body:      TASTStatement  read FBody      write FBody;
  end;
  {$ENDREGION}

  {$REGION 'repeat'}
  TASTRepeat = class(TASTStatement)
  private
    FStatements: TObjectList<TASTStatement>;
    FCondition:  TASTExpression;
  public
    constructor Create(ACondition: TASTExpression; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Statements: TObjectList<TASTStatement> read FStatements;
    property Condition:  TASTExpression             read FCondition write FCondition;
  end;
  {$ENDREGION}

  {$REGION 'for'}
  TASTFor = class(TASTStatement)
  private
    FLoopVar:   String;
    FStartExpr: TASTExpression;
    FStopExpr:  TASTExpression;
    FDownto:    Boolean;
    FBody:      TASTStatement;
  public
    constructor Create(const ALoopVar: String; AStartExpr, AStopExpr: TASTExpression; ADownto: Boolean; ABody: TASTStatement; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property LoopVar:   String         read FLoopVar   write FLoopVar;
    property StartExpr: TASTExpression read FStartExpr write FStartExpr;
    property StopExpr:  TASTExpression read FStopExpr  write FStopExpr;
    property &Downto:   Boolean        read FDownto    write FDownto;
    property Body:      TASTStatement  read FBody      write FBody;
  end;
  {$ENDREGION}

  {$REGION 'procedure call'}
  TASTProcCall = class(TASTStatement)
  private
    FCallExpr: TASTCallExpr;
  public
    constructor Create(ACallExpr: TASTCallExpr; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property CallExpr: TASTCallExpr read FCallExpr write FCallExpr;
  end;
  {$ENDREGION}

  {$REGION 'case :'}
  TASTCaseBranch = class(TASTNode)
  type
    {$REGION 'MatchValue'}
    TMatchValue = record
    type
      TKind = (SingleValue, RangeValue);
    public
      Kind:     TKind;
      LowVal:   Integer;
      HighVal:  Integer;
    end;
    {$ENDREGION}
  private
    FValues:    TList<TMatchValue>;
    FStatement: TASTStatement;
  public
    constructor Create(ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Values:    TList<TMatchValue> read FValues;
    property Statement: TASTStatement      read FStatement write FStatement;
  end;
  {$ENDREGION}

  {$REGION 'case'}
  TASTCase = class(TASTStatement)
  private
    FSelector: TASTExpression;
    FBranches: TObjectList<TASTCaseBranch>;
    FElseStmt: TASTStatement;
  public
    constructor Create(ASelector: TASTExpression; AElseStmt: TASTStatement = nil; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Selector: TASTExpression              read FSelector write FSelector;
    property Branches: TObjectList<TASTCaseBranch> read FBranches;
    property ElseStmt: TASTStatement               read FElseStmt write FElseStmt;
  end;
  {$ENDREGION}

  TASTExit     = class(TASTStatement);
  TASTBreak    = class(TASTStatement);
  TASTContinue = class(TASTStatement);

  {$ENDREGION}

  {$REGION 'Declarations'}
  TASTDeclaration = class(TASTNode)
  private
    FIsUsed: Boolean;
  public
    constructor Create(ALine: Integer = 0; ACol: Integer = 0);

    property IsUsed: Boolean read FIsUsed write FIsUsed;
  end;

  {$REGION 'var'}
  TASTVarDecl = class(TASTDeclaration)
  private
    FNames:        TList<String>;
    FVarType:      TASTType;
    FInitialValue: TASTExpression;
  public
    constructor Create(AVarType: TASTType; AInitialValue: TASTExpression = nil; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Names:        TList<String>  read FNames;
    property VarType:      TASTType       read FVarType      write FVarType;
    property InitialValue: TASTExpression read FInitialValue write FInitialValue;
  end;
  {$ENDREGION}

  {$REGION 'const'}
  TASTConstDecl = class(TASTDeclaration)
  private
    FName:      String;
    FConstType: TASTType;
    FValue:     TASTExpression;
    FConstVal:  TConstValue;
  public
    constructor Create(const AName: String; AValue: TASTExpression; const AConstVal: TConstValue; AConstType: TASTType = nil; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Name:      String         read FName      write FName;
    property ConstType: TASTType       read FConstType write FConstType;
    property Value:     TASTExpression read FValue     write FValue;
    property ConstVal:  TConstValue    read FConstVal  write FConstVal;
  end;
  {$ENDREGION}

  {$REGION 'type'}
  TASTTypeDecl = class(TASTDeclaration)
  private
    FName:     String;
    FDeclType: TASTType;
  public
    constructor Create(const AName: String; ADeclType: TASTType; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Name:     String   read FName     write FName;
    property DeclType: TASTType read FDeclType write FDeclType;
  end;
  {$ENDREGION}

  {$REGION 'parameter'}
  TASTParamDecl = class(TASTNode)
  type
    {$REGION 'Modifier'}
    TModifier = (
      Value,
      &Var,
      &Const,
      &Out);
    {$ENDREGION}
  private
    FName:      String;
    FParamType: TASTType;
    FModifier:  TModifier;
  public
    constructor Create(const AName: String; AParamType: TASTType; AModifier: TModifier = TModifier.Value; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Name:      String    read FName      write FName;
    property ParamType: TASTType  read FParamType write FParamType;
    property Modifier:  TModifier read FModifier  write FModifier;
  end;
  {$ENDREGION}

  {$REGION 'routine'}
  TASTRoutineDecl = class(TASTDeclaration)
  private
    FName:           String;
    FIsFunction:     Boolean;
    FIsSysCall:      Boolean;
    FSysCallID:      Cardinal;
    FSysCallExpr:    TASTExpression;
    FParams:         TObjectList<TASTParamDecl>;
    FReturnType:     TASTType;
    FDeclarations:   TObjectList<TASTDeclaration>;
    FBody:           TASTBlock;
    FParentTypeName: String;
    FIsRecordMethod: Boolean;
    FIsInterrupt:    Boolean;
    FIsVarArgs:      Boolean;
  public
    constructor Create(const AName: String; AIsFunction: Boolean; AReturnType: TASTType = nil; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Name:           String                       read FName           write FName;
    property IsFunction:     Boolean                      read FIsFunction     write FIsFunction;
    property IsSysCall:      Boolean                      read FIsSysCall      write FIsSysCall;
    property SysCallID:      Cardinal                     read FSysCallID      write FSysCallID;
    property SysCallExpr:    TASTExpression               read FSysCallExpr    write FSysCallExpr;
    property Params:         TObjectList<TASTParamDecl>   read FParams;
    property ReturnType:     TASTType                     read FReturnType     write FReturnType;
    property Declarations:   TObjectList<TASTDeclaration> read FDeclarations;
    property Body:           TASTBlock                    read FBody           write FBody;
    property ParentTypeName: String                       read FParentTypeName write FParentTypeName;
    property IsRecordMethod: Boolean                      read FIsRecordMethod write FIsRecordMethod;
    property IsInterrupt:    Boolean                      read FIsInterrupt    write FIsInterrupt;
    property IsVarArgs:      Boolean                      read FIsVarArgs      write FIsVarArgs;
  end;
  {$ENDREGION}

  {$REGION 'property'}
  TASTProperty = class(TASTNode)
  private
    FName:         String;
    FPropertyType: TASTType;
    FReadSpec:     String;
    FWriteSpec:    String;
    FVisibility:   TVisibility;
  public
    constructor Create(const AName: String; APropertyType: TASTType; const AReadSpec, AWriteSpec: String; AVisibility: TVisibility; ALine: Integer = 0; ACol: Integer = 0);
    destructor  Destroy; override;

    property Name:         String      read FName         write FName;
    property PropertyType: TASTType    read FPropertyType write FPropertyType;
    property ReadSpec:     String      read FReadSpec     write FReadSpec;
    property WriteSpec:    String      read FWriteSpec    write FWriteSpec;
    property Visibility:   TVisibility read FVisibility   write FVisibility;
  end;
  {$ENDREGION}

  {$ENDREGION}

  {$REGION 'Units'}
  {$REGION 'CompilationUnit'}
  TASTCompilationUnit = class(TASTNode)
  private
    FName:         String;
    FHeader:       TROMHeader;
    FUsesUnits:    TList<String>;
    FDeclarations: TObjectList<TASTDeclaration>;
  public
    constructor Create(const AName: String = '');
    destructor  Destroy; override;

    property Name:         String                       read FName   write FName;
    property Header:       TROMHeader                   read FHeader write FHeader;
    property UsesUnits:    TList<String>                read FUsesUnits;
    property Declarations: TObjectList<TASTDeclaration> read FDeclarations;
  end;
  {$ENDREGION}

  {$REGION 'Program'}
  TASTProgram = class(TASTCompilationUnit)
  private
    FBody: TASTBlock;
  public
    Header: TROMHeader;

    constructor Create(const AName: String = '');
    destructor  Destroy; override;

    property Body: TASTBlock read FBody write FBody;
  end;
  {$ENDREGION}

  {$REGION 'Unit'}
  TASTUnit = class(TASTCompilationUnit)
  private
    FInterfaceUses:       TList<String>;
    FInterfaceDecls:      TObjectList<TASTDeclaration>;
    FImplementationUses:  TList<String>;
    FImplementationDecls: TObjectList<TASTDeclaration>;
    FInitializationBlock: TASTBlock;
  public
    constructor Create(const AName: String = '');
    destructor  Destroy; override;

    property InterfaceUses:       TList<String>                read FInterfaceUses;
    property InterfaceDecls:      TObjectList<TASTDeclaration> read FInterfaceDecls;
    property ImplementationUses:  TList<String>                read FImplementationUses;
    property ImplementationDecls: TObjectList<TASTDeclaration> read FImplementationDecls;
    property InitializationBlock: TASTBlock                    read FInitializationBlock write FInitializationBlock;
  end;
  {$ENDREGION}
  {$ENDREGION}

implementation

{$REGION 'ConstValue'}
class function TConstValue.MakeInt(AVal: Cardinal): TConstValue;
begin
  Result := Default(TConstValue);

  Result.Kind     := TConstValue.TKind.Integer;
  Result.ValueInt := AVal;
end;

class function TConstValue.MakeFloat(AVal: Single): TConstValue;
begin
  Result := Default(TConstValue);

  Result.Kind       := TConstValue.TKind.Single;
  Result.ValueFloat := AVal;
end;

class function TConstValue.MakeBool(AVal: Boolean): TConstValue;
begin
  Result := Default(TConstValue);

  Result.Kind      := TConstValue.TKind.Boolean;
  Result.ValueBool := AVal;
end;

class function TConstValue.MakeStr(const AVal: String): TConstValue;
begin
  Result := Default(TConstValue);

  Result.Kind     := TConstValue.TKind.String;
  Result.ValueStr := AVal;
end;

class function TConstValue.MakePtr(AVal: Cardinal): TConstValue;
begin
  Result := Default(TConstValue);

  Result.Kind     := TConstValue.TKind.Pointer;
  Result.ValueInt := AVal;
end;
{$ENDREGION}

{$REGION 'ASTNode'}
constructor TASTNode.Create(ALine, ACol: Integer);
begin
  inherited Create;

  FLine := ALine;
  FCol  := ACol;
end;
{$ENDREGION}

{$REGION 'ASTType'}
constructor TASTType.Create(AKind: TKind; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FKind             := AKind;
  FElementType      := nil;
  FRecordFields     := TObjectList<TASTNode>.Create(True);
  FRecordMethods    := TObjectList<TASTNode>.Create(True);
  FEnumElements     := TList<TEnumElement>.Create;
  FRecordProperties := TObjectList<TASTNode>.Create(True);
end;

constructor TASTType.Create(const AName: String; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FKind             := TKind.NamedAlias;
  FTypeName         := AName;
  FElementType      := nil;
  FRecordFields     := TObjectList<TASTNode>.Create(True);
  FRecordMethods    := TObjectList<TASTNode>.Create(True);
  FEnumElements     := TList<TEnumElement>.Create;
  FRecordProperties := TObjectList<TASTNode>.Create(True);
end;

destructor TASTType.Destroy;
begin
  if Assigned(FElementType) then
    FElementType.Free;

  FRecordFields.Free;
  FRecordMethods.Free;
  FEnumElements.Free;
  FRecordProperties.Free;

  inherited;
end;

function TASTType.Size: Cardinal;
begin
  case FKind of
    TKind.Byte,
    TKind.Char,
    TKind.Boolean,
    TKind.ShortInt,
    TKind.Enum:
      Result := 1;

    TKind.Word,
    TKind.SmallInt:
      Result := 2;

    TKind.Integer,
    TKind.Single,
    TKind.Cardinal,
    TKind.String,
    TKind.Pointer,
    TKind.Set:
      Result := 4;

    TKind.Array:
    begin
      var Count := (FSubrangeHigh - FSubrangeLow) + 1;

      if Count < 0 then
        Count := 0;

      if Assigned(FElementType) then
        Result := Cardinal(Count) * FElementType.Size
      else
        Result := Cardinal(Count) * 4;
    end;

    TKind.Record:
    begin
      Result := 0;

      for var Node in FRecordFields do
      begin
        if Node is TASTVarDecl then
        begin
          var VarDecl := TASTVarDecl(Node);

          if Assigned(VarDecl.VarType) then
          begin
            var FieldSize := (VarDecl.VarType.Size + 3) and not Cardinal(3);

            Result := Result + (Cardinal(VarDecl.Names.Count) * FieldSize);
          end;
        end;
      end;
    end;
  else
    Result := 4;
  end;
end;

function TASTType.Clone: TASTType;
begin
  Result := TASTType.Create(FKind, Line, Col);

  Result.TypeName     := FTypeName;
  Result.SubrangeLow  := FSubrangeLow;
  Result.SubrangeHigh := FSubrangeHigh;

  for var Elem in FEnumElements do
    Result.EnumElements.Add(Elem);

  if Assigned(FElementType) then
    Result.ElementType := FElementType.Clone;

  for var FieldNode in FRecordFields do
  begin
    if FieldNode is TASTVarDecl then
    begin
      var VD    := TASTVarDecl(FieldNode);
      var NewVD := TASTVarDecl.Create(VD.VarType.Clone, nil, VD.Line, VD.Col);

      for var N in VD.Names do
        NewVD.Names.Add(N);

      Result.RecordFields.Add(NewVD);
    end;
  end;
end;

function TASTType.IsFloat: Boolean;
begin
  Result := FKind = TKind.Single;
end;

function TASTType.IsInteger: Boolean;
begin
  Result := FKind in [TKind.Integer, TKind.Byte, TKind.Word, TKind.Cardinal, TKind.ShortInt, TKind.SmallInt];
end;

function TASTType.IsNumeric: Boolean;
begin
  Result := IsInteger or IsFloat;
end;

function TASTType.IsBoolean: Boolean;
begin
  Result := FKind = TKind.Boolean;
end;

function TASTType.IsString: Boolean;
begin
  Result := FKind = TKind.String;
end;

function TASTType.IsSigned: Boolean;
begin
  Result := FKind in [TKind.Integer, TKind.SmallInt, TKind.ShortInt];
end;

function TASTType.IsSet: Boolean;
begin
  Result := FKind = TKind.Set;
end;
{$ENDREGION}

{$REGION 'Expressions'}

{$REGION 'Literal'}
constructor TASTLiteral.CreateInt(AValue: Cardinal; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FKind     := TKind.Integer;
  FValueInt := AValue;
end;

constructor TASTLiteral.CreateFloat(AValue: Single; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FKind       := TKind.Float;
  FValueFloat := AValue;
end;

constructor TASTLiteral.CreateStr(const AValue: String; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FKind     := TKind.String;
  FValueStr := AValue;
end;

constructor TASTLiteral.CreateChar(AValue: Char; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FKind     := TKind.Char;
  FValueStr := AValue;
end;

constructor TASTLiteral.CreateBool(AValue: Boolean; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FKind      := TKind.Boolean;
  FValueBool := AValue;
end;

constructor TASTLiteral.CreateNil(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FKind := TKind.Nil;
end;
{$ENDREGION}

{$REGION 'Array literal'}
constructor TASTArrayLiteral.Create(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FElements := TObjectList<TASTExpression>.Create(True);
end;

destructor TASTArrayLiteral.Destroy;
begin
  FElements.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'Type cast'}
constructor TASTTypeCast.Create(ATargetType: TASTType; AExpression: TASTExpression; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FTargetType := ATargetType;
  FExpression := AExpression;
end;

destructor TASTTypeCast.Destroy;
begin
  if Assigned(FTargetType) then
    FTargetType.Free;

  if Assigned(FExpression) then
    FExpression.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'Identifier'}
constructor TASTIdentifier.Create(const AName: String; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FName := AName;
end;
{$ENDREGION}

{$REGION 'Binary op'}
constructor TASTBinary.Create(ALeft: TASTExpression; AOp: TOp; ARight: TASTExpression; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FLeft  := ALeft;
  FOp    := AOp;
  FRight := ARight;
end;

destructor TASTBinary.Destroy;
begin
  if Assigned(FLeft) then
    FLeft.Free;

  if Assigned(FRight) then
    FRight.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'Unary op'}
constructor TASTUnary.Create(AOp: TOp; AOperand: TASTExpression; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FOp      := AOp;
  FOperand := AOperand;
end;

destructor TASTUnary.Destroy;
begin
  if Assigned(FOperand) then
    FOperand.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'Member access'}
constructor TASTMemberAccess.Create(AExpression: TASTExpression; const AMemberName: String; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FExpression := AExpression;
  FMemberName := AMemberName;
end;

destructor TASTMemberAccess.Destroy;
begin
  if Assigned(FExpression) then
    FExpression.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'Array access'}
constructor TASTArrayAccess.Create(AArrayExpr: TASTExpression; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FArrayExpr   := AArrayExpr;
  FIndexExprs  := TObjectList<TASTExpression>.Create(True);
  FElementSize := 4;
  FLowBound    := 0;
end;

destructor TASTArrayAccess.Destroy;
begin
  if Assigned(FArrayExpr) then
    FArrayExpr.Free;

  FIndexExprs.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'Call'}
constructor TASTCallExpr.Create(const ACalleeName: String; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FCalleeName := ACalleeName;
  FArguments  := TObjectList<TASTExpression>.Create(True);
end;

destructor TASTCallExpr.Destroy;
begin
  FArguments.Free;

  inherited;
end;
{$ENDREGION}

{$ENDREGION}

{$REGION 'Statements'}

{$REGION 'begin/end'}
constructor TASTBlock.Create(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FStatements := TObjectList<TASTStatement>.Create(True);
end;

destructor TASTBlock.Destroy;
begin
  FStatements.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'Assign'}
constructor TASTAssign.Create(ATarget: TASTExpression; AOp: TOp; AExpression: TASTExpression; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FTarget     := ATarget;
  FOp         := AOp;
  FExpression := AExpression;
end;

destructor TASTAssign.Destroy;
begin
  if Assigned(FTarget) then
    FTarget.Free;

  if Assigned(FExpression) then
    FExpression.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'if'}
constructor TASTIf.Create(ACondition: TASTExpression; AThenStmt, AElseStmt: TASTStatement; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FCondition := ACondition;
  FThenStmt  := AThenStmt;
  FElseStmt  := AElseStmt;
end;

destructor TASTIf.Destroy;
begin
  if Assigned(FCondition) then
    FCondition.Free;

  if Assigned(FThenStmt) then
    FThenStmt.Free;

  if Assigned(FElseStmt) then
    FElseStmt.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'while'}
constructor TASTWhile.Create(ACondition: TASTExpression; ABody: TASTStatement; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FCondition := ACondition;
  FBody      := ABody;
end;

destructor TASTWhile.Destroy;
begin
  if Assigned(FCondition) then
    FCondition.Free;

  if Assigned(FBody) then
    FBody.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'repeat'}
constructor TASTRepeat.Create(ACondition: TASTExpression; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FCondition  := ACondition;
  FStatements := TObjectList<TASTStatement>.Create(True);
end;

destructor TASTRepeat.Destroy;
begin
  if Assigned(FCondition) then
    FCondition.Free;

  FStatements.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'for'}
constructor TASTFor.Create(const ALoopVar: String; AStartExpr, AStopExpr: TASTExpression; ADownto: Boolean; ABody: TASTStatement; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FLoopVar   := ALoopVar;
  FStartExpr := AStartExpr;
  FStopExpr  := AStopExpr;
  FDownto    := ADownto;
  FBody      := ABody;
end;

destructor TASTFor.Destroy;
begin
  if Assigned(FStartExpr) then
    FStartExpr.Free;

  if Assigned(FStopExpr) then
    FStopExpr.Free;

  if Assigned(FBody) then
    FBody.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'Procedure call'}
constructor TASTProcCall.Create(ACallExpr: TASTCallExpr; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FCallExpr := ACallExpr;
end;

destructor TASTProcCall.Destroy;
begin
  if Assigned(FCallExpr) then
    FCallExpr.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'case :'}
constructor TASTCaseBranch.Create(ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FValues    := TList<TMatchValue>.Create;
  FStatement := nil;
end;

destructor TASTCaseBranch.Destroy;
begin
  FValues.Free;

  if Assigned(FStatement) then
    FStatement.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'case'}
constructor TASTCase.Create(ASelector: TASTExpression; AElseStmt: TASTStatement; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FSelector := ASelector;
  FBranches := TObjectList<TASTCaseBranch>.Create(True);
  FElseStmt := AElseStmt;
end;

destructor TASTCase.Destroy;
begin
  if Assigned(FSelector) then
    FSelector.Free;

  FBranches.Free;

  if Assigned(FElseStmt) then
    FElseStmt.Free;

  inherited;
end;
{$ENDREGION}

{$ENDREGION}

{$REGION 'Declarations'}
constructor TASTDeclaration.Create(ALine: Integer = 0; ACol: Integer = 0);
begin
  inherited Create(ALine, ACol);

  FIsUsed := False;
end;

{$REGION 'var'}
constructor TASTVarDecl.Create(AVarType: TASTType; AInitialValue: TASTExpression; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FNames        := TList<String>.Create;
  FVarType      := AVarType;
  FInitialValue := AInitialValue;
end;

destructor TASTVarDecl.Destroy;
begin
  FNames.Free;

  if Assigned(FVarType) then
    FVarType.Free;

  if Assigned(FInitialValue) then
    FInitialValue.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'const'}
constructor TASTConstDecl.Create(const AName: String; AValue: TASTExpression; const AConstVal: TConstValue; AConstType: TASTType; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FName      := AName;
  FValue     := AValue;
  FConstVal  := AConstVal;
  FConstType := AConstType;
end;

destructor TASTConstDecl.Destroy;
begin
  if Assigned(FConstType) then
    FConstType.Free;

  if Assigned(FValue) then
    FValue.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'type'}
constructor TASTTypeDecl.Create(const AName: String; ADeclType: TASTType; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FName     := AName;
  FDeclType := ADeclType;
end;

destructor TASTTypeDecl.Destroy;
begin
  if Assigned(FDeclType) then
    FDeclType.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'Parameter'}
constructor TASTParamDecl.Create(const AName: String; AParamType: TASTType; AModifier: TModifier; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FName      := AName;
  FParamType := AParamType;
  FModifier  := AModifier;
end;

destructor TASTParamDecl.Destroy;
begin
  if Assigned(FParamType) then
    FParamType.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'Routine'}
constructor TASTRoutineDecl.Create(const AName: String; AIsFunction: Boolean; AReturnType: TASTType; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FName         := AName;
  FIsFunction   := AIsFunction;
  FReturnType   := AReturnType;
  FParams       := TObjectList<TASTParamDecl>.Create(True);
  FDeclarations := TObjectList<TASTDeclaration>.Create(True);
  FBody         := nil;
end;

destructor TASTRoutineDecl.Destroy;
begin
  FParams.Free;

  if Assigned(FReturnType) then
    FReturnType.Free;

  FDeclarations.Free;

  if Assigned(FBody) then
    FBody.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'property'}
constructor TASTProperty.Create(const AName: String; APropertyType: TASTType; const AReadSpec, AWriteSpec: String; AVisibility: TVisibility; ALine, ACol: Integer);
begin
  inherited Create(ALine, ACol);

  FName         := AName;
  FPropertyType := APropertyType;
  FReadSpec     := AReadSpec;
  FWriteSpec    := AWriteSpec;
  FVisibility   := AVisibility;
end;

destructor TASTProperty.Destroy;
begin
  if Assigned(FPropertyType) then
    FPropertyType.Free;

  inherited;
end;
{$ENDREGION}

{$ENDREGION}

{$REGION 'Units'}

{$REGION 'CompilationUnit'}
constructor TASTCompilationUnit.Create(const AName: String);
begin
  inherited Create(1, 1);

  FName := AName;

  FHeader.Reset;
  FHeader.ROM.Name := AName;

  FUsesUnits    := TList<String>.Create;
  FDeclarations := TObjectList<TASTDeclaration>.Create(True);
end;

destructor TASTCompilationUnit.Destroy;
begin
  FUsesUnits.Free;
  FDeclarations.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'Program'}
constructor TASTProgram.Create(const AName: String);
begin
  inherited Create(AName);

  FBody := nil;
end;

destructor TASTProgram.Destroy;
begin
  if Assigned(FBody) then
    FBody.Free;

  inherited;
end;
{$ENDREGION}

{$REGION 'Unit'}
constructor TASTUnit.Create(const AName: String);
begin
  inherited Create(AName);

  FInterfaceUses       := TList<String>.Create;
  FInterfaceDecls      := TObjectList<TASTDeclaration>.Create(True);
  FImplementationUses  := TList<String>.Create;
  FImplementationDecls := TObjectList<TASTDeclaration>.Create(True);
  FInitializationBlock := nil;
end;

destructor TASTUnit.Destroy;
begin
  FInterfaceUses.Free;
  FInterfaceDecls.Free;
  FImplementationUses.Free;
  FImplementationDecls.Free;

  if Assigned(FInitializationBlock) then
    FInitializationBlock.Free;

  inherited;
end;
{$ENDREGION}

{$ENDREGION}

end.
