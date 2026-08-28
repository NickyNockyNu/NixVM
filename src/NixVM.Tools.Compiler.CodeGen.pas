{
  NixVM.Tools.Compiler.CodeGen.pas
    IR code generator

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

unit NixVM.Tools.Compiler.CodeGen;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,

  NixVM.Core.Registers,
  NixVM.Core.Instructions,

  NixVM.Tools.IR,
  
  NixVM.Tools.Compiler.AST,
  NixVM.Tools.Compiler.Semantics;

type
  {$REGION 'CodeGenerator'}
  TCodeGenerator = class
 type
    {$REGION 'LoopContext'}
    TLoopContext = record
      StartLabel:    String;
      ContinueLabel: String;
      EndLabel:      String;
    end;
    {$ENDREGION}

    {$REGION 'WithContext'}
    TWithContext = record
      RecordType:  TType;
      StackOffset: Integer;
    end;
    {$ENDREGION}
  private
    FProgram:         TASTProgram;
    FAnalyzer:        TSemanticAnalyzer;
    FIR:              TIRList;
    FLabelCounter:    Integer;
    FStringTable:     TDictionary<String, String>;
    FStringCounter:   Integer;
    FCurrentScope:    TScope;
    FLoopStack:       TStack<TLoopContext>;
    FWithStack:       TList<TWithContext>;
    FCurrentRoutine:  TASTRoutineDecl;
    FUnits:           TList<TASTUnit>;
    FSourceLines:     TStrings;
    FFileName:        String;
    FLastLine:        Integer;

    procedure EmitSourceComment(ANode: TASTNode);

    function  GenUniqueLabel(const APrefix: String = '@loc'): String;
    function  GetStringLabel(const AStr: String): String;

    function HasCalls(ANode: TASTNode): Boolean;

    procedure GenProgram;
    procedure GenRoutine(ARoutine: TASTRoutineDecl);

    procedure GenStatement(AStmt:   TASTStatement);
    procedure GenBlock    (ABlock:  TASTBlock);
    procedure GenWith     (AWith:   TASTWith);
    procedure GenAssign   (AAssign: TASTAssign);
    procedure GenIf       (AIf:     TASTIf);
    procedure GenWhile    (AWhile:  TASTWhile);
    procedure GenRepeat   (ARepeat: TASTRepeat);
    procedure GenFor      (AFor:    TASTFor);
    procedure GenCase     (ACase:   TASTCase);
    procedure GenProcCall (ACall:   TASTProcCall);

    procedure GenBreak;
    procedure GenContinue;

    procedure GenExpression  (AExpr:     TASTExpression);
    procedure GenBinary      (ABinary:   TASTBinary);
    procedure GenUnary       (AUnary:    TASTUnary);
    procedure GenLiteral     (ALiteral:  TASTLiteral);
    procedure GenIdentifier  (AIdent:    TASTIdentifier);
    procedure GenMemberAccess(AMember:   TASTMemberAccess);
    procedure GenArrayAccess (AArrayAcc: TASTArrayAccess);
    procedure GenCallExpr    (ACall:     TASTCallExpr);

    procedure GenStoreToTarget(ATarget: TASTExpression);

    procedure GenAddressOf(AExpr: TASTExpression);

    procedure GenDataSections;
  public
    constructor Create(AProgram: TASTProgram; AUnits: TList<TASTUnit>; AAnalyzer: TSemanticAnalyzer; const ASource: String = ''; const AFileName: String = '');
    destructor  Destroy; override;

    function Generate: TIRList;

    property IR: TIRList read FIR;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Core.System;

{$REGION 'CodeGenerator'}
constructor TCodeGenerator.Create(AProgram: TASTProgram; AUnits: TList<TASTUnit>; AAnalyzer: TSemanticAnalyzer; const ASource: String = ''; const AFileName: String = '');
begin
  inherited Create;

  FProgram       := AProgram;
  FAnalyzer      := AAnalyzer;
  FUnits         := AUnits;
  FIR            := TIRList.Create;
  FLabelCounter  := 0;
  FStringTable   := TDictionary<String, String>.Create;
  FStringCounter := 0;
  FCurrentScope  := FAnalyzer.GlobalScope;
  FLoopStack     := TStack<TLoopContext>.Create;
  FWithStack     := TList<TWithContext>.Create;
  FLastLine      := 0;

  FFileName      := ExtractFileName(AFileName);
  if FFileName = '' then
    FFileName := 'Unit.pas';

  FSourceLines := TStringList.Create;
  if ASource <> '' then
    FSourceLines.Text := ASource;
end;

destructor TCodeGenerator.Destroy;
begin
  FSourceLines.Free;
  FLoopStack.Free;
  FWithStack.Free;
  FStringTable.Free;

  inherited;
end;

procedure TCodeGenerator.EmitSourceComment(ANode: TASTNode);
begin
  if (ANode = nil) or (ANode.Line <= 0) then
    Exit;

  if ANode.Line <> FLastLine then
  begin
    FLastLine := ANode.Line;

    var LineText := '';

    if (ANode.Line - 1 >= 0) and (ANode.Line - 1 < FSourceLines.Count) then
      LineText := Trim(FSourceLines[ANode.Line - 1]);

    if LineText <> '' then
    begin
      FIR.AddBlankLine;
      FIR.AddComment(Format('%s(%d): %s', [FFileName, ANode.Line, Trim(LineText)]));
    end;
  end;
end;

function TCodeGenerator.GenUniqueLabel(const APrefix: String): String;
begin
  Inc(FLabelCounter);
  Result := Format('%s_%d', [APrefix, FLabelCounter]);
end;

function TCodeGenerator.GetStringLabel(const AStr: String): String;
begin
  if not FStringTable.TryGetValue(AStr, Result) then
  begin
    Inc(FStringCounter);
    Result := Format('_strconst_%d', [FStringCounter]);
    FStringTable.Add(AStr, Result);
  end;
end;

function TCodeGenerator.HasCalls(ANode: TASTNode): Boolean;
begin
  if ANode = nil then
    Exit(False);

  if (ANode is TASTCallExpr) or (ANode is TASTProcCall) then
    Exit(True);

  if ANode is TASTMemberAccess then
    Exit(HasCalls(TASTMemberAccess(ANode).Expression));

  if ANode is TASTBlock then
  begin
    for var Stmt in TASTBlock(ANode).Statements do
      if HasCalls(Stmt) then Exit(True);

    Exit(False);
  end;

  if ANode is TASTAssign then
    Exit(HasCalls(TASTAssign(ANode).Target) or HasCalls(TASTAssign(ANode).Expression));

  if ANode is TASTIf then
    Exit(HasCalls(TASTIf(ANode).Condition) or HasCalls(TASTIf(ANode).ThenStmt) or HasCalls(TASTIf(ANode).ElseStmt));

  if ANode is TASTWhile then
    Exit(HasCalls(TASTWhile(ANode).Condition) or HasCalls(TASTWhile(ANode).Body));

  if ANode is TASTRepeat then
  begin
    for var S in TASTRepeat(ANode).Statements do
      if HasCalls(S) then Exit(True);

    Exit(HasCalls(TASTRepeat(ANode).Condition));
  end;

  if ANode is TASTFor then
    Exit(HasCalls(TASTFor(ANode).StartExpr) or HasCalls(TASTFor(ANode).StopExpr) or HasCalls(TASTFor(ANode).Body));

  if ANode is TASTBinary then
    Exit(HasCalls(TASTBinary(ANode).Left) or HasCalls(TASTBinary(ANode).Right));

  if ANode is TASTUnary then
    Exit(HasCalls(TASTUnary(ANode).Operand));

  Result := False;
end;

procedure TCodeGenerator.GenLiteral(ALiteral: TASTLiteral);
begin
  case ALiteral.Kind of
    TASTLiteral.TKind.Integer,
    TASTLiteral.TKind.Set:
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, ALiteral.ValueInt);

    TASTLiteral.TKind.Float:
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, PCardinal(@ALiteral.ValueFloat)^);

    TASTLiteral.TKind.Boolean:
      if ALiteral.ValueBool then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, 1)
      else
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, 0);

    TASTLiteral.TKind.String:
    begin
      var StrLbl := GetStringLabel(ALiteral.ValueStr);
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, TLabelString(StrLbl));
    end;

    TASTLiteral.TKind.Char:
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, Ord(ALiteral.ValueStr[1]));

    TASTLiteral.TKind.Nil:
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, 0);
  end;
end;

procedure TCodeGenerator.GenIdentifier(AIdent: TASTIdentifier);
var
  ElemSize: Cardinal;
  IsSignedType: Boolean;
begin
  for var i := FWithStack.Count - 1 downto 0 do
  begin
    var Ctx := FWithStack[i];

    if Ctx.RecordType <> nil then
    begin
      var Field: TType.TRecordField;

      if Ctx.RecordType.FindField(AIdent.Name, Field) then
      begin
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R1, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.R1, Field.Offset);

        Exit;
      end;

      var Prop: TType.TProperty;

      if Ctx.RecordType.FindProperty(AIdent.Name, Prop) then
      begin
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));

        if Prop.IsDirectRead then
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.R0, Prop.ReadOffset)
        else
        begin
          var MangledName := Ctx.RecordType.Name + '_' + Prop.ReadSpec;

          FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(MangledName));
        end;

        Exit;
      end;
    end;
  end;

  var SelfSym := FCurrentScope.Resolve('self');

  if (SelfSym <> nil) and (SelfSym.SymbolType <> nil) and (SelfSym.SymbolType.Kind = TType.TKind.Record) then
  begin
    var Field: TType.TRecordField;

    if SelfSym.SymbolType.FindField(AIdent.Name, Field) then
    begin
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R1, TRegisters.ID.BP, Cardinal(SelfSym.StackOffset));
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.R1, Field.Offset);

      Exit;
    end;
  end;

  var Sym := FCurrentScope.Resolve(AIdent.Name);

  if Sym = nil then
    Exit;

  if Sym.Kind = TSymbol.TKind.Constant then
  begin
    if Sym.ConstVal.Kind = TConstValue.TKind.Single then
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, PCardinal(@Sym.ConstVal.ValueFloat)^)

    else if Sym.ConstVal.Kind = TConstValue.TKind.String then
    begin
      var StrLbl := GetStringLabel(Sym.ConstVal.ValueStr);

      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, TLabelString(StrLbl));
    end
    else
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, Sym.ConstVal.ValueInt);

    Exit;
  end;

  if Sym.Kind = TSymbol.TKind.Function then
  begin
    if Sym.IsSysCall then
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.syscall, Cardinal(Sym.SysCallID))
    else
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(Sym.Name));

    Exit;
  end;

  ElemSize     := 4;
  IsSignedType := False;

  if Sym.SymbolType <> nil then
  begin
    ElemSize     := Sym.SymbolType.Size;
    IsSignedType := Sym.SymbolType.IsSigned;
  end;

  case Sym.Storage of
    TSymbol.TStorage.Global:
    begin
      case ElemSize of
        1:
        begin
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TLabelString(Sym.GlobalLabel));
          FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ldb, TRegisters.ID.R0, TRegisters.ID.R1);

          if IsSignedType then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextb, TRegisters.ID.R0, TRegisters.ID.R0);
        end;

        2:
        begin
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TLabelString(Sym.GlobalLabel));
          FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ldw, TRegisters.ID.R0, TRegisters.ID.R1);

          if IsSignedType then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextw, TRegisters.ID.R0, TRegisters.ID.R0);
        end;
      else
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.ld, TRegisters.ID.R0, TLabelString(Sym.GlobalLabel));
      end;
    end;

    TSymbol.TStorage.Local:
    begin
      case ElemSize of
        1:
        begin
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldob, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Sym.StackOffset));

          if IsSignedType then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextb, TRegisters.ID.R0, TRegisters.ID.R0);
        end;

        2:
        begin
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldow, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Sym.StackOffset));

          if IsSignedType then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextw, TRegisters.ID.R0, TRegisters.ID.R0);
        end;
      else
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Sym.StackOffset));
      end;
    end;

    TSymbol.TStorage.Parameter:
    begin
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Sym.StackOffset));

      if Sym.IsVarParam and (Sym.SymbolType.Kind <> TType.TKind.Record) then
      begin
        case ElemSize of
          1:
          begin
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ldb, TRegisters.ID.R0, TRegisters.ID.R0);

            if IsSignedType then
              FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextb, TRegisters.ID.R0, TRegisters.ID.R0);
          end;

          2:
          begin
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ldw, TRegisters.ID.R0, TRegisters.ID.R0);

            if IsSignedType then
              FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextw, TRegisters.ID.R0, TRegisters.ID.R0);
          end;
        else
          FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ld, TRegisters.ID.R0, TRegisters.ID.R0);
        end;
      end;
    end;
  end;
end;

procedure TCodeGenerator.GenMemberAccess(AMember: TASTMemberAccess);
begin
  if AMember.Expression is TASTIdentifier then
  begin
    var IdentName := TASTIdentifier(AMember.Expression).Name;
    var Sym := FCurrentScope.Resolve(IdentName);

    if (Sym <> nil) and (Sym.Kind = TSymbol.TKind.Type) and (Sym.SymbolType.Kind = TType.TKind.Enum) then
      for var Elem in Sym.SymbolType.EnumElements do
        if SameText(Elem.Name, AMember.MemberName) then
        begin
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, Cardinal(Elem.Value));
          Exit;
        end;
  end;

  if (AMember.Expression.ResolvedType <> nil) then
  begin
    var BaseType := AMember.Expression.ResolvedType;

    if (BaseType.Kind = TASTType.TKind.Pointer) and (BaseType.ElementType <> nil) then
      BaseType := BaseType.ElementType;

    var Sym := FAnalyzer.GlobalScope.Resolve(BaseType.TypeName);

    if (Sym <> nil) and (Sym.SymbolType <> nil) and (Sym.SymbolType.Kind = TType.TKind.Record) then
    begin
      var Prop: TType.TProperty;

      if Sym.SymbolType.FindProperty(AMember.MemberName, Prop) then
      begin
        if Prop.IsDirectRead then
        begin
          GenAddressOf(AMember.Expression);
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.R0, Prop.ReadOffset);

          Exit;
        end;

        if Length(Prop.ReadSpec) > 0 then
        begin
          GenAddressOf(AMember.Expression);
          var MangledName := Sym.SymbolType.Name + '_' + Prop.ReadSpec;
          FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(MangledName));

          Exit;
        end;

        GenAddressOf(AMember.Expression);
        var MangledName := Sym.SymbolType.Name + '_' + Prop.ReadSpec;
        FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(MangledName));

        Exit;
      end;
    end;
  end;

  GenAddressOf(AMember.Expression);
  FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.R0, AMember.FieldOffset);
end;

procedure TCodeGenerator.GenArrayAccess(AArrayAcc: TASTArrayAccess);
begin
  GenAddressOf(AArrayAcc);

  var ElemSize: Cardinal := AArrayAcc.ElementSize;

  if ElemSize = 0 then
    ElemSize := 4;

  case ElemSize of
    1: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ldb, TRegisters.ID.R0, TRegisters.ID.R0);
    2: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ldw, TRegisters.ID.R0, TRegisters.ID.R0);
  else
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ld,  TRegisters.ID.R0, TRegisters.ID.R0);
  end;
end;

procedure TCodeGenerator.GenUnary(AUnary: TASTUnary);
begin
  GenExpression(AUnary.Operand);

  case AUnary.Op of
    TASTUnary.TOp.Negate:
    begin
      if (AUnary.Operand.ResolvedType <> nil) and AUnary.Operand.ResolvedType.IsFloat then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.xor, TRegisters.ID.R0, $80000000)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ineg, TRegisters.ID.R0, TRegisters.ID.R0);
    end;

    TASTUnary.TOp.Not:
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.not, TRegisters.ID.R0, TRegisters.ID.R0);

    TASTUnary.TOp.AddressOf:
    begin
      if AUnary.Operand is TASTIdentifier then
      begin
        var IdentName := TASTIdentifier(AUnary.Operand).Name;
        var Sym := FCurrentScope.Resolve(IdentName);

        if Sym <> nil then
        begin
          if Sym.Kind in [TSymbol.TKind.Procedure, TSymbol.TKind.Function] then
          begin
            var MangledName := Sym.Name;

            if (Sym.Declaration <> nil) and Sym.Declaration.IsRecordMethod and (Length(Sym.Declaration.ParentTypeName) > 0) then
              MangledName := Sym.Declaration.ParentTypeName + '_' + Sym.Declaration.Name;

            FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, TLabelString(MangledName));

            Exit;
          end;

          case Sym.Storage of
            TSymbol.TStorage.Global:
              FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, TLabelString(Sym.GlobalLabel));

            TSymbol.TStorage.Local:
              FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.lea, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Sym.StackOffset));

            TSymbol.TStorage.Parameter:
              FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.lea, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Sym.StackOffset));
          end;
        end;
      end;
    end;

    TASTUnary.TOp.Dereference:
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ld, TRegisters.ID.R0, TRegisters.ID.R0);
  end;
end;

procedure TCodeGenerator.GenBinary(ABinary: TASTBinary);
  function IsBoolExpr(AExpr: TASTExpression): Boolean;
  begin
    if AExpr = nil then
      Exit(False);

    if (AExpr is TASTLiteral) and (TASTLiteral(AExpr).Kind = TASTLiteral.TKind.Boolean) then
      Exit(True);

    if (AExpr is TASTBinary) and (TASTBinary(AExpr).Op in [TASTBinary.TOp.Equal, TASTBinary.TOp.NotEqual,
                                                           TASTBinary.TOp.Less,  TASTBinary.TOp.LessEqual,
                                                           TASTBinary.TOp.Greater, TASTBinary.TOp.GreaterEqual,
                                                           TASTBinary.TOp.In]) then
      Exit(True);

    if (AExpr.ResolvedType <> nil) and AExpr.ResolvedType.IsBoolean then
      Exit(True);

    if AExpr is TASTIdentifier then
    begin
      var Sym := FCurrentScope.Resolve(TASTIdentifier(AExpr).Name);

      if (Sym <> nil) then
      begin
        if (Sym.Kind = TSymbol.TKind.Function) and (Sym.SymbolType <> nil) and (Sym.SymbolType.ReturnType <> nil) then
          Exit(Sym.SymbolType.ReturnType.IsBoolean);

        if Sym.SymbolType <> nil then
          Exit(Sym.SymbolType.IsBoolean);
      end;
    end;

    if AExpr is TASTCallExpr then
    begin
      var Sym := FCurrentScope.Resolve(TASTCallExpr(AExpr).CalleeName);

      if (Sym <> nil) and (Sym.SymbolType <> nil) and (Sym.SymbolType.ReturnType <> nil) then
        Exit(Sym.SymbolType.ReturnType.IsBoolean);
    end;

    Result := False;
  end;
begin
  var IsSetOp := ((ABinary.ResolvedType <> nil) and ABinary.ResolvedType.IsSet) or
                 ((ABinary.Left.ResolvedType <> nil) and ABinary.Left.ResolvedType.IsSet) or
                 ((ABinary.Right.ResolvedType <> nil) and ABinary.Right.ResolvedType.IsSet);

  if IsSetOp then
  begin
    GenExpression(ABinary.Left);
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

    GenExpression(ABinary.Right);
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);
    FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0);

    case ABinary.Op of
      TASTBinary.TOp.Add:      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.&or,  TRegisters.ID.R0, TRegisters.ID.R1);
      TASTBinary.TOp.Multiply: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.&and, TRegisters.ID.R0, TRegisters.ID.R1);
      TASTBinary.TOp.Subtract: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.bclr, TRegisters.ID.R0, TRegisters.ID.R1); // <-- BCLR!
      TASTBinary.TOp.Xor:      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.&xor, TRegisters.ID.R0, TRegisters.ID.R1);

      TASTBinary.TOp.Equal:
      begin
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, TRegisters.ID.R1);
        FIR.AddInstrR1(TCPUInstruction.TOpCode.sete, TRegisters.ID.R0);
      end;

      TASTBinary.TOp.NotEqual:
      begin
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, TRegisters.ID.R1);
        FIR.AddInstrR1(TCPUInstruction.TOpCode.setne, TRegisters.ID.R0);
      end;

      TASTBinary.TOp.LessEqual:
      begin
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.bclr, TRegisters.ID.R0, TRegisters.ID.R1);
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, 0);
        FIR.AddInstrR1(TCPUInstruction.TOpCode.sete, TRegisters.ID.R0);
      end;

      TASTBinary.TOp.GreaterEqual:
      begin
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.bclr, TRegisters.ID.R1, TRegisters.ID.R0);
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R1, 0);
        FIR.AddInstrR1(TCPUInstruction.TOpCode.sete, TRegisters.ID.R0);
      end;
    end;

    Exit;
  end;

  var IsSetWithElem := (ABinary.Left.ResolvedType <> nil) and ABinary.Left.ResolvedType.IsSet and (ABinary.Right.ResolvedType <> nil) and (not ABinary.Right.ResolvedType.IsSet);

  if IsSetWithElem then
  begin
    GenExpression(ABinary.Left);
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

    GenExpression(ABinary.Right);
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, 1);
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.shl, TRegisters.ID.R1, TRegisters.ID.R0);
    FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0);

    if ABinary.Op = TASTBinary.TOp.Subtract then
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.bclr, TRegisters.ID.R0, TRegisters.ID.R1)
    else
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.&or, TRegisters.ID.R0, TRegisters.ID.R1);

    Exit;
  end;

  if ABinary.Op = TASTBinary.TOp.In then
  begin
    GenExpression(ABinary.Left);
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

    GenExpression(ABinary.Right);

    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);
    FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0);

    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R2, 1);
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.shl, TRegisters.ID.R2, TRegisters.ID.R0);

    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.btst, TRegisters.ID.R1, TRegisters.ID.R2);
    FIR.AddInstrR1(TCPUInstruction.TOpCode.setne, TRegisters.ID.R0);

    Exit;
  end;

  if (ABinary.Op = TASTBinary.TOp.And) and (IsBoolExpr(ABinary.Left) or IsBoolExpr(ABinary.Right)) then
  begin
    var FalseLabel := GenUniqueLabel('@and_false');
    var EndLabel   := GenUniqueLabel('@and_end');

    GenExpression(ABinary.Left);
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, 0);
    FIR.AddInstrImm(TCPUInstruction.TOpCode.je, TLabelString(FalseLabel));

    GenExpression(ABinary.Right);
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, 0);
    FIR.AddInstrR1(TCPUInstruction.TOpCode.setne, TRegisters.ID.R0);
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.jmp, TLabelString(EndLabel));

    FIR.AddLabel(TLabelString(FalseLabel));
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, 0);

    FIR.AddLabel(TLabelString(EndLabel));

    Exit;
  end;

  if (ABinary.Op = TASTBinary.TOp.Or) and (IsBoolExpr(ABinary.Left) or IsBoolExpr(ABinary.Right)) then
  begin
    var TrueLabel := GenUniqueLabel('@or_true');
    var EndLabel  := GenUniqueLabel('@or_end');

    GenExpression(ABinary.Left);
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, 0);
    FIR.AddInstrImm(TCPUInstruction.TOpCode.jnz, TLabelString(TrueLabel));

    GenExpression(ABinary.Right);
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, 0);
    FIR.AddInstrR1(TCPUInstruction.TOpCode.setne, TRegisters.ID.R0);
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.jmp, TLabelString(EndLabel));

    FIR.AddLabel(TLabelString(TrueLabel));
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, 1);

    FIR.AddLabel(TLabelString(EndLabel));

    Exit;
  end;

  var IsStringOp := ((ABinary.Left.ResolvedType <> nil) and ABinary.Left.ResolvedType.IsString) or ((ABinary.Right.ResolvedType <> nil) and ABinary.Right.ResolvedType.IsString);

  if IsStringOp and (ABinary.Op = TASTBinary.TOp.Add) then
  begin
    GenExpression(ABinary.Left);
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

    GenExpression(ABinary.Right);
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);
    FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0);

    FIR.AddInstrRImm(TCPUInstruction.TOpCode.syscall, Cardinal(TSysCalls.ID.StringConcat));

    Exit;
  end;

  if IsStringOp and (ABinary.Op in [TASTBinary.TOp.Equal, TASTBinary.TOp.NotEqual, TASTBinary.TOp.Less, TASTBinary.TOp.LessEqual, TASTBinary.TOp.Greater, TASTBinary.TOp.GreaterEqual]) then
  begin
    GenExpression(ABinary.Left);
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

    GenExpression(ABinary.Right);
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);
    FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0);

    FIR.AddInstrRImm(TCPUInstruction.TOpCode.syscall, Cardinal(TSysCalls.ID.StringCompare));
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, 0);

    case ABinary.Op of
      TASTBinary.TOp.Equal:        FIR.AddInstrR1(TCPUInstruction.TOpCode.sete,  TRegisters.ID.R0);
      TASTBinary.TOp.NotEqual:     FIR.AddInstrR1(TCPUInstruction.TOpCode.setne, TRegisters.ID.R0);
      TASTBinary.TOp.Less:         FIR.AddInstrR1(TCPUInstruction.TOpCode.setl,  TRegisters.ID.R0);
      TASTBinary.TOp.LessEqual:    FIR.AddInstrR1(TCPUInstruction.TOpCode.setle, TRegisters.ID.R0);
      TASTBinary.TOp.Greater:      FIR.AddInstrR1(TCPUInstruction.TOpCode.setg,  TRegisters.ID.R0);
      TASTBinary.TOp.GreaterEqual: FIR.AddInstrR1(TCPUInstruction.TOpCode.setge, TRegisters.ID.R0);
    end;
    Exit;
  end;

  GenExpression(ABinary.Left);
  FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

  GenExpression(ABinary.Right);
  FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);
  FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0);

  var IsFloatOp := ((ABinary.Left.ResolvedType <> nil) and ABinary.Left.ResolvedType.IsFloat) or ((ABinary.Right.ResolvedType <> nil) and ABinary.Right.ResolvedType.IsFloat);

  case ABinary.Op of
    TASTBinary.TOp.Add:
      if IsFloatOp then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fadd, TRegisters.ID.R0, TRegisters.ID.R1)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, TRegisters.ID.R1);

    TASTBinary.TOp.Subtract:
      if IsFloatOp then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fsub, TRegisters.ID.R0, TRegisters.ID.R1)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.sub, TRegisters.ID.R0, TRegisters.ID.R1);

    TASTBinary.TOp.Multiply:
      if IsFloatOp then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fmul, TRegisters.ID.R0, TRegisters.ID.R1)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mul, TRegisters.ID.R0, TRegisters.ID.R1);

    TASTBinary.TOp.Divide:    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fdiv, TRegisters.ID.R0, TRegisters.ID.R1);
    TASTBinary.TOp.IntDivide: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.div,  TRegisters.ID.R0, TRegisters.ID.R1);
    TASTBinary.TOp.Modulo:    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mod,  TRegisters.ID.R0, TRegisters.ID.R1);

    TASTBinary.TOp.And: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.and, TRegisters.ID.R0, TRegisters.ID.R1);
    TASTBinary.TOp.Or:  FIR.AddInstrR1R2(TCPUInstruction.TOpCode.or,  TRegisters.ID.R0, TRegisters.ID.R1);
    TASTBinary.TOp.Xor: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.xor, TRegisters.ID.R0, TRegisters.ID.R1);
    TASTBinary.TOp.Shl: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.shl, TRegisters.ID.R0, TRegisters.ID.R1);
    TASTBinary.TOp.Shr: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.shr, TRegisters.ID.R0, TRegisters.ID.R1);

    TASTBinary.TOp.Equal,
    TASTBinary.TOp.NotEqual,
    TASTBinary.TOp.Less,
    TASTBinary.TOp.LessEqual,
    TASTBinary.TOp.Greater,
    TASTBinary.TOp.GreaterEqual:
    begin
      var IsFloatComparison := (ABinary.Left.ResolvedType <> nil) and ABinary.Left.ResolvedType.IsFloat;

      if IsFloatComparison then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fcmp, TRegisters.ID.R0, TRegisters.ID.R1)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, TRegisters.ID.R1);

      case ABinary.Op of
        TASTBinary.TOp.Equal:        FIR.AddInstrR1(TCPUInstruction.TOpCode.sete,  TRegisters.ID.R0);
        TASTBinary.TOp.NotEqual:     FIR.AddInstrR1(TCPUInstruction.TOpCode.setne, TRegisters.ID.R0);
        TASTBinary.TOp.Less:         FIR.AddInstrR1(TCPUInstruction.TOpCode.setl,  TRegisters.ID.R0);
        TASTBinary.TOp.LessEqual:    FIR.AddInstrR1(TCPUInstruction.TOpCode.setle, TRegisters.ID.R0);
        TASTBinary.TOp.Greater:      FIR.AddInstrR1(TCPUInstruction.TOpCode.setg,  TRegisters.ID.R0);
        TASTBinary.TOp.GreaterEqual: FIR.AddInstrR1(TCPUInstruction.TOpCode.setge, TRegisters.ID.R0);
      end;
    end;
  end;
end;

procedure TCodeGenerator.GenCallExpr(ACall: TASTCallExpr);
var
  CalleeLower: String;
  RoutineSym:  TSymbol;
  ArgList:     TList<TASTExpression>;
  MaxRegs:     Integer;
  RegArgs:     Integer;
  StackArgs:   Integer;
begin
  if ACall.BaseExpr = nil then
  begin
    for var i := FWithStack.Count - 1 downto 0 do
    begin
      var Ctx := FWithStack[i];

      if Ctx.RecordType <> nil then
      begin
        var MethodDecl: TASTRoutineDecl;

        if (Ctx.RecordType.Methods <> nil) and Ctx.RecordType.Methods.TryGetValue(LowerCase(ACall.CalleeName), MethodDecl) then
        begin
          var MangledName := Ctx.RecordType.Name + '_' + ACall.CalleeName;

          for var k := ACall.Arguments.Count - 1 downto 0 do
          begin
            GenExpression(ACall.Arguments[k]);
            FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
          end;

          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));
          FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

          var TotalRegs := ACall.Arguments.Count + 1;

          if TotalRegs > 4 then
            TotalRegs := 4;

          if TotalRegs = 1 then
            FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0)
          else
            FIR.AddInstrRn(TCPUInstruction.TOpCode.popr, TotalRegs);

          FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(MangledName));

          Exit;
        end;
      end;
    end;
  end;

  if ACall.BaseExpr <> nil then
  begin
    var BaseType := ACall.BaseExpr.ResolvedType;

    if (BaseType <> nil) and (BaseType.Kind = TASTType.TKind.Pointer) and (BaseType.ElementType <> nil) then
      BaseType := BaseType.ElementType;

    var TypeName := '';

    if BaseType <> nil then
      TypeName := BaseType.TypeName;

    var MangledName := TypeName + '_' + ACall.CalleeName;

    for var i := ACall.Arguments.Count - 1 downto 0 do
    begin
      GenExpression(ACall.Arguments[i]);
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
    end;

    GenAddressOf(ACall.BaseExpr);
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

    var TotalRegs := ACall.Arguments.Count + 1;

    if TotalRegs > 4 then
      TotalRegs := 4;

    if TotalRegs = 1 then
      FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0)
    else if TotalRegs > 1 then
      FIR.AddInstrRn(TCPUInstruction.TOpCode.popr, TotalRegs);

    FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(MangledName));

    Exit;
  end;

  CalleeLower := LowerCase(ACall.CalleeName);

  if CalleeLower = 'halt' then
  begin
    if ACall.Arguments.Count > 0 then
    begin
      GenExpression(ACall.Arguments[0]);

      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TCoreSystemMemory.UserCodeAddress);
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.st, TRegisters.ID.R1, TRegisters.ID.R0);
    end;

    FIR.AddInstr(TCPUInstruction.TOpCode.halt);

    Exit;
  end;

  if CalleeLower = 'yield' then
  begin
    FIR.AddInstr(TCPUInstruction.TOpCode.yield);

    Exit;
  end;

  if (CalleeLower = 'sin')  or (CalleeLower = 'cos')   or (CalleeLower = 'tan')   or
     (CalleeLower = 'atan') or (CalleeLower = 'exp')   or (CalleeLower = 'ln')    or
     (CalleeLower = 'sqrt') or (CalleeLower = 'round') or (CalleeLower = 'trunc') then
  begin
    if ACall.Arguments.Count = 1 then
    begin
      var Arg := ACall.Arguments[0];
      GenExpression(Arg);

      if (Arg.ResolvedType <> nil) and Arg.ResolvedType.IsInteger and (CalleeLower <> 'trunc') and (CalleeLower <> 'round') then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.itof, TRegisters.ID.R0, TRegisters.ID.R0);

      if (CalleeLower = 'trunc') or (CalleeLower = 'round') then
      begin
        if (Arg.ResolvedType <> nil) and Arg.ResolvedType.IsFloat then
        begin
          if CalleeLower = 'trunc' then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ftoi, TRegisters.ID.R0, TRegisters.ID.R0)
          else
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.frnd, TRegisters.ID.R0, TRegisters.ID.R0);
        end;
      end
      else
      begin
             if CalleeLower = 'sin'  then FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fsin,  TRegisters.ID.R0, TRegisters.ID.R0)
        else if CalleeLower = 'cos'  then FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fcos,  TRegisters.ID.R0, TRegisters.ID.R0)
        else if CalleeLower = 'tan'  then FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ftan,  TRegisters.ID.R0, TRegisters.ID.R0)
        else if CalleeLower = 'atan' then FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fatan, TRegisters.ID.R0, TRegisters.ID.R0)
        else if CalleeLower = 'exp'  then FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fexp,  TRegisters.ID.R0, TRegisters.ID.R0)
        else if CalleeLower = 'ln'   then FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fln,   TRegisters.ID.R0, TRegisters.ID.R0)
        else if CalleeLower = 'sqrt' then FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fsqrt, TRegisters.ID.R0, TRegisters.ID.R0);
      end;
    end;

    Exit;
  end;
  if (CalleeLower = 'round') or (CalleeLower = 'trunc') then
  begin

    Exit;
  end;

  if (CalleeLower = 'writeln') or (CalleeLower = 'write') or (CalleeLower = 'format') then
  begin
    if ACall.Arguments.Count > 0 then
    begin
      ArgList := TList<TASTExpression>.Create;

      try
        if (ACall.Arguments.Count > 1) and (ACall.Arguments[1] is TASTArrayLiteral) then
        begin
          var ArrLit := TASTArrayLiteral(ACall.Arguments[1]);

          for var i := 0 to ArrLit.Elements.Count - 1 do
          begin
            if i >= 12 then
              Break;

            ArgList.Add(ArrLit.Elements[i]);
          end;
        end

        else if ACall.Arguments.Count > 1 then
        begin
          for var i := 1 to ACall.Arguments.Count - 1 do
          begin
            if i > 12 then
              Break;

            ArgList.Add(ACall.Arguments[i]);
          end;
        end;

        for var i := ArgList.Count - 1 downto 0 do
        begin
          GenExpression(ArgList[i]);
          FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
        end;

        if (CalleeLower = 'writeln') and (ACall.Arguments[0] is TASTLiteral) then
        begin
          var FmtStr := TASTLiteral(ACall.Arguments[0]).ValueStr + #13#10;
          var StrLbl := GetStringLabel(FmtStr);

          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, TLabelString(StrLbl));
        end
        else
          GenExpression(ACall.Arguments[0]);

        FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

        var TotalRegs := ArgList.Count + 1;

        if TotalRegs = 1 then
          FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0)
        else if TotalRegs > 1 then
          FIR.AddInstrRn(TCPUInstruction.TOpCode.popr, TotalRegs);

        if CalleeLower = 'format' then
          FIR.AddInstrRImm(TCPUInstruction.TOpCode.syscall, Cardinal(TSysCalls.ID.StringFormat))
        else
          FIR.AddInstrRImm(TCPUInstruction.TOpCode.syscall, Cardinal(TSysCalls.ID.DebugPrint));
      finally
        ArgList.Free;
      end;
    end;

    Exit;
  end;

  if CalleeLower = 'length' then
  begin
    if ACall.Arguments.Count > 0 then
    begin
      GenExpression(ACall.Arguments[0]);
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.syscall, Cardinal(TSysCalls.ID.StringLength));
    end;

    Exit;
  end;

  if CalleeLower = 'copy' then
  begin
    if ACall.Arguments.Count = 3 then
    begin
      GenExpression(ACall.Arguments[2]);
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

      GenExpression(ACall.Arguments[1]);
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

      GenExpression(ACall.Arguments[0]);
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

      FIR.AddInstrRn(TCPUInstruction.TOpCode.popr, 3);

      FIR.AddInstrRImm(TCPUInstruction.TOpCode.syscall, Cardinal(TSysCalls.ID.StringCopy));
    end;

    Exit;
  end;

  if (CalleeLower = 'inc') or (CalleeLower = 'dec') then
  begin
    if (ACall.Arguments.Count >= 1) and (ACall.Arguments.Count <= 2) then
    begin
      var TargetExpr := ACall.Arguments[0];
      var ElemScale: Cardinal := 1;

      if (TargetExpr.ResolvedType <> nil) and (TargetExpr.ResolvedType.Kind = TASTType.TKind.Pointer) and (TargetExpr.ResolvedType.ElementType <> nil) then
      begin
        ElemScale := TargetExpr.ResolvedType.ElementType.Size;

        if ElemScale = 0 then
          ElemScale := 1;
      end;

      if ACall.Arguments.Count = 2 then
      begin
        GenExpression(ACall.Arguments[1]);

        if ElemScale > 1 then
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mul, TRegisters.ID.R0, ElemScale);

        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);
      end
      else
      begin
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, ElemScale);
      end;

      GenExpression(TargetExpr);

      if CalleeLower = 'inc' then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, TRegisters.ID.R1)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.sub, TRegisters.ID.R0, TRegisters.ID.R1);

      GenStoreToTarget(TargetExpr);
    end;

    Exit;
  end;

  if (CalleeLower = 'ord') or (CalleeLower = 'chr') then
  begin
    if ACall.Arguments.Count = 1 then
    begin
      GenExpression(ACall.Arguments[0]);

      if CalleeLower = 'chr' then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.&and, TRegisters.ID.R0, $FF);
    end;

    Exit;
  end;

  if (CalleeLower = 'succ') or (CalleeLower = 'pred') then
  begin
    if ACall.Arguments.Count = 1 then
    begin
      GenExpression(ACall.Arguments[0]);

      if CalleeLower = 'succ' then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, 1)
      else
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.sub, TRegisters.ID.R0, 1);
    end;

    Exit;
  end;

  if CalleeLower = 'assigned' then
  begin
    if ACall.Arguments.Count = 1 then
    begin
      GenExpression(ACall.Arguments[0]);
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, 0);
      FIR.AddInstrR1(TCPUInstruction.TOpCode.setne, TRegisters.ID.R0);
    end;

    Exit;
  end;

  RoutineSym := FAnalyzer.GlobalScope.Resolve(ACall.CalleeName);

  MaxRegs := 4;

  if (RoutineSym <> nil) and RoutineSym.IsSysCall then
    MaxRegs := 13;

  ArgList := TList<TASTExpression>.Create;

  try
    for var k := 0 to ACall.Arguments.Count - 1 do
      ArgList.Add(ACall.Arguments[k]);

    var TotalArgs := ArgList.Count;

    if TotalArgs <= MaxRegs then
    begin
      RegArgs   := TotalArgs;
      StackArgs := 0;
    end
    else
    begin
      RegArgs   := MaxRegs;
      StackArgs := TotalArgs - MaxRegs;
    end;

    for var i := TotalArgs - 1 downto RegArgs do
    begin
      GenExpression(ArgList[i]);
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
    end;

    for var i := RegArgs - 1 downto 0 do
    begin
      var IsVarParam := False;

      if (RoutineSym <> nil) and (RoutineSym.Declaration <> nil) and (i < RoutineSym.Declaration.Params.Count) then
        IsVarParam := (RoutineSym.Declaration.Params[i].Modifier in [TASTParamDecl.TModifier.Var, TASTParamDecl.TModifier.Out]);

      if IsVarParam and (ArgList[i] is TASTIdentifier) then
      begin
        var VarSym := FCurrentScope.Resolve(TASTIdentifier(ArgList[i]).Name);

        if (VarSym <> nil) and (VarSym.Storage = TSymbol.TStorage.Global) then
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, TLabelString(VarSym.GlobalLabel))
        else
          GenAddressOf(ArgList[i]);
      end
      else
        GenExpression(ArgList[i]);

      FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
    end;

    if RegArgs = 1 then
      FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0)
    else if RegArgs > 1 then
      FIR.AddInstrRn(TCPUInstruction.TOpCode.popr, RegArgs);

    if (RoutineSym <> nil) and RoutineSym.IsSysCall then
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.syscall, Cardinal(RoutineSym.SysCallID))
    else
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(ACall.CalleeName));

    if StackArgs > 0 then
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add, TRegisters.ID.SP, Cardinal(StackArgs * 4));
  finally
    ArgList.Free;
  end;
end;

procedure TCodeGenerator.GenExpression(AExpr: TASTExpression);
begin
  if AExpr = nil then
    Exit;

       if AExpr is TASTLiteral        then GenLiteral     (TASTLiteral     (AExpr))
  else if AExpr is TASTIdentifier     then GenIdentifier  (TASTIdentifier  (AExpr))
  else if AExpr is TASTBinary         then GenBinary      (TASTBinary      (AExpr))
  else if AExpr is TASTUnary          then GenUnary       (TASTUnary       (AExpr))
  else if AExpr is TASTMemberAccess   then GenMemberAccess(TASTMemberAccess(AExpr))
  else if AExpr is TASTArrayAccess    then GenArrayAccess (TASTArrayAccess (AExpr))
  else if AExpr is TASTCallExpr       then GenCallExpr    (TASTCallExpr    (AExpr))

  else if AExpr is TASTTypeCast then
  begin
    var TypeCast := TASTTypeCast(AExpr);
    GenExpression(TypeCast.Expression);

    var TargetIsFloat := (TypeCast.TargetType <> nil) and TypeCast.TargetType.IsFloat;
    var TargetIsInt   := (TypeCast.TargetType <> nil) and TypeCast.TargetType.IsInteger;
    var SrcIsFloat    := (TypeCast.Expression.ResolvedType <> nil) and TypeCast.Expression.ResolvedType.IsFloat;
    var SrcIsInt      := (TypeCast.Expression.ResolvedType <> nil) and TypeCast.Expression.ResolvedType.IsInteger;

    if TargetIsFloat and SrcIsInt then
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.itof, TRegisters.ID.R0, TRegisters.ID.R0)
    else if TargetIsInt and SrcIsFloat then
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ftoi, TRegisters.ID.R0, TRegisters.ID.R0);
  end

   else if AExpr is TASTArrayLiteral then
  begin
    var ArrLit := TASTArrayLiteral(AExpr);

    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, 0);

    for var i := 0 to ArrLit.Elements.Count - 1 do
    begin
      var Elem := ArrLit.Elements[i];

      if Elem is TASTRange then
      begin
        var RangeNode := TASTRange(Elem);
        var LowVal, HighVal: TConstValue;

        if FAnalyzer.EvaluateConstValue(RangeNode.LowExpr, LowVal) and FAnalyzer.EvaluateConstValue(RangeNode.HighExpr, HighVal) then
        begin
          var RangeMask: Cardinal := 0;

          for var k := LowVal.ValueInt to HighVal.ValueInt do
            if k < 32 then
              RangeMask := RangeMask or (1 shl k);

          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.&or, TRegisters.ID.R0, RangeMask);
        end
        else
        begin
          // Runtime range: generate bitmask loop / shifts
          // (For standard game enums, ranges are constants)
        end;
      end
      else if Elem is TASTLiteral then
      begin
        var BitIdx := TASTLiteral(Elem).ValueInt;

        if BitIdx < 32 then
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.&or, TRegisters.ID.R0, 1 shl BitIdx);
      end
      else
      begin
        FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
        GenExpression(Elem);
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, 1);
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.shl, TRegisters.ID.R1, TRegisters.ID.R0);
        FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0);
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.&or, TRegisters.ID.R0, TRegisters.ID.R1);
      end;
    end;
  end;
end;

procedure TCodeGenerator.GenStoreToTarget(ATarget: TASTExpression);
var
  ElemSize: Cardinal;
begin
  if ATarget = nil then
    Exit;

  if ATarget is TASTMemberAccess then
  begin
    var MemberAcc := TASTMemberAccess(ATarget);

    if (MemberAcc.Expression.ResolvedType <> nil) then
    begin
      var BaseType := MemberAcc.Expression.ResolvedType;

      if (BaseType.Kind = TASTType.TKind.Pointer) and (BaseType.ElementType <> nil) then
        BaseType := BaseType.ElementType;

      var Sym := FAnalyzer.GlobalScope.Resolve(BaseType.TypeName);

      if (Sym <> nil) and (Sym.SymbolType <> nil) and (Sym.SymbolType.Kind = TType.TKind.Record) then
      begin
        var Prop: TType.TProperty;

        if Sym.SymbolType.FindProperty(MemberAcc.MemberName, Prop) then
        begin
          if not Prop.IsDirectWrite and (Length(Prop.WriteSpec) > 0) then
          begin
            FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
            GenAddressOf(MemberAcc.Expression);
            FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R1);

            var MangledName := Sym.SymbolType.Name + '_' + Prop.WriteSpec;

            FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(MangledName));

            Exit;
          end;

          if Prop.IsDirectWrite then
          begin
            FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
            GenAddressOf(MemberAcc.Expression);
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);
            FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0);
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.R1, TRegisters.ID.R0, Prop.WriteOffset);

            Exit;
          end;
        end;
      end;
    end;

    FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
    GenAddressOf(MemberAcc);
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);
    FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0);

    ElemSize := 4;

    if MemberAcc.ResolvedType <> nil then
      ElemSize := MemberAcc.ResolvedType.Size;

    case ElemSize of
      1: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.stb, TRegisters.ID.R1, TRegisters.ID.R0);
      2: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.stw, TRegisters.ID.R1, TRegisters.ID.R0);
    else
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.st,  TRegisters.ID.R1, TRegisters.ID.R0);
    end;

    Exit;
  end;

  if (ATarget is TASTArrayAccess) or ((ATarget is TASTUnary) and (TASTUnary(ATarget).Op = TASTUnary.TOp.Dereference)) then
  begin
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
    GenAddressOf(ATarget);
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);
    FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0);

    ElemSize := 4;

    if ATarget is TASTArrayAccess then
      ElemSize := TASTArrayAccess(ATarget).ElementSize
    else if ATarget.ResolvedType <> nil then
      ElemSize := ATarget.ResolvedType.Size;

    case ElemSize of
      1: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.stb, TRegisters.ID.R1, TRegisters.ID.R0);
      2: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.stw, TRegisters.ID.R1, TRegisters.ID.R0);
    else
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.st,  TRegisters.ID.R1, TRegisters.ID.R0);
    end;

    Exit;
  end;

if ATarget is TASTIdentifier then
  begin
    var TargetName := TASTIdentifier(ATarget).Name;

    for var i := FWithStack.Count - 1 downto 0 do
    begin
      var Ctx := FWithStack[i];

      if Ctx.RecordType <> nil then
      begin
        var Field: TType.TRecordField;

        if Ctx.RecordType.FindField(TargetName, Field) then
        begin
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R1, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.R1, TRegisters.ID.R0, Field.Offset);

          Exit;
        end;

        var Prop: TType.TProperty;

        if Ctx.RecordType.FindProperty(TargetName, Prop) then
        begin
          if not Prop.IsDirectWrite and (Length(Prop.WriteSpec) > 0) then
          begin
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));

            var MangledName := Ctx.RecordType.Name + '_' + Prop.WriteSpec;
            FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(MangledName));

            Exit;
          end;

          if Prop.IsDirectWrite then
          begin
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R1, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.R1, TRegisters.ID.R0, Prop.WriteOffset);

            Exit;
          end;
        end;
      end;
    end;

    var SelfSym := FCurrentScope.Resolve('self');

    if (SelfSym <> nil) and (SelfSym.SymbolType <> nil) and (SelfSym.SymbolType.Kind = TType.TKind.Record) then
    begin
      var Field: TType.TRecordField;

      if SelfSym.SymbolType.FindField(TargetName, Field) then
      begin
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R1, TRegisters.ID.BP, Cardinal(SelfSym.StackOffset));
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.R1, TRegisters.ID.R0, Field.Offset);

        Exit;
      end;
    end;

    var Sym := FCurrentScope.Resolve(TargetName);

    if Sym = nil then
      Exit;

    ElemSize := 4;

    if Sym.SymbolType <> nil then
      ElemSize := Sym.SymbolType.Size;

    case Sym.Storage of
      TSymbol.TStorage.Global:
      begin
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TLabelString(Sym.GlobalLabel));

        case ElemSize of
          1: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.stb, TRegisters.ID.R1, TRegisters.ID.R0);
          2: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.stw, TRegisters.ID.R1, TRegisters.ID.R0);
        else
          FIR.AddInstrR1R2(TCPUInstruction.TOpCode.st,  TRegisters.ID.R1, TRegisters.ID.R0);
        end;
      end;

      TSymbol.TStorage.Local:
      begin
        case ElemSize of
          1: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stob, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(Sym.StackOffset));
          2: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stow, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(Sym.StackOffset));
        else
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto,  TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(Sym.StackOffset));
        end;
      end;

      TSymbol.TStorage.Parameter:
      begin
        if Sym.IsVarParam then
        begin
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R1, TRegisters.ID.BP, Cardinal(Sym.StackOffset));

          case ElemSize of
            1: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.stb, TRegisters.ID.R1, TRegisters.ID.R0);
            2: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.stw, TRegisters.ID.R1, TRegisters.ID.R0);
          else
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.st,  TRegisters.ID.R1, TRegisters.ID.R0);
          end;
        end
        else
        begin
          case ElemSize of
            1: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stob, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(Sym.StackOffset));
            2: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stow, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(Sym.StackOffset));
          else
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto,  TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(Sym.StackOffset));
          end;
        end;
      end;
    end;
  end;
end;

procedure TCodeGenerator.GenAssign(AAssign: TASTAssign);
begin
  if (AAssign = nil) or (AAssign.Target = nil) or (AAssign.Expression = nil) then
    Exit;

  if (AAssign.Target.ResolvedType <> nil) and (AAssign.Target.ResolvedType.Kind in [TASTType.TKind.Record, TASTType.TKind.Array]) then
  begin
    var StructSize: Cardinal;

    var Sym := FAnalyzer.GlobalScope.Resolve(AAssign.Target.ResolvedType.TypeName);

    if (Sym <> nil) and (Sym.SymbolType <> nil) then
      StructSize := Sym.SymbolType.Size
    else
      StructSize := AAssign.Target.ResolvedType.Size;

    if StructSize > 0 then
    begin
      GenAddressOf(AAssign.Target);
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

      GenAddressOf(AAssign.Expression);
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

      FIR.AddInstrRn(TCPUInstruction.TOpCode.popr, 2);

      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R2, StructSize);
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.syscall, Cardinal(TSysCalls.ID.MemoryCopy));
    end;

    Exit;
  end;

  GenExpression(AAssign.Expression);

  if AAssign.Op in [TASTAssign.TOp.PlusAssign, TASTAssign.TOp.MinusAssign] then
  begin
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
    GenExpression(AAssign.Target);
    FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R1);

    var IsFloatMath := (AAssign.Target.ResolvedType <> nil) and AAssign.Target.ResolvedType.IsFloat;

    if AAssign.Op = TASTAssign.TOp.PlusAssign then
    begin
      if IsFloatMath then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fadd, TRegisters.ID.R0, TRegisters.ID.R1)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, TRegisters.ID.R1);
    end
    else
    begin
      if IsFloatMath then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fsub, TRegisters.ID.R0, TRegisters.ID.R1)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.sub, TRegisters.ID.R0, TRegisters.ID.R1);
    end;
  end;

  GenStoreToTarget(AAssign.Target);
end;

procedure TCodeGenerator.GenIf(AIf: TASTIf);
var
  ElseLabel, EndLabel: String;
begin
  ElseLabel := GenUniqueLabel('@else');
  EndLabel  := GenUniqueLabel('@endif');

  GenExpression(AIf.Condition);

  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, 0);

  if Assigned(AIf.ElseStmt) then
    FIR.AddInstrImm(TCPUInstruction.TOpCode.je, TLabelString(ElseLabel))
  else
    FIR.AddInstrImm(TCPUInstruction.TOpCode.je, TLabelString(EndLabel));

  GenStatement(AIf.ThenStmt);

  if Assigned(AIf.ElseStmt) then
  begin
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.jmp, TLabelString(EndLabel));
    FIR.AddLabel(TLabelString(ElseLabel));
    GenStatement(AIf.ElseStmt);
  end;

  FIR.AddLabel(TLabelString(EndLabel));
end;

procedure TCodeGenerator.GenWhile(AWhile: TASTWhile);
var
  Loop: TLoopContext;
begin
  Loop.StartLabel    := GenUniqueLabel('@while');
  Loop.ContinueLabel := Loop.StartLabel;
  Loop.EndLabel      := GenUniqueLabel('@endwhile');

  FIR.AddLabel(TLabelString(Loop.StartLabel));
  GenExpression(AWhile.Condition);
  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, 0);
  FIR.AddInstrImm(TCPUInstruction.TOpCode.je, TLabelString(Loop.EndLabel));

  FLoopStack.Push(Loop);

  try
    GenStatement(AWhile.Body);
  finally
    FLoopStack.Pop;
  end;

  FIR.AddInstrRImm(TCPUInstruction.TOpCode.jmp, TLabelString(Loop.StartLabel));
  FIR.AddLabel(TLabelString(Loop.EndLabel));
end;

procedure TCodeGenerator.GenRepeat(ARepeat: TASTRepeat);
var
  Loop: TLoopContext;
begin
  Loop.StartLabel    := GenUniqueLabel('@repeat');
  Loop.ContinueLabel := GenUniqueLabel('@repeat_cond');
  Loop.EndLabel      := GenUniqueLabel('@endrepeat');

  FIR.AddLabel(TLabelString(Loop.StartLabel));

  FLoopStack.Push(Loop);

  try
    for var Stmt in ARepeat.Statements do
      GenStatement(Stmt);
  finally
    FLoopStack.Pop;
  end;

  FIR.AddLabel(TLabelString(Loop.ContinueLabel));
  GenExpression(ARepeat.Condition);
  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, 0);
  FIR.AddInstrImm(TCPUInstruction.TOpCode.je, TLabelString(Loop.StartLabel));

  FIR.AddLabel(TLabelString(Loop.EndLabel));
end;

procedure TCodeGenerator.GenFor(AFor: TASTFor);
var
  Loop: TLoopContext;
  LoopVarSym: TSymbol;

  procedure LoadLoopVar(AReg: TRegisters.ID);
  begin
    if LoopVarSym.Storage = TSymbol.TStorage.Local then
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, AReg, TRegisters.ID.BP, Cardinal(LoopVarSym.StackOffset))
    else
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.ld, AReg, TLabelString(LoopVarSym.GlobalLabel));
  end;

  procedure StoreLoopVar(AReg: TRegisters.ID);
  begin
    if LoopVarSym.Storage = TSymbol.TStorage.Local then
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.BP, AReg, Cardinal(LoopVarSym.StackOffset))
    else
    begin
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TLabelString(LoopVarSym.GlobalLabel));
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.st, TRegisters.ID.R1, AReg);
    end;
  end;

begin
  Loop.StartLabel    := GenUniqueLabel('@for');
  Loop.ContinueLabel := GenUniqueLabel('@for_step');
  Loop.EndLabel      := GenUniqueLabel('@endfor');
  LoopVarSym         := FCurrentScope.Resolve(AFor.LoopVar);

  if LoopVarSym = nil then
    Exit;

  GenExpression(AFor.StartExpr);
  StoreLoopVar(TRegisters.ID.R0);

  FIR.AddLabel(TLabelString(Loop.StartLabel));

  if AFor.StopExpr is TASTLiteral then
  begin
    LoadLoopVar(TRegisters.ID.R0);
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, TASTLiteral(AFor.StopExpr).ValueInt);
  end
  else
  begin
    GenExpression(AFor.StopExpr);
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);

    LoadLoopVar(TRegisters.ID.R0);
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, TRegisters.ID.R1);
  end;

  if AFor.&Downto then
    FIR.AddInstrImm(TCPUInstruction.TOpCode.jl, TLabelString(Loop.EndLabel))
  else
    FIR.AddInstrImm(TCPUInstruction.TOpCode.jg, TLabelString(Loop.EndLabel));

  FLoopStack.Push(Loop);

  try
    GenStatement(AFor.Body);
  finally
    FLoopStack.Pop;
  end;

  FIR.AddLabel(TLabelString(Loop.ContinueLabel));
  LoadLoopVar(TRegisters.ID.R0);

  if AFor.&Downto then
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.sub, TRegisters.ID.R0, 1)
  else
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, 1);

  StoreLoopVar(TRegisters.ID.R0);

  FIR.AddInstrRImm(TCPUInstruction.TOpCode.jmp, TLabelString(Loop.StartLabel));
  FIR.AddLabel(TLabelString(Loop.EndLabel));
end;

procedure TCodeGenerator.GenCase(ACase: TASTCase);
var
  EndLabel: String;
  BranchLabels: TList<String>;
  NextLabels:   TList<String>;
begin
  EndLabel     := GenUniqueLabel('@endcase');
  BranchLabels := TList<String>.Create;
  NextLabels   := TList<String>.Create;

  try
    for var i := 0 to ACase.Branches.Count - 1 do
    begin
      BranchLabels.Add(GenUniqueLabel('@case_branch'));
      NextLabels.Add(GenUniqueLabel('@case_next'));
    end;

    GenExpression(ACase.Selector);
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

    for var i := 0 to ACase.Branches.Count - 1 do
    begin
      var Branch := ACase.Branches[i];

      for var Val in Branch.Values do
      begin
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.SP, 0);

        if Val.Kind = TASTCaseBranch.TMatchValue.TKind.SingleValue then
        begin
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, Cardinal(Val.LowVal));
          FIR.AddInstrImm(TCPUInstruction.TOpCode.je, TLabelString(BranchLabels[i]));
        end
        else
        begin
          var SkipRangeLabel := GenUniqueLabel('@skip_range');

          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, Cardinal(Val.LowVal));
          FIR.AddInstrImm(TCPUInstruction.TOpCode.jl, TLabelString(SkipRangeLabel));

          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, Cardinal(Val.HighVal));
          FIR.AddInstrImm(TCPUInstruction.TOpCode.jle, TLabelString(BranchLabels[i]));

          FIR.AddLabel(TLabelString(SkipRangeLabel));
        end;
      end;

      FIR.AddInstrRImm(TCPUInstruction.TOpCode.jmp, TLabelString(NextLabels[i]));

      FIR.AddLabel(TLabelString(BranchLabels[i]));
      GenStatement(Branch.Statement);
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.jmp, TLabelString(EndLabel));

      FIR.AddLabel(TLabelString(NextLabels[i]));
    end;

    if Assigned(ACase.ElseStmt) then
      GenStatement(ACase.ElseStmt);

    FIR.AddLabel(TLabelString(EndLabel));
    FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0);
  finally
    BranchLabels.Free;
    NextLabels.Free;
  end;
end;

procedure TCodeGenerator.GenProcCall(ACall: TASTProcCall);
begin
  GenCallExpr(ACall.CallExpr);
end;

procedure TCodeGenerator.GenBreak;
begin
  if FLoopStack.Count > 0 then
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.jmp, TLabelString(FLoopStack.Peek.EndLabel));
end;

procedure TCodeGenerator.GenContinue;
begin
  if FLoopStack.Count > 0 then
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.jmp, TLabelString(FLoopStack.Peek.ContinueLabel));
end;

procedure TCodeGenerator.GenBlock(ABlock: TASTBlock);
begin
  for var Stmt in ABlock.Statements do
    GenStatement(Stmt);
end;

procedure TCodeGenerator.GenWith(AWith: TASTWith);
var
  PushedCount: Integer;
begin
  PushedCount := 0;

  for var Expr in AWith.Expressions do
  begin
    var BaseType := Expr.ResolvedType;

    if (BaseType <> nil) and (BaseType.Kind = TASTType.TKind.Pointer) and (BaseType.ElementType <> nil) then
      BaseType := BaseType.ElementType;

    var Sym := FAnalyzer.GlobalScope.Resolve(BaseType.TypeName);

    GenAddressOf(Expr);

    FCurrentScope.LocalSize := FCurrentSCope.LocalSize + 4;
    var TempOffset := -Integer(FCurrentScope.LocalSize);
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(TempOffset));

    var Ctx: TWithContext;

    if (Sym <> nil) and (Sym.SymbolType <> nil) then
      Ctx.RecordType := Sym.SymbolType
    else
      Ctx.RecordType := nil;

    Ctx.StackOffset := TempOffset;
    FWithStack.Add(Ctx);
    Inc(PushedCount);
  end;

  try
    GenStatement(AWith.Body);
  finally
    for var i := 1 to PushedCount do
      FWithStack.Delete(FWithStack.Count - 1);
  end;
end;

procedure TCodeGenerator.GenStatement(AStmt: TASTStatement);
begin
  if AStmt = nil then
    Exit;

  if not (AStmt is TASTBlock) then
    EmitSourceComment(AStmt);

       if AStmt is TASTBlock    then GenBlock   (TASTBlock   (AStmt))
  else if AStmt is TASTWith     then GenWith    (TASTWith    (AStmt))
  else if AStmt is TASTAssign   then GenAssign  (TASTAssign  (AStmt))
  else if AStmt is TASTIf       then GenIf      (TASTIf      (AStmt))
  else if AStmt is TASTWhile    then GenWhile   (TASTWhile   (AStmt))
  else if AStmt is TASTRepeat   then GenRepeat  (TASTRepeat  (AStmt))
  else if AStmt is TASTFor      then GenFor     (TASTFor     (AStmt))
  else if AStmt is TASTCase     then GenCase    (TASTCase    (AStmt))
  else if AStmt is TASTProcCall then GenProcCall(TASTProcCall(AStmt))
  else if AStmt is TASTBreak    then GenBreak
  else if AStmt is TASTContinue then GenContinue
  else if AStmt is TASTExit     then
  begin
    if (FCurrentScope <> nil) and (FCurrentScope.LocalSize > 0) then
      FIR.AddInstr(TCPUInstruction.TOpCode.leave);

    if (FCurrentRoutine <> nil) and FCurrentRoutine.IsInterrupt then
      FIR.AddInstr(TCPUInstruction.TOpCode.iret)
    else
      FIR.AddInstr(TCPUInstruction.TOpCode.ret);
  end;
end;

procedure TCodeGenerator.GenRoutine(ARoutine: TASTRoutineDecl);
var
  RoutineSym:   TSymbol;
  SavedScope:   TScope;
  SavedRoutine: TASTRoutineDecl;
  FrameSize:    Cardinal;

  function RoutineNeedsZeroInit: Boolean;
  begin
    if ARoutine.IsFunction and (ARoutine.ReturnType <> nil) and ARoutine.ReturnType.IsString then
      Exit(True);

    for var Decl in ARoutine.Declarations do
      if Decl is TASTVarDecl then
      begin
        var VarDecl := TASTVarDecl(Decl);

        if (VarDecl.VarType <> nil) and (VarDecl.VarType.IsString or (VarDecl.VarType.Kind = TASTType.TKind.Record)) then
          Exit(True);
      end;

    Result := False;
  end;

  procedure FinalizeType(ABaseOffset: Integer; AType: TType);
  begin
    if AType = nil then
      Exit;

    if AType.IsString then
    begin
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(ABaseOffset));
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.syscall, Cardinal(TSysCalls.ID.StringDispose));
    end

    else if AType.Kind = TType.TKind.Record then
      for var Field in AType.RecordFields do
      begin
        var FieldOffset := ABaseOffset + Integer(Field.Offset);

        FinalizeType(FieldOffset, Field.&Type);
      end

    else if (AType.Kind = TType.TKind.Array) and (AType.ElementType <> nil) and (AType.ElementType.IsString or (AType.ElementType.Kind = TType.TKind.Record)) then
      for var i := AType.SubrangeLow to AType.SubrangeHigh do
      begin
        var ElemOffset := ABaseOffset + ((i - AType.SubrangeLow) * Integer(AType.ElementType.Size));

        FinalizeType(ElemOffset, AType.ElementType);
      end;
  end;

begin
  if ARoutine.IsSysCall then
    Exit;

  FIR.AddBlankLine;

  var MangledName := ARoutine.Name;

  if ARoutine.IsRecordMethod and (Length(ARoutine.ParentTypeName) > 0) then
    MangledName := ARoutine.ParentTypeName + '_' + ARoutine.Name;

  FIR.AddLabel(TLabelString(MangledName));

  RoutineSym   := FAnalyzer.GlobalScope.Resolve(MangledName);
  SavedScope   := FCurrentScope;
  SavedRoutine := FCurrentRoutine;
  FCurrentRoutine := ARoutine;

  if (RoutineSym <> nil) and (RoutineSym.LocalScope <> nil) then
  begin
    FCurrentScope := RoutineSym.LocalScope;
    FrameSize     := FCurrentScope.LocalSize;

    if FrameSize > 0 then
    begin
      var RegSpillCount := ARoutine.Params.Count;

      if ARoutine.IsRecordMethod and (Length(ARoutine.ParentTypeName) > 0) then
        Inc(RegSpillCount);

      if RegSpillCount > 4 then
        RegSpillCount := 4;

      if RoutineNeedsZeroInit then
        FIR.AddInstrRnImm(TCPUInstruction.TOpCode.zenter, RegSpillCount, FrameSize)
      else
        FIR.AddInstrRnImm(TCPUInstruction.TOpCode.enter, RegSpillCount, FrameSize);
    end;

    GenBlock(ARoutine.Body);

    var ReturnsString := ARoutine.IsFunction and (ARoutine.ReturnType <> nil) and ARoutine.ReturnType.IsString;

    if ARoutine.IsFunction then
    begin
      var ResultSym := FCurrentScope.Resolve('result');

      if ResultSym <> nil then
      begin
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(ResultSym.StackOffset));

        if ReturnsString then
          FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
      end;
    end;

    for var Decl in ARoutine.Declarations do
      if Decl is TASTVarDecl then
      begin
        var VarDecl := TASTVarDecl(Decl);

        for var Name in VarDecl.Names do
        begin
          var LocalSym := FCurrentScope.Resolve(Name);

          if (LocalSym <> nil) and (LocalSym.Storage = TSymbol.TStorage.Local) then
            FinalizeType(LocalSym.StackOffset, LocalSym.SymbolType);
        end;
      end;

    if ReturnsString then
      FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0);

    if FrameSize > 0 then
      FIR.AddInstr(TCPUInstruction.TOpCode.leave);
  end;

  if ARoutine.IsInterrupt then
    FIR.AddInstr(TCPUInstruction.TOpCode.iret)
  else
    FIR.AddInstr(TCPUInstruction.TOpCode.ret);

  FCurrentScope   := SavedScope;
  FCurrentRoutine := SavedRoutine;
end;

procedure TCodeGenerator.GenAddressOf(AExpr: TASTExpression);
begin
  if AExpr = nil then
    Exit;

  if AExpr is TASTIdentifier then
  begin
    var TargetName := TASTIdentifier(AExpr).Name;

    for var i := FWithStack.Count - 1 downto 0 do
    begin
      var Ctx := FWithStack[i];

      if Ctx.RecordType <> nil then
      begin
        var Field: TType.TRecordField;

        if Ctx.RecordType.FindField(TargetName, Field) then
        begin
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));

          if Field.Offset > 0 then
            FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, Field.Offset);

          Exit;
        end;
      end;
    end;

    var SelfSym := FCurrentScope.Resolve('self');

    if (SelfSym <> nil) and (SelfSym.SymbolType <> nil) and (SelfSym.SymbolType.Kind = TType.TKind.Record) then
    begin
      var Field: TType.TRecordField;

      if SelfSym.SymbolType.FindField(TargetName, Field) then
      begin
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(SelfSym.StackOffset));

        if Field.Offset > 0 then
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, Field.Offset);

        Exit;
      end;
    end;

    var Sym := FCurrentScope.Resolve(TargetName);

    if Sym <> nil then
    begin
      case Sym.Storage of
        TSymbol.TStorage.Global:
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, TLabelString(Sym.GlobalLabel));

        TSymbol.TStorage.Local:
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.lea, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Sym.StackOffset));

        TSymbol.TStorage.Parameter:
          if Sym.IsVarParam then
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Sym.StackOffset))
          else
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.lea, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Sym.StackOffset));
      end;
    end;

    Exit;
  end;

  if AExpr is TASTMemberAccess then
  begin
    var MemberAcc := TASTMemberAccess(AExpr);
    GenAddressOf(MemberAcc.Expression);

    if MemberAcc.FieldOffset > 0 then
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, MemberAcc.FieldOffset);

    Exit;
  end;

  if AExpr is TASTArrayAccess then
  begin
    var ArrayAcc := TASTArrayAccess(AExpr);
    var Sym: TSymbol := nil;

    if ArrayAcc.ArrayExpr is TASTIdentifier then
      Sym := FCurrentScope.Resolve(TASTIdentifier(ArrayAcc.ArrayExpr).Name);

    if ArrayAcc.IndexExprs.Count = 1 then
    begin
      var IdxExpr := ArrayAcc.IndexExprs[0];

      if IdxExpr is TASTLiteral then
      begin
        var ConstIdx := Integer(TASTLiteral(IdxExpr).ValueInt);
        var ByteOffset := (ConstIdx - ArrayAcc.LowBound) * Integer(ArrayAcc.ElementSize);

        if (Sym <> nil) and (Sym.Storage = TSymbol.TStorage.Local) then
        begin
          var TotalOfs := Sym.StackOffset + ByteOffset;
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.lea, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(TotalOfs));

          Exit;
        end

        else if (Sym <> nil) and (Sym.Storage = TSymbol.TStorage.Global) then
        begin
          var Idx := FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, TLabelString(Sym.GlobalLabel));

          if ByteOffset <> 0 then
          begin
            var Item := FIR.Items[Idx];

            Item.Imm.Delta := ByteOffset;
            FIR.Items[Idx] := Item;
          end;

          Exit;
        end;
      end;

      GenExpression(IdxExpr);

      if ArrayAcc.LowBound > 0 then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.sub, TRegisters.ID.R0, Cardinal(ArrayAcc.LowBound));

      case ArrayAcc.ElementSize of
        1: ;
        2:  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, TRegisters.ID.R0, 1);
        4:  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, TRegisters.ID.R0, 2);
        8:  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, TRegisters.ID.R0, 3);
        12: FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mul, TRegisters.ID.R0, 12);
        16: FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, TRegisters.ID.R0, 4);
      else
        if ArrayAcc.ElementSize > 1 then
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mul, TRegisters.ID.R0, ArrayAcc.ElementSize);
      end;

      if (Sym <> nil) and (Sym.Storage = TSymbol.TStorage.Global) then
      begin
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.lea, TRegisters.ID.R0, TRegisters.ID.R0, TLabelString(Sym.GlobalLabel));

        Exit;
      end
      else if (Sym <> nil) and (Sym.Storage = TSymbol.TStorage.Local) then
      begin
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, TRegisters.ID.BP);
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, Cardinal(Sym.StackOffset));

        Exit;
      end
      else
      begin
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);
        GenExpression(ArrayAcc.ArrayExpr);
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, TRegisters.ID.R1);

        Exit;
      end;
    end;

    var SymType: TType := nil;

    if Sym <> nil then
      SymType := Sym.SymbolType;

    GenAddressOf(ArrayAcc.ArrayExpr);

    if (SymType <> nil) and (SymType.IsString or (SymType.Kind = TType.TKind.Pointer)) then
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ld, TRegisters.ID.R0, TRegisters.ID.R0);

    for var i := 0 to ArrayAcc.IndexExprs.Count - 1 do
    begin
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
      GenExpression(ArrayAcc.IndexExprs[i]);

      if ArrayAcc.LowBound > 0 then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.sub, TRegisters.ID.R0, ArrayAcc.LowBound);

      if ArrayAcc.ElementSize > 1 then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mul, TRegisters.ID.R0, ArrayAcc.ElementSize);

      FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R1);
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, TRegisters.ID.R1);
    end;

    Exit;
  end;

  if (AExpr is TASTUnary) and (TASTUnary(AExpr).Op = TASTUnary.TOp.Dereference) then
    GenExpression(TASTUnary(AExpr).Operand);
end;

procedure TCodeGenerator.GenDataSections;
  procedure EmitVarDecl(ADecl: TASTDeclaration);
  begin
    if (ADecl is TASTVarDecl) and ADecl.IsUsed then
    begin
      var VarDecl := TASTVarDecl(ADecl);
      var VType   := FAnalyzer.GlobalScope.Resolve(VarDecl.Names[0]).SymbolType;
      var VarSize := (VType.Size + 3) and not Cardinal(3);

      for var Name in VarDecl.Names do
      begin
        FIR.AddBlankLine;
        FIR.AddLabel(TLabelString('_var_' + LowerCase(Name)));
        FIR.AddDataReserved(VarSize);
      end;
    end;
  end;

begin
  FIR.AddBlankLine;

  if FUnits <> nil then
  begin
    for var U in FUnits do
    begin
      for var Decl in U.InterfaceDecls do
        EmitVarDecl(Decl);

      for var Decl in U.ImplementationDecls do
        EmitVarDecl(Decl);
    end;
  end;

  for var Decl in FProgram.Declarations do
    EmitVarDecl(Decl);

  for var Pair in FStringTable do
  begin
    FIR.AddBlankLine;
    FIR.AddLabel(TLabelString(Pair.Value));
    FIR.AddDataString(AnsiString(Pair.Key), True);
  end;
end;

procedure TCodeGenerator.GenProgram;
  procedure EmitTypeMethods(ADecls: TObjectList<TASTDeclaration>);
  begin
    for var Decl in ADecls do
      if Decl is TASTTypeDecl then
        for var MNode in TASTTypeDecl(Decl).DeclType.RecordMethods do
          if (MNode is TASTRoutineDecl) and (TASTRoutineDecl(MNode).Body <> nil) and TASTRoutineDecl(MNode).IsUsed then
            GenRoutine(TASTRoutineDecl(MNode));
  end;

begin
  FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, 'Main');
  FIR.AddInstr(TCPUInstruction.TOpCode.halt);

  if FUnits <> nil then
  begin
    for var U in FUnits do
    begin
      EmitTypeMethods(U.InterfaceDecls);
      EmitTypeMethods(U.ImplementationDecls);

      for var Decl in U.ImplementationDecls do
        if (Decl is TASTRoutineDecl) and Decl.IsUsed then
          GenRoutine(TASTRoutineDecl(Decl));
    end;
  end;

  EmitTypeMethods(FProgram.Declarations);

  for var Decl in FProgram.Declarations do
    if (Decl is TASTRoutineDecl) and Decl.IsUsed then
      GenRoutine(TASTRoutineDecl(Decl));

  FIR.AddBlankLine;
  FIR.AddLabel('Main');

  var SavedScope := FCurrentScope;
  FCurrentScope := FAnalyzer.GlobalScope;

  var MainBodyIR := TIRList.Create;
  var OldIR := FIR;
  FIR := MainBodyIR;

  try
    if FUnits <> nil then
      for var U in FUnits do
        if Assigned(U.InitializationBlock) then
          GenBlock(U.InitializationBlock);

    if Assigned(FProgram.Body) then
      GenBlock(FProgram.Body);
  finally
    FIR := OldIR;
  end;

  var MainFrameSize := FCurrentScope.LocalSize;

  if MainFrameSize > 0 then
    FIR.AddInstrImm(TCPUInstruction.TOpCode.enter, MainFrameSize);

  for var j := 0 to MainBodyIR.Count - 1 do
    FIR.Add(MainBodyIR[j]);

  MainBodyIR.Free;

  if MainFrameSize > 0 then
    FIR.AddInstr(TCPUInstruction.TOpCode.leave);

  FIR.AddInstr(TCPUInstruction.TOpCode.ret);

  FCurrentScope := SavedScope;

  GenDataSections;
end;

function TCodeGenerator.Generate: TIRList;
begin
  FIR.Clear;
  GenProgram;
  Result := FIR;
end;
{$ENDREGION}

end.
