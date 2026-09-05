program harness.passe;

{$APPTYPE CONSOLE}
{.$R *.res}

uses
  NixVM.Passe in '..\src\NixVM.Passe.pas',
  NixVM.Passe.Memory in '..\src\NixVM.Passe.Memory.pas',
  NixVM.Passe.Video in '..\src\NixVM.Passe.Video.pas',
  NixVM.Passe.Renderer in '..\src\NixVM.Passe.Renderer.pas',
  NixVM.Harness.Passe in '..\src\NixVM.Harness.Passe.pas';

begin
  TPasse.Run;
end.
