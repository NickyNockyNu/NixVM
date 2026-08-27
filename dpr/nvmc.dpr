{
  nvmc.dpr
    NixVM Cli Pascal compiler

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

program nvmc;

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

  NixVM.Tools.IR,
  NixVM.Tools.Assembler,
  NixVM.Tools.Disasm,
  NixVM.Tools.Compiler,

  NixVM.Tools.Compiler.Lexer,
  NixVM.Tools.Compiler.AST,
  NixVM.Tools.Compiler.Parser,
  NixVM.Tools.Compiler.Semantics,
  NixVM.Tools.Compiler.CodeGen;

procedure PrintBanner;
begin
  Writeln('NixVM Pascal Compiler v1.0');
  Writeln('Copyright (c) 2026 Nicholas Smith');
  Writeln('https://github.com/NickyNockyNu/NixVM');
  Writeln;
end;

procedure PrintUsage;
begin
  Writeln('Usage: nvmc <input.pas> [options]');
  Writeln;
  Writeln('Options:');
  Writeln('  -o <file>       Specify output filename (default: <input>.nvm)');
  Writeln('  -I <path>       Add unit search directory');
  Writeln('  -s <file>       Save intermediate assembly source (.asm)');
  Writeln('  -l <file>       Save linked assembly listing (.lst)');
  Writeln('  -heap <size>    Override Heap size (e.g. -heap 128k, -heap $20000)');
  Writeln('  -stack <size>   Override Stack size (e.g. -stack 32k, -stack $8000)');
  Writeln('  -b <address>    Override base address (e.g. -b $000004E0)');
  Writeln('  -raw            Emit raw binary payload without ROM header');
  Writeln('  -v              Verbose compilation info');
  Writeln('  -h, --help      Display this help screen');
  Writeln;
end;

function RunCompiler: Integer;
var
  InputFile:     String;
  OutputFile:    String;
  AsmFile:       String;
  ListingFile:   String;
  RawBinary:     Boolean;
  Verbose:       Boolean;
  BaseOverride:  Cardinal;
  HeapOverride:  Cardinal;
  StackOverride: Cardinal;
  HasBaseOver:   Boolean;
  HasHeapOver:   Boolean;
  HasStackOver:  Boolean;
  i:             Integer;
  Compiler:      TCompiler;
begin
  InputFile     := '';
  OutputFile    := '';
  AsmFile       := '';
  ListingFile   := '';
  RawBinary     := False;
  Verbose       := False;
  BaseOverride  := 0;
  HeapOverride  := 0;
  StackOverride := 0;
  HasBaseOver   := False;
  HasHeapOver   := False;
  HasStackOver  := False;

  if ParamCount = 0 then
  begin
    PrintBanner;
    PrintUsage;
    Exit(1);
  end;

  Compiler := TCompiler.Create;

  try
    i := 1;

    while i <= ParamCount do
    begin
      var Param := ParamStr(i);

      if (Param = '-h') or (Param = '--help') or (Param = '/?') then
      begin
        PrintBanner;
        PrintUsage;

        Exit(0);
      end

      else if Param = '-raw' then
        RawBinary := True

      else if (Param = '-v') or (Param = '--verbose') then
        Verbose := True

      else if Param = '-o' then
      begin
        Inc(i);

        if i <= ParamCount then
          OutputFile := ParamStr(i);
      end

      else if (Param = '-I') or (Param = '-i') then
      begin
        Inc(i);

        if i <= ParamCount then
          Compiler.SearchPaths.Add(ParamStr(i));
      end

      else if Param = '-s' then
      begin
        Inc(i);

        if i <= ParamCount then
          AsmFile := ParamStr(i);
      end

      else if Param = '-l' then
      begin
        Inc(i);

        if i <= ParamCount then
          ListingFile := ParamStr(i);
      end

      else if (Param = '-b') or (Param = '--base') then
      begin
        Inc(i);
        if i <= ParamCount then
        begin
          var BaseStr := ParamStr(i);

          if not TAssembler.ParseNumber(BaseStr, BaseOverride) then
          begin
            Writeln('Invalid base address: ', BaseStr);
            Exit(1);
          end;

          HasBaseOver := True;
        end;
      end

      else if (Param = '-heap') or (Param = '--heap') then
      begin
        Inc(i);

        if i <= ParamCount then
        begin
          var HeapStr := ParamStr(i);

          if not TAssembler.ParseNumber(HeapStr, HeapOverride) then
          begin
            Writeln('Invalid heap size: ', HeapStr);
            Exit(1);
          end;

          HasHeapOver := True;
        end;
      end

      else if (Param = '-stack') or (Param = '--stack') then
      begin
        Inc(i);

        if i <= ParamCount then
        begin
          var StackStr := ParamStr(i);

          if not TAssembler.ParseNumber(StackStr, StackOverride) then
          begin
            Writeln('Invalid stack size: ', StackStr);
            Exit(1);
          end;

          HasStackOver := True;
        end;
      end

      else if (Length(Param) > 0) and (Param[1] <> '-') then
        InputFile := Param;

      Inc(i);
    end;

    if Length(InputFile) = 0 then
    begin
      Writeln('No input file specified.');
      Exit(1);
    end;

    if not FileExists(InputFile) then
    begin
      Writeln(Format('Input file not found: "%s"', [InputFile]));
      Exit(1);
    end;

    if Length(OutputFile) = 0 then
    begin
      if RawBinary then
        OutputFile := ChangeFileExt(InputFile, '.bin')
      else
        OutputFile := ChangeFileExt(InputFile, '.nvm');
    end;

    if Verbose then
    begin
      PrintBanner;
      Writeln(Format('Compiling "%s" ...', [ExtractFileName(InputFile)]));
    end;

    if not Compiler.CompileFile(InputFile) then
    begin
      if Verbose then
        Writeln('= COMPILATION ERRORS =');

      for var Err in Compiler.Errors do
        Writeln(Err);

      Writeln;
      Exit(1);
    end;

    if Length(AsmFile) > 0 then
      TFile.WriteAllText(AsmFile, Compiler.IR.ToString);

    if HasBaseOver then
      Compiler.ROMHeader.UserAddress := BaseOverride;

    if HasHeapOver then
      Compiler.ROMHeader.HeapSize := HeapOverride;

    if HasStackOver then
      Compiler.ROMHeader.StackSize := StackOverride;

    if not Compiler.Link(OutputFile, not RawBinary) then
    begin
      if Verbose then
        Writeln('= LINKER ERRORS =');

      for var Err in Compiler.Errors do
        Writeln(Err);

      Writeln;
      Exit(1);
    end;

    if Length(ListingFile) > 0 then
      TFile.WriteAllText(ListingFile, Compiler.IR.ToString);

    if Verbose then
    begin
      Writeln(Format('SUCCESS: Cartridge written to "%s"', [OutputFile]));
      Writeln;
      Writeln(Compiler.ROMHeader.ToString);
    end;

    Result := 0;
  finally
    Compiler.Free;
  end;
end;

begin
  try
    ExitCode := RunCompiler;
  except
    on E: Exception do
    begin
      Writeln('FATAL ERROR: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
