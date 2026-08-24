program NixVMTest;

{
  TODO:
    DivZero enable/disable instruction
    ...or extend set/get instructions to support interrupts and divz flags
}

{$APPTYPE CONSOLE}
{$R *.res}

uses
  NixVM.CPU in '..\src\NixVM.CPU.pas',
  NixVM.Harness in '..\src\NixVM.Harness.pas',
  NixVM.Instructions in '..\src\NixVM.Instructions.pas',
  NixVM.Memory in '..\src\NixVM.Memory.pas',
  NixVM.Registers in '..\src\NixVM.Registers.pas',
  NixVM.Strings in '..\src\NixVM.Strings.pas',
  NixVM.System in '..\src\NixVM.System.pas',
  NixVM.Timing in '..\src\NixVM.Timing.pas';

type
  TTestSystemMemory = packed record

  end;

  TTest = class(TCustomHarness<TTestSystemMemory>)

  end;

begin
  TTest.Run;
end.
