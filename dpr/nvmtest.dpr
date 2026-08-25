program nvmtest;

{$APPTYPE CONSOLE}

uses
  NixVM.Harness;

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
end;

begin
  TTest.Run(ParamStr(1));
end.
