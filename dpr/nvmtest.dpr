program nvmtest;

{$APPTYPE CONSOLE}

uses
  NixVM.Harness,
  NixVM.Harness.Timing;

type
  TTestSystemMemory = packed record

  end;

  TTest = class(TCustomHarness<TTestSystemMemory>)
  protected
    procedure Initialize; override;
  end;

procedure TTest.Initialize;
begin
  inherited;
  StopOnHalt := True;
end;

begin
  //Writeln(TTest.GenTargetInc);
  TTest.Run(ParamStr(1));
end.
