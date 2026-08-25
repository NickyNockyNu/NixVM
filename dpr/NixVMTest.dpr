program NixVMTest;

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
  end;

procedure TTest.Initialize;
begin
  inherited;

  Memory.Resize(1024, 1024, 1024);
end;

procedure TTest.Started;
const SourceCode = '''
call SayHello
call remotefunc
halt

.include "d:\test.asm"

.align 8, 255
SayHello:
  mov r0, _strconst_format + 7
  mov r1, _strconst_hello - 4
  mov r2, _strconst_world
  syscall 1 ; DebugPrint
  ret

.align 8
_strconst_format: .ds "hidden %s, %s!", 13, 10, 0
.ascii "Hell"
_strconst_hello:  .ascii "o", 0
_strconst_world:  .str "World", 0
''';
var
  Errors:    TStrings;
  CodeBytes: Cardinal;
  IR:        TIRList;
begin
  Writeln('=== SOURCE ===');
  Writeln(SourceCode);

  IR := TAssembler.Parse(SourceCode, Errors);
  IR.ResolveLabels(Memory.UserAddress, Errors);

  if (Errors <> nil) and (Errors.Count > 0) then
  begin
    Writeln('=== ASSEMBLY ERRORS ===');
    Writeln(Errors.Text);
    Exit;
  end;

//  Writeln('=== IR ===');
//  Writeln(IR.ToString);

  CodeBytes := IR.Emit(Memory, Memory.UserAddress);

  Writeln('=== DISASM ===');
  Writeln(TDisassembler.DisassembleToString(Memory, Memory.UserAddress, CodeBytes));

  Writeln('=== RUNNING ===');
end;

begin
  TTest.Run;
end.
