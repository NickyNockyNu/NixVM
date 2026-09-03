{
  NixVM.Core.Instructions.pas
    CPU instructions

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

unit NixVM.Core.Instructions;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  NixVM.Core.Registers;

type
  {$REGION 'TCPUInstruction'}
  TCPUInstruction = record
  type
    TParameters = (None, Imm, R1, R1R2, R1Imm, RImm, R1R2Imm, Rn, RnImm);

    TDefinition = record
      Mnemonic:  String[8];
      Params:    TParameters;
    end;

    {$REGION 'OpCode'}
    TOpCode = type Byte;

    TOpCodeHelper = record helper for TOpCode
    const
      {$REGION 'OpCodes'}
      halt   = $00;
      yield  = $01;
      &raise = $02;

      mov   = $10;
      swap  = $11;
      cmp   = $12;
      lea   = $13;
      zextb = $14;
      zextw = $15;

      add  = $20;
      sub  = $21;
      mul  = $22;
      &div = $23;
      &mod = $24;

      imul  = $30;
      idiv  = $31;
      imod  = $32;
      isar  = $33;
      ineg  = $34;
      iextb = $35;
      iextw = $36;

      &and = $40;
      &or  = $41;
      &xor = $42;
      &shl = $43;
      &shr = $44;
      &not = $45;

      ldb = $50;
      ldw = $51;
      ld  = $52;

      stb = $53;
      stw = $54;
      st  = $55;

      ldib = $56;
      ldiw = $57;
      ldi  = $58;

      stib = $59;
      stiw = $5A;
      sti  = $5B;

      stsb = $5C;
      stsw = $5D;
      sts  = $5E;

      ldob = $60;
      ldow = $61;
      ldo  = $62;

      stob = $63;
      stow = $64;
      sto  = $65;

      jnz  = $70;
      je   = $71;
      jl   = $72;
      jle  = $73;
      jg   = $74;
      jge  = $75;
      jb   = $76;
      jae  = $77;
      jmp  = $78;
      loop = $79;

      call    = $80;
      syscall = $81;
      int     = $82;
      ret     = $83;
      iret    = $84;
      enter   = $85;
      leave   = $86;
      zenter  = $87;

      push  = $90;
      pop   = $91;
      pushf = $92;
      popf  = $93;
      pushr = $94;
      popr  = $95;

      fadd  = $B0;
      fsub  = $B1;
      fmul  = $B2;
      fdiv  = $B3;
      itof  = $B4;
      ftoi  = $B5;
      frnd  = $B6;
      fsin  = $B7;
      fcos  = $B8;
      ftan  = $B9;
      fatan = $BA;
      fexp  = $BB;
      fln   = $BC;
      fsqrt = $BD;
      fce   = $BE;
      fcmp  = $BF;

      sete  = $C0;
      setne = $C1;
      setl  = $C2;
      setle = $C3;
      setg  = $C4;
      setge = $C5;

      bset  = $D0;
      bclr  = $D1;
      btst  = $D2;
      bsetf = $D3;
      bclrf = $D4;
      btstf = $D5;

      nop = $FF;
      {$ENDREGION}
    public
      function Definition: TDefinition; inline;

      function ToString: String;
      class function FromString(const S: String; out AValid: Boolean): TOpCode; static;
    end;
    {$ENDREGION}
  const
    Definitions: array[TOpCode] of TDefinition = (
      {$REGION 'Definitions'}
      {00}(Mnemonic:'halt'),
      {01}(Mnemonic:'yield'),
      {02}(Mnemonic:'raise'; Params:TParameters.RImm),
      {03}(),
      {04}(),
      {05}(),
      {06}(),
      {07}(),
      {08}(),
      {09}(),
      {0A}(),
      {0B}(),
      {0C}(),
      {0D}(),
      {0E}(),
      {0F}(),

      {10}(Mnemonic:'mov';   Params:TParameters.R1R2),
      {11}(Mnemonic:'swap';  Params:TParameters.R1R2),
      {12}(Mnemonic:'cmp';   Params:TParameters.R1R2),
      {13}(Mnemonic:'lea';   Params:TParameters.R1R2Imm),
      {14}(Mnemonic:'zextb'; Params:TParameters.R1R2),
      {15}(Mnemonic:'zextw'; Params:TParameters.R1R2),
      {16}(),
      {17}(),
      {18}(),
      {19}(),
      {1A}(),
      {1B}(),
      {1C}(),
      {1D}(),
      {1E}(),
      {1F}(),

      {20}(Mnemonic:'add'; Params:TParameters.R1R2),
      {21}(Mnemonic:'sub'; Params:TParameters.R1R2),
      {22}(Mnemonic:'mul'; Params:TParameters.R1R2),
      {23}(Mnemonic:'div'; Params:TParameters.R1R2),
      {24}(),
      {25}(),
      {26}(),
      {27}(),
      {28}(),
      {29}(),
      {2A}(),
      {2B}(),
      {2C}(),
      {2D}(),
      {2E}(),
      {2F}(),

      {30}(Mnemonic:'imul';  Params:TParameters.R1R2),
      {31}(Mnemonic:'idiv';  Params:TParameters.R1R2),
      {32}(Mnemonic:'imod';  Params:TParameters.R1R2),
      {33}(Mnemonic:'isar';  Params:TParameters.R1R2),
      {34}(Mnemonic:'ineg';  Params:TParameters.R1R2),
      {35}(Mnemonic:'iextb'; Params:TParameters.R1R2),
      {36}(Mnemonic:'iextw'; Params:TParameters.R1R2),
      {37}(),
      {38}(),
      {39}(),
      {3A}(),
      {3B}(),
      {3C}(),
      {3D}(),
      {3E}(),
      {3F}(),

      {40}(Mnemonic:'and'; Params:TParameters.R1R2),
      {41}(Mnemonic:'or';  Params:TParameters.R1R2),
      {42}(Mnemonic:'xor'; Params:TParameters.R1R2),
      {43}(Mnemonic:'shl'; Params:TParameters.R1R2),
      {44}(Mnemonic:'shr'; Params:TParameters.R1R2),
      {45}(Mnemonic:'not'; Params:TParameters.R1R2),
      {46}(),
      {47}(),
      {48}(),
      {49}(),
      {4A}(),
      {4B}(),
      {4C}(),
      {4D}(),
      {4E}(),
      {4F}(),

      {50}(Mnemonic:'ldb';  Params:TParameters.R1R2),
      {51}(Mnemonic:'ldw';  Params:TParameters.R1R2),
      {52}(Mnemonic:'ld';   Params:TParameters.R1R2),
      {53}(Mnemonic:'stb';  Params:TParameters.R1R2),
      {54}(Mnemonic:'stw';  Params:TParameters.R1R2),
      {55}(Mnemonic:'st';   Params:TParameters.R1R2),
      {56}(Mnemonic:'ldib'; Params:TParameters.R1R2),
      {57}(Mnemonic:'ldiw'; Params:TParameters.R1R2),
      {58}(Mnemonic:'ldi';  Params:TParameters.R1R2),
      {59}(Mnemonic:'stib'; Params:TParameters.R1R2),
      {5A}(Mnemonic:'stiw'; Params:TParameters.R1R2),
      {5B}(Mnemonic:'sti';  Params:TParameters.R1R2),
      {5C}(Mnemonic:'stsb'; Params:TParameters.R1R2),
      {5D}(Mnemonic:'stsw'; Params:TParameters.R1R2),
      {5E}(Mnemonic:'sts';  Params:TParameters.R1R2),
      {5F}(),

      {60}(Mnemonic:'ldob'; Params:TParameters.R1R2Imm),
      {61}(Mnemonic:'ldow'; Params:TParameters.R1R2Imm),
      {62}(Mnemonic:'ldo';  Params:TParameters.R1R2Imm),
      {63}(Mnemonic:'stob'; Params:TParameters.R1R2Imm),
      {64}(Mnemonic:'stow'; Params:TParameters.R1R2Imm),
      {65}(Mnemonic:'sto';  Params:TParameters.R1R2Imm),
      {66}(),
      {67}(),
      {68}(),
      {69}(),
      {6A}(),
      {6B}(),
      {6C}(),
      {6D}(),
      {6E}(),
      {6F}(),

      {70}(Mnemonic:'jnz';  Params:TParameters.Imm),
      {71}(Mnemonic:'je';   Params:TParameters.Imm),
      {72}(Mnemonic:'jl';   Params:TParameters.Imm),
      {73}(Mnemonic:'jle';  Params:TParameters.Imm),
      {74}(Mnemonic:'jg';   Params:TParameters.Imm),
      {75}(Mnemonic:'jge';  Params:TParameters.Imm),
      {76}(Mnemonic:'jb';   Params:TParameters.Imm),
      {77}(Mnemonic:'jae';  Params:TParameters.Imm),
      {78}(Mnemonic:'jmp';  Params:TParameters.RImm),
      {79}(Mnemonic:'loop'; Params:TParameters.R1Imm),
      {7A}(),
      {7B}(),
      {7C}(),
      {7D}(),
      {7E}(),
      {7F}(),

      {80}(Mnemonic:'call';    Params:TParameters.RImm),
      {81}(Mnemonic:'syscall'; Params:TParameters.RImm),
      {82}(Mnemonic:'int';     Params:TParameters.RImm),
      {83}(Mnemonic:'ret'),
      {84}(Mnemonic:'iret'),
      {85}(Mnemonic:'enter';   Params:TParameters.RnImm),
      {86}(Mnemonic:'leave'),
      {87}(Mnemonic:'zenter';  Params:TParameters.RnImm),
      {88}(),
      {89}(),
      {8A}(),
      {8B}(),
      {8C}(),
      {8D}(),
      {8E}(),
      {8F}(),

      {90}(Mnemonic:'push';   Params:TParameters.RImm),
      {91}(Mnemonic:'pop';    Params:TParameters.R1),
      {92}(Mnemonic:'pushf'),
      {93}(Mnemonic:'popf'),
      {94}(Mnemonic:'pushr';  Params:TParameters.Rn),
      {95}(Mnemonic:'popr';   Params:TParameters.Rn),
      {96}(),
      {97}(),
      {98}(),
      {99}(),
      {9A}(),
      {9B}(),
      {9C}(),
      {9D}(),
      {9E}(),
      {9F}(),

      {A0}(),
      {A1}(),
      {A2}(),
      {A3}(),
      {A4}(),
      {A5}(),
      {A6}(),
      {A7}(),
      {A8}(),
      {A9}(),
      {AA}(),
      {AB}(),
      {AC}(),
      {AD}(),
      {AE}(),
      {AF}(),

      {B0}(Mnemonic:'fadd';  Params:TParameters.R1R2),
      {B1}(Mnemonic:'fsub';  Params:TParameters.R1R2),
      {B2}(Mnemonic:'fmul';  Params:TParameters.R1R2),
      {B3}(Mnemonic:'fdiv';  Params:TParameters.R1R2),
      {B4}(Mnemonic:'itof';  Params:TParameters.R1R2),
      {B5}(Mnemonic:'ftoi';  Params:TParameters.R1R2),
      {B6}(Mnemonic:'frnd';  Params:TParameters.R1R2),
      {B7}(Mnemonic:'fsin';  Params:TParameters.R1R2),
      {B8}(Mnemonic:'fcos';  Params:TParameters.R1R2),
      {B9}(Mnemonic:'ftan';  Params:TParameters.R1R2),
      {BA}(Mnemonic:'fatan'; Params:TParameters.R1R2),
      {BB}(Mnemonic:'fexp';  Params:TParameters.R1R2),
      {BC}(Mnemonic:'fln';   Params:TParameters.R1R2),
      {BD}(Mnemonic:'fsqrt'; Params:TParameters.R1R2),
      {BE}(Mnemonic:'fce'),
      {BF}(Mnemonic:'fcmp';  Params:TParameters.R1R2),

      {C0}(Mnemonic:'sete';  Params:TParameters.R1),
      {C1}(Mnemonic:'setne'; Params:TParameters.R1),
      {C2}(Mnemonic:'setl';  Params:TParameters.R1),
      {C3}(Mnemonic:'setle'; Params:TParameters.R1),
      {C4}(Mnemonic:'setg';  Params:TParameters.R1),
      {C5}(Mnemonic:'setge'; Params:TParameters.R1),
      {C6}(),
      {C7}(),
      {C8}(),
      {C9}(),
      {CA}(),
      {CB}(),
      {CC}(),
      {CD}(),
      {CE}(),
      {CF}(),

      {D0}(Mnemonic:'bset';   Params:TParameters.R1R2),
      {D1}(Mnemonic:'bclr';   Params:TParameters.R1R2),
      {D2}(Mnemonic:'btst';   Params:TParameters.R1R2),
      {D3}(Mnemonic:'bsetf';  Params:TParameters.RImm),
      {D4}(Mnemonic:'bclrf';  Params:TParameters.RImm),
      {D5}(Mnemonic:'btstf';  Params:TParameters.RImm),
      {D6}(),
      {D7}(),
      {D8}(),
      {D9}(),
      {DA}(),
      {DB}(),
      {DC}(),
      {DD}(),
      {DE}(),
      {DF}(),

      {E0}(),
      {E1}(),
      {E2}(),
      {E3}(),
      {E4}(),
      {E5}(),
      {E6}(),
      {E7}(),
      {E8}(),
      {E9}(),
      {EA}(),
      {EB}(),
      {EC}(),
      {ED}(),
      {EE}(),
      {EF}(),

      {F0}(),
      {F1}(),
      {F2}(),
      {F3}(),
      {F4}(),
      {F5}(),
      {F6}(),
      {F7}(),
      {F8}(),
      {F9}(),
      {FA}(),
      {FB}(),
      {FC}(),
      {FD}(),
      {FE}(),
      {FF}(Mnemonic:'nop')
      {$ENDREGION}
    );
  public
    OpCode: TOpCode;
    RegA:   TRegisters.ID;
    RegB:   TRegisters.ID;

    class operator Implicit(      AWord:  Word):            TCPUInstruction; overload; inline;
    class operator Implicit(const AInstr: TCPUInstruction): Word;            overload; inline;

    function ToString: String;
    class function FromString(const S: String; out AValid: Boolean): TCPUInstruction; static;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Core.Strings;

{$REGION 'TCPUInstruction'}
{$REGION 'OpCode'}
function TCPUInstruction.TOpCodeHelper.Definition: TDefinition;
begin
  Result := Definitions[Self];
end;

function TCPUInstruction.TOpCodeHelper.ToString: String;
begin
  Result := String(Definitions[Self].Mnemonic);
end;

class function TCPUInstruction.TOpCodeHelper.FromString(const S: String; out AValid: Boolean): TOpCode;
var
  U: ShortString;
begin
  U := ShortString(Lowercase(TrimWhitespace(S)));

  for var i := 0 to 255 do
    if U = Definitions[i].Mnemonic then
    begin
      Result := i;
      AValid := True;
      Exit;
    end;

  Result := 0;
  AValid := False;
end;
{$ENDREGION}

class operator TCPUInstruction.Implicit(AWord: Word): TCPUInstruction;
begin
  Result.OpCode := AWord and $FF;
  TRegisters.Decode(AWord shr 8, Result.RegA, Result.RegB);
end;

class operator TCPUInstruction.Implicit(const AInstr: TCPUInstruction): Word;
begin
  Result := AInstr.OpCode or (TRegisters.Encode(AInstr.RegA, AInstr.RegB) shl 8);
end;

function TCPUInstruction.ToString: String;
begin
  Result := OpCode.ToString + ' ' + RegA.ToString + ', ' + RegB.ToString;
end;

class function TCPUInstruction.FromString(const S: String; out AValid: Boolean): TCPUInstruction;
var
  j: Integer;
  c: Char;
  U:      String;
  Instr:  String;
  Param1: String;
  Param2: String;
begin
  AValid := False;

  U := TrimWhitespace(S);

  if Length(U) = 0 then
    Exit;

  j := 0;

  Instr  := '';
  Param1 := '';
  Param2 := '';

  for var i := 1 to Length(U) do
  begin
    c := U[i];

    case j of
      0:
      begin
        if Pos(c, #32#9) > 0 then
          Inc(j)
        else
          Instr := Instr + c;
      end;

      1:
      begin
        if c = ',' then
          inc(j)
        else
          Param1 := Param1 + c;
      end;

      2:
      begin
        if c = ',' then
          Inc(j)
        else
          Param2 := Param2 + c;
      end;
    else
      Break;
    end;
  end;

  Result.OpCode := TOpCode.FromString(Instr, AValid);
  if not AValid then
    Exit;

  Result.RegA := TRegisters.ID.FromString(Param1, AValid);
  if not AValid then
    Exit;

  Result.RegB := TRegisters.ID.FromString(Param2, AValid);
  if not AValid then
    Exit;
end;
{$ENDREGION}

end.

