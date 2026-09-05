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

    {$REGION 'InlineVarContext'}
    TInlineVarContext = record
      Name:        String;
      StackOffset: Integer;
    end;
    {$ENDREGION}
  private
    FProgram:          TASTProgram;
    FAnalyzer:         TSemanticAnalyzer;
    FIR:               TIRList;
    FLabelCounter:     Integer;
    FStringTable:      TDictionary<String, String>;
    FStringCounter:    Integer;
    FCurrentScope:     TScope;
    FLoopStack:        TStack<TLoopContext>;
    FWithStack:        TList<TWithContext>;
    FCurrentRoutine:   TASTRoutineDecl;
    FUnits:            TList<TASTUnit>;
    FSourceLines:      TStrings;
    FFileName:         String;
    FLastLine:         Integer;
    FCurrentExitLabel: String;

    procedure EmitSourceComment(ANode: TASTNode; ARoot: Boolean = False);

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
    procedure GenForIn    (AForIn:  TASTForIn);
    procedure GenCase     (ACase:   TASTCase);
    procedure GenProcCall (ACall:   TASTProcCall);
    procedure GenRaise    (ARaise:  TASTRaise);
    procedure GenExit     (AExit:   TASTExit);
    procedure GenBreak;
    procedure GenContinue;


    procedure GenExpression  (AExpr:     TASTExpression;   ADestReg: TRegisters.ID = TRegisters.ID.R0);
    procedure GenIfExpression(AIfExpr:   TASTIfExpression; ADestReg: TRegisters.ID = TRegisters.ID.R0);
    procedure GenBinary      (ABinary:   TASTBinary;       ADestReg: TRegisters.ID = TRegisters.ID.R0);
    procedure GenUnary       (AUnary:    TASTUnary;        ADestReg: TRegisters.ID = TRegisters.ID.R0);
    procedure GenLiteral     (ALiteral:  TASTLiteral;      ADestReg: TRegisters.ID = TRegisters.ID.R0);
    procedure GenIdentifier  (AIdent:    TASTIdentifier;   ADestReg: TRegisters.ID = TRegisters.ID.R0);
    procedure GenMemberAccess(AMember:   TASTMemberAccess; ADestReg: TRegisters.ID = TRegisters.ID.R0);
    procedure GenArrayAccess (AArrayAcc: TASTArrayAccess;  ADestReg: TRegisters.ID = TRegisters.ID.R0);
    procedure GenCallExpr    (ACall:     TASTCallExpr;     ADestReg: TRegisters.ID = TRegisters.ID.R0);

    procedure GenStoreToTarget(ATarget: TASTExpression; ASrcReg: TRegisters.ID = TRegisters.ID.R0);

    procedure GenAddressOf(AExpr: TASTExpression; ADestReg: TRegisters.ID = TRegisters.ID.R0);

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

  FProgram        := AProgram;
  FAnalyzer       := AAnalyzer;
  FUnits          := AUnits;
  FIR             := TIRList.Create;
  FLabelCounter   := 0;
  FStringTable    := TDictionary<String, String>.Create;
  FStringCounter  := 0;
  FCurrentScope   := FAnalyzer.GlobalScope;
  FLoopStack      := TStack<TLoopContext>.Create;
  FWithStack      := TList<TWithContext>.Create;
  FLastLine       := 0;

  FFileName       := ExtractFileName(AFileName);
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

procedure TCodeGenerator.EmitSourceComment(ANode: TASTNode; ARoot: Boolean = False);
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

      var Comment := Format('%s(%d): %s', [FFileName, ANode.Line, Trim(LineText)]);

      if ARoot then
        Comment := #255 + Comment;

      FIR.AddComment(Comment);
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

procedure TCodeGenerator.GenLiteral(ALiteral: TASTLiteral; ADestReg: TRegisters.ID);
begin
  case ALiteral.Kind of
    TASTLiteral.TKind.Integer,
    TASTLiteral.TKind.Set:
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, ALiteral.ValueInt);

    TASTLiteral.TKind.Float:
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, PCardinal(@ALiteral.ValueFloat)^);

    TASTLiteral.TKind.Boolean:
      if ALiteral.ValueBool then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, 1)
      else
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, 0);

    TASTLiteral.TKind.String:
    begin
      var StrLbl := GetStringLabel(ALiteral.ValueStr);
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, TLabelString(StrLbl));
    end;

    TASTLiteral.TKind.Char:
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, Ord(ALiteral.ValueStr[1]));

    TASTLiteral.TKind.Nil:
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, 0);
  end;
end;

procedure TCodeGenerator.GenIdentifier(AIdent: TASTIdentifier; ADestReg: TRegisters.ID);
var
  ElemSize:     Cardinal;
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
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R5, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));

        case Field.&Type.Size of
          1:
          begin
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldob, ADestReg, TRegisters.ID.R5, Field.Offset);

            if Field.&Type.IsSigned then
              FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextb, ADestReg, ADestReg);
          end;

          2:
          begin
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldow, ADestReg, TRegisters.ID.R5, Field.Offset);

            if Field.&Type.IsSigned then
              FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextw, ADestReg, ADestReg);
          end;
        else
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, ADestReg, TRegisters.ID.R5, Field.Offset);
        end;

        Exit;
      end;

      var Prop: TType.TProperty;

      if Ctx.RecordType.FindProperty(AIdent.Name, Prop) then
      begin
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));

        if Prop.IsDirectRead then
        begin
          case Prop.PropType.Size of
            1:
            begin
              FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldob, ADestReg, TRegisters.ID.R0, Prop.ReadOffset);

              if Prop.PropType.IsSigned then
                FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextb, ADestReg, ADestReg);
            end;

            2:
            begin
              FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldow, ADestReg, TRegisters.ID.R0, Prop.ReadOffset);

              if Prop.PropType.IsSigned then
                FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextw, ADestReg, ADestReg);
            end;
          else
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, ADestReg, TRegisters.ID.R0, Prop.ReadOffset);
          end;
        end
        else
        begin
          var MangledName := Ctx.RecordType.Name + '_' + Prop.ReadSpec;
          FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(MangledName));

          if ADestReg <> TRegisters.ID.R0 then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, ADestReg, TRegisters.ID.R0);
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
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R5, TRegisters.ID.BP, Cardinal(SelfSym.StackOffset));

      case Field.&Type.Size of
        1:
        begin
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldob, ADestReg, TRegisters.ID.R5, Field.Offset);

          if Field.&Type.IsSigned then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextb, ADestReg, ADestReg);
        end;

        2:
        begin
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldow, ADestReg, TRegisters.ID.R5, Field.Offset);

          if Field.&Type.IsSigned then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextw, ADestReg, ADestReg);
        end;
      else
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, ADestReg, TRegisters.ID.R5, Field.Offset);
      end;

      Exit;
    end;

    var Prop: TType.TProperty;

    if SelfSym.SymbolType.FindProperty(AIdent.Name, Prop) then
    begin
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(SelfSym.StackOffset));

      if Prop.IsDirectRead then
      begin
        case Prop.PropType.Size of
          1:
          begin
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldob, ADestReg, TRegisters.ID.R0, Prop.ReadOffset);

            if Prop.PropType.IsSigned then
              FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextb, ADestReg, ADestReg);
          end;

          2:
          begin
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldow, ADestReg, TRegisters.ID.R0, Prop.ReadOffset);

            if Prop.PropType.IsSigned then
              FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextw, ADestReg, ADestReg);
          end;
        else
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, ADestReg, TRegisters.ID.R0, Prop.ReadOffset);
        end;
      end
      else
      begin
        var MangledName := SelfSym.SymbolType.Name + '_' + Prop.ReadSpec;
        FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(MangledName));

        if ADestReg <> TRegisters.ID.R0 then
          FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, ADestReg, TRegisters.ID.R0);
      end;

      Exit;
    end;
  end;

  var Sym: TSymbol := TSymbol(AIdent.Symbol);

  if Sym = nil then
    Sym := FCurrentScope.Resolve(AIdent.Name);

  if Sym = nil then
    Exit;

  if Sym.Kind = TSymbol.TKind.Constant then
  begin
    if Sym.IsEmbed then
    begin
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, TLabelString(Sym.GlobalLabel));
      Exit;
    end;

    if Sym.ConstVal.Kind = TConstValue.TKind.Single then
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, PCardinal(@Sym.ConstVal.ValueFloat)^)

    else if Sym.ConstVal.Kind = TConstValue.TKind.String then
    begin
      var StrLbl := GetStringLabel(Sym.ConstVal.ValueStr);
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, TLabelString(StrLbl));
    end
    else
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, Sym.ConstVal.ValueInt);

    Exit;
  end;

  if Sym.Kind = TSymbol.TKind.Function then
  begin
    if Sym.IsSysCall then
      FIR.AddSysCall(Sym.SysCallID)
    else
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(Sym.Name));

    if ADestReg <> TRegisters.ID.R0 then
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, ADestReg, TRegisters.ID.R0);

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
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R5, TLabelString(Sym.GlobalLabel));
          FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.ldb, ADestReg, TRegisters.ID.R5);

          if IsSignedType then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextb, ADestReg, ADestReg);
        end;

        2:
        begin
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R5, TLabelString(Sym.GlobalLabel));
          FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.ldw, ADestReg, TRegisters.ID.R5);

          if IsSignedType then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextw, ADestReg, ADestReg);
        end;
      else
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.ld, ADestReg, TLabelString(Sym.GlobalLabel));
      end;
    end;

    TSymbol.TStorage.Local:
    begin
      case ElemSize of
        1:
        begin
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldob, ADestReg, TRegisters.ID.BP, Cardinal(Sym.StackOffset));

          if IsSignedType then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextb, ADestReg, ADestReg);
        end;

        2:
        begin
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldow, ADestReg, TRegisters.ID.BP, Cardinal(Sym.StackOffset));

          if IsSignedType then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextw, ADestReg, ADestReg);
        end;
      else
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, ADestReg, TRegisters.ID.BP, Cardinal(Sym.StackOffset));
      end;
    end;

    TSymbol.TStorage.Parameter:
    begin
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, ADestReg, TRegisters.ID.BP, Cardinal(Sym.StackOffset));

      if Sym.IsVarParam and (Sym.SymbolType.Kind <> TType.TKind.Record) then
      begin
        case ElemSize of
          1:
          begin
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ldb, ADestReg, ADestReg);

            if IsSignedType then
              FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextb, ADestReg, ADestReg);
          end;

          2:
          begin
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ldw, ADestReg, ADestReg);

            if IsSignedType then
              FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextw, ADestReg, ADestReg);
          end;
        else
          FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ld, ADestReg, ADestReg);
        end;
      end;
    end;
  end;
end;

procedure TCodeGenerator.GenMemberAccess(AMember: TASTMemberAccess; ADestReg: TRegisters.ID);
var
  ElemSize:     Cardinal;
  IsSignedType: Boolean;
begin
  if AMember.Expression is TASTIdentifier then
  begin
    var IdentName := TASTIdentifier(AMember.Expression).Name;
    var Sym := FCurrentScope.Resolve(IdentName);

    if (Sym <> nil) and (Sym.Kind = TSymbol.TKind.Type) and (Sym.SymbolType <> nil) and (Sym.SymbolType.Kind = TType.TKind.Enum) then
      for var Elem in Sym.SymbolType.EnumElements do
        if SameText(Elem.Name, AMember.MemberName) then
        begin
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, Cardinal(Elem.Value));

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
          GenAddressOf(AMember.Expression, ADestReg);

          case Prop.PropType.Size of
            1:
            begin
              FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldob, ADestReg, ADestReg, Prop.ReadOffset);

              if Prop.PropType.IsSigned then
                FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextb, ADestReg, ADestReg);
            end;

            2:
            begin
              FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldow, ADestReg, ADestReg, Prop.ReadOffset);

              if Prop.PropType.IsSigned then
                FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextw, ADestReg, ADestReg);
            end;
          else
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, ADestReg, ADestReg, Prop.ReadOffset);
          end;

          Exit;
        end;

        if Length(Prop.ReadSpec) > 0 then
        begin
          GenAddressOf(AMember.Expression, TRegisters.ID.R0);
          var MangledName := Sym.SymbolType.Name + '_' + Prop.ReadSpec;
          FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(MangledName));

          if ADestReg <> TRegisters.ID.R0 then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, ADestReg, TRegisters.ID.R0);

          Exit;
        end;
      end;
    end;
  end;

  GenAddressOf(AMember.Expression, ADestReg);

  ElemSize     := 4;
  IsSignedType := False;

  if AMember.ResolvedType <> nil then
  begin
    ElemSize     := AMember.ResolvedType.Size;
    IsSignedType := AMember.ResolvedType.IsSigned;
  end;

  case ElemSize of
    1:
    begin
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldob, ADestReg, ADestReg, AMember.FieldOffset);

      if IsSignedType then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextb, ADestReg, ADestReg);
    end;

    2:
    begin
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldow, ADestReg, ADestReg, AMember.FieldOffset);

      if IsSignedType then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.iextw, ADestReg, ADestReg);
    end;
  else
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, ADestReg, ADestReg, AMember.FieldOffset);
  end;
end;

procedure TCodeGenerator.GenArrayAccess(AArrayAcc: TASTArrayAccess; ADestReg: TRegisters.ID);
var
  ElemSize: Cardinal;
begin
  GenAddressOf(AArrayAcc, ADestReg);

  ElemSize := AArrayAcc.ElementSize;

  if ElemSize = 0 then
    ElemSize := 4;

  case ElemSize of
    1: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ldb, ADestReg, ADestReg);
    2: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ldw, ADestReg, ADestReg);
  else
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ld,  ADestReg, ADestReg);
  end;
end;

procedure TCodeGenerator.GenUnary(AUnary: TASTUnary; ADestReg: TRegisters.ID);
begin
  if AUnary = nil then
    Exit;

  if AUnary.Op = TASTUnary.TOp.AddressOf then
  begin
    if AUnary.Operand is TASTIdentifier then
    begin
      var IdentName := TASTIdentifier(AUnary.Operand).Name;
      var Sym := FCurrentScope.Resolve(IdentName);

      if (Sym <> nil) and (Sym.Kind in [TSymbol.TKind.Procedure, TSymbol.TKind.Function]) then
      begin
        var MangledName := Sym.Name;

        if (Sym.Declaration <> nil) and Sym.Declaration.IsRecordMethod and (Length(Sym.Declaration.ParentTypeName) > 0) then
          MangledName := Sym.Declaration.ParentTypeName + '_' + Sym.Declaration.Name;

        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, TLabelString(MangledName));

        Exit;
      end;
    end;

    GenAddressOf(AUnary.Operand, ADestReg);
    Exit;
  end;

  GenExpression(AUnary.Operand, ADestReg);

  case AUnary.Op of
    TASTUnary.TOp.Negate:
      if (AUnary.Operand.ResolvedType <> nil) and AUnary.Operand.ResolvedType.IsFloat then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.&xor, ADestReg, $80000000)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ineg, ADestReg, ADestReg);

    TASTUnary.TOp.Not:
    begin
      var IsBool := (AUnary.Operand.ResolvedType <> nil) and AUnary.Operand.ResolvedType.IsBoolean;

      if IsBool then
      begin
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp,  ADestReg, 0);
        FIR.AddInstrR1   (TCPUInstruction.TOpCode.sete, ADestReg);
      end
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.&not, ADestReg, ADestReg);
    end;

    TASTUnary.TOp.Dereference:
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ld, ADestReg, ADestReg);
  end;
end;

procedure TCodeGenerator.GenBinary(ABinary: TASTBinary; ADestReg: TRegisters.ID);
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

      if Sym <> nil then
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

var
  ScratchReg: TRegisters.ID;
begin
  if ABinary = nil then
    Exit;

  if ADestReg <> TRegisters.ID.R5 then
    ScratchReg := TRegisters.ID.R5
  else
    ScratchReg := TRegisters.ID.R6;

  if ABinary.Op = TASTBinary.TOp.In then
  begin
    GenExpression(ABinary.Left, TRegisters.ID.R5);
    GenExpression(ABinary.Right, TRegisters.ID.R1);

    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov,   ADestReg, 1);
    FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.shl,   ADestReg, TRegisters.ID.R5);
    FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.btst,  TRegisters.ID.R1, ADestReg);
    FIR.AddInstrR1   (TCPUInstruction.TOpCode.setne, ADestReg);
    Exit;
  end;

  var IsSetOp := ((ABinary.ResolvedType <> nil) and ABinary.ResolvedType.IsSet) or
                 ((ABinary.Left.ResolvedType <> nil) and ABinary.Left.ResolvedType.IsSet) or
                 ((ABinary.Right.ResolvedType <> nil) and ABinary.Right.ResolvedType.IsSet);

  if IsSetOp then
  begin
    GenExpression(ABinary.Left, ADestReg);
    GenExpression(ABinary.Right, ScratchReg);

    case ABinary.Op of
      TASTBinary.TOp.Add:      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.&or,  ADestReg, ScratchReg);
      TASTBinary.TOp.Multiply: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.&and, ADestReg, ScratchReg);
      TASTBinary.TOp.Subtract: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.bclr, ADestReg, ScratchReg);
      TASTBinary.TOp.Xor:      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.&xor, ADestReg, ScratchReg);

      TASTBinary.TOp.Equal:
      begin
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.cmp,  ADestReg, ScratchReg);
        FIR.AddInstrR1  (TCPUInstruction.TOpCode.sete, ADestReg);
      end;

      TASTBinary.TOp.NotEqual:
      begin
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.cmp,   ADestReg, ScratchReg);
        FIR.AddInstrR1  (TCPUInstruction.TOpCode.setne, ADestReg);
      end;

      TASTBinary.TOp.LessEqual:
      begin
        FIR.AddInstrR1R2  (TCPUInstruction.TOpCode.bclr, ADestReg, ScratchReg);
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp,   ADestReg, 0);
        FIR.AddInstrR1   (TCPUInstruction.TOpCode.sete,  ADestReg);
      end;

      TASTBinary.TOp.GreaterEqual:
      begin
        FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.bclr, ScratchReg, ADestReg);
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp,  ScratchReg, 0);
        FIR.AddInstrR1   (TCPUInstruction.TOpCode.sete, ADestReg);
      end;
    end;

    Exit;
  end;

  if (ABinary.Op = TASTBinary.TOp.And) and (IsBoolExpr(ABinary.Left) or IsBoolExpr(ABinary.Right)) then
  begin
    var FalseLabel := GenUniqueLabel('@and_false');
    var EndLabel   := GenUniqueLabel('@and_end');

    GenExpression    (ABinary.Left,                  ADestReg);
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp,   ADestReg, 0);
    FIR.AddInstrImm  (TCPUInstruction.TOpCode.je,    TLabelString(FalseLabel));
    GenExpression    (ABinary.Right,                 ADestReg);
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp,   ADestReg, 0);
    FIR.AddInstrR1   (TCPUInstruction.TOpCode.setne, ADestReg);
    FIR.AddInstrRImm (TCPUInstruction.TOpCode.jmp,   TLabelString(EndLabel));
    FIR.AddLabel     (TLabelString(FalseLabel));
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov,   ADestReg, 0);
    FIR.AddLabel    (TLabelString(EndLabel));

    Exit;
  end;

  if (ABinary.Op = TASTBinary.TOp.Or) and (IsBoolExpr(ABinary.Left) or IsBoolExpr(ABinary.Right)) then
  begin
    var TrueLabel := GenUniqueLabel('@or_true');
    var EndLabel  := GenUniqueLabel('@or_end');

    GenExpression    (ABinary.Left,                  ADestReg);
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp,   ADestReg, 0);
    FIR.AddInstrImm  (TCPUInstruction.TOpCode.jnz,   TLabelString(TrueLabel));
    GenExpression    (ABinary.Right,                 ADestReg);
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp,   ADestReg, 0);
    FIR.AddInstrR1   (TCPUInstruction.TOpCode.setne, ADestReg);
    FIR.AddInstrRImm (TCPUInstruction.TOpCode.jmp,   TLabelString(EndLabel));
    FIR.AddLabel     (TLabelString(TrueLabel));
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov,   ADestReg, 1);
    FIR.AddLabel    (TLabelString(EndLabel));

    Exit;
  end;

  var IsStringOp := ((ABinary.Left.ResolvedType <> nil) and ABinary.Left.ResolvedType.IsString) or
                    ((ABinary.Right.ResolvedType <> nil) and ABinary.Right.ResolvedType.IsString);

  if IsStringOp and (ABinary.Op = TASTBinary.TOp.Add) then
  begin
    GenExpression   (ABinary.Left,                 TRegisters.ID.R0);
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
    GenExpression   (ABinary.Right,                TRegisters.ID.R1);
    FIR.AddInstrR1  (TCPUInstruction.TOpCode.pop,  TRegisters.ID.R0);
    FIR.AddSysCall  (TSysCalls.ID.StringConcat);

    if ADestReg <> TRegisters.ID.R0 then
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, ADestReg, TRegisters.ID.R0);

    Exit;
  end;

  if IsStringOp and (ABinary.Op in [TASTBinary.TOp.Equal, TASTBinary.TOp.NotEqual, TASTBinary.TOp.Less, TASTBinary.TOp.LessEqual, TASTBinary.TOp.Greater, TASTBinary.TOp.GreaterEqual]) then
  begin
    GenExpression    (ABinary.Left,                 TRegisters.ID.R0);
    FIR.AddInstrRImm (TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
    GenExpression    (ABinary.Right,                TRegisters.ID.R1);
    FIR.AddInstrR1   (TCPUInstruction.TOpCode.pop,  TRegisters.ID.R0);
    FIR.AddSysCall   (TSysCalls.ID.StringCompare);
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp,  TRegisters.ID.R0, 0);

    case ABinary.Op of
      TASTBinary.TOp.Equal:        FIR.AddInstrR1(TCPUInstruction.TOpCode.sete,  ADestReg);
      TASTBinary.TOp.NotEqual:     FIR.AddInstrR1(TCPUInstruction.TOpCode.setne, ADestReg);
      TASTBinary.TOp.Less:         FIR.AddInstrR1(TCPUInstruction.TOpCode.setl,  ADestReg);
      TASTBinary.TOp.LessEqual:    FIR.AddInstrR1(TCPUInstruction.TOpCode.setle, ADestReg);
      TASTBinary.TOp.Greater:      FIR.AddInstrR1(TCPUInstruction.TOpCode.setg,  ADestReg);
      TASTBinary.TOp.GreaterEqual: FIR.AddInstrR1(TCPUInstruction.TOpCode.setge, ADestReg);
    end;

    Exit;
  end;

  var IsFloatOp := ((ABinary.Left.ResolvedType <> nil) and ABinary.Left.ResolvedType.IsFloat) or
                   ((ABinary.Right.ResolvedType <> nil) and ABinary.Right.ResolvedType.IsFloat);

  if (not IsFloatOp) and (ABinary.Right is TASTLiteral) and (TASTLiteral(ABinary.Right).Kind in [TASTLiteral.TKind.Integer, TASTLiteral.TKind.Set]) then
  begin
    GenExpression(ABinary.Left, ADestReg);
    var LitVal := TASTLiteral(ABinary.Right).ValueInt;

    case ABinary.Op of
      TASTBinary.TOp.Add:       FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add,  ADestReg, LitVal);
      TASTBinary.TOp.Subtract:  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.sub,  ADestReg, LitVal);
      TASTBinary.TOp.Multiply:  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mul,  ADestReg, LitVal);
      TASTBinary.TOp.IntDivide: FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.div,  ADestReg, LitVal);
      TASTBinary.TOp.Modulo:    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mod,  ADestReg, LitVal);
      TASTBinary.TOp.And:       FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.&and, ADestReg, LitVal);
      TASTBinary.TOp.Or:        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.&or,  ADestReg, LitVal);
      TASTBinary.TOp.Xor:       FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.&xor, ADestReg, LitVal);
      TASTBinary.TOp.Shl:       FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl,  ADestReg, LitVal);
      TASTBinary.TOp.Shr:       FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shr,  ADestReg, LitVal);
      TASTBinary.TOp.Sar:       FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.isar, ADestReg, LitVal);

      TASTBinary.TOp.Equal,
      TASTBinary.TOp.NotEqual,
      TASTBinary.TOp.Less,
      TASTBinary.TOp.LessEqual,
      TASTBinary.TOp.Greater,
      TASTBinary.TOp.GreaterEqual:
      begin
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, ADestReg, LitVal);

        case ABinary.Op of
          TASTBinary.TOp.Equal:        FIR.AddInstrR1(TCPUInstruction.TOpCode.sete,  ADestReg);
          TASTBinary.TOp.NotEqual:     FIR.AddInstrR1(TCPUInstruction.TOpCode.setne, ADestReg);
          TASTBinary.TOp.Less:         FIR.AddInstrR1(TCPUInstruction.TOpCode.setl,  ADestReg);
          TASTBinary.TOp.LessEqual:    FIR.AddInstrR1(TCPUInstruction.TOpCode.setle, ADestReg);
          TASTBinary.TOp.Greater:      FIR.AddInstrR1(TCPUInstruction.TOpCode.setg,  ADestReg);
          TASTBinary.TOp.GreaterEqual: FIR.AddInstrR1(TCPUInstruction.TOpCode.setge, ADestReg);
        end;
      end;
    end;

    Exit;
  end;

  if HasCalls(ABinary.Right) then
  begin
    GenExpression(ABinary.Left, ADestReg);
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, ADestReg);
    GenExpression(ABinary.Right, ScratchReg);
    FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, ADestReg);
  end
  else
  begin
    GenExpression(ABinary.Left, ADestReg);
    GenExpression(ABinary.Right, ScratchReg);
  end;

  case ABinary.Op of
    TASTBinary.TOp.Add:
      if IsFloatOp then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fadd, ADestReg, ScratchReg)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.add, ADestReg, ScratchReg);

    TASTBinary.TOp.Subtract:
      if IsFloatOp then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fsub, ADestReg, ScratchReg)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.sub, ADestReg, ScratchReg);

    TASTBinary.TOp.Multiply:
      if IsFloatOp then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fmul, ADestReg, ScratchReg)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mul, ADestReg, ScratchReg);

    TASTBinary.TOp.Divide:    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fdiv, ADestReg, ScratchReg);
    TASTBinary.TOp.IntDivide: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.div,  ADestReg, ScratchReg);
    TASTBinary.TOp.Modulo:    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mod,  ADestReg, ScratchReg);

    TASTBinary.TOp.And: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.and,  ADestReg, ScratchReg);
    TASTBinary.TOp.Or:  FIR.AddInstrR1R2(TCPUInstruction.TOpCode.or,   ADestReg, ScratchReg);
    TASTBinary.TOp.Xor: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.xor,  ADestReg, ScratchReg);
    TASTBinary.TOp.Shl: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.shl,  ADestReg, ScratchReg);
    TASTBinary.TOp.Shr: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.shr,  ADestReg, ScratchReg);
    TASTBinary.TOp.Sar: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.isar, ADestReg, ScratchReg);

    TASTBinary.TOp.Equal,
    TASTBinary.TOp.NotEqual,
    TASTBinary.TOp.Less,
    TASTBinary.TOp.LessEqual,
    TASTBinary.TOp.Greater,
    TASTBinary.TOp.GreaterEqual:
    begin
      var IsFloatComparison := (ABinary.Left.ResolvedType <> nil) and ABinary.Left.ResolvedType.IsFloat;

      if IsFloatComparison then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fcmp, ADestReg, ScratchReg)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.cmp, ADestReg, ScratchReg);

      case ABinary.Op of
        TASTBinary.TOp.Equal:        FIR.AddInstrR1(TCPUInstruction.TOpCode.sete,  ADestReg);
        TASTBinary.TOp.NotEqual:     FIR.AddInstrR1(TCPUInstruction.TOpCode.setne, ADestReg);
        TASTBinary.TOp.Less:         FIR.AddInstrR1(TCPUInstruction.TOpCode.setl,  ADestReg);
        TASTBinary.TOp.LessEqual:    FIR.AddInstrR1(TCPUInstruction.TOpCode.setle, ADestReg);
        TASTBinary.TOp.Greater:      FIR.AddInstrR1(TCPUInstruction.TOpCode.setg,  ADestReg);
        TASTBinary.TOp.GreaterEqual: FIR.AddInstrR1(TCPUInstruction.TOpCode.setge, ADestReg);
      end;
    end;
  end;
end;

procedure TCodeGenerator.GenCallExpr(ACall: TASTCallExpr; ADestReg: TRegisters.ID);
var
  CalleeLower: String;
  RoutineSym:  TSymbol;
  ArgList:     TList<TASTExpression>;
  MaxRegs:     Integer;
  RegArgs:     Integer;
  StackArgs:   Integer;
  AnyCalls:    Boolean;
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
            GenExpression   (ACall.Arguments[k],           TRegisters.ID.R0);
            FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
          end;

          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo,  TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));
          FIR.AddInstrRImm   (TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

          var TotalRegs := ACall.Arguments.Count + 1;

          if TotalRegs > 4 then
            TotalRegs := 4;

          if TotalRegs = 1 then
            FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0)
          else
            FIR.AddInstrRn(TCPUInstruction.TOpCode.popr, TotalRegs);

          FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(MangledName));

          if ADestReg <> TRegisters.ID.R0 then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, ADestReg, TRegisters.ID.R0);

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
      GenExpression   (ACall.Arguments[i],           TRegisters.ID.R0);
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
    end;

    GenAddressOf    (ACall.BaseExpr,               TRegisters.ID.R0);
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

    var TotalRegs := ACall.Arguments.Count + 1;

    if TotalRegs > 4 then
      TotalRegs := 4;

    if TotalRegs = 1 then
      FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0)
    else if TotalRegs > 1 then
      FIR.AddInstrRn(TCPUInstruction.TOpCode.popr, TotalRegs);

    FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(MangledName));

    if ADestReg <> TRegisters.ID.R0 then
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, ADestReg, TRegisters.ID.R0);

    Exit;
  end;

  CalleeLower := LowerCase(ACall.CalleeName);

  if (CalleeLower = '_bsetf') or (CalleeLower = '_bclrf') or (CalleeLower = '_btstf') then
  begin
    if ACall.Arguments.Count = 1 then
    begin
      var Arg := ACall.Arguments[0];

      if (Arg is TASTLiteral) and (TASTLiteral(Arg).Kind in [TASTLiteral.TKind.Integer, TASTLiteral.TKind.Set]) then
      begin
        var LitVal := TASTLiteral(Arg).ValueInt;

        if CalleeLower = '_bsetf' then
          FIR.AddInstrRImm(TCPUInstruction.TOpCode.bsetf, LitVal)
        else if CalleeLower = '_bclrf' then
          FIR.AddInstrRImm(TCPUInstruction.TOpCode.bclrf, LitVal)
        else
        begin
          FIR.AddInstrRImm(TCPUInstruction.TOpCode.btstf, LitVal);
          FIR.AddInstrR1  (TCPUInstruction.TOpCode.setne, ADestReg);
        end;
      end
      else
      begin
        GenExpression(Arg, TRegisters.ID.R5);

        if CalleeLower = '_bsetf' then
          FIR.AddInstrRImm(TCPUInstruction.TOpCode.bsetf, TRegisters.ID.R5)
        else if CalleeLower = '_bclrf' then
          FIR.AddInstrRImm(TCPUInstruction.TOpCode.bclrf, TRegisters.ID.R5)
        else
        begin
          FIR.AddInstrRImm(TCPUInstruction.TOpCode.btstf, TRegisters.ID.R5);
          FIR.AddInstrR1  (TCPUInstruction.TOpCode.setne, ADestReg);
        end;
      end;
    end;

    Exit;
  end;

  if CalleeLower = 'halt' then
  begin
    if ACall.Arguments.Count = 1 then
    begin
      var Arg := ACall.Arguments[0];

      if (Arg is TASTLiteral) and (TASTLiteral(Arg).Kind in [TASTLiteral.TKind.Integer, TASTLiteral.TKind.Set]) then
      begin
        var LitVal := TASTLiteral(Arg).ValueInt;

        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R5, TCoreSystemMemory.UserCodeAddress);
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.st,  TRegisters.ID.R5, LitVal);
      end
      else
      begin
        GenExpression(Arg, TRegisters.ID.R0);

        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R5, TCoreSystemMemory.UserCodeAddress);
        FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.st,  TRegisters.ID.R5, TRegisters.ID.R0);
      end;
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
      GenExpression(Arg, ADestReg);

      if (Arg.ResolvedType <> nil) and Arg.ResolvedType.IsInteger and (CalleeLower <> 'trunc') and (CalleeLower <> 'round') then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.itof, ADestReg, ADestReg);

      if (CalleeLower = 'trunc') or (CalleeLower = 'round') then
      begin
        if (Arg.ResolvedType <> nil) and Arg.ResolvedType.IsFloat then
        begin
          if CalleeLower = 'trunc' then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ftoi, ADestReg, ADestReg)
          else
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.frnd, ADestReg, ADestReg);
        end;
      end
      else
      begin
             if CalleeLower = 'sin'  then FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fsin,  ADestReg, ADestReg)
        else if CalleeLower = 'cos'  then FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fcos,  ADestReg, ADestReg)
        else if CalleeLower = 'tan'  then FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ftan,  ADestReg, ADestReg)
        else if CalleeLower = 'atan' then FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fatan, ADestReg, ADestReg)
        else if CalleeLower = 'exp'  then FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fexp,  ADestReg, ADestReg)
        else if CalleeLower = 'ln'   then FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fln,   ADestReg, ADestReg)
        else if CalleeLower = 'sqrt' then FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fsqrt, ADestReg, ADestReg);
      end;
    end;

    Exit;
  end;

  if (CalleeLower = 'println') or (CalleeLower = 'print') or (CalleeLower = 'format') then
  begin
    if ACall.Arguments.Count = 0 then
    begin
      if CalleeLower = 'println' then
      begin
        var EmptyStrLbl := GetStringLabel('');
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, TLabelString(EmptyStrLbl));
        FIR.AddSysCall   (TSysCalls.ID.DebugPrintLn);
      end;

      Exit;
    end;

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
        GenExpression   (ArgList[i],                   TRegisters.ID.R0);
        FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
      end;

      GenExpression   (ACall.Arguments[0],           TRegisters.ID.R0);
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);

      var TotalRegs := ArgList.Count + 1;

      if TotalRegs = 1 then
        FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0)
      else
        FIR.AddInstrRn(TCPUInstruction.TOpCode.popr, TotalRegs);

      if CalleeLower = 'format' then
        FIR.AddSysCall(TSysCalls.ID.StringFormat)

      else if CalleeLower = 'println' then
        FIR.AddSysCall(TSysCalls.ID.DebugPrintLn)

      else
        FIR.AddSysCall(TSysCalls.ID.DebugPrint);

      if ADestReg <> TRegisters.ID.R0 then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, ADestReg, TRegisters.ID.R0);
    finally
      ArgList.Free;
    end;

    Exit;
  end;

  if CalleeLower = 'setlength' then
  begin
    if ACall.Arguments.Count = 2 then
    begin
      var TargetExpr := ACall.Arguments[0];

      if (TargetExpr.ResolvedType <> nil) and TargetExpr.ResolvedType.IsString then
      begin
        GenExpression   (TargetExpr,         TRegisters.ID.R0);
        GenExpression   (ACall.Arguments[1], TRegisters.ID.R1);
        FIR.AddSysCall  (TSysCalls.ID.StringSetLength);
        GenStoreToTarget(TargetExpr, TRegisters.ID.R0);

        Exit;
      end;

      var ElemSize: Cardinal := 4;

      if TargetExpr is TASTIdentifier then
      begin
        var Sym := FCurrentScope.Resolve(TASTIdentifier(TargetExpr).Name);

        if (Sym <> nil) and (Sym.SymbolType <> nil) and (Sym.SymbolType.ElementType <> nil) then
          ElemSize := Sym.SymbolType.ElementType.Size;
      end

      else if (TargetExpr.ResolvedType <> nil) and (TargetExpr.ResolvedType.ElementType <> nil) then
      begin
        var ElemTypeName := TargetExpr.ResolvedType.ElementType.TypeName;

        if ElemTypeName <> '' then
        begin
          var Sym := FAnalyzer.GlobalScope.Resolve(ElemTypeName);

          if (Sym <> nil) and (Sym.SymbolType <> nil) then
            ElemSize := Sym.SymbolType.Size
          else
            ElemSize := TargetExpr.ResolvedType.ElementType.Size;
        end

        else
          ElemSize := TargetExpr.ResolvedType.ElementType.Size;
      end;

      if ElemSize = 0 then
        ElemSize := 4;

      GenExpression    (TargetExpr,                  TRegisters.ID.R0);
      GenExpression    (ACall.Arguments[1],          TRegisters.ID.R1);
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R2, ElemSize);
      FIR.AddSysCall   (TSysCalls.ID.ArraySetLength);
      GenStoreToTarget (TargetExpr,                  TRegisters.ID.R0);
    end;

    Exit;
  end;

  if (CalleeLower = 'high') or (CalleeLower = 'low') then
  begin
    if ACall.Arguments.Count = 1 then
    begin
      var Arg := ACall.Arguments[0];

      if (Arg.ResolvedType <> nil) and (Arg.ResolvedType.Kind = TASTType.TKind.DynamicArray) then
      begin
        if CalleeLower = 'low' then
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, 0)
        else
        begin
          GenExpression(Arg, ADestReg);

          var NotNullLbl := GenUniqueLabel('@da_high');
          var EndLbl     := GenUniqueLabel('@dn_high_end');

          FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.cmp, ADestReg, 0);
          FIR.AddInstrImm    (TCPUInstruction.TOpCode.jnz, TLabelString(NotNullLbl));
          FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.mov, ADestReg, Cardinal(-1));
          FIR.AddInstrRImm   (TCPUInstruction.TOpCode.jmp, TLabelString(EndLbl));
          FIR.AddLabel       (TLabelString(NotNullLbl));
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, ADestReg, ADestReg, Cardinal(-4));
          FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.sub, ADestReg, 1);
          FIR.AddLabel       (TLabelString(EndLbl));
        end;

        Exit;
      end

      else if (Arg.ResolvedType <> nil) and Arg.ResolvedType.IsString then
      begin
        if CalleeLower = 'low' then
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, 1)
        else
        begin
          GenExpression(Arg, TRegisters.ID.R0);
          FIR.AddSysCall(TSysCalls.ID.StringLength);

          if ADestReg <> TRegisters.ID.R0 then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, ADestReg, TRegisters.ID.R0);
        end;

        Exit;
      end;
    end;
  end;

  if CalleeLower = 'length' then
  begin
    if ACall.Arguments.Count = 1 then
    begin
      var Arg := ACall.Arguments[0];

      if (Arg.ResolvedType <> nil) and (Arg.ResolvedType.Kind = TASTType.TKind.DynamicArray) then
      begin
        GenExpression(Arg, ADestReg);

        var NotNullLbl := GenUniqueLabel('@da_len');
        var EndLbl     := GenUniqueLabel('@da_len_end');

        FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.cmp, ADestReg, 0);
        FIR.AddInstrImm    (TCPUInstruction.TOpCode.jnz, TLabelString(NotNullLbl));
        FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.mov, ADestReg, 0);
        FIR.AddInstrRImm   (TCPUInstruction.TOpCode.jmp, TLabelString(EndLbl));
        FIR.AddLabel       (TLabelString(NotNullLbl));
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, ADestReg, ADestReg, Cardinal(-4));
        FIR.AddLabel       (TLabelString(EndLbl));
      end
      else
      begin
        GenExpression(Arg, TRegisters.ID.R0);
        FIR.AddSysCall(TSysCalls.ID.StringLength);

        if ADestReg <> TRegisters.ID.R0 then
          FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, ADestReg, TRegisters.ID.R0);
      end;
    end;

    Exit;
  end;

  if CalleeLower = 'copy' then
  begin
    if ACall.Arguments.Count = 3 then
    begin
      var Arg0 := ACall.Arguments[0];

      GenExpression(ACall.Arguments[0], TRegisters.ID.R0);
      GenExpression(ACall.Arguments[1], TRegisters.ID.R1);
      GenExpression(ACall.Arguments[2], TRegisters.ID.R2);

      if (Arg0.ResolvedType <> nil) and (Arg0.ResolvedType.Kind = TASTType.TKind.DynamicArray) then
        FIR.AddSysCall(TSysCalls.ID.ArrayCopy)
      else
        FIR.AddSysCall(TSysCalls.ID.StringCopy);

      if ADestReg <> TRegisters.ID.R0 then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, ADestReg, TRegisters.ID.R0);

      Exit;
    end;
  end;

  if (CalleeLower = 'inc') or (CalleeLower = 'dec') then
  begin
    if (ACall.Arguments.Count >= 1) and (ACall.Arguments.Count <= 2) then
    begin
      var TargetExpr := ACall.Arguments[0];
      var ElemScale: Cardinal := 1;

      if (TargetExpr.ResolvedType <> nil) and (TargetExpr.ResolvedType.Kind = TASTType.TKind.Pointer) then
      begin
        var TypeName := TargetExpr.ResolvedType.TypeName;

        if TypeName <> '' then
        begin
          var Sym := FAnalyzer.GlobalScope.Resolve(TypeName);

          if (Sym <> nil) and (Sym.SymbolType <> nil) then
            ElemScale := Sym.SymbolType.Size

          else if TargetExpr.ResolvedType.ElementType <> nil then
            ElemScale := TargetExpr.ResolvedType.ElementType.Size;
        end

        else if TargetExpr.ResolvedType.ElementType <> nil then
          ElemScale := TargetExpr.ResolvedType.ElementType.Size;

        if ElemScale = 0 then
          ElemScale := 1;
      end;

      if ACall.Arguments.Count = 2 then
      begin
        GenExpression(ACall.Arguments[1], TRegisters.ID.R5);

        if ElemScale > 1 then
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mul, TRegisters.ID.R5, ElemScale);
      end
      else
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R5, ElemScale);

      GenExpression(TargetExpr, TRegisters.ID.R0);

      if CalleeLower = 'inc' then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, TRegisters.ID.R5)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.sub, TRegisters.ID.R0, TRegisters.ID.R5);

      GenStoreToTarget(TargetExpr, TRegisters.ID.R0);
    end;

    Exit;
  end;

  if (CalleeLower = 'ord') or (CalleeLower = 'chr') then
  begin
    if ACall.Arguments.Count = 1 then
    begin
      GenExpression(ACall.Arguments[0], ADestReg);

      if CalleeLower = 'chr' then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.&and, ADestReg, $FF);
    end;

    Exit;
  end;

  if (CalleeLower = 'succ') or (CalleeLower = 'pred') then
  begin
    if ACall.Arguments.Count = 1 then
    begin
      GenExpression(ACall.Arguments[0], ADestReg);

      if CalleeLower = 'succ' then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add, ADestReg, 1)
      else
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.sub, ADestReg, 1);
    end;

    Exit;
  end;

  if CalleeLower = 'assigned' then
  begin
    if ACall.Arguments.Count = 1 then
    begin
      GenExpression    (ACall.Arguments[0],            ADestReg);
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp,   ADestReg, 0);
      FIR.AddInstrR1   (TCPUInstruction.TOpCode.setne, ADestReg);
    end;

    Exit;
  end;

  RoutineSym := FAnalyzer.GlobalScope.Resolve(ACall.CalleeName);

  if (RoutineSym <> nil) and (RoutineSym.Kind = TSymbol.TKind.Type) then
  begin
    if ACall.Arguments.Count = 1 then
    begin
      var CastArg := ACall.Arguments[0];
      GenExpression(CastArg, ADestReg);

      var TargetIsFloat := (RoutineSym.SymbolType <> nil) and RoutineSym.SymbolType.IsFloat;
      var SrcIsInt      := (CastArg.ResolvedType  <> nil) and CastArg.ResolvedType.IsInteger;
      var TargetIsInt   := (RoutineSym.SymbolType <> nil) and RoutineSym.SymbolType.IsInteger;
      var SrcIsFloat    := (CastArg.ResolvedType  <> nil) and CastArg.ResolvedType.IsFloat;

      if TargetIsFloat and SrcIsInt then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.itof, ADestReg, ADestReg)
      else if TargetIsInt and SrcIsFloat then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ftoi, ADestReg, ADestReg);

      Exit;
    end;
  end;

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

    AnyCalls := False;
    for var i := 0 to TotalArgs - 1 do
      if HasCalls(ArgList[i]) then
      begin
        AnyCalls := True;
        Break;
      end;

    if AnyCalls then
    begin
      for var i := TotalArgs - 1 downto RegArgs do
      begin
        GenExpression   (ArgList[i],                   TRegisters.ID.R0);
        FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
      end;

      for var i := RegArgs - 1 downto 0 do
      begin
        var IsVarParam := False;

        if (RoutineSym <> nil) and (RoutineSym.Declaration <> nil) and (i < RoutineSym.Declaration.Params.Count) then
          IsVarParam := (RoutineSym.Declaration.Params[i].Modifier in [TASTParamDecl.TModifier.Var, TASTParamDecl.TModifier.Out]);

        if IsVarParam then
          GenAddressOf(ArgList[i], TRegisters.ID.R0)
        else
          GenExpression(ArgList[i], TRegisters.ID.R0);

        FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
      end;

      if RegArgs = 1 then
        FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0)

      else if RegArgs > 1 then
        FIR.AddInstrRn(TCPUInstruction.TOpCode.popr, RegArgs);
    end
    else
    begin
      for var i := TotalArgs - 1 downto RegArgs do
      begin
        GenExpression(ArgList[i], TRegisters.ID.R5);
        FIR.AddInstrRImm(TCPUInstruction.TOpCode.push, TRegisters.ID.R5);
      end;

      for var i := 0 to RegArgs - 1 do
      begin
        var IsVarParam := False;

        if (RoutineSym <> nil) and (RoutineSym.Declaration <> nil) and (i < RoutineSym.Declaration.Params.Count) then
          IsVarParam := (RoutineSym.Declaration.Params[i].Modifier in [TASTParamDecl.TModifier.Var, TASTParamDecl.TModifier.Out]);

        if IsVarParam then
          GenAddressOf(ArgList[i], TRegisters.ID(i))
        else
          GenExpression(ArgList[i], TRegisters.ID(i));
      end;
    end;

    if (RoutineSym <> nil) and RoutineSym.IsSysCall then
      FIR.AddSysCall(RoutineSym.SysCallID)
    else
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(ACall.CalleeName));

    if StackArgs > 0 then
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add, TRegisters.ID.SP, Cardinal(StackArgs * 4));

    if ADestReg <> TRegisters.ID.R0 then
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, ADestReg, TRegisters.ID.R0);
  finally
    ArgList.Free;
  end;
end;

procedure TCodeGenerator.GenExpression(AExpr: TASTExpression; ADestReg: TRegisters.ID);
begin
  if AExpr = nil then
    Exit;

       if AExpr is TASTLiteral        then GenLiteral     (TASTLiteral     (AExpr), ADestReg)
  else if AExpr is TASTIdentifier     then GenIdentifier  (TASTIdentifier  (AExpr), ADestReg)
  else if AExpr is TASTBinary         then GenBinary      (TASTBinary      (AExpr), ADestReg)
  else if AExpr is TASTUnary          then GenUnary       (TASTUnary       (AExpr), ADestReg)
  else if AExpr is TASTMemberAccess   then GenMemberAccess(TASTMemberAccess(AExpr), ADestReg)
  else if AExpr is TASTArrayAccess    then GenArrayAccess (TASTArrayAccess (AExpr), ADestReg)
  else if AExpr is TASTCallExpr       then GenCallExpr    (TASTCallExpr    (AExpr), ADestReg)
  else if AExpr is TASTIfExpression   then GenIfExpression(TASTIfExpression(AExpr), ADestReg)

  else if AExpr is TASTTypeCast then
  begin
    var TypeCast := TASTTypeCast(AExpr);
    GenExpression(TypeCast.Expression, ADestReg);

    var TargetIsFloat := (TypeCast.TargetType              <> nil) and TypeCast.TargetType.IsFloat;
    var TargetIsInt   := (TypeCast.TargetType              <> nil) and TypeCast.TargetType.IsInteger;
    var SrcIsFloat    := (TypeCast.Expression.ResolvedType <> nil) and TypeCast.Expression.ResolvedType.IsFloat;
    var SrcIsInt      := (TypeCast.Expression.ResolvedType <> nil) and TypeCast.Expression.ResolvedType.IsInteger;

    if TargetIsFloat and SrcIsInt then
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.itof, ADestReg, ADestReg)

    else if TargetIsInt and SrcIsFloat then
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ftoi, ADestReg, ADestReg);
  end

  else if AExpr is TASTArrayLiteral then
  begin
    var ArrLit := TASTArrayLiteral(AExpr);

    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, 0);

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

          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.&or, ADestReg, RangeMask);
        end;
      end
      else if Elem is TASTLiteral then
      begin
        var BitIdx := TASTLiteral(Elem).ValueInt;

        if BitIdx < 32 then
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.&or, ADestReg, 1 shl BitIdx);
      end
      else
      begin
        GenExpression    (Elem,                        TRegisters.ID.R5);
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R6, 1);
        FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.shl, TRegisters.ID.R6, TRegisters.ID.R5);
        FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.&or, ADestReg, TRegisters.ID.R6);
      end;
    end;
  end;
end;

procedure TCodeGenerator.GenIfExpression(AIfExpr: TASTIfExpression; ADestReg: TRegisters.ID);
var
  ElseLabel, EndLabel: String;
  TargetIsFloat: Boolean;
begin
  ElseLabel := GenUniqueLabel('@ifexp_else');
  EndLabel  := GenUniqueLabel('@ifexp_end');

  TargetIsFloat := (AIfExpr.ResolvedType <> nil) and AIfExpr.ResolvedType.IsFloat;

  GenExpression    (AIfExpr.Condition,           ADestReg);
  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, ADestReg, 0);
  FIR.AddInstrImm  (TCPUInstruction.TOpCode.je,  TLabelString(ElseLabel));
  GenExpression    (AIfExpr.ThenExpr,            ADestReg);

  if TargetIsFloat and (AIfExpr.ThenExpr.ResolvedType <> nil) and AIfExpr.ThenExpr.ResolvedType.IsInteger then
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.itof, ADestReg, ADestReg);

  FIR.AddInstrRImm(TCPUInstruction.TOpCode.jmp, TLabelString(EndLabel));
  FIR.AddLabel    (TLabelString(ElseLabel));
  GenExpression   (AIfExpr.ElseExpr,            ADestReg);

  if TargetIsFloat and (AIfExpr.ElseExpr.ResolvedType <> nil) and AIfExpr.ElseExpr.ResolvedType.IsInteger then
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.itof, ADestReg, ADestReg);

  FIR.AddLabel(TLabelString(EndLabel));
end;

procedure TCodeGenerator.GenStoreToTarget(ATarget: TASTExpression; ASrcReg: TRegisters.ID);
var
  ElemSize: Cardinal;
begin
  if ATarget = nil then
    Exit;

  if ATarget is TASTMemberAccess then
  begin
    var MemberAcc := TASTMemberAccess(ATarget);

    if (MemberAcc.Expression is TASTIdentifier) and (FWithStack.Count > 0) then
    begin
      var SubRecName := TASTIdentifier(MemberAcc.Expression).Name;

      for var i := FWithStack.Count - 1 downto 0 do
      begin
        var Ctx := FWithStack[i];

        if Ctx.RecordType <> nil then
        begin
          var SubField: TType.TRecordField;

          if Ctx.RecordType.FindField(SubRecName, SubField) then
          begin
            var TotalOffset := SubField.Offset + MemberAcc.FieldOffset;

            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R5, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));

            ElemSize := 4;

            if MemberAcc.ResolvedType <> nil then
              ElemSize := MemberAcc.ResolvedType.Size;

            case ElemSize of
              1: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stob, TRegisters.ID.R5, ASrcReg, TotalOffset);
              2: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stow, TRegisters.ID.R5, ASrcReg, TotalOffset);
            else
              FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto,  TRegisters.ID.R5, ASrcReg, TotalOffset);
            end;

            Exit;
          end;
        end;
      end;
    end;

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
            if ASrcReg <> TRegisters.ID.R1 then
              FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, ASrcReg);

            GenAddressOf(MemberAcc.Expression, TRegisters.ID.R0);

            var MangledName := Sym.SymbolType.Name + '_' + Prop.WriteSpec;
            FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, TLabelString(MangledName));

            Exit;
          end;

          if Prop.IsDirectWrite then
          begin
            GenAddressOf(MemberAcc.Expression, TRegisters.ID.R5);

            case Prop.PropType.Size of
              1: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stob, TRegisters.ID.R5, ASrcReg, Prop.WriteOffset);
              2: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stow, TRegisters.ID.R5, ASrcReg, Prop.WriteOffset);
            else
              FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto,  TRegisters.ID.R5, ASrcReg, Prop.WriteOffset);
            end;

            Exit;
          end;
        end;
      end;
    end;

    GenAddressOf(MemberAcc.Expression, TRegisters.ID.R5);

    ElemSize := 4;

    if MemberAcc.ResolvedType <> nil then
      ElemSize := MemberAcc.ResolvedType.Size;

    case ElemSize of
      1: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stob, TRegisters.ID.R5, ASrcReg, MemberAcc.FieldOffset);
      2: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stow, TRegisters.ID.R5, ASrcReg, MemberAcc.FieldOffset);
    else
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto,  TRegisters.ID.R5, ASrcReg, MemberAcc.FieldOffset);
    end;

    Exit;
  end;

  if (ATarget is TASTArrayAccess) or ((ATarget is TASTUnary) and (TASTUnary(ATarget).Op = TASTUnary.TOp.Dereference)) then
  begin
    if (ATarget is TASTArrayAccess) and (FWithStack.Count > 0) then
    begin
      var ArrAcc := TASTArrayAccess(ATarget);

      if (ArrAcc.ArrayExpr is TASTIdentifier) and (ArrAcc.IndexExprs.Count = 1) and (ArrAcc.IndexExprs[0] is TASTLiteral) then
      begin
        var ArrFieldName := TASTIdentifier(ArrAcc.ArrayExpr).Name;

        for var i := FWithStack.Count - 1 downto 0 do
        begin
          var Ctx := FWithStack[i];

          if Ctx.RecordType <> nil then
          begin
            var Field: TType.TRecordField;

            if Ctx.RecordType.FindField(ArrFieldName, Field) then
            begin
              var ConstIdx    := Integer(TASTLiteral(ArrAcc.IndexExprs[0]).ValueInt);
              var TotalOffset := Field.Offset + Cardinal((ConstIdx - ArrAcc.LowBound) * Integer(ArrAcc.ElementSize));

              FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R5, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));

              case ArrAcc.ElementSize of
                1: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stob, TRegisters.ID.R5, ASrcReg, TotalOffset);
                2: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stow, TRegisters.ID.R5, ASrcReg, TotalOffset);
              else
                FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto,  TRegisters.ID.R5, ASrcReg, TotalOffset);
              end;

              Exit;
            end;
          end;
        end;
      end;
    end;

    GenAddressOf(ATarget, TRegisters.ID.R5);

    ElemSize := 4;

    if ATarget is TASTArrayAccess then
      ElemSize := TASTArrayAccess(ATarget).ElementSize

    else if ATarget.ResolvedType <> nil then
      ElemSize := ATarget.ResolvedType.Size;

    case ElemSize of
      1: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.stb, TRegisters.ID.R5, ASrcReg);
      2: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.stw, TRegisters.ID.R5, ASrcReg);
    else
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.st,  TRegisters.ID.R5, ASrcReg);
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
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R5, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));

          case Field.&Type.Size of
            1: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stob, TRegisters.ID.R5, ASrcReg, Field.Offset);
            2: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stow, TRegisters.ID.R5, ASrcReg, Field.Offset);
          else
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto,  TRegisters.ID.R5, ASrcReg, Field.Offset);
          end;

          Exit;
        end;

        var Prop: TType.TProperty;

        if Ctx.RecordType.FindProperty(TargetName, Prop) then
        begin
          if not Prop.IsDirectWrite and (Length(Prop.WriteSpec) > 0) then
          begin
            if ASrcReg <> TRegisters.ID.R1 then
              FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, ASrcReg);

            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo,  TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));
            var MangledName := Ctx.RecordType.Name + '_' + Prop.WriteSpec;
            FIR.AddInstrRImm   (TCPUInstruction.TOpCode.call, TLabelString(MangledName));

            Exit;
          end;

          if Prop.IsDirectWrite then
          begin
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R5, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));

            case Prop.PropType.Size of
              1: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stob, TRegisters.ID.R5, ASrcReg, Prop.WriteOffset);
              2: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stow, TRegisters.ID.R5, ASrcReg, Prop.WriteOffset);
            else
              FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto,  TRegisters.ID.R5, ASrcReg, Prop.WriteOffset);
            end;

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
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R5, TRegisters.ID.BP, Cardinal(SelfSym.StackOffset));

        case Field.&Type.Size of
          1: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stob, TRegisters.ID.R5, ASrcReg, Field.Offset);
          2: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stow, TRegisters.ID.R5, ASrcReg, Field.Offset);
        else
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto,  TRegisters.ID.R5, ASrcReg, Field.Offset);
        end;

        Exit;
      end;

      var Prop: TType.TProperty;

      if SelfSym.SymbolType.FindProperty(TargetName, Prop) then
      begin
        if not Prop.IsDirectWrite and (Length(Prop.WriteSpec) > 0) then
        begin
          if ASrcReg <> TRegisters.ID.R1 then
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, ASrcReg);

          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo,  TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(SelfSym.StackOffset));
          var MangledName := SelfSym.SymbolType.Name + '_' + Prop.WriteSpec;
          FIR.AddInstrRImm   (TCPUInstruction.TOpCode.call, TLabelString(MangledName));

          Exit;
        end;

        if Prop.IsDirectWrite then
        begin
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R5, TRegisters.ID.BP, Cardinal(SelfSym.StackOffset));

          case Prop.PropType.Size of
            1: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stob, TRegisters.ID.R5, ASrcReg, Prop.WriteOffset);
            2: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stow, TRegisters.ID.R5, ASrcReg, Prop.WriteOffset);
          else
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto,  TRegisters.ID.R5, ASrcReg, Prop.WriteOffset);
          end;

          Exit;
        end;
      end;
    end;

    var Sym: TSymbol := TSymbol(TASTIdentifier(ATarget).Symbol);

    if Sym = nil then
      Sym := FCurrentScope.Resolve(TargetName);

    if Sym = nil then
      Exit;

    ElemSize := 4;

    if Sym.SymbolType <> nil then
      ElemSize := Sym.SymbolType.Size;

    case Sym.Storage of
      TSymbol.TStorage.Global:
      begin
        case ElemSize of
          1:
          begin
            FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R5, TLabelString(Sym.GlobalLabel));
            FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.stb, TRegisters.ID.R5, ASrcReg);
          end;

          2:
          begin
            FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R5, TLabelString(Sym.GlobalLabel));
            FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.stw, TRegisters.ID.R5, ASrcReg);
          end;
        else
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R5, TLabelString(Sym.GlobalLabel));
          FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.st,  TRegisters.ID.R5, ASrcReg);
        end;
      end;

      TSymbol.TStorage.Local:
        case ElemSize of
          1: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stob, TRegisters.ID.BP, ASrcReg, Cardinal(Sym.StackOffset));
          2: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stow, TRegisters.ID.BP, ASrcReg, Cardinal(Sym.StackOffset));
        else
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto,  TRegisters.ID.BP, ASrcReg, Cardinal(Sym.StackOffset));
        end;

      TSymbol.TStorage.Parameter:
        if Sym.IsVarParam then
        begin
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R5, TRegisters.ID.BP, Cardinal(Sym.StackOffset));

          case ElemSize of
            1: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.stb, TRegisters.ID.R5, ASrcReg);
            2: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.stw, TRegisters.ID.R5, ASrcReg);
          else
            FIR.AddInstrR1R2(TCPUInstruction.TOpCode.st,  TRegisters.ID.R5, ASrcReg);
          end;
        end
        else
          case ElemSize of
            1: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stob, TRegisters.ID.BP, ASrcReg, Cardinal(Sym.StackOffset));
            2: FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stow, TRegisters.ID.BP, ASrcReg, Cardinal(Sym.StackOffset));
          else
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto,  TRegisters.ID.BP, ASrcReg, Cardinal(Sym.StackOffset));
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
      GenAddressOf     (AAssign.Target,              TRegisters.ID.R0);
      GenAddressOf     (AAssign.Expression,          TRegisters.ID.R1);
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R2, StructSize);
      FIR.AddSysCall   (TSysCalls.ID.MemoryCopy);
    end;

    Exit;
  end;

  GenExpression(AAssign.Expression, TRegisters.ID.R0);

  if AAssign.Op in [TASTAssign.TOp.PlusAssign, TASTAssign.TOp.MinusAssign] then
  begin
    GenExpression(AAssign.Target, TRegisters.ID.R5);

    var IsFloatMath := (AAssign.Target.ResolvedType <> nil) and AAssign.Target.ResolvedType.IsFloat;

    if AAssign.Op = TASTAssign.TOp.PlusAssign then
    begin
      if IsFloatMath then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fadd, TRegisters.ID.R5, TRegisters.ID.R0)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.add , TRegisters.ID.R5, TRegisters.ID.R0);
    end
    else
    begin
      if IsFloatMath then
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.fsub, TRegisters.ID.R5, TRegisters.ID.R0)
      else
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.sub,  TRegisters.ID.R5, TRegisters.ID.R0);
    end;

    GenStoreToTarget(AAssign.Target, TRegisters.ID.R5);
    Exit;
  end;

  GenStoreToTarget(AAssign.Target, TRegisters.ID.R0);
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
    FIR.AddLabel    (TLabelString(ElseLabel));
    GenStatement    (AIf.ElseStmt);
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

  FIR.AddLabel     (TLabelString(Loop.StartLabel));
  GenExpression    (AWhile.Condition);
  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, 0);
  FIR.AddInstrImm  (TCPUInstruction.TOpCode.je,  TLabelString(Loop.EndLabel));

  FLoopStack.Push(Loop);

  try
    GenStatement(AWhile.Body);
  finally
    FLoopStack.Pop;
  end;

  FIR.AddInstrRImm(TCPUInstruction.TOpCode.jmp, TLabelString(Loop.StartLabel));
  FIR.AddLabel    (TLabelString(Loop.EndLabel));
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

  FIR.AddLabel     (TLabelString(Loop.ContinueLabel));
  GenExpression    (ARepeat.Condition);
  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, 0);
  FIR.AddInstrImm  (TCPUInstruction.TOpCode.je,  TLabelString(Loop.StartLabel));

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
      FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.st,  TRegisters.ID.R1, AReg);
    end;
  end;

begin
  Loop.StartLabel    := GenUniqueLabel('@for');
  Loop.ContinueLabel := GenUniqueLabel('@for_step');
  Loop.EndLabel      := GenUniqueLabel('@endfor');

  LoopVarSym := TSymbol(AFor.Symbol);

  if LoopVarSym = nil then
    LoopVarSym := FCurrentScope.Resolve(AFor.LoopVar);

  if LoopVarSym = nil then
    Exit;

  GenExpression(AFor.StartExpr);
  StoreLoopVar(TRegisters.ID.R0);

  FIR.AddLabel(TLabelString(Loop.StartLabel));

  if AFor.StopExpr is TASTLiteral then
  begin
    LoadLoopVar      (TRegisters.ID.R0);
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, TASTLiteral(AFor.StopExpr).ValueInt);
  end
  else
  begin
    GenExpression   (AFor.StopExpr);
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);

    LoadLoopVar     (TRegisters.ID.R0);
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
  FIR.AddLabel    (TLabelString(Loop.EndLabel));
end;

procedure TCodeGenerator.GenForIn(AForIn: TASTForIn);
var
  Loop:       TLoopContext;
  LoopVarSym: TSymbol;
  CollType:   TType;
  IsSet:      Boolean;
  IsString:   Boolean;
begin
  LoopVarSym := TSymbol(AForIn.Symbol);

  if LoopVarSym = nil then
    LoopVarSym := FCurrentScope.Resolve(AForIn.LoopVar);

  if LoopVarSym = nil then
    Exit;

  CollType := nil;

  if (AForIn.Collection.ResolvedType <> nil) and (AForIn.Collection.ResolvedType.TypeName <> '') then
  begin
    var Sym := FAnalyzer.GlobalScope.Resolve(AForIn.Collection.ResolvedType.TypeName);

    if (Sym <> nil) and (Sym.SymbolType <> nil) then
      CollType := Sym.SymbolType;
  end;

  if (CollType = nil) and (AForIn.Collection is TASTIdentifier) then
  begin
    var Sym := FCurrentScope.Resolve(TASTIdentifier(AForIn.Collection).Name);

    if (Sym <> nil) and (Sym.SymbolType <> nil) then
      CollType := Sym.SymbolType;
  end;

  IsSet    := False;
  IsString := False;

  if AForIn.Collection.ResolvedType <> nil then
  begin
    IsSet    :=  AForIn.Collection.ResolvedType.IsSet;
    IsString :=  AForIn.Collection.ResolvedType.IsString;
  end;

  if CollType <> nil then
  begin
    if CollType.IsSet then
      IsSet := True;

    if CollType.IsString then
      IsString := True;
  end;

  Loop.StartLabel    := GenUniqueLabel('@forin_start');
  Loop.ContinueLabel := GenUniqueLabel('@forin_next');
  Loop.EndLabel      := GenUniqueLabel('@forin_end');

  if IsSet then
  begin
    GenExpression(AForIn.Collection);
    FCurrentScope.LocalSize := FCurrentScope.LocalSize + 4;
    var SetSlot := -Integer(FCurrentScope.LocalSize);
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(SetSlot));
    FCurrentScope.LocalSize := FCurrentScope.LocalSize + 4;
    var CounterSlot := -Integer(FCurrentScope.LocalSize);
    FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, 0);
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(CounterSlot));
    FIR.AddLabel       (TLabelString(Loop.StartLabel));
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo,  TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(CounterSlot));
    FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.cmp,  TRegisters.ID.R0, 32);
    FIR.AddInstrImm    (TCPUInstruction.TOpCode.jge,  TLabelString(Loop.EndLabel));
    FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.mov,  TRegisters.ID.R1, 1);
    FIR.AddInstrR1R2   (TCPUInstruction.TOpCode.shl,  TRegisters.ID.R1, TRegisters.ID.R0);
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo,  TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(SetSlot));
    FIR.AddInstrR1R2   (TCPUInstruction.TOpCode.btst, TRegisters.ID.R0, TRegisters.ID.R1);
    FIR.AddInstrImm    (TCPUInstruction.TOpCode.je,   TLabelString(Loop.ContinueLabel));
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo,  TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(CounterSlot));

    if LoopVarSym.Storage = TSymbol.TStorage.Local then
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stob, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(LoopVarSym.StackOffset))
    else
    begin
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TLabelString(LoopVarSym.GlobalLabel));
      FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.stb, TRegisters.ID.R1, TRegisters.ID.R0);
    end;

    FLoopStack.Push(Loop);
    try
      GenStatement(AForIn.Body);
    finally
      FLoopStack.Pop;
    end;

    FIR.AddLabel       (TLabelString(Loop.ContinueLabel));
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(CounterSlot));
    FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.add, TRegisters.ID.R0, 1);
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(CounterSlot));
    FIR.AddInstrRImm   (TCPUInstruction.TOpCode.jmp, TLabelString(Loop.StartLabel));
    FIR.AddLabel       (TLabelString(Loop.EndLabel));

    Exit;
  end;

  if IsString then
  begin
    GenExpression(AForIn.Collection);
    FCurrentScope.LocalSize := FCurrentScope.LocalSize + 4;
    var StrSlot := -Integer(FCurrentScope.LocalSize);
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(StrSlot));
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(StrSlot));
    FIR.AddSysCall     (TSysCalls.ID.StringLength);
    FCurrentScope.LocalSize := FCurrentScope.LocalSize + 4;
    var LenSlot := -Integer(FCurrentScope.LocalSize);
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(LenSlot));
    FCurrentScope.LocalSize := FCurrentScope.LocalSize + 4;
    var IdxSlot := -Integer(FCurrentScope.LocalSize);
    FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, 1);
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(IdxSlot));
    FIR.AddLabel(TLabelString(Loop.StartLabel));
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(IdxSlot));
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R1, TRegisters.ID.BP, Cardinal(LenSlot));
    FIR.AddInstrR1R2   (TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, TRegisters.ID.R1);
    FIR.AddInstrImm    (TCPUInstruction.TOpCode.jg,  TLabelString(Loop.EndLabel));
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(IdxSlot));
    FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.sub, TRegisters.ID.R0, 1);
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R1, TRegisters.ID.BP, Cardinal(StrSlot));
    FIR.AddInstrR1R2   (TCPUInstruction.TOpCode.add, TRegisters.ID.R0, TRegisters.ID.R1);
    FIR.AddInstrR1R2   (TCPUInstruction.TOpCode.ldb, TRegisters.ID.R0, TRegisters.ID.R0);

    if LoopVarSym.Storage = TSymbol.TStorage.Local then
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.stob, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(LoopVarSym.StackOffset))
    else
    begin
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TLabelString(LoopVarSym.GlobalLabel));
      FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.stb, TRegisters.ID.R1, TRegisters.ID.R0);
    end;

    FLoopStack.Push(Loop);
    try
      GenStatement(AForIn.Body);
    finally
      FLoopStack.Pop;
    end;

    FIR.AddLabel(TLabelString(Loop.ContinueLabel));
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(IdxSlot));
    FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.add, TRegisters.ID.R0, 1);
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(IdxSlot));
    FIR.AddInstrRImm   (TCPUInstruction.TOpCode.jmp, TLabelString(Loop.StartLabel));

    FIR.AddLabel(TLabelString(Loop.EndLabel));

    Exit;
  end;

  var LowBound  := 0;
  var HighBound := 0;
  var ElemSize  := 4;
  var CollSym: TSymbol := nil;

  if AForIn.Collection is TASTIdentifier then
    CollSym := FCurrentScope.Resolve(TASTIdentifier(AForIn.Collection).Name);

  if (CollType <> nil) and (CollType.Kind = TType.TKind.Array) then
  begin
    LowBound  := CollType.SubrangeLow;
    HighBound := CollType.SubrangeHigh;

    if CollType.ElementType <> nil then
      ElemSize := CollType.ElementType.Size;
  end;

  FCurrentScope.LocalSize := FCurrentScope.LocalSize + 4;
  var IdxSlot := -Integer(FCurrentScope.LocalSize);

  FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, Cardinal(LowBound));
  FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(IdxSlot));
  FIR.AddLabel       (TLabelString(Loop.StartLabel));
  FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(IdxSlot));
  FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, Cardinal(HighBound));
  FIR.AddInstrImm    (TCPUInstruction.TOpCode.jg,  TLabelString(Loop.EndLabel));

  FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(IdxSlot));

  if LowBound > 0 then
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.sub, TRegisters.ID.R0, Cardinal(LowBound));

  case ElemSize of
    1:  ;
    2:  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, TRegisters.ID.R0, 1);
    4:  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, TRegisters.ID.R0, 2);
    8:  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, TRegisters.ID.R0, 3);
    12: FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mul, TRegisters.ID.R0, 12);
    16: FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, TRegisters.ID.R0, 4);
  else
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mul, TRegisters.ID.R0, ElemSize);
  end;

  if (CollSym <> nil) and (CollSym.Storage = TSymbol.TStorage.Global) then
    FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.lea, TRegisters.ID.R0, TRegisters.ID.R0, TLabelString(CollSym.GlobalLabel))

  else if (CollSym <> nil) and (CollSym.Storage = TSymbol.TStorage.Local) then
  begin
    FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.add, TRegisters.ID.R0, TRegisters.ID.BP);
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, Cardinal(CollSym.StackOffset));
  end

  else
  begin
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);
    GenAddressOf    (AForIn.Collection);
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.add, TRegisters.ID.R0, TRegisters.ID.R1);
  end;

  if (CollType <> nil) and (CollType.ElementType <> nil) and (CollType.ElementType.Kind = TType.TKind.Record) then
  begin
    FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TRegisters.ID.R0);

    if LoopVarSym.Storage = TSymbol.TStorage.Local then
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.lea, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(LoopVarSym.StackOffset))
    else
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R0, TLabelString(LoopVarSym.GlobalLabel));

    FIR.AddInstrRImm (TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
    FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.mov,  TRegisters.ID.R0, TRegisters.ID.R1);
    FIR.AddInstrRImm (TCPUInstruction.TOpCode.push, TRegisters.ID.R0);
    FIR.AddInstrRn   (TCPUInstruction.TOpCode.popr, 2);
    FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov,  TRegisters.ID.R2, ElemSize);
    FIR.AddSysCall   (TSysCalls.ID.MemoryCopy);
  end
  else
  begin
    case ElemSize of
      1: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ldb, TRegisters.ID.R0, TRegisters.ID.R0);
      2: FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ldw, TRegisters.ID.R0, TRegisters.ID.R0);
    else
      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.ld,  TRegisters.ID.R0, TRegisters.ID.R0);
    end;

    if LoopVarSym.Storage = TSymbol.TStorage.Local then
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(LoopVarSym.StackOffset))
    else
    begin
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, TRegisters.ID.R1, TLabelString(LoopVarSym.GlobalLabel));
      FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.st,  TRegisters.ID.R1, TRegisters.ID.R0);
    end;
  end;

  FLoopStack.Push(Loop);
  try
    GenStatement(AForIn.Body);
  finally
    FLoopStack.Pop;
  end;

  FIR.AddLabel       (TLabelString(Loop.ContinueLabel));
  FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(IdxSlot));
  FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.add, TRegisters.ID.R0, 1);
  FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(IdxSlot));
  FIR.AddInstrRImm   (TCPUInstruction.TOpCode.jmp, TLabelString(Loop.StartLabel));
  FIR.AddLabel       (TLabelString(Loop.EndLabel));
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

    GenExpression   (ACase.Selector);
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
          FIR.AddInstrImm  (TCPUInstruction.TOpCode.je,  TLabelString(BranchLabels[i]));
        end
        else
        begin
          var SkipRangeLabel := GenUniqueLabel('@skip_range');

          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, Cardinal(Val.LowVal));
          FIR.AddInstrImm  (TCPUInstruction.TOpCode.jl,  TLabelString(SkipRangeLabel));

          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.cmp, TRegisters.ID.R0, Cardinal(Val.HighVal));
          FIR.AddInstrImm  (TCPUInstruction.TOpCode.jle, TLabelString(BranchLabels[i]));

          FIR.AddLabel(TLabelString(SkipRangeLabel));
        end;
      end;

      FIR.AddInstrRImm(TCPUInstruction.TOpCode.jmp, TLabelString(NextLabels[i]));
      FIR.AddLabel    (TLabelString(BranchLabels[i]));
      GenStatement    (Branch.Statement);
      FIR.AddInstrRImm(TCPUInstruction.TOpCode.jmp, TLabelString(EndLabel));
      FIR.AddLabel    (TLabelString(NextLabels[i]));
    end;

    if Assigned(ACase.ElseStmt) then
      GenStatement(ACase.ElseStmt);

    FIR.AddLabel  (TLabelString(EndLabel));
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

procedure TCodeGenerator.GenRaise(ARaise: TASTRaise);
begin
  if ARaise.Expression = nil then
  begin
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.raise, 0);
    Exit;
  end;

  if (ARaise.Expression is TASTLiteral) and (TASTLiteral(ARaise.Expression).Kind in [TASTLiteral.TKind.Integer, TASTLiteral.TKind.Set]) then
  begin
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.raise, TASTLiteral(ARaise.Expression).ValueInt);
    Exit;
  end;

  if (ARaise.Expression.ResolvedType <> nil) and (ARaise.Expression.ResolvedType.Kind = TASTType.TKind.Record) then
  begin
    GenAddressOf(ARaise.Expression);
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.raise, TRegisters.ID.R0);
    Exit;
  end;

  GenExpression   (ARaise.Expression);
  FIR.AddInstrRImm(TCPUInstruction.TOpCode.raise, TRegisters.ID.R0);
end;

procedure TCodeGenerator.GenExit(AExit: TASTExit);
begin
  if AExit.Expression <> nil then
  begin
    GenExpression(AExit.Expression);

    var ResultSym := FCurrentScope.Resolve('result');

    if ResultSym <> nil then
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.sto, TRegisters.ID.BP, TRegisters.ID.R0, Cardinal(ResultSym.StackOffset));
  end;

  if FCurrentExitLabel <> '' then
    FIR.AddInstrRImm(TCPUInstruction.TOpCode.jmp, TLabelString(FCurrentExitLabel))
  else
    FIR.AddInstr(TCPUInstruction.TOpCode.ret);
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

    var Sym: TSymbol := nil;
    if (BaseType <> nil) and (BaseType.TypeName <> '') then
      Sym := FAnalyzer.GlobalScope.Resolve(BaseType.TypeName);

    GenAddressOf(Expr, TRegisters.ID.R0);

    FCurrentScope.LocalSize := FCurrentScope.LocalSize + 4;
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
  else if AStmt is TASTForIn    then GenForIn   (TASTForIn   (AStmt))
  else if AStmt is TASTCase     then GenCase    (TASTCase    (AStmt))
  else if AStmt is TASTProcCall then GenProcCall(TASTProcCall(AStmt))
  else if AStmt is TASTRaise    then GenRaise   (TASTRaise   (AStmt))
  else if AStmt is TASTExit     then GenExit    (TASTExit    (AStmt))
  else if AStmt is TASTBreak    then GenBreak
  else if AStmt is TASTContinue then GenContinue;
end;

procedure TCodeGenerator.GenRoutine(ARoutine: TASTRoutineDecl);
var
  RoutineSym:     TSymbol;
  SavedScope:     TScope;
  SavedRoutine:   TASTRoutineDecl;
  SavedExitLabel: String;
  FrameSize:      Cardinal;

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
      FIR.AddSysCall    (TSysCalls.ID.StringDispose);
    end

    else if AType.Kind = TType.TKind.Record then
    begin
      for var Field in AType.RecordFields do
      begin
        var FieldOffset := ABaseOffset + Integer(Field.Offset);
        FinalizeType(FieldOffset, Field.&Type);
      end;
    end

    else if AType.Kind = TType.TKind.DynamicArray then
    begin
      FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, TRegisters.ID.R0, TRegisters.ID.BP, Cardinal(ABaseOffset));
      FIR.AddSysCall     (TSysCalls.ID.ArrayDispose);
    end

    else if (AType.Kind = TType.TKind.Array) and (AType.ElementType <> nil) and (AType.ElementType.IsString or (AType.ElementType.Kind = TType.TKind.Record)) then
    begin
      var ElemCount := (AType.SubrangeHigh - AType.SubrangeLow) + 1;

      if ElemCount <= 0 then
        Exit;

      if ElemCount <= 2 then
      begin
        for var i := AType.SubrangeLow to AType.SubrangeHigh do
        begin
          var ElemOffset := ABaseOffset + ((i - AType.SubrangeLow) * Integer(AType.ElementType.Size));

          FinalizeType(ElemOffset, AType.ElementType);
        end;
      end
      else
      begin
        var LoopLbl := GenUniqueLabel('@finalize_arr');
        var ElemSize := AType.ElementType.Size;


        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.lea,  TRegisters.ID.R1, TRegisters.ID.BP, Cardinal(ABaseOffset));
        FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.mov,  TRegisters.ID.R2, Cardinal(ElemCount));
        FIR.AddLabel       (TLabelString(LoopLbl));
        FIR.AddInstrR1R2   (TCPUInstruction.TOpCode.ld,   TRegisters.ID.R0, TRegisters.ID.R1);
        FIR.AddSysCall     (TSysCalls.ID.StringDispose);
        FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.add,  TRegisters.ID.R1, ElemSize);
        FIR.AddInstrR1Imm  (TCPUInstruction.TOpCode.loop, TRegisters.ID.R2, TLabelString(LoopLbl));
      end;
    end;
  end;
begin
  if ARoutine.IsSysCall then
    Exit;

  FIR.AddBlankLine;

  var MangledName := ARoutine.Name;

  if ARoutine.IsRecordMethod and (Length(ARoutine.ParentTypeName) > 0) then
    MangledName := ARoutine.ParentTypeName + '_' + ARoutine.Name;

  EmitSourceComment(ARoutine, True);
  FIR.AddLabel(TLabelString(MangledName));

  RoutineSym      := FAnalyzer.GlobalScope.Resolve(MangledName);
  SavedScope      := FCurrentScope;
  SavedRoutine    := FCurrentRoutine;
  SavedExitLabel  := FCurrentExitLabel;

  FCurrentRoutine   := ARoutine;
  FCurrentExitLabel := GenUniqueLabel('@exit_' + MangledName);

  if (RoutineSym <> nil) and (RoutineSym.LocalScope <> nil) then
  begin
    FCurrentScope := RoutineSym.LocalScope;

    var BodyIR := TIRList.Create;
    var OldIR  := FIR;

    FIR := BodyIR;

    try
      GenBlock(ARoutine.Body);

      FIR.AddLabel(TLabelString(FCurrentExitLabel));

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

      FIR.AddBlankLine;
      FIR.AddComment('end (' + MangledName + ')');

      for var Decl in ARoutine.Declarations do
      begin
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
      end;

      if ReturnsString then
        FIR.AddInstrR1(TCPUInstruction.TOpCode.pop, TRegisters.ID.R0);

    finally
      FIR := OldIR;
    end;

    FrameSize := FCurrentScope.LocalSize;

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

    for var j := 0 to BodyIR.Count - 1 do
      FIR.Add(BodyIR[j]);

    BodyIR.Free;

    if FrameSize > 0 then
      FIR.AddInstr(TCPUInstruction.TOpCode.leave);
  end;

  if ARoutine.IsInterrupt then
    FIR.AddInstr(TCPUInstruction.TOpCode.iret)
  else
    FIR.AddInstr(TCPUInstruction.TOpCode.ret);

  FCurrentExitLabel := SavedExitLabel;
  FCurrentScope     := SavedScope;
  FCurrentRoutine   := SavedRoutine;
end;

procedure TCodeGenerator.GenAddressOf(AExpr: TASTExpression; ADestReg: TRegisters.ID);
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
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, ADestReg, TRegisters.ID.BP, Cardinal(Ctx.StackOffset));

          if Field.Offset > 0 then
            FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add, ADestReg, Field.Offset);

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
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, ADestReg, TRegisters.ID.BP, Cardinal(SelfSym.StackOffset));

        if Field.Offset > 0 then
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add, ADestReg, Field.Offset);

        Exit;
      end;
    end;

    var Sym: TSymbol := TSymbol(TASTIdentifier(AExpr).Symbol);

    if Sym = nil then
      Sym := FCurrentScope.Resolve(TargetName);

    if Sym <> nil then
    begin
      if (Sym.Kind = TSymbol.TKind.Constant) and Sym.IsEmbed then
      begin
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, TLabelString(Sym.GlobalLabel));
        Exit;
      end;

      case Sym.Storage of
        TSymbol.TStorage.Global:
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, TLabelString(Sym.GlobalLabel));

        TSymbol.TStorage.Local:
          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.lea, ADestReg, TRegisters.ID.BP, Cardinal(Sym.StackOffset));

        TSymbol.TStorage.Parameter:
          if Sym.IsVarParam then
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.ldo, ADestReg, TRegisters.ID.BP, Cardinal(Sym.StackOffset))
          else
            FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.lea, ADestReg, TRegisters.ID.BP, Cardinal(Sym.StackOffset));
      end;
    end;

    Exit;
  end;

  if AExpr is TASTMemberAccess then
  begin
    var MemberAcc := TASTMemberAccess(AExpr);

    GenAddressOf(MemberAcc.Expression, ADestReg);

    if MemberAcc.FieldOffset > 0 then
      FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add, ADestReg, MemberAcc.FieldOffset);

    Exit;
  end;

  if AExpr is TASTArrayAccess then
  begin
    var ArrayAcc := TASTArrayAccess(AExpr);
    var Sym: TSymbol := nil;

    if ArrayAcc.ArrayExpr is TASTIdentifier then
    begin
      Sym := TSymbol(TASTIdentifier(ArrayAcc.ArrayExpr).Symbol);
      if Sym = nil then
        Sym := FCurrentScope.Resolve(TASTIdentifier(ArrayAcc.ArrayExpr).Name);
    end;

    var IsHeapRef := (ArrayAcc.ArrayExpr.ResolvedType <> nil) and (ArrayAcc.ArrayExpr.ResolvedType.IsString or (ArrayAcc.ArrayExpr.ResolvedType.Kind in [TASTType.TKind.Pointer, TASTType.TKind.DynamicArray]));

    if (not IsHeapRef) and (Sym <> nil) and (Sym.SymbolType <> nil) and (Sym.SymbolType.IsString or (Sym.SymbolType.Kind in [TType.TKind.Pointer, TType.TKind.DynamicArray])) then
      IsHeapRef := True;

    if IsHeapRef then
    begin
      var IdxReg: TRegisters.ID;
      if ADestReg <> TRegisters.ID.R6 then
        IdxReg := TRegisters.ID.R6
      else
        IdxReg := TRegisters.ID.R7;

      GenExpression(ArrayAcc.IndexExprs[0], IdxReg);

      if ArrayAcc.LowBound > 0 then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.sub, IdxReg, Cardinal(ArrayAcc.LowBound));

      case ArrayAcc.ElementSize of
        1: ;
        2:  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, IdxReg, 1);
        4:  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, IdxReg, 2);
        8:  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, IdxReg, 3);
        12: FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mul, IdxReg, 12);
        16: FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, IdxReg, 4);
      else
        if ArrayAcc.ElementSize > 1 then
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mul, IdxReg, ArrayAcc.ElementSize);
      end;

      GenExpression(ArrayAcc.ArrayExpr, ADestReg);

      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.add, ADestReg, IdxReg);
      Exit;
    end;

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

          FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.lea, ADestReg, TRegisters.ID.BP, Cardinal(TotalOfs));

          Exit;
        end

        else if (Sym <> nil) and (Sym.Storage = TSymbol.TStorage.Global) then
        begin
          var Idx := FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mov, ADestReg, TLabelString(Sym.GlobalLabel));

          if ByteOffset <> 0 then
          begin
            var Item := FIR.Items[Idx];
            Item.Imm.Delta := ByteOffset;
            FIR.Items[Idx] := Item;
          end;

          Exit;
        end;
      end;

      GenExpression(IdxExpr, ADestReg);

      if ArrayAcc.LowBound > 0 then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.sub, ADestReg, Cardinal(ArrayAcc.LowBound));

      case ArrayAcc.ElementSize of
        1: ;
        2:  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, ADestReg, 1);
        4:  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, ADestReg, 2);
        8:  FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, ADestReg, 3);
        12: FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mul, ADestReg, 12);
        16: FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.shl, ADestReg, 4);
      else
        if ArrayAcc.ElementSize > 1 then
          FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mul, ADestReg, ArrayAcc.ElementSize);
      end;

      if (Sym <> nil) and (Sym.Storage = TSymbol.TStorage.Global) then
      begin
        FIR.AddInstrR1R2Imm(TCPUInstruction.TOpCode.lea, ADestReg, ADestReg, TLabelString(Sym.GlobalLabel));
        Exit;
      end
      else if (Sym <> nil) and (Sym.Storage = TSymbol.TStorage.Local) then
      begin
        FIR.AddInstrR1R2 (TCPUInstruction.TOpCode.add, ADestReg, TRegisters.ID.BP);
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.add, ADestReg, Cardinal(Sym.StackOffset));

        Exit;
      end
      else
      begin
        var TempReg: TRegisters.ID;

        if ADestReg <> TRegisters.ID.R6 then
          TempReg := TRegisters.ID.R6
        else
          TempReg := TRegisters.ID.R7;

        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.mov, TempReg, ADestReg);
        GenAddressOf    (ArrayAcc.ArrayExpr, ADestReg);
        FIR.AddInstrR1R2(TCPUInstruction.TOpCode.add, ADestReg, TempReg);

        Exit;
      end;
    end;

    GenAddressOf(ArrayAcc.ArrayExpr, ADestReg);

    var CurType: TType := nil;

    if (Sym <> nil) and (Sym.SymbolType <> nil) then
      CurType := Sym.SymbolType

    else if (ArrayAcc.ArrayExpr.ResolvedType <> nil) and (ArrayAcc.ArrayExpr.ResolvedType.TypeName <> '') then
    begin
      var SymLookup := FAnalyzer.GlobalScope.Resolve(ArrayAcc.ArrayExpr.ResolvedType.TypeName);

      if (SymLookup <> nil) and (SymLookup.SymbolType <> nil) then
        CurType := SymLookup.SymbolType;
    end;

    for var i := 0 to ArrayAcc.IndexExprs.Count - 1 do
    begin
      var DimReg: TRegisters.ID;

      if ADestReg <> TRegisters.ID.R6 then
        DimReg := TRegisters.ID.R6
      else
        DimReg := TRegisters.ID.R7;

      GenExpression(ArrayAcc.IndexExprs[i], DimReg);

      var DimLow := 0;
      var DimStride: Cardinal;

      if (CurType <> nil) and (CurType.Kind = TType.TKind.Array) then
      begin
        DimLow := CurType.SubrangeLow;

        if CurType.ElementType <> nil then
          DimStride := CurType.ElementType.Size
        else
          DimStride := ArrayAcc.ElementSize;

        CurType := CurType.ElementType;
      end
      else
        DimStride := ArrayAcc.ElementSize;

      if DimLow > 0 then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.sub, DimReg, Cardinal(DimLow));

      if DimStride > 1 then
        FIR.AddInstrR1Imm(TCPUInstruction.TOpCode.mul, DimReg, DimStride);

      FIR.AddInstrR1R2(TCPUInstruction.TOpCode.add, ADestReg, DimReg);
    end;

    Exit;
  end;

  if (AExpr is TASTUnary) and (TASTUnary(AExpr).Op = TASTUnary.TOp.Dereference) then
    GenExpression(TASTUnary(AExpr).Operand, ADestReg);
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
        FIR.AddLabel       (TLabelString('_var_' + LowerCase(Name)));
        FIR.AddDataReserved(VarSize);
      end;
    end;
  end;

  procedure EmitEmbedDecl(ADecl: TASTDeclaration);
  begin
    if (ADecl is TASTConstDecl) and TASTConstDecl(ADecl).IsEmbed and ADecl.IsUsed then
    begin
      var ConstDecl := TASTConstDecl(ADecl);

      FIR.AddBlankLine;
      FIR.AddLabel(TLabelString('_embed_' + LowerCase(ConstDecl.Name)));
      FIR.AddEmbed(ConstDecl.EmbedFile, ConstDecl.EmbedBytes);
    end;
  end;

begin
  FIR.AddBlankLine;

  if FUnits <> nil then
  begin
    for var U in FUnits do
    begin
      for var Decl in U.InterfaceDecls do
      begin
        EmitVarDecl  (Decl);
        EmitEmbedDecl(Decl);
      end;

      for var Decl in U.ImplementationDecls do
      begin
        EmitVarDecl  (Decl);
        EmitEmbedDecl(Decl);
      end;
    end;
  end;

  for var Decl in FProgram.Declarations do
  begin
    EmitVarDecl  (Decl);
    EmitEmbedDecl(Decl);
  end;

  for var Pair in FStringTable do
  begin
    FIR.AddBlankLine;
    FIR.AddLabel     (TLabelString(Pair.Value));
    FIR.AddDataString(AnsiString(Pair.Key), True);
  end;
end;

procedure TCodeGenerator.GenProgram;
  procedure SwitchSourceContext(const ASource, AFile: String);
  begin
    FFileName := ExtractFileName(AFile);
    if FFileName = '' then
      FFileName := 'Source.pas';

    FSourceLines.Clear;
    if ASource <> '' then
      FSourceLines.Text := ASource;

    FLastLine := 0;
  end;

  procedure EmitTypeMethods(ADecls: TObjectList<TASTDeclaration>);
  begin
    for var Decl in ADecls do
      if Decl is TASTTypeDecl then
        for var MNode in TASTTypeDecl(Decl).DeclType.RecordMethods do
          if (MNode is TASTRoutineDecl) and (TASTRoutineDecl(MNode).Body <> nil) and (not TASTRoutineDecl(MNode).IsForward) and TASTRoutineDecl(MNode).IsUsed then
            GenRoutine(TASTRoutineDecl(MNode));
  end;

const
  EntryPoint = '__program_begin_';
begin
  FIR.AddInstrRImm(TCPUInstruction.TOpCode.call, EntryPoint);
  FIR.AddInstr(TCPUInstruction.TOpCode.halt);

  if FUnits <> nil then
    for var U in FUnits do
    begin
      SwitchSourceContext(U.Source, U.FileName);

      EmitTypeMethods(U.InterfaceDecls);
      EmitTypeMethods(U.ImplementationDecls);

      for var Decl in U.ImplementationDecls do
        if (Decl is TASTRoutineDecl) then
        begin
          var R := TASTRoutineDecl(Decl);

          if (not R.IsForward) and (R.Body <> nil) and R.IsUsed then
            GenRoutine(R);
        end;
    end;

  SwitchSourceContext(FProgram.Source, FProgram.FileName);

  EmitTypeMethods(FProgram.Declarations);

  for var Decl in FProgram.Declarations do
    if (Decl is TASTRoutineDecl) then
    begin
      var R := TASTRoutineDecl(Decl);

      if (not R.IsForward) and (R.Body <> nil) and R.IsUsed then
        GenRoutine(R);
    end;

  FIR.AddBlankLine;

  if Assigned(FProgram.Body) then
    EmitSourceComment(FProgram.Body, True);

  FIR.AddLabel(EntryPoint);

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
