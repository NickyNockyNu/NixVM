{
  NixVM.Core.ROM.pas
    Universal binary format

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

unit NixVM.Core.ROM;

{$INCLUDE 'NixVM.Options.inc'}

interface

type
  {$REGION 'TargetInfo'}
  PTargetInfo = ^TTargetInfo;
  TTargetInfo = packed record
    Magic: Cardinal;

    UserAddress:  Cardinal;

    HarnessMajor: Word;
    HarnessMinor: Word;

    OEMSize: Cardinal;

    Reserved: Cardinal;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'ROMHeader'}
  PROMHeader = ^TROMHeader;
  TROMHeader = packed record
  type
    TSignature = packed array[0..3] of AnsiChar;

    {$REGION 'Version'}
    TVersion = packed record
    private
      function  GetName: String;              inline;
      procedure SetName(const AName: String); inline;
    public
      FName: packed array[0..31] of AnsiChar;

      Major: Word;
      Minor: Word;

      function ToString: String; inline;

      property Name: String read GetName write SetName;
    end;
    {$ENDREGION}
  const
    Magic: TSignature = 'NVMX';
  public
    Signature:   TSignature;
    Harness:     TVersion;
    ROM:         TVersion;
    UserAddress: Cardinal;
    UserSize:    Cardinal;
    HeapSize:    Cardinal;
    StackSize:   Cardinal;

    procedure Reset;

    function Load(const AFileName: String): Boolean;

    function IsValid: Boolean; inline;

    function ToString: String;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Core.System,
  NixVM.Core.Strings;

{$REGION 'TargetInfo'}
procedure TTargetInfo.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);

  Magic := Cardinal(TROMHeader.Magic);

  UserAddress := (SizeOf(TCoreSystemMemory) + 3) and not Cardinal(3);

  HarnessMajor := 1;
end;
{$ENDREGION}

{$REGION 'ROMHeader'}
{$REGION 'Version'}
function TROMHeader.TVersion.GetName: String;
begin
  Result := String(PAnsiChar(@FName[0]));
end;

procedure TROMHeader.TVersion.SetName(const AName: String);
var
  S: AnsiString;
begin
  FillChar(FName, SizeOf(FName), 0);

  S := AnsiString(AName);

  if Length(S) > SizeOf(FName) - 1 then
    SetLength(S, SizeOf(FName) - 1);

  Move(S[1], FName[0], Length(S));
end;

function TROMHeader.TVersion.ToString: String;
begin
  Result := Name + ' v' + IntToStr(Major) + '.' + IntToStr(Minor);
end;
{$ENDREGION}

procedure TROMHeader.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);

  Signature := Magic;

  ROM.Major := 1;

  UserAddress := (SizeOf(TCoreSystemMemory) + 3) and not Cardinal(3);

  HeapSize  := 64 * 1024;
  StackSize := 16 * 1024;
end;

function TROMHeader.Load(const AFileName: String): Boolean;
var
  F:         file;
  OldMode:   Byte;
  BytesRead: Integer;
begin
  Result   := False;

  OldMode  := FileMode;
  FileMode := 0;

  AssignFile(F, AFileName);

  try
    {$I-}System.Reset(F, 1);{$I+}

    if IOResult <> 0 then
      Exit;

    try
      BlockRead(F, Self, SizeOf(Self), BytesRead);

      if (BytesRead <> SizeOf(Self)) or not IsValid then
        Exit;
    finally
      CloseFile(F);
    end;
  finally
    FileMode := OldMode;
  end;

  Result := True;
end;

function TROMHeader.IsValid: Boolean;
begin
  Result := Signature = Magic;
end;

function TROMHeader.ToString: String;
begin
  Result :=
    '          ROM: ' + ROM.    ToString + #13#10;

  if Length(Harness.Name) > 0 then
    Result := Result +
    '      Harness: ' + Harness.ToString + #13#10;

  Result := Result +
    '  UserAddress: 0x' + IntToHex(UserAddress, 8) + #13#10 +

    '     UserSize: ' + IntToStr(UserSize) + #13#10 +
    '     HeapSize: ' + IntToStr(HeapSize) + #13#10 +
    '    StackSize: ' + IntToStr(StackSize);
end;
{$ENDREGION}

end.
