{
  nvma.dpr
    NixVM Cli assembler

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

program nvma;

{$APPTYPE CONSOLE}
{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}

uses
  System.SysUtils,
  System.Classes,

  NixVM.Core.ROM,

  NixVM.Tools.IR,
  NixVM.Tools.Assembler;

procedure PrintBanner;
begin
  Writeln('NixVM Assembler v1.0');
  Writeln('Copyright (c) 2026 Nicholas Smith');
  Writeln('https://github.com/NickyNockyNu/NixVM');
  Writeln;
end;

procedure PrintUsage;
begin
  Writeln('Usage: nvma <input.asm> [options]');
  Writeln;
  Writeln('Options:');
  Writeln('  -o <file>       Specify output filename (default: <input>.nvm)');
  Writeln('  -b <address>    Base address (e.g. -b $000004E0 or -b 0x4E0)');
  Writeln('  -h <size>       Heap size (e.g. -h 1M)');
  Writeln('  -s <size>       Stack size (e.g. -s 16k)');
  Writeln('  -raw            Emit raw binary payload without ROM header');
  Writeln('  -v              Verbose information');
  Writeln('  -h, --help      Display this help screen');
  Writeln;
end;

function RunAssembler: Integer;
var
  InputFile:     String;
  OutputFile:    String;
  RawBinary:     Boolean;
  BaseOverride:  Cardinal;
  HeapOverride:  Cardinal;
  StackOverride: Cardinal;
  HasBaseOver:   Boolean;
  HasHeapOver:   Boolean;
  HasStackOver:  Boolean;
  Verbose:       Boolean;
  i:             Integer;
  Errors:        TStrings;
  Header:        TROMHeader;
  IR:            TIRList;
  CodeBytes:     TBytes;
  F:             file;
begin
  InputFile     := '';
  OutputFile    := '';
  RawBinary     := False;
  BaseOverride  := 0;
  HeapOverride  := 0;
  StackOverride := 0;
  HasBaseOver   := False;
  HasHeapOver   := False;
  HasStackOver  := False;
  Verbose       := False;

  if ParamCount = 0 then
  begin
    PrintBanner;
    PrintUsage;

    Exit(1);
  end;

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
      if i <= ParamCount then OutputFile := ParamStr(i);
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

    else if (Param = '-h') or (Param = '--heap') then
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

    else if (Param = '-s') or (Param = '--stack') then
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
    Writeln(Format('Assembling "%s" ...', [ExtractFileName(InputFile)]));
  end;

  Header.Reset;
  Errors := nil;

  IR := TAssembler.ParseFile(InputFile, Errors, @Header);

  try
    if (Errors <> nil) and (Errors.Count > 0) then
    begin
      if Verbose then
        Writeln('= ASSEMBLER ERRORS =');

      for var s in Errors do
        Writeln(s);

      Writeln;

      Exit(1);
    end;

    if HasBaseOver then
      Header.UserAddress := BaseOverride;

    if HasHeapOver then
      Header.HeapSize := HeapOverride;

    if HasStackOver then
      Header.StackSize := StackOverride;

    if not IR.ResolveLabels(Header.UserAddress, Errors) then
    begin
      if Verbose then
        Writeln('= LINKER ERRORS =');

      for var s in Errors do
        Writeln(s);

      Writeln;

      Exit(1);
    end;

    CodeBytes := IR.EmitToBytes;
    Header.UserSize := Length(CodeBytes);

    if Length(Header.ROM.Name) = 0 then
      Header.ROM.Name := ChangeFileExt(ExtractFileName(InputFile), '');

    AssignFile(F, OutputFile);
    Rewrite(F, 1);

    try
      if not RawBinary then
        BlockWrite(F, Header, SizeOf(TROMHeader));

      if Length(CodeBytes) > 0 then
        BlockWrite(F, CodeBytes[0], Length(CodeBytes));
    finally
      CloseFile(F);
    end;

    if Verbose then
    begin
      Writeln(Format('SUCCESS: Output written to "%s"', [OutputFile]));
      Writeln;
      Writeln(Format('  Base Address: $%s', [IntToHex(Header.UserAddress, 8)]));
      Writeln(Format('  Code Size:    %s bytes', [FormatFloat('#,##0', Length(CodeBytes))]));

      if not RawBinary then
      begin
        Writeln(Format('  Target:       "%s" (v%d.%d)', [Header.Harness.Name, Header.Harness.Major, Header.Harness.Minor]));
        Writeln(Format('  ROM Title:    "%s" (v%d.%d)', [Header.ROM.Name, Header.ROM.Major, Header.ROM.Minor]));
        Writeln(Format('  Heap Size:    %s bytes', [FormatFloat('#,##0', Header.HeapSize)]));
        Writeln(Format('  Stack Size:   %s bytes', [FormatFloat('#,##0', Header.StackSize)]));
      end;
    end;

    Result := 0;
  finally
    IR.Free;

    if Errors <> nil then
      Errors.Free;
  end;
end;

begin
  try
    ExitCode := RunAssembler;
  except
    on E: Exception do
    begin
      Writeln('FATAL ERROR: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
