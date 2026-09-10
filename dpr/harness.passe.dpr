program harness.passe;

{$APPTYPE CONSOLE}
{.$R *.res}

uses
  NixVM.Passe in '..\src\NixVM.Passe.pas',
  NixVM.Passe.Memory in '..\src\NixVM.Passe.Memory.pas',
  NixVM.Passe.Video in '..\src\NixVM.Passe.Video.pas',
  NixVM.Passe.Renderer in '..\src\NixVM.Passe.Renderer.pas',
  NixVM.Harness.Passe in '..\src\NixVM.Harness.Passe.pas',
  NixVM.Passe.Video.VDU in '..\src\NixVM.Passe.Video.VDU.pas',
  NixVM.Passe.Input in '..\src\NixVM.Passe.Input.pas',
  NixVM.Passe.Input.HID in '..\src\NixVM.Passe.Input.HID.pas',
  NixVM.Passe.Audio in '..\src\NixVM.Passe.Audio.pas',
  NixVM.Passe.Audio.SID in '..\src\NixVM.Passe.Audio.SID.pas';

begin
  TPasse.Run;
end.
