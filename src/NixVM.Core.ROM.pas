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
  {$REGION 'Header'}
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
    function IsValid: Boolean; inline;
  end;
  {$ENDREGION}

implementation

{$REGION 'Header'}
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
{$ENDREGION}

procedure TROMHeader.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);

  Signature := Magic;

  ROM.Major := 1;

  HeapSize  := 64 * 1024;
  StackSize := 16 * 1024;
end;

function TROMHeader.IsValid: Boolean;
begin
  Result := Signature = Magic;
end;
{$ENDREGION}

end.
