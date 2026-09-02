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
  {$REGION 'VerionInfo'}
  TVersionInfo = record
  public
    FileDescription: String;
    ProductName:     String;
    InternalName:    String;
    CompanyName:     String;
    LegalCopyright:  String;
    Major:           Word;
    Minor:           Word;
    Release:         Word;
    Build:           Word;

    class function FromROMHeader(const AHeader: TROMHeader): TVersionInfo; static;

    function ToString: String;
  end;
  {$ENDREGION}

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

    class function AddIcon       (const AExePath, AIcoPath: String; const AIconGroupName: String = 'MAINICON'; AErrors: TStrings = nil): Boolean;
    class function AddVersionInfo(const AExePath: String; const AVerInfo: TVersionInfo; AErrors: TStrings = nil): Boolean;
  end;
  {$ENDREGION}

  {$REGION 'Icon file/resource formats'}
  PIconDirEntry = ^TIconDirEntry;
  TIconDirEntry = packed record
    bWidth:        Byte;
    bHeight:       Byte;
    bColorCount:   Byte;
    bReserved:     Byte;
    wPlanes:       Word;
    wBitCount:     Word;
    dwBytesInRes:  DWORD;
    dwImageOffset: DWORD;
  end;

  PIconHeader = ^TIconHeader;
  TIconHeader = packed record
    idReserved: Word;
    idType:     Word;
    idCount:    Word;
  end;

  PGrpIconDirEntry = ^TGrpIconDirEntry;
  TGrpIconDirEntry = packed record
    bWidth:       Byte;
    bHeight:      Byte;
    bColorCount:  Byte;
    bReserved:    Byte;
    wPlanes:      Word;
    wBitCount:    Word;
    dwBytesInRes: DWORD;
    nID:          Word;
  end;

  PGrpIconHeader = ^TGrpIconHeader;
  TGrpIconHeader = packed record
    idReserved: Word;
    idType:     Word;
    idCount:    Word;
  end;
  {$ENDREGION}

const
  DOS_HEADER_TARGET_OFFSET = $28;

implementation

{$REGION 'VersionInfo'}
class function TVersionInfo.FromROMHeader(const AHeader: TROMHeader): TVersionInfo;
begin
  Result := Default(TVersionInfo);

  Result.ProductName     := AHeader.ROM.Name;
  Result.FileDescription := AHeader.ROM.Name;
  Result.InternalName    := AHeader.ROM.Name;
  Result.Major           := AHeader.ROM.Major;
  Result.Minor           := AHeader.ROM.Minor;
  Result.Release         := 0;
  Result.Build           := 0;
  Result.LegalCopyright  := '';

  if Length(AHeader.Harness.Name) > 0 then
    Result.InternalName := Result.InternalName + ' (' + AHeader.Harness.Name + ')';
end;

function TVersionInfo.ToString: String;
  procedure Add(AName, AValue: String);
  begin
    if Length(AValue) = 0 then
      Exit;

    if Length(Result) > 0 then
      Result := Result + #13#10;

    while Length(AName) < 17 do
      AName := ' ' + AName;

    Result := Result + AName + ': ' + AValue;
  end;
begin
  Result := '';

  Add('Product name',     ProductName);
  Add('File description', FileDescription);
  Add('Internal name',    InternalName);
  Add('Version',          Format('%d.%d.%d.%d', [Major, Minor, Release, Build]));
  Add('Legal copyright',  LegalCopyright);
end;
{$ENDREGION}

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

class function TBuildPE.AddIcon(const AExePath, AIcoPath: String; const AIconGroupName: String = 'MAINICON'; AErrors: TStrings = nil): Boolean;
var
  IcoBytes:     TBytes;
  IcoHeader:    PIconHeader;
  IcoEntries:   PIconDirEntry;
  GrpHeaderSize: Integer;
  GrpBuffer:    TBytes;
  GrpHeader:    PGrpIconHeader;
  GrpEntry:     PGrpIconDirEntry;
  HUpdate:      THandle;
  ImagePtr:     Pointer;
  i:            Integer;
begin
  Result := False;

  if not FileExists(AExePath) then
  begin
    if Assigned(AErrors) then
      AErrors.Add('Executable not found: ' + AExePath);

    Exit;
  end;

  if not FileExists(AIcoPath) then
  begin
    if Assigned(AErrors) then
      AErrors.Add('Icon file not found: ' + AIcoPath);

    Exit;
  end;

  try
    IcoBytes := TFile.ReadAllBytes(AIcoPath);
  except
    on E: Exception do
    begin
      if Assigned(AErrors) then
        AErrors.Add('Failed to read icon file: ' + E.Message);

      Exit;
    end;
  end;

  if Length(IcoBytes) < SizeOf(TIconHeader) + SizeOf(TIconDirEntry) then
  begin
    if Assigned(AErrors) then
      AErrors.Add('Invalid icon file (too small)');

    Exit;
  end;

  IcoHeader := PIconHeader(@IcoBytes[0]);

  if (IcoHeader^.idReserved <> 0) or (IcoHeader^.idType <> 1) or (IcoHeader^.idCount = 0) then
  begin
    if Assigned(AErrors) then
      AErrors.Add('File is not a valid Windows .ico file');

    Exit;
  end;

  HUpdate := BeginUpdateResource(PChar(AExePath), False);

  if HUpdate = 0 then
  begin
    if Assigned(AErrors) then
      AErrors.Add(Format('Failed to open executable resource section (Error %d)', [GetLastError]));

    Exit;
  end;

  try
    IcoEntries := PIconDirEntry(@IcoBytes[SizeOf(TIconHeader)]);

    GrpHeaderSize := SizeOf(TGrpIconHeader) + (IcoHeader^.idCount * SizeOf(TGrpIconDirEntry));
    SetLength(GrpBuffer, GrpHeaderSize);

    GrpHeader := PGrpIconHeader(@GrpBuffer[0]);

    GrpHeader^.idReserved := 0;
    GrpHeader^.idType     := 1;
    GrpHeader^.idCount    := IcoHeader^.idCount;

    for i := 0 to IcoHeader^.idCount - 1 do
    begin
      var Entry := PIconDirEntry(NativeUInt(IcoEntries) + (Cardinal(i) * SizeOf(TIconDirEntry)));

      GrpEntry := PGrpIconDirEntry(NativeUInt(@GrpBuffer[0]) + SizeOf(TGrpIconHeader) + (Cardinal(i) * SizeOf(TGrpIconDirEntry)));

      GrpEntry^.bWidth       := Entry^.bWidth;
      GrpEntry^.bHeight      := Entry^.bHeight;
      GrpEntry^.bColorCount  := Entry^.bColorCount;
      GrpEntry^.bReserved    := 0;
      GrpEntry^.wPlanes      := Entry^.wPlanes;
      GrpEntry^.wBitCount    := Entry^.wBitCount;
      GrpEntry^.dwBytesInRes := Entry^.dwBytesInRes;
      GrpEntry^.nID          := i + 1;

      if Entry^.dwImageOffset + Entry^.dwBytesInRes <= Cardinal(Length(IcoBytes)) then
      begin
        ImagePtr := @IcoBytes[Entry^.dwImageOffset];

        if not UpdateResource(HUpdate, RT_ICON, MAKEINTRESOURCE(i + 1), MAKELANGID(LANG_NEUTRAL, SUBLANG_NEUTRAL), ImagePtr, Entry^.dwBytesInRes) then
        begin
          if Assigned(AErrors) then
            AErrors.Add(Format('Failed to write RT_ICON #%d (Error %d)', [i + 1, GetLastError]));


          EndUpdateResource(HUpdate, True);

          Exit;
        end;
      end;
    end;

    if not UpdateResource(HUpdate, RT_GROUP_ICON, PChar(AIconGroupName), MAKELANGID(LANG_NEUTRAL, SUBLANG_NEUTRAL), @GrpBuffer[0], Length(GrpBuffer)) then
    begin
      if Assigned(AErrors) then
        AErrors.Add(Format('Failed to write RT_GROUP_ICON (Error %d)', [GetLastError]));

      EndUpdateResource(HUpdate, True);

      Exit;
    end;

    if not EndUpdateResource(HUpdate, False) then
    begin
      if Assigned(AErrors) then
        AErrors.Add(Format('Failed to commit icon resource update (Error %d)', [GetLastError]));

      Exit;
    end;

    Result := True;
  except
    on E: Exception do
    begin
      EndUpdateResource(HUpdate, True);

      if Assigned(AErrors) then
        AErrors.Add('Exception injecting icon: ' + E.Message);

      Result := False;
    end;
  end;
end;

class function TBuildPE.AddVersionInfo(const AExePath: String; const AVerInfo: TVersionInfo; AErrors: TStrings = nil): Boolean;
var
  Stream:   TMemoryStream;
  HUpdate:  THandle;

  procedure PadDWord;
  var
    Pad: Byte;
  begin
    Pad := 0;

    while (Stream.Position mod 4) <> 0 do
      Stream.WriteBuffer(Pad, 1);
  end;

  procedure WriteWideString(const S: String);
  const
    NullChar: WideChar = #0;
  var
    WS: WideString;
  begin
    WS := WideString(S);

    if Length(WS) > 0 then
      Stream.WriteBuffer(WS[1], Length(WS) * SizeOf(WideChar));

    Stream.WriteBuffer(NullChar, SizeOf(WideChar));
  end;

  function WriteStringEntry(const AKey, AValue: String): Integer;
  var
    StartPos: Int64;
    ValPos:   Int64;
    EndPos:   Int64;
    wLen:     Word;
    wValLen:  Word;
    wType:    Word;
  begin
    PadDWord;
    StartPos := Stream.Position;

    wLen     := 0;
    wValLen  := Length(WideString(AValue)) + 1;
    wType    := 1;

    Stream.WriteBuffer(wLen,    SizeOf(Word));
    Stream.WriteBuffer(wValLen, SizeOf(Word));
    Stream.WriteBuffer(wType,   SizeOf(Word));

    WriteWideString(AKey);

    PadDWord;
    ValPos := Stream.Position;
    WriteWideString(AValue);

    EndPos := Stream.Position;
    wLen   := EndPos - StartPos;

    Stream.Position := StartPos;
    Stream.WriteBuffer(wLen, SizeOf(Word));
    Stream.Position := EndPos;

    Result := wLen;
  end;

var
  RootStart, RootValPos, RootEnd: Int64;
  StrInfoStart, StrInfoEnd:       Int64;
  TableStart, TableEnd:           Int64;
  VarInfoStart, VarInfoEnd:       Int64;
  VarEntryStart, VarEntryEnd:     Int64;
  wLen, wValLen, wType:           Word;
  FixedInfo:                      tagVS_FIXEDFILEINFO;
  VerStr:                         String;
  Trans:                          packed array[0..1] of Word;
begin
  Result := False;

  if not FileExists(AExePath) then
  begin
    if Assigned(AErrors) then
      AErrors.Add('Executable not found: ' + AExePath);

    Exit;
  end;

  VerStr := Format('%d.%d.%d.%d', [AVerInfo.Major, AVerInfo.Minor, AVerInfo.Release, AVerInfo.Build]);

  Stream := TMemoryStream.Create;
  try
    RootStart := Stream.Position;
    wLen      := 0;
    wValLen   := SizeOf(tagVS_FIXEDFILEINFO);
    wType     := 0;

    Stream.WriteBuffer(wLen, SizeOf(Word));
    Stream.WriteBuffer(wValLen, SizeOf(Word));
    Stream.WriteBuffer(wType, SizeOf(Word));

    WriteWideString('VS_VERSION_INFO');

    PadDWord;
    RootValPos := Stream.Position;

    FillChar(FixedInfo, SizeOf(FixedInfo), 0);

    FixedInfo.dwSignature        := $FEEF04BD;
    FixedInfo.dwStrucVersion     := $00010000;
    FixedInfo.dwFileVersionMS    := (AVerInfo.Major   shl 16) or AVerInfo.Minor;
    FixedInfo.dwFileVersionLS    := (AVerInfo.Release shl 16) or AVerInfo.Build;
    FixedInfo.dwProductVersionMS := FixedInfo.dwFileVersionMS;
    FixedInfo.dwProductVersionLS := FixedInfo.dwFileVersionLS;
    FixedInfo.dwFileFlagsMask    := $3F;
    FixedInfo.dwFileFlags        := 0;
    FixedInfo.dwFileOS           := VOS_NT_WINDOWS32;
    FixedInfo.dwFileType         := VFT_APP;

    Stream.WriteBuffer(FixedInfo, SizeOf(FixedInfo));

    PadDWord;

    StrInfoStart := Stream.Position;
    wLen         := 0;
    wValLen      := 0;
    wType        := 1;

    Stream.WriteBuffer(wLen, SizeOf(Word));
    Stream.WriteBuffer(wValLen, SizeOf(Word));
    Stream.WriteBuffer(wType, SizeOf(Word));

    WriteWideString('StringFileInfo');

    PadDWord;

    TableStart := Stream.Position;
    wLen       := 0;
    wValLen    := 0;
    wType      := 1;

    Stream.WriteBuffer(wLen,    SizeOf(Word));
    Stream.WriteBuffer(wValLen, SizeOf(Word));
    Stream.WriteBuffer(wType,   SizeOf(Word));

    WriteWideString('040904B0');

    WriteStringEntry('FileDescription',  AVerInfo.FileDescription);
    WriteStringEntry('FileVersion',      VerStr);
    WriteStringEntry('InternalName',     AVerInfo.InternalName);
    WriteStringEntry('OriginalFilename', ExtractFileName(AExePath));
    WriteStringEntry('ProductName',      AVerInfo.ProductName);
    WriteStringEntry('ProductVersion',   VerStr);
    WriteStringEntry('Comments',         'Built with NixVM - https://github.com/NickyNockyNu/NixVM');

    if AVerInfo.CompanyName <> '' then
      WriteStringEntry('CompanyName', AVerInfo.CompanyName);

    if AVerInfo.LegalCopyright <> '' then
      WriteStringEntry('LegalCopyright', AVerInfo.LegalCopyright);

    TableEnd := Stream.Position;
    wLen     := TableEnd - TableStart;

    Stream.Position := TableStart;
    Stream.WriteBuffer(wLen, SizeOf(Word));
    Stream.Position := TableEnd;

    StrInfoEnd := Stream.Position;
    wLen       := StrInfoEnd - StrInfoStart;

    Stream.Position := StrInfoStart;
    Stream.WriteBuffer(wLen, SizeOf(Word));
    Stream.Position := StrInfoEnd;

    PadDWord;

    VarInfoStart := Stream.Position;
    wLen         := 0;
    wValLen      := 0;
    wType        := 1;

    Stream.WriteBuffer(wLen, SizeOf(Word));
    Stream.WriteBuffer(wValLen, SizeOf(Word));
    Stream.WriteBuffer(wType, SizeOf(Word));

    WriteWideString('VarFileInfo');

    PadDWord;

    VarEntryStart := Stream.Position;
    wLen          := 0;
    wValLen       := SizeOf(Trans);
    wType         := 0;

    Stream.WriteBuffer(wLen, SizeOf(Word));
    Stream.WriteBuffer(wValLen, SizeOf(Word));
    Stream.WriteBuffer(wType, SizeOf(Word));

    WriteWideString('Translation');

    PadDWord;

    Trans[0] := $0809; // or $0409 for US English
    Trans[1] := $04B0;

    Stream.WriteBuffer(Trans, SizeOf(Trans));

    VarEntryEnd := Stream.Position;
    wLen        := VarEntryEnd - VarEntryStart;

    Stream.Position := VarEntryStart;
    Stream.WriteBuffer(wLen, SizeOf(Word));
    Stream.Position := VarEntryEnd;

    VarInfoEnd := Stream.Position;
    wLen       := VarInfoEnd - VarInfoStart;

    Stream.Position := VarInfoStart;
    Stream.WriteBuffer(wLen, SizeOf(Word));
    Stream.Position := VarInfoEnd;

    RootEnd := Stream.Position;
    wLen    := RootEnd - RootStart;

    Stream.Position := RootStart;
    Stream.WriteBuffer(wLen, SizeOf(Word));
    Stream.Position := RootEnd;

    HUpdate := BeginUpdateResource(PChar(AExePath), False);

    if HUpdate = 0 then
    begin
      if Assigned(AErrors) then
        AErrors.Add(Format('Failed to open executable for version update (Error %d)', [GetLastError]));

      Exit;
    end;

    if not UpdateResource(HUpdate, RT_VERSION, MAKEINTRESOURCE(1), MAKELANGID(LANG_NEUTRAL, SUBLANG_NEUTRAL), Stream.Memory, Stream.Size) then
    begin
      if Assigned(AErrors) then
        AErrors.Add(Format('Failed to write RT_VERSION (Error %d)', [GetLastError]));

      EndUpdateResource(HUpdate, True);

      Exit;
    end;

    if not EndUpdateResource(HUpdate, False) then
    begin
      if Assigned(AErrors) then
        AErrors.Add(Format('Failed to commit version resource update (Error %d)', [GetLastError]));

      Exit;
    end;

    Result := True;
  finally
    Stream.Free;
  end;
end;
{$ENDREGION}

end.
