program harness.console;

{$APPTYPE CONSOLE}

uses
  NixVM.Harness,
  NixVM.Harness.PE,
  NixVM.Harness.Timing,
  NixVM.Tools.Params in '..\src\NixVM.Tools.Params.pas';

type
  TConsoleSystemMemory = packed record

  end;

  TConsole = class(TCustomPEHarness<TConsoleSystemMemory>)
  protected
    procedure Initialize; override;
  end;

procedure TConsole.Initialize;
begin
  StopOnHalt := True;

  inherited;
end;

begin
  TConsole.Run;
end.
