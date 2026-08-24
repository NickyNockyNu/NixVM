program NixVMTest;

{
  TODO:
    DivZero enable/disable instruction
    ...or extend set/get instructions to support interrupts and divz flags
}

{$APPTYPE CONSOLE}
{$R *.res}

uses
  NixVM.CPU in 'NixVM.CPU.pas',
  NixVM.Harness in 'NixVM.Harness.pas',
  NixVM.Instructions in 'NixVM.Instructions.pas',
  NixVM.Memory in 'NixVM.Memory.pas',
  NixVM.Registers in 'NixVM.Registers.pas',
  NixVM.Strings in 'NixVM.Strings.pas',
  NixVM.System in 'NixVM.System.pas',
  NixVM.Timing in 'NixVM.Timing.pas';

type
  TTestSystemMemory = packed record

  end;

  TTest = class(TCustomHarness<TTestSystemMemory>)

  end;

begin
  TTest.Run;
end.
