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

{
  TODO:

  Language features:

    "packed" for records (They are now packed by default, they used to be aligned so it should be easy to add)

    labled for (for continue and break)
      or contine and break can take the "for variable" as a parameter. eg:
        for var y := 0 to 99 do
          for var x := 0 to 99 do
            if someexitcondition then break y;
      ... or named block `begin is name` and a `break name;`

  Compiler:

    TCodeGenerator.GenCallExpr - More checks for literal arguments (see `_bsetf` etc)

  This tool:

    Stubfile elimnation on non windows targets
    Finish up the "gen" tool and GenUnits

  Core features:

  IDE (WiP):

    Keyword: raise, SetLength,
    So big it requires it's own TODO list (see the nvmide source for the TODO list)

  Other possible languages (way down the line):

    C-like with extended language features:
       Structs with method and property support
       Managed strings
       Dynamic managed arrays

    BASIC (QB45-like) with extended language features

}

{$APPTYPE CONSOLE}
{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}

uses
{$IF DEFINED(MSWINDOWS)}
  Winapi.Windows,
  Winapi.ShellAPI,
{$ELSE IF DEFINED(POSIX)}
  Posix.Stdlib,
{$ENDIF}
  System.SysUtils,
  System.Classes,
  System.IOUtils,

  NixVM.Core.Registers,
  NixVM.Core.Instructions,
  NixVM.Core.Strings,
  NixVM.Core.Memory,
  NixVM.Core.System,
  NixVM.Core.ROM,

  NixVM.Harness,

  NixVM.Tools.GenUnits,
  NixVM.Tools.Params,
  NixVM.Tools.IR,
  NixVM.Tools.Assembler,
  NixVM.Tools.Disasm,
{$IF DEFINED(MSWINDOWS)}
  NixVM.Tools.BuildPE,
{$ENDIF}
  NixVM.Tools.Compiler,
  NixVM.Tools.Compiler.Lexer,
  NixVM.Tools.Compiler.AST,
  NixVM.Tools.Compiler.Parser,
  NixVM.Tools.Compiler.Semantics,
  NixVM.Tools.Compiler.CodeGen;

type
  TConsoleMemory = record

  end;

  TConsole = class(TCustomHarness<TConsoleMemory>)
  protected
    procedure Initialize; override;
  end;

procedure TConsole.Initialize;
begin
  StopOnHalt := True;

  inherited;
end;

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

procedure PrintDefaultOptions(AOutput: Boolean = True);
begin
  Writeln('  -h, --help             Display usage (e.g. nvm compile --help)');
  Writeln('  -v, --verbose          Verbose output');

  if AOutput then
    Writeln('  -o, --output <file>    Specify output file');
end;

procedure PrintBuildOptions;
begin
{$IF DEFINED(MSWINDOWS)}
  Writeln('  -x, --exe              Build executable file');
{$ENDIF}
  Writeln('  -t, --target <name>    Override target');
  Writeln('  -z, --optimize         Optimise output');
  Writeln('  -base <addr>           Override base address (e.g. -base 0x4E0)');
  Writeln('  -heap <size>           Override heap size (e.g. -heap 128k, -heap $20000)');
  Writeln('  -stack <size>          Override stack size');
{$IF DEFINED(MSWINDOWS)}
  Writeln('  -i, --icon <file.ico>  Override the executables icon');
  Writeln('  -vi, --version         Emit version information in executable (disable with -vi-)');
{$ENDIF}
  Writeln('  -r, --run              Run the output on successful build');
end;

procedure AddBuildOptions;
begin
  TParams.AddOpt(TParams.TOption.TKind.Bool, 'z',  'optimize');

  TParams.AddOpt(TParams.TOption.TKind.Num, 'base',  'base');
  TParams.AddOpt(TParams.TOption.TKind.Num, 'heap',  'heap');
  TParams.AddOpt(TParams.TOption.TKind.Num, 'stack', 'stack');

  TParams.AddOpt(TParams.TOption.TKind.Str, 't', 'target');

{$IF DEFINED(MSWINDOWS)}
  TParams.AddOpt(TParams.TOption.TKind.Bool, 'x', 'exe');

  TParams.AddOpt(TParams.TOption.TKind.Str, 'i', 'icon');

  TParams.AddOpt(TParams.TOption.TKind.Bool, 'vi', 'version');
{$ENDIF}

  TParams.AddOpt(TParams.TOption.TKind.Bool, 'r', 'run');
end;

procedure PrintUsage;
begin
  Writeln('Usage: nvm <compile|assemble|disassemble|link|stamp|info|run> <file> [options]');
  Writeln;
  Writeln('General options:');
  PrintDefaultOptions(False);
  Writeln;
  Writeln('For tool specific options use:');
  Writeln('  nvm --help <compile|assemble|disassemble|link|stamp|info|run>');
  Writeln;
end;

procedure ProcessFiles(const AOutExt: String; const AInExt: String = '');
begin
  InputFile  := TParams.Params[1];
  OutputFile := TParams.GetOpt('-o', ChangeFileExt(InputFile, '.' + AOutExt));

  if not FileExists(InputFile) then
  begin
    if Length(AInExt) > 0 then
    begin
      var NewFile := ChangeFileExt(InputFile, '.' + AInExt);

      if FileExists(NewFile) then
      begin
        InputFIle := NewFile;
        Exit;
      end;
    end;

    Writeln('File does not exist: ', InputFile);
    Halt(1);
  end;
end;

procedure Execute(const AExe, AParams: String);
var
  CommandLine: String;
{$IF DEFINED(MSWINDOWS)}
  SI: TStartupInfo;
  PI: TProcessInformation;
begin
  if Length(AParams) > 0 then
    CommandLine := '"' + AExe + '" ' + AParams
  else
    CommandLine := '"' + AExe + '"';

  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);

  if Verbose then
    Writeln(#13#10'Executing ' + CommandLine + #13#10);

  var Result := CreateProcess(nil, PChar(CommandLine), nil, nil, True, 0, nil, nil, SI, PI);

  if Result then
    try
      WaitForSingleObject(PI.hProcess, INFINITE);
      //GetExitCodeProcess(PI.hProcess, ExitCode);
    finally
      CloseHandle(PI.hThread);
      CloseHandle(PI.hProcess);
    end
  else if Verbose then
    Writeln('Failed to create process');

  //ShellExecute(0, 'open', PChar(AExe), PChar(AParams), nil, SW_SHOWNORMAL);
{$ELSE IF DEFINED(POSIX)}
begin
  if Length(AParams) > 0 then
    CommandLine := AExe + ' ' + AParams
  else
    CommandLine := AExe;

  if Verbose then
    Writeln(#13#10'Executing ' + CommandLine + #13#10);

  _wsystem(PAnsiChar(UTF8Encode(CommandLine)));
{$ENDIF}
end;

procedure DoCompile;
var
  Compiler:    TCompiler;
  Assemble:    Boolean;
  Build:       Boolean;
  TargetInfo:  TTargetInfo;
  StubFile:    String;
  VersionInfo: TVersionInfo;
begin
  AddBuildOptions;
  TParams.AddOpt(TParams.TOption.TKind.Bool, 'a', 'assemble');

  TParams.Process;

  Assemble := TParams.GetOpt('-a', False);
{$IF DEFINED(MSWINDOWS)}
  Build := TParams.GetOpt('-x', False);
{$ELSE}
  Build := False;
{$ENDIF}

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
    ProcessFiles('asm', 'pas')
  else if Build then
    ProcessFiles('exe', 'pas')
  else
    ProcessFiles('nvm', 'pas');

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

    if Length(Compiler.ROMHeader.Harness.Name) > 0 then
      StubFile := TParams.GetOpt('-t', Compiler.ROMHeader.Harness.Name)
    else
      StubFile := TParams.GetOpt('-t', 'console');

    if Verbose then
      Writeln('Target: ', StubFile);

    // TODO: Can only do this on windows
    StubFile := TPath.Combine(ExtractFilePath(ParamStr(0)), 'harness.' + StubFile + '.exe');

    if FileExists(StubFile) then
    begin
      if Verbose then
        Write('Reading target information ... ');

      if not TBuildPE.ReadStubTargetInfo(StubFile, TargetInfo) then
      begin
        if Verbose then
          Writeln('[failed]');

        Writeln(StubFile);
        Writeln('Failed to read target information');
        Halt(1);
      end;

      if Verbose then
        Writeln('[ok]');

      if Compiler.ROMHeader.UserAddress = 0 then
        Compiler.ROMHeader.UserAddress := TargetInfo.UserAddress;

      if (Compiler.ROMHeader.Harness.Major > TargetInfo.HarnessMajor) or ((Compiler.ROMHeader.Harness.Major = TargetInfo.HarnessMajor) and (Compiler.ROMHeader.Harness.Minor > TargetInfo.HarnessMinor)) then
      begin
        Writeln(Format('Program requires target "%s" v%d.%d, but harness is v%d.%d', [Compiler.ROMHeader.Harness.Name, Compiler.ROMHeader.Harness.Major, Compiler.ROMHeader.Harness.Minor, TargetInfo.HarnessMajor, TargetInfo.HarnessMinor]));
        Halt(1);
      end;
    end
    else
    begin
      if Verbose then
        Writeln('Warning: target harness does not exist');

      if Compiler.ROMHeader.UserAddress = 0 then
        Compiler.ROMHeader.UserAddress := (SizeOf(TCoreSystemMemory) + 3) and not Cardinal(3);
    end;

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
{$IF DEFINED(MSWINDOWS)}
    else if Build then
    begin
      var ROMStream := TBytesStream.Create;

      try
        if Verbose then
          Write('Linking ', OutputFile, ' ... ');

        if not Compiler.Link(ROMStream, True) then
        begin
          if Verbose then
            Writeln('[failed]');

          for var Err in Compiler.Errors do
            Writeln(Err);

          Halt(1);
        end;

        if Verbose then
          Writeln('[ok]');

        var CodeBytes := ROMStream.Bytes;
        SetLength(CodeBytes, ROMStream.Size);

        var Errors := TStringList.Create;

        try
          if Verbose then
            Write('Embedding NVM ... ');

          if not TBuildPE.EmbedROMData(StubFile, CodeBytes, OutputFile, TBuildPE.DefaultResourceName, Errors) then
          begin
            if Verbose then
              Writeln('[failed]');

            for var Err in Errors do
              Writeln(Err);

            Halt(1);
          end;

          if Verbose then
            Writeln('[ok]');

          Compiler.IconFile := TParams.GetOpt('-i', Compiler.IconFile);

          if Length(Compiler.IconFile) > 0 then
          begin
            if Verbose then
              Write('Embedding Icon ... ');

            if not TBuildPE.AddIcon(OutputFile, Compiler.IconFile, 'MAINICON', Errors) then
            begin
              if Verbose then
                Writeln('[failed]');

              for var Err in Errors do
                Writeln(Err);

              Halt(1);
            end;

            if Verbose then
              Writeln('[ok]');
          end;

          if TParams.GetOpt('-vi', True) then
          begin
            if Verbose then
              Write('Embedding VersionInfo ... ');

            VersionInfo := TVersionInfo.FromROMHeader(Compiler.ROMHeader);

            if Length(Compiler.Description) > 0 then
              VersionInfo.FileDescription := Compiler.Description;

            if Length(Compiler.Copyright) > 0 then
              VersionInfo.LegalCopyright := Compiler.Copyright;

            if not TBuildPE.AddVersionInfo(OutputFile, VersionInfo, Errors) then
            begin
              if Verbose then
                Writeln('[failed]');

              for var Err in Errors do
                Writeln(Err);

              Halt(1);
            end;

            if Verbose then
              Writeln('[ok]');

            if Verbose then
            begin
              Writeln;
              Writeln('-- Version information ----------------------------');
              Writeln(VersionInfo.ToString);
            end;
          end;
        finally
          Errors.Free;
        end;
      finally
        ROMStream.Free;
      end;
    end
{$ENDIF}
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
      Writeln('-- ROM information --------------------------------');
      Writeln(Compiler.ROMHeader.ToString);

      if Compiler.Optimise then
        Writeln('Optimisations: ', Compiler.SizeBeforeOpt, ' -> ', Compiler.SizeAfterOpt);
    end;
  finally
    Compiler.Free;
  end;

  if TParams.GetOpt('-r', False) then
  begin
    if Build then
      Execute(OutputFile, '')
    else
      Execute(StubFile, OutputFile);
  end;
end;

procedure DoAssemble;
var
  &Assembler:  TAssembler;
  RawBinary:   Boolean;
  Build:       Boolean;
  TargetInfo:  TTargetInfo;
  StubFile:    String;
  VersionInfo: TVersionInfo;
begin
  AddBuildOptions;
  TParams.AddOpt(TParams.TOption.TKind.Bool, 'r', 'raw');
  TParams.Process;

  RawBinary := TParams.GetOpt('-r', False);

{$IF DEFINED(MSWINDOWS)}
  Build := TParams.GetOpt('-x', False);
{$ELSE}
  Build := False;
{$ENDIF}

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

  if RawBinary then
    ProcessFiles('bin', 'asm')
  else if Build then
    ProcessFiles('exe', 'asm')
  else
    ProcessFiles('nvm', 'asm');

  &Assembler := TAssembler.Create;
  &Assembler.Optimise := TParams.GetOpt('-z', &Assembler.Optimise);

  try
    if Verbose then
      Write('Assembling ', InputFile, ' ... ');

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

    if Length(&Assembler.ROMHeader.Harness.Name) > 0 then
      StubFile := TParams.GetOpt('-t', &Assembler.ROMHeader.Harness.Name)
    else
      StubFile := TParams.GetOpt('-t', 'console');

    if Verbose then
      Writeln('Target: ', StubFile);


    // TODO: Can't do this on non windows platforms
    StubFile := TPath.Combine(ExtractFilePath(ParamStr(0)), 'harness.' + StubFile + '.exe');

    if FileExists(StubFile) then
    begin
      if Verbose then
        Write('Reading target information ... ');

      if not TBuildPE.ReadStubTargetInfo(StubFile, TargetInfo) then
      begin
        if Verbose then
          Writeln('[failed]');

        Writeln(StubFile);
        Writeln('Failed to read target information');
        Halt(1);
      end;

      if Verbose then
        Writeln('[ok]');

      if &Assembler.ROMHeader.UserAddress = 0 then
        &Assembler.ROMHeader.UserAddress := TargetInfo.UserAddress;

      if (&Assembler.ROMHeader.Harness.Major > TargetInfo.HarnessMajor) or ((&Assembler.ROMHeader.Harness.Major = TargetInfo.HarnessMajor) and (&Assembler.ROMHeader.Harness.Minor > TargetInfo.HarnessMinor)) then
      begin
        Writeln(Format('Program requires target "%s" v%d.%d, but harness is v%d.%d', [&Assembler.ROMHeader.Harness.Name, &Assembler.ROMHeader.Harness.Major, &Assembler.ROMHeader.Harness.Minor, TargetInfo.HarnessMajor, TargetInfo.HarnessMinor]));

        Halt(1);
      end;
    end
    else
    begin
      if Verbose then
        Writeln('Warning: target harness does not exist');

      if &Assembler.ROMHeader.UserAddress = 0 then
        &Assembler.ROMHeader.UserAddress := (SizeOf(TCoreSystemMemory) + 3) and not Cardinal(3);
    end;

    &Assembler.ROMHeader.UserAddress := TParams.GetOpt('-base',  &Assembler.ROMHeader.UserAddress);
    &Assembler.ROMHeader.HeapSize    := TParams.GetOpt('-heap',  &Assembler.ROMHeader.HeapSize);
    &Assembler.ROMHeader.StackSize   := TParams.GetOpt('-stack', &Assembler.ROMHeader.StackSize);


    if Build then
    begin
      var ROMStream := TBytesStream.Create;
      try
        if Verbose then
          Write('Linking ', OutputFile, ' ... ');

        if not &Assembler.Link(ROMStream, True) then
        begin
          if Verbose then
            Writeln('[failed]');

          for var Err in &Assembler.Errors do
            Writeln(Err);

          Halt(1);
        end;

        if Verbose then
          Writeln('[ok]');

        var CodeBytes := ROMStream.Bytes;
        SetLength(CodeBytes, ROMStream.Size);

        var Errors := TStringList.Create;

        try
          if Verbose then
            Write('Embedding NVM ... ');

          if not TBuildPE.EmbedROMData(StubFile, CodeBytes, OutputFile, TBuildPE.DefaultResourceName, Errors) then
          begin
            if Verbose then
              Writeln('[failed]');

            for var Err in Errors do
              Writeln(Err);

            Halt(1);
          end;

          if Verbose then
            Writeln('[ok]');

          &Assembler.IconFile := TParams.GetOpt('-i', &Assembler.IconFile);

          if Length(&Assembler.IconFile) > 0 then
          begin
            if Verbose then
              Write('Embedding Icon ... ');

            if not TBuildPE.AddIcon(OutputFile, &Assembler.IconFile, 'MAINICON', Errors) then
            begin
              if Verbose then
                Writeln('[failed]');

              for var Err in Errors do
                Writeln(Err);

              Halt(1);
            end;

            if Verbose then
              Writeln('[ok]');
          end;

          if TParams.GetOpt('-vi', True) then
          begin
            if Verbose then
              Write('Embedding VersionInfo ... ');

            VersionInfo := TVersionInfo.FromROMHeader(&Assembler.ROMHeader);

            if Length(&Assembler.Description) > 0 then
              VersionInfo.FileDescription := &Assembler.Description;

            if Length(&Assembler.Copyright) > 0 then
              VersionInfo.LegalCopyright := &Assembler.Copyright;

            if not TBuildPE.AddVersionInfo(OutputFile, VersionInfo, Errors) then
            begin
              if Verbose then
                Writeln('[failed]');

              for var Err in Errors do
                Writeln(Err);

              Halt(1);
            end;

            if Verbose then
              Writeln('[ok]');

            if Verbose then
            begin
              Writeln;
              Writeln('-- Version information ----------------------------');
              Writeln(VersionInfo.ToString);
            end;
          end;
        finally
          Errors.Free;
        end;
      finally
        ROMStream.Free;
      end;
    end
    else
    begin
      if Verbose then
        Write('Linking ', OutputFile, ' ... ');

      if not &Assembler.Link(OutputFile, not RawBinary) then
      begin
        if Verbose then
          Writeln('[failed]');

        for var Err in &Assembler.Errors do
          Writeln(Err);

        Halt(1);
      end;

      if Verbose then
        Writeln('[ok]');
    end;

    if Verbose then
    begin
      Writeln;
      Writeln('-- ROM information --------------------------------');
      Writeln(&Assembler.ROMHeader.ToString);

      if &Assembler.Optimise then
        Writeln('Optimisations: ', &Assembler.SizeBeforeOpt, ' -> ', &Assembler.SizeAfterOpt);
    end;
  finally
    &Assembler.Free;
  end;

  if TParams.GetOpt('-r', False) then
  begin
    if Build then
      Execute(OutputFile, '')
    else
      Execute(StubFile, OutputFile);
  end;
end;

procedure DoDisassemble;
var
  Disassembler: TDisassembler;
  Success:      Boolean;
  ROMBytes:     TBytes;
  IsRaw:        Boolean;
begin
  TParams.AddOpt(TParams.TOption.TKind.Bool, 'r',     'raw');
  TParams.AddOpt(TParams.TOption.TKind.Num,  'base',  'base');
  TParams.Process;

  Success := False;

  if TParams.GetOpt('-h', False) or (TParams.ParamCount < 2) then
  begin
    Writeln('Usage: nvm disassemble <file.nvm|file.exe|file.bin> [options]');
    Writeln;
    Writeln('Options:');
    PrintDefaultOptions;
    Writeln('  -r, --raw              Raw binary input (no header)');
    Writeln('  -base <addr>           Override base address for raw binary (e.g. -base 0x4E0)');

    Halt(0);
  end;

  ProcessFiles('asm', 'nvm');

  Disassembler := TDisassembler.Create;

  try
    if Verbose then
      Write('Disassembling ', InputFile + ' ... ');

    IsRaw := TParams.GetOpt('-r', False);
    Disassembler.EmitDirectives := not IsRaw;

    if not IsRaw and (SameText(ExtractFileExt(InputFile), '.exe') or TBuildPE.HasEmbeddedROM(InputFile)) then
    begin
      if TBuildPE.ExtractROM(InputFile, ROMBytes) then
      begin
        var MS := TBytesStream.Create(ROMBytes);

        try
          Success := Disassembler.Disassemble(MS);
        finally
          MS.Free;
        end;
      end
      else
      begin
        if Verbose then
          Writeln('[failed]');

        Writeln('No embedded ROM resource found inside executable: ', InputFile);
        Halt(1);
      end;
    end

    else if Disassembler.EmitDirectives then
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
  Header:      TROMHeader;
  StubFile:    String;
  VersionInfo: TVersionInfo;
  IconFile:    String;
begin
  TParams.AddOpt(TParams.TOption.TKind.Str,  't',  'target');
  TParams.AddOpt(TParams.TOption.TKind.Str,  'i',  'icon');
  TParams.AddOpt(TParams.TOption.TKind.Bool, 'vi', 'version');
  TParams.Process;

  if TParams.GetOpt('-h', False) or (TParams.ParamCount < 2) then
  begin
    Writeln('Usage: nvm link <file.nvm> [options]');
    Writeln;
    Writeln('Options:');
    PrintDefaultOptions;
    Writeln('  -i, --icon <file.ico>  Set executable icon');
    Writeln('  -vi, --version         Emit version information in executable (disable with -vi-)');
    Writeln('  -t, --target <name>    Override target');

    Halt(0);
  end;

  ProcessFiles('exe', 'nvm');

  if Verbose then
    Write('Reading ', InputFile, ' ... ');

  if not Header.Load(InputFile) then
  begin
    if Verbose then
      Writeln('[failed]');

    Writeln('Failed to read nvm header');

    Halt(1);
  end;

  if Verbose then
    Writeln('[ok]');

  StubFile := TParams.GetOpt('-t', Header.Harness.Name);

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


    IconFile := TParams.GetOpt('-i', '');

    if Length(IconFile) > 0 then
    begin
      if Verbose then
        Write('Embedding Icon ... ');

      if not TBuildPE.AddIcon(OutputFile, IconFile, 'MAINICON', Errors) then
      begin
        if Verbose then
          Writeln('[failed]');

        for var Err in Errors do
          Writeln(Err);

        Halt(1);
      end;

      if Verbose then
        Writeln('[ok]');
    end;

    if TParams.GetOpt('-vi', True) then
    begin
      if Verbose then
        Write('Embedding VersionInfo ... ');

      VersionInfo := TVersionInfo.FromROMHeader(Header);

      if not TBuildPE.AddVersionInfo(OutputFile, VersionInfo, Errors) then
      begin
        if Verbose then
          Writeln('[failed]');

        for var Err in Errors do
          Writeln(Err);

        Halt(1);
      end;

      if Verbose then
        Writeln('[ok]');

      if Verbose then
      begin
        Writeln;
        Writeln('-- Version information ----------------------------');
        Writeln(VersionInfo.ToString);
      end;
    end;

    if Verbose then
    begin
      Writeln;
      Writeln('-- ROM information --------------------------------');
      Writeln(Header.ToString);
    end;
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

  ProcessFiles('exe', 'exe');

  TargetInfo.Reset;

  if TParams.GetOpt('t', False) then
    Writeln('true');

  TargetInfo.UserAddress  := TParams.GetOpt('-base',  TargetInfo.UserAddress);
  TargetInfo.HarnessMajor := TParams.GetOpt('-major', TargetInfo.HarnessMajor);
  TargetInfo.HarnessMinor := TParams.GetOpt('-minor', TargetInfo.HarnessMinor);
  TargetInfo.OEMSize      := TParams.GetOpt('-oem',   TargetInfo.OEMSize);

  if InputFile <> OutputFile then
    TFile.Copy(InputFile, OutputFile, True);

  if Verbose then
    Write('Stamping ', OutputFile + ' ... ');

  if not TBuildPE.WriteStubTargetInfo(OutputFile, TargetInfo) then
  begin
    if Verbose then
      Writeln('[failed]');

    Writeln('Failed to write target information');

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

procedure DoInfo;
var
  Header:     TROMHeader;
  TargetInfo: TTargetInfo;
  ROMBytes:   TBytes;
  IsExe:      Boolean;
  HasTarget:  Boolean;
  HasROM:     Boolean;
begin
  TParams.Process;

  if TParams.GetOpt('-h', False) or (TParams.ParamCount < 2) then
  begin
    Writeln('Usage: nvm info <file.nvm|file.exe>');
    Writeln;
    Writeln('Options:');
    PrintDefaultOptions(False);

    Halt(0);
  end;

  InputFile := TParams.Params[1];

  if not FileExists(InputFile) then
  begin
    Writeln('File does not exist: ', InputFile);
    Halt(1);
  end;

  IsExe     := SameText(ExtractFileExt(InputFile), '.exe');
  HasROM    := False;

  Writeln('File: ', InputFile);
  Writeln('Size: ', TFile.GetSize(InputFile), ' bytes');

  if IsExe then
  begin
    HasTarget := TBuildPE.ReadStubTargetInfo(InputFile, TargetInfo);

    if HasTarget then
    begin
      Writeln;
      Writeln('Target Harness Information:');
      Writeln('    User Address: 0x', IntToHex(TargetInfo.UserAddress, 8));
      Writeln('  Target Version: v', TargetInfo.HarnessMajor, '.', TargetInfo.HarnessMinor);
      Writeln('        OEM Size: ', TargetInfo.OEMSize, ' bytes');
    end;

    if TBuildPE.ExtractROM(InputFile, ROMBytes) and (Length(ROMBytes) >= SizeOf(TROMHeader)) then
    begin
      Header := PROMHeader(@ROMBytes[0])^;

      if Header.IsValid then
      begin
        Writeln;
        Writeln('Embedded Cartridge ROM:');
        Writeln(Header.ToString);

        HasROM := True;
      end;
    end;

    if not HasTarget and not HasROM then
      Writeln('No NixVM target metadata or embedded ROM found in this executable.');
  end
  else
  begin
    var FS := TFileStream.Create(InputFile, fmOpenRead or fmShareDenyNone);

    try
      if (FS.Size >= SizeOf(TROMHeader)) and Header.Load(InputFile) then
      begin
        Writeln;
        Writeln('Cartridge ROM Information:');
        Writeln(Header.ToString);
      end
      else
        Writeln('File is not a valid NixVM ROM.');
    finally
      FS.Free;
    end;
  end;
end;

procedure DoRun;
begin
  if TParams.GetOpt('-h', False) or (TParams.ParamCount < 2) then
  begin
    Writeln('Usage: nvm run <file.nvm>');
    Writeln;
    Writeln('Runs an .nvm file using a built-in "console" target');
    Halt(0);
  end;

  ProcessFiles('nvm', 'nvm');

  TConsole.Run(InputFile);
end;

procedure DoGenUnits;
begin
  Writeln(TGenUnits.GetSysConst);
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
    else if tool = 'info'        then DoInfo
    else if tool = 'gen'         then DoGenUnits
    else if tool = 'run'         then DoRun
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
