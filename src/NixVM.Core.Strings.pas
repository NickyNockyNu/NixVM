{
  NixVM.Core.Strings.pas
    Common string routines

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

unit NixVM.Core.Strings;

{$INCLUDE 'NixVM.Options.inc'}

interface

function Lowercase(const AString: String): String;

function IntToStr(AValue: Integer):                      String;
function IntToHex(AValue: Cardinal; ASize: Integer = 8): String;

function StrToInt(const AString: String; ADefault: Integer = 0): Integer;

function FloatToStr(AValue: Single; APrec: Integer = 2): String;

function TrimWhitespace(const AString: String): String;

implementation

function Lowercase(const AString: String): String;
begin
  SetLength(Result, Length(AString));

  for var i := 1 to Length(AString) do
    if (AString[i] >= 'A') and (AString[i] <= 'Z') then
      Result[i] := Chr(Ord(AString[i]) + 32)
    else
      Result[i] := AString[i];
end;

function IntToStr(AValue: Integer): String;
var
  S: ShortString;
begin
  Str(AValue, S);
  Result := String(S);
end;

function IntToHex(AValue: Cardinal; ASize: Integer): String;
const
  HexChars = '0123456789ABCDEF';
var
  Trim: Boolean;
begin
  Result := '';

  Trim := ASize = 0;
  if Trim then
    ASize := 8;

  if AValue = 0 then
  begin
    if Trim then
      Exit('0');

    for var i := 1 to ASize do
      Result := Result + '0';

    Exit;
  end;

  for var i := 1 to ASize do
  begin
    Result := HexChars[(AValue and $F) + 1] + Result;
    AValue := AValue shr 4;
  end;

  if Trim then
    for var i := 1 to Length(Result) do
      if Result[i] <> '0' then
      begin
        Result := Copy(Result, i, Length(Result));
        Break;
      end;
end;

function StrToInt(const AString: String; ADefault: Integer = 0): Integer;
var
  Code: Integer;
begin
  Val(AString, Result, Code);

  if Code <> 0 then
    Result := ADefault;
end;

function FloatToStr(AValue: Single; APrec: Integer): String;
var
  S: ShortString;
begin
  Str(AValue:APrec:APrec, S);
  Result := String(S);
end;

function TrimWhitespace(const AString: String): String;
const
  Whitespace = #32#9;
begin
  Result := AString;

  for var i := 1 to Length(Result) do
    if Pos(Result[i], Whitespace) = 0 then
    begin
      Result := Copy(Result, i, Length(Result));
      Break;
    end;

  for var i := Length(Result) downto 1 do
    if Pos(Result[i], Whitespace) = 0 then
    begin
      Result := Copy(Result, 1, i);
      Break;
    end;
end;

end.
