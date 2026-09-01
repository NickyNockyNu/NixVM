{
  nvm.dpr
    NixVM cli tool

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

program nvm;

{$APPTYPE CONSOLE}
{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,

  NixVM.Core.Registers,
  NixVM.Core.Instructions,
  NixVM.Core.Strings,
  NixVM.Core.Memory,
  NixVM.Core.System,
  NixVM.Core.ROM,

  NixVM.Tools.Params,
  NixVM.Tools.IR,
  NixVM.Tools.Assembler,
  NixVM.Tools.Disasm,
  NixVM.Tools.BuildPE,
  NixVM.Tools.Compiler,
  NixVM.Tools.Compiler.Lexer,
  NixVM.Tools.Compiler.AST,
  NixVM.Tools.Compiler.Parser,
  NixVM.Tools.Compiler.Semantics,
  NixVM.Tools.Compiler.CodeGen;

var
  Verbose:    Boolean;
  InputFile:  String;
  OutputFile: String;

procedure PrintBanner;
begin
  Writeln('NixVM build tools');
  Writeln('Copyright (c) 2026 Nicholas Smith');
  Writeln('https://github.com/NickyNockyNu/NixVM');
  Writeln;
end;

procedure PrintDefaultOptions;
begin
  Writeln('  -h, --help             Display usage (e.g. nvm compile --help)');
  Writeln('  -v, --verbose          Verbose output');
  Writeln('  -o, --output <file>    Specify output file');
end;

procedure PrintBuildOptions;
begin
  Writeln('  -z, --optimize         Optimise output');
  Writeln('  -base <addr>           Override base address (e.g. -base 0x4E0)');
  Writeln('  -heap <size>           Override heap size (e.g. -heap 128k, -heap $20000)');
  Writeln('  -stack <size>          Override stack size');
end;

procedure AddBuildOptions;
begin
  TParams.AddOpt(TParams.TOption.TKind.Bool, 'z',  'optimize');

  TParams.AddOpt(TParams.TOption.TKind.Num, 'base',  'base');
  TParams.AddOpt(TParams.TOption.TKind.Num, 'heap',  'heap');
  TParams.AddOpt(TParams.TOption.TKind.Num, 'stack', 'stack');
end;


procedure PrintUsage;
begin
  Writeln('Usage: nvm <compile|assemble|disassemble|link|stamp> <file> [options]');
  Writeln;
  Writeln('General options:');
  PrintDefaultOptions;
  Writeln;
  Writeln('For tool specific options use:');
  Writeln('  nvm --help <compile|assemble|disassemble|link|stamp>');
  Writeln;
end;

procedure ProcessFiles(const AOutExt: String);
begin
  InputFile  := TParams.Params[1];
  OutputFile := TParams.GetOpt('-o', ChangeFileExt(InputFile, '.' + AOutExt));

  if not FileExists(InputFile) then
  begin
    Writeln('File does not exist: ', InputFile);
    Halt(1);
  end;
end;

procedure DoCompile;
var
  Compiler:   TCompiler;
  Assemble:   Boolean;
  TargetInfo: TTargetInfo;
begin
  AddBuildOptions;
  TParams.AddOpt(TParams.TOption.TKind.Bool, 'a', 'assemble');
  TParams.Process;

  Assemble := TParams.GetOpt('-a', False);

  if TParams.GetOpt('-h', False) or (TParams.ParamCount < 2) then
  begin
    Writeln('Usage: nvm compile <file.pas> [options]');
    Writeln;
    Writeln('Options:');
    PrintDefaultOptions;
    PrintBuildOptions;
    Writeln('  -a, --assemble         Output assembly only');

    Halt(0);
  end;

  if Assemble then
    ProcessFiles('asm')
  else
    ProcessFiles('nvm');

  Compiler := TCompiler.Create;

  Compiler.Optimise := TParams.GetOpt('-z', Compiler.Optimise);

  try
    if Verbose then
      Write('Compiling ', InputFile + ' ... ');

    if not Compiler.CompileFile(InputFile) then
    begin
      if Verbose then
        Writeln('[failed]');

      for var Err in Compiler.Errors do
        Writeln(Err);

      Halt(1);
    end;

    if Verbose then
      Writeln('[ok]');

    Compiler.ROMHeader.UserAddress := TParams.GetOpt('-base',  Compiler.ROMHeader.UserAddress);
    Compiler.ROMHeader.HeapSize    := TParams.GetOpt('-heap',  Compiler.ROMHeader.HeapSize);
    Compiler.ROMHeader.StackSize   := TParams.GetOpt('-stack', Compiler.ROMHeader.StackSize);

    if Assemble then
    begin
      if Verbose then
        Write('Saving ', OutputFile, ' ... ');

      Compiler.ROMHeader.UserSize := Compiler.IR.Size;

      try
        TFile.WriteAllText(OutputFile, Compiler.ToAsmString);

        if Verbose then
          Writeln('[ok]');
      except
        on E: Exception do
        begin
          if Verbose then
            Writeln('[failed]');

          Writeln(E.Message);
          Halt(1);
        end;
      end;
    end
    else
    begin
      if Verbose then
        Write('Linking ', OutputFile, ' ... ');

      if not Compiler.Link(OutputFile, True{not RawBinary}) then
      begin
        if Verbose then
          Writeln('[failed]');

        for var Err in Compiler.Errors do
          Writeln(Err);

        Halt(1);
      end;

      if Verbose then
        Writeln('[ok]');
    end;

    if Verbose then
    begin
      Writeln;
      Writeln(Compiler.ROMHeader.ToString);

      if Compiler.Optimise then
        Writeln('Optimisations: ', Compiler.SizeBeforeOpt, ' -> ', Compiler.SizeAfterOpt);
    end;
  finally
    Compiler.Free;
  end;
end;

procedure DoAssemble;
var
  &Assembler: TAssembler;
  Binary:     Boolean;
begin
  AddBuildOptions;
  TParams.AddOpt(TParams.TOption.TKind.Bool, 'r', 'raw');
  TParams.Process;

  Binary := TParams.GetOpt('-a', False);

  if TParams.GetOpt('-h', False) or (TParams.ParamCount < 2) then
  begin
    Writeln('Usage: nvm assemble <file.asm> [options]');
    Writeln;
    Writeln('Options:');
    PrintDefaultOptions;
    PrintBuildOptions;
    Writeln('  -r, --raw              Raw binary output');

    Halt(0);
  end;

  if Binary then
    ProcessFiles('bin')
  else
    ProcessFiles('nvm');

  &Assembler := TAssembler.Create;

  &Assembler.Optimise := TParams.GetOpt('-z', &Assembler.Optimise);

  try
    if Verbose then
      Write('Assembling ', InputFile + ' ... ');

    if not &Assembler.AssembleFile(InputFile) then
    begin
      if Verbose then
        Writeln('[failed]');

      for var Err in &Assembler.Errors do
        Writeln(Err);

      Halt(1);
    end;

    if Verbose then
      Writeln('[ok]');

    &Assembler.ROMHeader.UserAddress := TParams.GetOpt('-base',  &Assembler.ROMHeader.UserAddress);
    &Assembler.ROMHeader.HeapSize    := TParams.GetOpt('-heap',  &Assembler.ROMHeader.HeapSize);
    &Assembler.ROMHeader.StackSize   := TParams.GetOpt('-stack', &Assembler.ROMHeader.StackSize);

    if Verbose then
      Write('Linking ', OutputFile, ' ... ');

    if not &Assembler.Link(OutputFile, not Binary) then
    begin
      if Verbose then
        Writeln('[failed]');

      for var Err in &Assembler.Errors do
        Writeln(Err);

      Halt(1);
    end;

    if Verbose then
      Writeln('[ok]');

    if Verbose then
    begin
      Writeln;
      Writeln(&Assembler.ROMHeader.ToString);

      if &Assembler.Optimise then
        Writeln('Optimisations: ', &Assembler.SizeBeforeOpt, ' -> ', &Assembler.SizeAfterOpt);
    end;
  finally
    &Assembler.Free;
  end;
end;

procedure DoDisassemble;
var
  Disassembler: TDisassembler;
  Success:      Boolean;
begin
  TParams.AddOpt(TParams.TOption.TKind.Bool, 'r', 'raw');
  TParams.AddOpt(TParams.TOption.TKind.Num, 'base',  'base');
  TParams.Process;

  if TParams.GetOpt('-h', False) or (TParams.ParamCount < 2) then
  begin
    Writeln('Usage: nvm disassemble <file.nvm> [options]');
    Writeln;
    Writeln('Options:');
    PrintDefaultOptions;
    Writeln('  -r, --raw              Raw binary input');
    Writeln('  -base <addr>           Override base address for raw binary (e.g. -base 0x4E0)');

    Halt(0);
  end;

  ProcessFiles('asm');

  Disassembler := TDisassembler.Create;

  try
    if Verbose then
      Write('Disassembling ', InputFile + ' ... ');

    Disassembler.EmitDirectives := not TParams.GetOpt('-r', False);

    if Disassembler.EmitDirectives then
      Success := Disassembler.DisassembleFile(InputFile)
    else
      Success := Disassembler.DisassembleRawFile(InputFile, TParams.GetOpt('-base', Disassembler.ROMHeader.UserAddress));

    if not Success then
    begin
      if Verbose then
        Writeln('[failed]');

      for var Err in Disassembler.Errors do
        Writeln(Err);

      Halt(1);
    end;

    if Verbose then
      Writeln('[ok]');

    if Verbose then
      Write('Saving ', OutputFile, ' ... ');

    if not Disassembler.SaveToFile(OutputFile) then
    begin
      if Verbose then
        Writeln('[failed]');

      for var Err in Disassembler.Errors do
        Writeln(Err);

      Halt(1);
    end;

    if Verbose then
      Writeln('[ok]');
  finally
    Disassembler.Free;
  end;
end;

procedure DoLink;
var
  Header:   TROMHeader;
  StubFile: String;
begin
  TParams.AddOpt(TParams.TOption.TKind.Str, 's', 'stub');
  TParams.Process;

  if TParams.GetOpt('-h', False) or (TParams.ParamCount < 2) then
  begin
    Writeln('Usage: nvm link <file.nvm> [options]');
    Writeln;
    Writeln('Options:');
    PrintDefaultOptions;

    Halt(0);
  end;

  ProcessFiles('exe');

  if Verbose then
    Write('Reading ', InputFile, ' ... ');

  if not Header.Load(InputFile) then
  begin
    //if Verbose then
      Writeln('[failed]');

    Halt(1);
  end;

  if Verbose then
    Writeln('[ok]');

  StubFile := TParams.GetOpt('-s', Header.Harness.Name);

  if Verbose then
    Writeln('Targetting "', StubFile, '"');

  if Length(StubFile) = 0 then
  begin
    Writeln('No harness specified');

    Halt(1);
  end;

  StubFile := TPath.Combine(ExtractFilePath(ParamStr(0)), 'harness.' + StubFile + '.exe');

  var Errors := TStringList.Create;

  try
    if Verbose then
      Write('Linking ', OutputFile, ' ... ');

    if not TBuildPE.EmbedROM(StubFile, InputFile, OutputFile, TBuildPE.DefaultResourceName, Errors) then
    begin
      if Verbose then
        Writeln('[failed]');

      for var Err in Errors do
        Writeln(Err);

      Halt(1);
    end;

    if Verbose then
      Writeln('[ok]');
  finally
    Errors.Free;
  end;
end;

procedure DoStamp;
var
  TargetInfo: TTargetInfo;
begin
  TParams.AddOpt(TParams.TOption.TKind.Num, 'base',  'base');
  TParams.AddOpt(TParams.TOption.TKind.Num, 'major', 'major');
  TParams.AddOpt(TParams.TOption.TKind.Num, 'minor', 'minor');
  TParams.AddOpt(TParams.TOption.TKind.Num, 'oem',   'oem');
  TParams.Process;

  if TParams.GetOpt('-h', False) then
  begin
    Writeln('Usage: nvm stamp <file.exe> [options]');
    Writeln;
    Writeln('Options:');
    PrintDefaultOptions;
    Writeln('  -base <addr>           User base address (e.g. -base 0x4E0)');
    Writeln('  -major <size>          Harness version major (defaults: 1)');
    Writeln('  -minor <size>          Harness version minor (defaults: 0)');
    Writeln('  -oem <size>            OEM memory size');

    Halt(0);
  end;

  ProcessFiles('exe');

  TargetInfo.Reset;

  TargetInfo.UserAddress  := TParams.GetOpt('base',  TargetInfo.UserAddress);
  TargetInfo.HarnessMajor := TParams.GetOpt('major', TargetInfo.HarnessMajor);
  TargetInfo.HarnessMinor := TParams.GetOpt('minor', TargetInfo.HarnessMinor);
  TargetInfo.OEMSize      := TParams.GetOpt('oem',   TargetInfo.OEMSize);

  if InputFile <> OutputFile then
    TFile.Copy(InputFile, OutputFile, True);

  if Verbose then
    Write('Stamping ', OutputFile + ' ... ');

  if not TBuildPE.WriteStubTargetInfo(OutputFile, TargetInfo) then
  begin
    //if Verbose then
      Writeln('[failed]');

    Halt(1);
  end;

  if Verbose then
    Writeln('[ok]');

  if Verbose then
  begin
    Writeln;
    Writeln('  User address: 0x', IntToHex(TargetInfo.UserAddress));
    Writeln(' Major version: ', TargetInfo.HarnessMajor);
    Writeln(' Minor version: ', TargetInfo.HarnessMinor);
    Writeln('      OEM size: ', TargetInfo.OEMSize);
  end;
end;

begin
  try
    TParams.AddOpt(TParams.TOption.TKind.Bool, 'h', 'help');
    TParams.AddOpt(TParams.TOption.TKind.Bool, 'v', 'verbose');

    TParams.AddOpt(TParams.TOption.TKind.Str,  'o', 'output');

    TParams.Process(True);

    Verbose := TParams.GetOpt('-v', False);

    //if Verbose then
    //  PrintBanner;

    if TParams.ParamCount < 1 then
    begin
      PrintBanner;
      PrintUsage;
      Halt(1);
    end;

    var tool := Lowercase(TParams.Params[0]);

         if tool = 'compile'     then DoCompile
    else if tool = 'assemble'    then DoAssemble
    else if tool = 'disassemble' then DoDisassemble
    else if tool = 'link'        then DoLink
    else if tool = 'stamp'       then DoStamp

    else
    begin
      Writeln('Unknown tool "', tool, '"');
      WRiteln;
      PrintUsage;
      Halt(1);
    end;
  except
    on E: Exception do
    begin
      Writeln('FATAL ERROR: ', E.Message);
      Halt(1);
    end;
  end;
end.
