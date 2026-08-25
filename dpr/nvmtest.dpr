program nvmtest;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.Classes,
  NixVM.Core.Strings in '..\src\NixVM.Core.Strings.pas',
  NixVM.Core.CPU in '..\src\NixVM.Core.CPU.pas',
  NixVM.Core.Instructions in '..\src\NixVM.Core.Instructions.pas',
  NixVM.Core.Memory in '..\src\NixVM.Core.Memory.pas',
  NixVM.Core.Registers in '..\src\NixVM.Core.Registers.pas',
  NixVM.Core.System in '..\src\NixVM.Core.System.pas',
  NixVM.Harness in '..\src\NixVM.Harness.pas',
  NixVM.Harness.Timing in '..\src\NixVM.Harness.Timing.pas',
  NixVM.Harness.Window in '..\src\NixVM.Harness.Window.pas',
  NixVM.Tools.IR in '..\src\NixVM.Tools.IR.pas',
  NixVM.Tools.Disasm in '..\src\NixVM.Tools.Disasm.pas',
  NixVM.Tools.Assembler in '..\src\NixVM.Tools.Assembler.pas',
  NixVM.Core.ROM in '..\src\NixVM.Core.ROM.pas';

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
