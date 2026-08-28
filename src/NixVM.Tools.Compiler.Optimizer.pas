{
  NixVM.Tools.Compiler.Optimizer.pas
    IR peephole optimizer

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

unit NixVM.Tools.Compiler.Optimizer;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,

  NixVM.Core.Registers,
  NixVM.Core.Instructions,
  NixVM.Tools.IR;

type
  TPeepholeOptimizer = class
  private
    class function NextCodeIndex(AIR: TIRList; AIndex: Integer): Integer; static;
    class function InstructionReadsReg(const AItem: TIRItem; AReg: TRegisters.ID): Boolean; static;
    class function InstructionOverwritesReg(const AItem: TIRItem; AReg: TRegisters.ID): Boolean; static;
    class function IsRegLiveDownstream(AIR: TIRList; AStartIndex: Integer; AReg: TRegisters.ID): Boolean; static;

    class function OptimizePass                (AIR: TIRList): Boolean; static;
    class function EliminateUnreachableCode    (AIR: TIRList): Boolean; static;
    class function ThreadJumps                 (AIR: TIRList): Boolean; static;
    class function EliminateUnreferencedSymbols(AIR: TIRList): Boolean; static;
  public
    class function Optimize(AIR: TIRList): Integer; static;
  end;

implementation

class function TPeepholeOptimizer.NextCodeIndex(AIR: TIRList; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;

  while (Result < AIR.Count) and (AIR[Result].Kind = TIRItem.TKind.None) and (AIR[Result].Comment = '') do
    Inc(Result);


  if (Result >= AIR.Count) or (AIR[Result].Kind <> TIRItem.TKind.Instruction) then
    Result := -1;
end;

class function TPeepholeOptimizer.InstructionReadsReg(const AItem: TIRItem; AReg: TRegisters.ID): Boolean;
begin
  Result := False;

  if AItem.Kind <> TIRItem.TKind.Instruction then
    Exit;

  if (AItem.OpCode = TCPUInstruction.TOpCode.call) or (AItem.OpCode = TCPUInstruction.TOpCode.syscall) then
    Exit(AReg in [TRegisters.ID.R0..TRegisters.ID.R3]);

  if (AItem.OpCode = TCPUInstruction.TOpCode.push) and (AItem.RegB = AReg) then
    Exit(True);

  if AItem.OpCode in [TCPUInstruction.TOpCode.st,   TCPUInstruction.TOpCode.stb,  TCPUInstruction.TOpCode.stw,
                      TCPUInstruction.TOpCode.sto,  TCPUInstruction.TOpCode.stob, TCPUInstruction.TOpCode.stow,
                      TCPUInstruction.TOpCode.sti,  TCPUInstruction.TOpCode.stib, TCPUInstruction.TOpCode.stiw,
                      TCPUInstruction.TOpCode.sts,  TCPUInstruction.TOpCode.stsb, TCPUInstruction.TOpCode.stsw] then
    Exit((AItem.RegA = AReg) or (AItem.RegB = AReg));


  if AItem.OpCode in [TCPUInstruction.TOpCode.ld,   TCPUInstruction.TOpCode.ldb,  TCPUInstruction.TOpCode.ldw,
                      TCPUInstruction.TOpCode.ldo,  TCPUInstruction.TOpCode.ldob, TCPUInstruction.TOpCode.ldow,
                      TCPUInstruction.TOpCode.ldi,  TCPUInstruction.TOpCode.ldib, TCPUInstruction.TOpCode.ldiw] then
    Exit(AItem.RegB = AReg);

  if AItem.OpCode in [TCPUInstruction.TOpCode.cmp, TCPUInstruction.TOpCode.fcmp] then
    Exit((AItem.RegA = AReg) or (AItem.RegB = AReg));

  if AItem.OpCode in [TCPUInstruction.TOpCode.add,  TCPUInstruction.TOpCode.sub,  TCPUInstruction.TOpCode.mul,
                      TCPUInstruction.TOpCode.&div, TCPUInstruction.TOpCode.&mod,
                      TCPUInstruction.TOpCode.imul, TCPUInstruction.TOpCode.idiv, TCPUInstruction.TOpCode.imod,
                      TCPUInstruction.TOpCode.&and, TCPUInstruction.TOpCode.&or,  TCPUInstruction.TOpCode.&xor,
                      TCPUInstruction.TOpCode.&shl, TCPUInstruction.TOpCode.&shr, TCPUInstruction.TOpCode.isar,
                      TCPUInstruction.TOpCode.fadd, TCPUInstruction.TOpCode.fsub, TCPUInstruction.TOpCode.fmul,
                      TCPUInstruction.TOpCode.fdiv, TCPUInstruction.TOpCode.bset, TCPUInstruction.TOpCode.bclr,
                      TCPUInstruction.TOpCode.btst] then
    Exit((AItem.RegA = AReg) or (AItem.RegB = AReg));


  if AItem.RegB = AReg then
    Exit(True);
end;

class function TPeepholeOptimizer.InstructionOverwritesReg(const AItem: TIRItem; AReg: TRegisters.ID): Boolean;
begin
  Result := False;
  if AItem.Kind <> TIRItem.TKind.Instruction then
    Exit;

  if (AItem.OpCode = TCPUInstruction.TOpCode.pop) and (AItem.RegA = AReg) then
    Exit(True);

  if AItem.OpCode = TCPUInstruction.TOpCode.popr then
    Exit(AReg < AItem.Offset.Value);

  if (AItem.OpCode = TCPUInstruction.TOpCode.call) or (AItem.OpCode = TCPUInstruction.TOpCode.syscall) then
    Exit(AReg = TRegisters.ID.R0);

  if AItem.OpCode in [TCPUInstruction.TOpCode.mov,   TCPUInstruction.TOpCode.lea,
                      TCPUInstruction.TOpCode.zextb, TCPUInstruction.TOpCode.zextw,
                      TCPUInstruction.TOpCode.iextb, TCPUInstruction.TOpCode.iextw,
                      TCPUInstruction.TOpCode.ld,    TCPUInstruction.TOpCode.ldb,  TCPUInstruction.TOpCode.ldw,
                      TCPUInstruction.TOpCode.ldo,   TCPUInstruction.TOpCode.ldob, TCPUInstruction.TOpCode.ldow,
                      TCPUInstruction.TOpCode.itof,  TCPUInstruction.TOpCode.ftoi, TCPUInstruction.TOpCode.frnd,
                      TCPUInstruction.TOpCode.sete,  TCPUInstruction.TOpCode.setne,
                      TCPUInstruction.TOpCode.setl,  TCPUInstruction.TOpCode.setle,
                      TCPUInstruction.TOpCode.setg,  TCPUInstruction.TOpCode.setge] then
    Exit(AItem.RegA = AReg);
end;

class function TPeepholeOptimizer.IsRegLiveDownstream(AIR: TIRList; AStartIndex: Integer; AReg: TRegisters.ID): Boolean;
begin
  Result := False;

  for var k := AStartIndex to AIR.Count - 1 do
  begin
    var KItem := AIR[k];

    if (KItem.Kind = TIRItem.TKind.&Label) or
       ((KItem.Kind = TIRItem.TKind.Instruction) and (KItem.OpCode.Definition.Params = TCPUInstruction.TParameters.Imm)) or
       ((KItem.Kind = TIRItem.TKind.Instruction) and (KItem.OpCode in [TCPUInstruction.TOpCode.jmp, TCPUInstruction.TOpCode.call])) then
      Exit(True);

    if (KItem.Kind = TIRItem.TKind.Instruction) and (KItem.OpCode in [TCPUInstruction.TOpCode.ret, TCPUInstruction.TOpCode.iret]) then
      Exit(AReg = TRegisters.ID.R0);

    if InstructionReadsReg(KItem, AReg) then
      Exit(True);

    if InstructionOverwritesReg(KItem, AReg) then
      Exit(False);
  end;
end;

class function TPeepholeOptimizer.OptimizePass(AIR: TIRList): Boolean;
var
  i: Integer;
begin
  Result := False;
  i := 0;

  while i < AIR.Count do
  begin
    var Item := AIR[i];

    if Item.Kind <> TIRItem.TKind.Instruction then
    begin
      Inc(i);
      Continue;
    end;

    // Redundant Self Moves (mov Rx, Rx)
    if (Item.OpCode = TCPUInstruction.TOpCode.mov) and (Item.RegA = Item.RegB) then
    begin
      AIR.Delete(i);

      Result := True;
      Continue;
    end;

    // Dead Write Elimination: mov Rx, Val where Rx is never read before being overwritten/RET
    if (Item.OpCode = TCPUInstruction.TOpCode.mov) and not IsRegLiveDownstream(AIR, i + 1, Item.RegA) then
    begin
      AIR.Delete(i);

      Result := True;
      Continue;
    end;

    // Redundant Arithmetic with 0 (+0, -0, shift 0)
    if (Item.OpCode in [TCPUInstruction.TOpCode.add, TCPUInstruction.TOpCode.sub,
                        TCPUInstruction.TOpCode.shl, TCPUInstruction.TOpCode.shr]) and
       (Item.RegB = TRegisters.ID.Imm) and (Item.Imm.Value = 0) and (Item.Imm.&Label = '') then
    begin
      AIR.Delete(i);

      Result := True;
      Continue;
    end;

    var NextIdx := NextCodeIndex(AIR, i);

    if NextIdx >= 0 then
    begin
      var NextItem := AIR[NextIdx];

      // PUSH Rx + POP Rx ==> ELIMINATE
      if (Item.OpCode = TCPUInstruction.TOpCode.push) and (NextItem.OpCode = TCPUInstruction.TOpCode.pop) and
         (Item.RegB = NextItem.RegA) then
      begin
        AIR.Delete(NextIdx);
        AIR.Delete(i);

        Result := True;
        Continue;
      end;

      // PUSH Rx + POP Ry ==> MOV Ry, Rx
      if (Item.OpCode = TCPUInstruction.TOpCode.push) and (NextItem.OpCode = TCPUInstruction.TOpCode.pop) and
         (Item.RegB <> NextItem.RegA) then
      begin
        var Replacement := Default(TIRItem);
        Replacement.Kind   := TIRItem.TKind.Instruction;
        Replacement.OpCode := TCPUInstruction.TOpCode.mov;
        Replacement.RegA   := NextItem.RegA;
        Replacement.RegB   := Item.RegB;

        AIR.Delete(NextIdx);
        AIR[i] := Replacement;

        Result := True;
        Continue;
      end;

      // Redundant Result Reload (sto bp, Rx, Ofs + ldo Rx, bp, Ofs ==> Delete ldo)
      if (Item.OpCode = TCPUInstruction.TOpCode.sto) and (Item.RegA = TRegisters.ID.BP) and
         (NextItem.OpCode = TCPUInstruction.TOpCode.ldo) and (NextItem.RegB = TRegisters.ID.BP) and
         (Item.RegB = NextItem.RegA) and (Item.Offset.Value = NextItem.Offset.Value) and
         (Item.Offset.&Label = NextItem.Offset.&Label) then
      begin
        AIR.Delete(NextIdx);

        Result := True;
        Continue;
      end;

      // Direct Global Load: mov R1, _var + ld R0, R1 ==> ld R0, _var
      if (Item.OpCode = TCPUInstruction.TOpCode.mov) and (Item.RegB = TRegisters.ID.Imm) and
         (NextItem.OpCode in [TCPUInstruction.TOpCode.ld, TCPUInstruction.TOpCode.ldb, TCPUInstruction.TOpCode.ldw]) and
         (NextItem.RegB = Item.RegA) then
      begin
        if not IsRegLiveDownstream(AIR, NextIdx + 1, Item.RegA) or (Item.RegA = NextItem.RegA) then
        begin
          var Replacement := Default(TIRItem);

          Replacement.Kind   := TIRItem.TKind.Instruction;
          Replacement.OpCode := NextItem.OpCode;
          Replacement.RegA   := NextItem.RegA;
          Replacement.RegB   := TRegisters.ID.Imm;
          Replacement.Imm    := Item.Imm;

          AIR.Delete(NextIdx);
          AIR[i] := Replacement;

          Result := True;
          Continue;
        end;
      end;

      // Consecutive ADD/SUB with Immediates (add R0, 4 + add R0, 8 ==> add R0, 12)
      if (Item.OpCode = TCPUInstruction.TOpCode.add) and (NextItem.OpCode = TCPUInstruction.TOpCode.add) and
         (Item.RegA = NextItem.RegA) and (Item.RegB = TRegisters.ID.Imm) and (NextItem.RegB = TRegisters.ID.Imm) and
         (Item.Imm.&Label = '') and (NextItem.Imm.&Label = '') then
      begin
        Item.Imm.Value := Item.Imm.Value + NextItem.Imm.Value;
        AIR.Delete(NextIdx);
        AIR[i] := Item;

        Result := True;
        Continue;
      end;

      // Fold MOV Reg, Imm + ADD Reg, Imm ==> MOV Reg, (Imm1 + Imm2)
      if (Item.OpCode = TCPUInstruction.TOpCode.mov) and (NextItem.OpCode = TCPUInstruction.TOpCode.add) and
         (Item.RegA = NextItem.RegA) and (Item.RegB = TRegisters.ID.Imm) and (NextItem.RegB = TRegisters.ID.Imm) and
         (Item.Imm.&Label = '') and (NextItem.Imm.&Label = '') then
      begin
        Item.Imm.Value := Item.Imm.Value + NextItem.Imm.Value;
        AIR.Delete(NextIdx);
        AIR[i] := Item;

        Result := True;
        Continue;
      end;

      // Fold Constant CMP R0, 0 + JMP into direct JMP
      if (Item.OpCode = TCPUInstruction.TOpCode.mov) and (Item.RegB = TRegisters.ID.Imm) and (Item.Imm.&Label = '') and
         (NextItem.OpCode = TCPUInstruction.TOpCode.cmp) and (NextItem.RegA = Item.RegA) and
         (NextItem.RegB = TRegisters.ID.Imm) and (NextItem.Imm.Value = 0) and (NextItem.Imm.&Label = '') then
      begin
        var NextNextIdx := NextCodeIndex(AIR, NextIdx);

        if NextNextIdx >= 0 then
        begin
          var BranchItem := AIR[NextNextIdx];
          var ConstVal   := Item.Imm.Value;

          if (ConstVal = 0) and (BranchItem.OpCode = TCPUInstruction.TOpCode.je) then
          begin
            var JmpItem := Default(TIRItem);

            JmpItem.Kind       := TIRItem.TKind.Instruction;
            JmpItem.OpCode     := TCPUInstruction.TOpCode.jmp;
            JmpItem.RegB       := TRegisters.ID.Imm;
            JmpItem.Imm.&Label := BranchItem.Offset.&Label;
            JmpItem.Imm.Delta  := BranchItem.Offset.Delta;

            AIR.Delete(NextNextIdx);
            AIR.Delete(NextIdx);
            AIR[i] := JmpItem;

            Result := True;
            Continue;
          end;

          if (ConstVal <> 0) and (BranchItem.OpCode = TCPUInstruction.TOpCode.je) then
          begin
            AIR.Delete(NextNextIdx);
            AIR.Delete(NextIdx);

            Result := True;
            Continue;
          end;

          if (ConstVal <> 0) and (BranchItem.OpCode = TCPUInstruction.TOpCode.jnz) then
          begin
            var JmpItem := Default(TIRItem);

            JmpItem.Kind       := TIRItem.TKind.Instruction;
            JmpItem.OpCode     := TCPUInstruction.TOpCode.jmp;
            JmpItem.RegB       := TRegisters.ID.Imm;
            JmpItem.Imm.&Label := BranchItem.Offset.&Label;
            JmpItem.Imm.Delta  := BranchItem.Offset.Delta;

            AIR.Delete(NextNextIdx);
            AIR.Delete(NextIdx);
            AIR[i] := JmpItem;

            Result := True;
            Continue;
          end;

          if (ConstVal = 0) and (BranchItem.OpCode = TCPUInstruction.TOpCode.jnz) then
          begin
            AIR.Delete(NextNextIdx);
            AIR.Delete(NextIdx);

            Result := True;
            Continue;
          end;
        end;
      end;

      // Dead Jump to Next Instruction
      if (Item.OpCode = TCPUInstruction.TOpCode.jmp) and (Item.RegB = TRegisters.ID.Imm) and (Item.Imm.&Label <> '') then
      begin
        var NextLabelIdx := i + 1;

        while (NextLabelIdx < AIR.Count) and (AIR[NextLabelIdx].Kind = TIRItem.TKind.None) and (AIR[NextLabelIdx].Comment = '') do
          Inc(NextLabelIdx);

        if (NextLabelIdx < AIR.Count) and (AIR[NextLabelIdx].Kind = TIRItem.TKind.&Label) and
           (AIR[NextLabelIdx].Name = Item.Imm.&Label) then
        begin
          AIR.Delete(i);

          Result := True;
          Continue;
        end;
      end;

      // Fold SETcc + CMP R0, 0 + JE/JNZ into Direct Conditional Branch
      if (Item.OpCode in [TCPUInstruction.TOpCode.sete, TCPUInstruction.TOpCode.setne,
                          TCPUInstruction.TOpCode.setl, TCPUInstruction.TOpCode.setle,
                          TCPUInstruction.TOpCode.setg, TCPUInstruction.TOpCode.setge]) and
         (NextItem.OpCode = TCPUInstruction.TOpCode.cmp) and
         (NextItem.RegA = Item.RegA) and (NextItem.RegB = TRegisters.ID.Imm) and (NextItem.Imm.Value = 0) and (NextItem.Imm.&Label = '') then
      begin
        var NextNextIdx := NextCodeIndex(AIR, NextIdx);

        if NextNextIdx >= 0 then
        begin
          var ThirdItem := AIR[NextNextIdx];

          if ThirdItem.OpCode in [TCPUInstruction.TOpCode.je, TCPUInstruction.TOpCode.jnz] then
          begin
            var TargetLabel := ThirdItem.Offset.&Label;
            var IsJE        := ThirdItem.OpCode = TCPUInstruction.TOpCode.je;
            var NewOpCode   := TCPUInstruction.TOpCode.nop;

            case Item.OpCode of
              TCPUInstruction.TOpCode.sete:  if IsJE then NewOpCode := TCPUInstruction.TOpCode.jnz else NewOpCode := TCPUInstruction.TOpCode.je;
              TCPUInstruction.TOpCode.setne: if IsJE then NewOpCode := TCPUInstruction.TOpCode.je  else NewOpCode := TCPUInstruction.TOpCode.jnz;
              TCPUInstruction.TOpCode.setl:  if IsJE then NewOpCode := TCPUInstruction.TOpCode.jge else NewOpCode := TCPUInstruction.TOpCode.jl;
              TCPUInstruction.TOpCode.setle: if IsJE then NewOpCode := TCPUInstruction.TOpCode.jg  else NewOpCode := TCPUInstruction.TOpCode.jle;
              TCPUInstruction.TOpCode.setg:  if IsJE then NewOpCode := TCPUInstruction.TOpCode.jle else NewOpCode := TCPUInstruction.TOpCode.jg;
              TCPUInstruction.TOpCode.setge: if IsJE then NewOpCode := TCPUInstruction.TOpCode.jl  else NewOpCode := TCPUInstruction.TOpCode.jge;
            end;

            if (NewOpCode <> TCPUInstruction.TOpCode.nop) and not IsRegLiveDownstream(AIR, NextNextIdx + 1, Item.RegA) then
            begin
              var NewBranch := Default(TIRItem);

              NewBranch.Kind          := TIRItem.TKind.Instruction;
              NewBranch.OpCode        := NewOpCode;
              NewBranch.Offset.&Label := TargetLabel;

              AIR.Delete(NextNextIdx);
              AIR.Delete(NextIdx);
              AIR[i] := NewBranch;

              Result := True;
              Continue;
            end;
          end;
        end;
      end;
    end;

    Inc(i);
  end;
end;

class function TPeepholeOptimizer.EliminateUnreachableCode(AIR: TIRList): Boolean;
var
  i: Integer;
begin
  Result := False;
  i := 0;

  while i < AIR.Count do
  begin
    var Item := AIR[i];

    if (Item.Kind = TIRItem.TKind.Instruction) and
       ((Item.OpCode = TCPUInstruction.TOpCode.jmp) or
        (Item.OpCode = TCPUInstruction.TOpCode.ret) or
        (Item.OpCode = TCPUInstruction.TOpCode.iret) or
        (Item.OpCode = TCPUInstruction.TOpCode.halt)) then
    begin
      var ScanIdx := i + 1;

      while (ScanIdx < AIR.Count) and (AIR[ScanIdx].Kind <> TIRItem.TKind.&Label) do
      begin
        if AIR[ScanIdx].Kind = TIRItem.TKind.Instruction then
        begin
          AIR.Delete(ScanIdx);
          Result := True;
        end
        else
          Inc(ScanIdx);
      end;
    end;

    Inc(i);
  end;
end;

class function TPeepholeOptimizer.ThreadJumps(AIR: TIRList): Boolean;
var
  LabelMap: TDictionary<TLabelString, Integer>;
  i:        Integer;
begin
  Result   := False;
  LabelMap := TDictionary<TLabelString, Integer>.Create;

  try
    for i := 0 to AIR.Count - 1 do
      if AIR[i].Kind = TIRItem.TKind.&Label then
      begin
        var NextIdx := NextCodeIndex(AIR, i);

        if NextIdx >= 0 then
          LabelMap.AddOrSetValue(AIR[i].Name, NextIdx);
      end;

    for i := 0 to AIR.Count - 1 do
      if AIR[i].Kind = TIRItem.TKind.Instruction then
      begin
        if (AIR[i].OpCode = TCPUInstruction.TOpCode.jmp) and (AIR[i].RegB = TRegisters.ID.Imm) and (AIR[i].Imm.&Label <> '') then
        begin
          var TargetCodeIdx: Integer;

          if LabelMap.TryGetValue(AIR[i].Imm.&Label, TargetCodeIdx) then
          begin
            var TargetItem := AIR[TargetCodeIdx];

            if (TargetItem.Kind = TIRItem.TKind.Instruction) and (TargetItem.OpCode = TCPUInstruction.TOpCode.jmp) and
               (TargetItem.RegB = TRegisters.ID.Imm) and (TargetItem.Imm.&Label <> '') and
               (TargetItem.Imm.&Label <> AIR[i].Imm.&Label) then
            begin
              var Item := AIR[i];

              Item.Imm := TargetItem.Imm;
              AIR[i] := Item;
              Result := True;
            end;
          end;
        end;
      end;
  finally
    LabelMap.Free;
  end;
end;

class function TPeepholeOptimizer.EliminateUnreferencedSymbols(AIR: TIRList): Boolean;
var
  UsedLabels: TDictionary<TLabelString, Boolean>;
  i:           Integer;
begin
  Result     := False;
  UsedLabels := TDictionary<TLabelString, Boolean>.Create;

  try
    for i := 0 to AIR.Count - 1 do
    begin
      var Item := AIR[i];

      if Item.Kind = TIRItem.TKind.Instruction then
      begin
        if Item.Imm.&Label <> '' then
          UsedLabels.AddOrSetValue(Item.Imm.&Label, True);

        if Item.Offset.&Label <> '' then
          UsedLabels.AddOrSetValue(Item.Offset.&Label, True);
      end;
    end;

    i := 0;

    while i < AIR.Count do
    begin
      if (AIR[i].Kind = TIRItem.TKind.&Label) and not UsedLabels.ContainsKey(AIR[i].Name) then
      begin
        var LblName := String(AIR[i].Name);

        if (Length(LblName) > 0) and (LblName[1] = '@') then
        begin
          AIR.Delete(i);

          Result := True;
          Continue;
        end;

        if Pos('_strconst_', LblName) = 1 then
        begin
          AIR.Delete(i);

          if (i < AIR.Count) and (AIR[i].Kind in [TIRItem.TKind.DataString, TIRItem.TKind.DataBytes]) then
            AIR.Delete(i);

          Result := True;
          Continue;
        end;
      end;

      Inc(i);
    end;
  finally
    UsedLabels.Free;
  end;
end;

class function TPeepholeOptimizer.Optimize(AIR: TIRList): Integer;
var
  Passes: Integer;
  Modified: Boolean;
begin
  Passes := 0;

  repeat
    Modified := False;

    if OptimizePass(AIR) then
      Modified := True;

    if ThreadJumps(AIR) then
      Modified := True;

    if EliminateUnreachableCode(AIR) then
      Modified := True;

    if EliminateUnreferencedSymbols(AIR) then
      Modified := True;

    Inc(Passes);
  until not Modified ;//or (Passes >= 32);

  Result := Passes;
end;

end.
