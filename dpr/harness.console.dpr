program harness.console;

{$APPTYPE CONSOLE}
{.$R *.res}

uses
  NixVM.Core.Strings,
  NixVM.Harness,
  NixVM.Harness.PE,
  NixVM.Harness.Timing;

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
