{
  NixVM.Harness.PE.pas
    Base harness for windows PE files

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

unit NixVM.Harness.PE;

{$INCLUDE 'NixVM.Options.inc'}

{$IF NOT DEFINED(MSWINDOWS)}
  {$MESSAGE FATAL 'NixVM PE harness is designed specifically for Windows'}
{$ENDIF}

interface

uses
  Winapi.Windows,

  NixVM.Core.ROM,
  NixVM.Core.Memory,
  NixVM.Core.Registers,
  NixVM.Core.Instructions,
  NixVM.Core.CPU,
  NixVM.Core.System,

  NixVM.Harness;

type
  {$REGION 'TCustomPEHarness'}
  TCustomPEHarness<TSystemMemory: record> = class(TCustomHarness<TSystemMemory>)
  public const
    DefaultResourceName = 'ROM';
  private
    FIsEmbeddedROM: Boolean;
    FResourceName:  String;
  protected
    procedure Initialize; override;

    function LoadROMFromBuffer  (const ABuffer: Pointer; ASize: Cardinal):           Boolean;
    function LoadROMFromResource(const AResourceName: String = DefaultResourceName): Boolean;
  public
    constructor Create(const AROMFile: String = ''; const AResourceName: String = DefaultResourceName);

    property IsEmbeddedROM: Boolean read FIsEmbeddedROM;
    property ResourceName:  String  read FResourceName;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Core.Strings;

{$REGION 'TCustomPEHarness'}
procedure TCustomPEHarness<TSystemMemory>.Initialize;
begin
  if LoadROMFromResource(DefaultResourceName) then
    FIsEmbeddedROM := True

  else if Length(ROMFile) > 0 then
  begin
    if not LoadROM(ROMFile) then
      CPU.Halt;
  end

  else if ParamCount >= 1 then
  begin
    if not LoadROM(ParamStr(1)) then
      CPU.Halt;
  end

  else
  begin
    DebugPrint('No ROM.'#13#10);
    CPU.Halt;
  end;
end;

function TCustomPEHarness<TSystemMemory>.LoadROMFromBuffer(const ABuffer: Pointer; ASize: Cardinal): Boolean;
var
  Header:   PROMHeader;
  DataPtr:  Pointer;
  DataSize: Cardinal;
begin
  Result := False;

  if (ABuffer = nil) or (ASize < SizeOf(TROMHeader)) then
  begin
    DebugPrint('Resource buffer too small'#13#10);
    Exit;
  end;

  Header := PROMHeader(ABuffer);

  if not Header^.IsValid then
  begin
    DebugPrint('Embedded resource is not a valid NixVM ROM'#13#10);
    Exit;
  end;

  if Header^.UserAddress <> Memory.UserAddress then
  begin
    DebugPrint('Incompatible memory layout'#13#10);
    Exit;
  end;

  if Length(Header^.Harness.Name) > 0 then
  begin
    if Lowercase(Header^.Harness.Name) <> Lowercase(HarnessName) then
    begin
      DebugPrint(AnsiString('Requires harness "' + Header^.Harness.Name + '", is "' + HarnessName + '"'#13#10));
      Exit;
    end;

    if (Header^.Harness.Major > HarnessMajor) or ((Header^.Harness.Major = HarnessMajor) and (Header^.Harness.Minor > HarnessMinor)) then
    begin
      DebugPrint(AnsiString('Requires harness version ' + IntToStr(Header^.Harness.Major) + '.' + IntToStr(Header^.Harness.Minor) + #13#10));
      Exit;
    end;
  end;

  if Header^.UserSize = 0 then
    Header^.UserSize := ASize - SizeOf(TROMHeader);

  //if Header^.HeapSize  = 0 then Header^.HeapSize  := 64 * 1024;
  //if Header^.StackSize = 0 then Header^.StackSize := 16 * 1024;

  Memory.Resize(Header^.UserSize, Header^.HeapSize, Header^.StackSize);
  Memory.Reset;

  DataSize := Header^.UserSize;
  DataPtr  := Pointer(NativeUInt(ABuffer) + SizeOf(TROMHeader));

  if DataSize > 0 then
    Memory.WriteData(Memory.UserAddress, DataPtr^, DataSize);

  CPU.Reset;

  Result := True;
end;

function TCustomPEHarness<TSystemMemory>.LoadROMFromResource(const AResourceName: String): Boolean;
var
  HResInfo: HRSRC;
  HResData: HGLOBAL;
  PRes:     Pointer;
  ResSize:  DWORD;
begin
  Result := False;

  HResInfo := FindResource(SysInit.HInstance, PChar(AResourceName), RT_RCDATA);
  if HResInfo = 0 then
    Exit;

  ResSize := SizeofResource(SysInit.HInstance, HResInfo);
  if ResSize < SizeOf(TROMHeader) then
    Exit;

  HResData := LoadResource(SysInit.HInstance, HResInfo);
  if HResData = 0 then
    Exit;

  PRes := LockResource(HResData);
  if PRes = nil then
    Exit;

  Result := LoadROMFromBuffer(PRes, ResSize);
end;

constructor TCustomPEHarness<TSystemMemory>.Create(const AROMFile: String; const AResourceName: String);
begin
  FResourceName  := AResourceName;
  FIsEmbeddedROM := False;

  inherited Create(AROMFile);
end;
{$ENDREGION}

end.
