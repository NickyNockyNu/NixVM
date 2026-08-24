program NixVMTest;

{
  TODO:
    DivZero enable/disable instruction
    ...or extend set/get instructions to support interrupts and divz flags
}

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
  NixVM.Tools.Assembler in '..\src\NixVM.Tools.Assembler.pas';

type
  TTestSystemMemory = packed record

  end;

  TTest = class(TCustomHarness<TTestSystemMemory>)
  protected
    procedure Initialize; override;
    procedure Started;    override;

    function HandleSysCall(ASysCall: TSysCalls.ID): Boolean; override;
  end;

procedure TTest.Initialize;
begin
  inherited;

  Memory.Resize(1024 * 16, 1024 * 16, 1024 * 16);
end;

procedure TTest.Started;
const SourceCode = '''
call @SayHello
halt

@SayHello:
  mov r0, _strconst_hello
  syscall 255
  ret

_strconst_hello:
db 2
ds "Hello, World!"
db 1, 2, 3, 4

''';
var
  Errors: TStrings;
  CodeBytes: Cardinal;
  IR: TIRList;
begin
  Writeln('=== ORIGINAL ===');
  Writeln(SourceCode);

  IR := TAssembler.Parse(SourceCode, Errors);
  IR.ResolveLabels(Memory.UserAddress, Errors);

  if (Errors <> nil) and (Errors.Count > 0) then
  begin
    Writeln('=== ASSEMBLY ERRORS ===');
    Writeln(Errors.Text);
    Exit;
  end;

  Writeln('=== IR ===');
  Writeln(IR.ToString);

  CodeBytes := IR.Emit(Memory, Memory.UserAddress);

  Writeln('=== DISASM ===');
  Writeln(TDisassembler.DisassembleToString(Memory, Memory.UserAddress, CodeBytes));

  Writeln('=== RUNNING ===');
end;

function TTest.HandleSysCall(ASysCall: TSysCalls.ID): Boolean;
begin
  Result := inherited;

  if Result then
    Exit;

  Result := True;

  case ASysCall of
    255: Writeln('Syscall: "', Memory.ReadString(CPU.Registers.R0), '"');
  else
    Result := False;
  end;
end;

begin
  TTest.Run;
end.
