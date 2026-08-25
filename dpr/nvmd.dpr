{
  nvmd.dpr
    NixVM Cli disassembler

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

program nvmd;

{$APPTYPE CONSOLE}
{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,

  NixVM.Core.ROM,

  NixVM.Tools.IR,
  NixVM.Tools.Assembler,
  NixVM.Tools.Disasm;

procedure PrintBanner;
begin
  Writeln('NixVM Disassembler v1.0');
  Writeln('Copyright (c) 2026 Nicholas Smith');
  Writeln('https://github.com/NickyNockyNu/NixVM');
  Writeln;
end;

procedure PrintUsage;
begin
  Writeln('Usage: nvmd <input.nvm> [options]');
  Writeln;
  Writeln('Options:');
  Writeln('  -o <file>       Specify output filename (default: stdout)');
  Writeln('  -b <address>    Base address for raw binary (default: $000004E0)');
  Writeln('  -raw            Disassemble raw binary file without ROM header');
  Writeln('  -v              Verbose header information');
  Writeln('  -h, --help      Display this help screen');
  Writeln;
end;

function RunDisassembler: Integer;
var
  InputFile:    String;
  OutputFile:   String;
  RawBinary:    Boolean;
  BaseOverride: Cardinal;
  HasBaseOver:  Boolean;
  Verbose:      Boolean;
  i:            Integer;
  Header:       TROMHeader;
  PayloadSize:  Cardinal;
  BytesRead:    Integer;
  PayloadBytes: TBytes;
  DisasmText:   String;
  SB:           TStringBuilder;
  IR:           TIRList;
  F:            file;
begin
  InputFile    := '';
  OutputFile   := '';
  RawBinary    := False;
  BaseOverride := $000004E0;
  HasBaseOver  := False;
  Verbose      := False;

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

  Header.Reset;
  PayloadSize := 0;

  AssignFile(F, InputFile);
  Reset(F, 1);

  try
    if not RawBinary then
    begin
      BlockRead(F, Header, SizeOf(TROMHeader), BytesRead);

      if (BytesRead <> SizeOf(TROMHeader)) or not Header.IsValid then
      begin
        Writeln(Format('Error: "%s" is not a valid NixVM ROM file (use -raw for raw binaries).', [InputFile]));
        Exit(1);
      end;

      if HasBaseOver then
        Header.UserAddress := BaseOverride;

      PayloadSize := Header.UserSize;

      if PayloadSize = 0 then
        PayloadSize := FileSize(F) - SizeOf(TROMHeader);
    end
    else
    begin
      Header.UserAddress := BaseOverride;
      PayloadSize        := FileSize(F);
    end;

    SetLength(PayloadBytes, PayloadSize);

    if PayloadSize > 0 then
      BlockRead(F, PayloadBytes[0], PayloadSize, BytesRead);
  finally
    CloseFile(F);
  end;

  if Verbose then
  begin
    PrintBanner;
    Writeln(Format('Disassembling "%s" ...', [ExtractFileName(InputFile)]));
    Writeln;
    Writeln(Format('  Base Address: $%s', [IntToHex(Header.UserAddress, 8)]));
    Writeln(Format('  Code Size:    %s bytes', [FormatFloat('#,##0', PayloadSize)]));

    if not RawBinary then
    begin
      Writeln(Format('  Target:       "%s" (v%d.%d)', [Header.Harness.Name, Header.Harness.Major, Header.Harness.Minor]));
      Writeln(Format('  ROM Title:    "%s" (v%d.%d)', [Header.ROM.Name, Header.ROM.Major, Header.ROM.Minor]));
      Writeln(Format('  Heap Size:    %s bytes', [FormatFloat('#,##0', Header.HeapSize)]));
      Writeln(Format('  Stack Size:   %s bytes', [FormatFloat('#,##0', Header.StackSize)]));
    end;

    Writeln;
  end;

  IR := TDisassembler.Disassemble(PayloadBytes, Header.UserAddress);

  try
    SB := TStringBuilder.Create;

    try
      if not RawBinary then
      begin
        SB.AppendLine('; ==============================================================================');
        SB.AppendLine('; Disassembled by nvmd v1.0');
        SB.AppendLine(Format('; ROM:    %s (v%d.%d)', [Header.ROM.Name, Header.ROM.Major, Header.ROM.Minor]));
        SB.AppendLine(Format('; Target: %s (v%d.%d)', [Header.Harness.Name, Header.Harness.Major, Header.Harness.Minor]));
        SB.AppendLine('; ==============================================================================');
        SB.AppendLine;

        if Length(Header.Harness.Name) > 0 then
          SB.AppendLine(Format('.target'#9'"%s", %d, %d', [Header.Harness.Name, Header.Harness.Major, Header.Harness.Minor]));

        if Length(Header.ROM.Name) > 0 then
          SB.AppendLine(Format('.name'#9'"%s"', [Header.ROM.Name]));

        if (Header.ROM.Major > 0) or (Header.ROM.Minor > 0) then
          SB.AppendLine(Format('.version'#9'%d, %d', [Header.ROM.Major, Header.ROM.Minor]));

        SB.AppendLine(Format('.base'#9'$%s', [IntToHex(Header.UserAddress, 0)]));

        if Header.HeapSize > 0 then
          SB.AppendLine(Format('.heap'#9'%d', [Header.HeapSize]));

        if Header.StackSize > 0 then
          SB.AppendLine(Format('.stack'#9'%d', [Header.StackSize]));

        SB.AppendLine;
      end;

      SB.Append(IR.ToString);
      DisasmText := SB.ToString;
    finally
      SB.Free;
    end;

    if Length(OutputFile) > 0 then
    begin
      TFile.WriteAllText(OutputFile, DisasmText);

      if Verbose then
        Writeln(Format('Disassembly written to "%s"', [OutputFile]));
    end
    else
    begin
      Write(DisasmText);
    end;

    Result := 0;
  finally
    IR.Free;
  end;
end;

begin
  try
    ExitCode := RunDisassembler;
  except
    on E: Exception do
    begin
      Writeln('FATAL ERROR: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
