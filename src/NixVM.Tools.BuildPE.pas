{
  NixVM.Tools.BuildPE.pas
    .nvm ROM file to Windows PE linker

    Copyright (c) 2026 Nicholas Smith (writetonik@gmail.com)
    https://github.com/NickyNockyNu/NixVM

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
}

unit NixVM.Tools.BuildPE;

{$INCLUDE 'NixVM.Options.inc'}

{$IF NOT DEFINED(MSWINDOWS)}
  {$MESSAGE FATAL 'PE Builder is designed specifically for Windows'}
{$ENDIF}

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,

  NixVM.Core.ROM;

type
  {$REGION 'TBuildPE'}
  TBuildPE = class abstract
  public const
    DefaultResourceName = 'ROM';
  public
    class function EmbedROM    (const AStubExePath, AROMFilePath, AOutputExePath: String; const AResourceName: String = DefaultResourceName; AErrors: TStrings = nil): Boolean; static;
    class function EmbedROMData(const AStubExePath: String; const AROMBytes: TBytes; const AOutputExePath: String; const AResourceName: String = DefaultResourceName; AErrors: TStrings = nil): Boolean; static;

    class function HasEmbeddedROM(const AExePath: String; const AResourceName: String = DefaultResourceName): Boolean; static;

    class function ExtractROM(const AExePath: String; out AROMBytes: TBytes; const AResourceName: String = DefaultResourceName): Boolean; static;

    class function ReadStubTargetInfo (const AExePath: String; out   ATargetInfo: TTargetInfo): Boolean;
    class function WriteStubTargetInfo(const AExePath: String; const ATargetInfo: TTargetInfo): Boolean;
  end;
  {$ENDREGION}

const
  DOS_HEADER_TARGET_OFFSET = $28;

implementation

{$REGION 'TBuildPE'}
class function TBuildPE.EmbedROMData(const AStubExePath: String; const AROMBytes: TBytes; const AOutputExePath: String; const AResourceName: String; AErrors: TStrings): Boolean;
var
  HUpdate: THandle;
  Header:  PROMHeader;
begin
  Result := False;

  if not FileExists(AStubExePath) then
  begin
    if Assigned(AErrors) then
      AErrors.Add(Format('Stub executable not found: "%s"', [AStubExePath]));

    Exit;
  end;

  if Length(AROMBytes) < SizeOf(TROMHeader) then
  begin
    if Assigned(AErrors) then
      AErrors.Add('ROM data is too small or invalid');

    Exit;
  end;

  Header := PROMHeader(@AROMBytes[0]);
  if not Header^.IsValid then
  begin
    if Assigned(AErrors) then
      AErrors.Add('Payload is not a valid NixVM ROM (bad magic signature)');

    Exit;
  end;

  try
    var OutDir := ExtractFilePath(AOutputExePath);

    if (OutDir <> '') and (not DirectoryExists(OutDir)) then
      TDirectory.CreateDirectory(OutDir);

    TFile.Copy(AStubExePath, AOutputExePath, True);
  except
    on E: Exception do
    begin
      if Assigned(AErrors) then
        AErrors.Add(Format('Failed to copy stub executable: %s', [E.Message]));

      Exit;
    end;
  end;

  HUpdate := BeginUpdateResource(PChar(AOutputExePath), False);
  if HUpdate = 0 then
  begin
    if Assigned(AErrors) then
      AErrors.Add(Format('Failed to open resource section for "%s" (Win32 Error: %d)', [AOutputExePath, GetLastError]));

    Exit;
  end;

  if not UpdateResource(HUpdate, RT_RCDATA, PChar(AResourceName), MAKELANGID(LANG_NEUTRAL, SUBLANG_NEUTRAL), @AROMBytes[0], Length(AROMBytes)) then
  begin
    if Assigned(AErrors) then
      AErrors.Add(Format('Failed to write resource into executable (Win32 Error: %d)', [GetLastError]));

    EndUpdateResource(HUpdate, True);

    Exit;
  end;

  if not EndUpdateResource(HUpdate, False) then
  begin
    if Assigned(AErrors) then
      AErrors.Add(Format('Failed to commit PE resource update (Win32 Error: %d)', [GetLastError]));

    Exit;
  end;

  Result := True;
end;

class function TBuildPE.EmbedROM(const AStubExePath, AROMFilePath, AOutputExePath: String; const AResourceName: String; AErrors: TStrings): Boolean;
var
  ROMBytes: TBytes;
begin
  if not FileExists(AROMFilePath) then
  begin
    if Assigned(AErrors) then
      AErrors.Add(Format('ROM file not found: "%s"', [AROMFilePath]));

    Exit(False);
  end;

  try
    ROMBytes := TFile.ReadAllBytes(AROMFilePath);
  except
    on E: Exception do
    begin
      if Assigned(AErrors) then
        AErrors.Add(Format('Error reading ROM file: %s', [E.Message]));

      Exit(False);
    end;
  end;

  Result := EmbedROMData(AStubExePath, ROMBytes, AOutputExePath, AResourceName, AErrors);
end;

class function TBuildPE.HasEmbeddedROM(const AExePath: String; const AResourceName: String): Boolean;
var
  HMod:    HMODULE;
  HRes:    HRSRC;
begin
  Result := False;

  if not FileExists(AExePath) then
    Exit;

  HMod := LoadLibraryEx(PChar(AExePath), 0, LOAD_LIBRARY_AS_DATAFILE);
  if HMod = 0 then
    Exit;

  try
    HRes   := FindResource(HMod, PChar(AResourceName), RT_RCDATA);
    Result := (HRes <> 0);
  finally
    FreeLibrary(HMod);
  end;
end;

class function TBuildPE.ExtractROM(const AExePath: String; out AROMBytes: TBytes; const AResourceName: String): Boolean;
var
  HMod:     HMODULE;
  HResInfo: HRSRC;
  HResData: HGLOBAL;
  PRes:     Pointer;
  ResSize:  DWORD;
begin
  Result    := False;
  AROMBytes := nil;

  if not FileExists(AExePath) then
    Exit;

  HMod := LoadLibraryEx(PChar(AExePath), 0, LOAD_LIBRARY_AS_DATAFILE);
  if HMod = 0 then
    Exit;

  try
    HResInfo := FindResource(HMod, PChar(AResourceName), RT_RCDATA);
    if HResInfo = 0 then
      Exit;

    ResSize := SizeofResource(HMod, HResInfo);
    if ResSize < SizeOf(TROMHeader) then
      Exit;

    HResData := LoadResource(HMod, HResInfo);
    if HResData = 0 then
      Exit;

    PRes := LockResource(HResData);
    if PRes = nil then
      Exit;

    SetLength(AROMBytes, ResSize);
    Move(PRes^, AROMBytes[0], ResSize);
    Result := True;
  finally
    FreeLibrary(HMod);
  end;
end;

class function TBuildPE.ReadStubTargetInfo(const AExePath: String; out ATargetInfo: TTargetInfo): Boolean;
var
  FS:     TFileStream;
  Header: array[0..63] of Byte;
  Target: PTargetInfo;
begin
  Result      := False;
  ATargetInfo := Default(TTargetInfo);

  if not FileExists(AExePath) then
    Exit(False);

  try
    FS := TFileStream.Create(AExePath, fmOpenRead or fmShareDenyNone);

    try
      if FS.Size < SizeOf(Header) then
        Exit;

      FS.ReadBuffer(Header[0], SizeOf(Header));

      if (Header[0] <> Ord('M')) or (Header[1] <> Ord('Z')) then
        Exit;

      Target := PTargetInfo(@Header[DOS_HEADER_TARGET_OFFSET]);

      if Target^.Magic = Cardinal(TROMHeader.Magic) then
      begin
        ATargetInfo := Target^;

        Result := True;
      end;
    finally
      FS.Free;
    end;
  except
    Result := False;
  end;
end;

class function TBuildPE.WriteStubTargetInfo(const AExePath: String; const ATargetInfo: TTargetInfo): Boolean;
var
  FS:     TFileStream;
  Header: array[0..63] of Byte;
  Target: PTargetInfo;
begin
  Result := False;

  if not FileExists(AExePath) then
    Exit;

  try
    FS := TFileStream.Create(AExePath, fmOpenReadWrite or fmShareDenyNone);

    try
      if FS.Size < SizeOf(Header) then
        Exit;

      FS.ReadBuffer(Header[0], SizeOf(Header));

      if (Header[0] <> Ord('M')) or (Header[1] <> Ord('Z')) then
        Exit;

      Target        := PTargetInfo(@Header[DOS_HEADER_TARGET_OFFSET]);
      Target^       := ATargetInfo;
      Target^.Magic := Cardinal(TROMHeader.Magic);

      FS.Position := 0;
      FS.WriteBuffer(Header[0], SizeOf(Header));

      Result := True;
    finally
      FS.Free;
    end;
  except
    Result := False;
  end;
end;
{$ENDREGION}

end.
