{
  NixVM.Strings.pas
    NixVM - Common string routines
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

unit NixVM.Strings;

{$INCLUDE 'NixVM.Options.inc'}

interface

function PosNQ(const ASubString, AString: String; AStart: Integer = 1; const AQuotes: String = '''"'): Integer;

function Uppercase(const AString: String): String;
function Lowercase(const AString: String): String;

function IntToStr(AValue: Integer):                      String;
function IntToHex(AValue: Cardinal; ASize: Integer = 8): String;

function StrToInt(const AString: String; ADefault: Integer = 0):  Integer;

function LTrimWhitespace(const AString: String): String;
function RTrimWhitespace(const AString: String): String;
function  TrimWhitespace(const AString: String): String; inline;

implementation

function PosNQ(const ASubString, AString: String; AStart: Integer = 1; const AQuotes: String = '''"'): Integer;
var
  q: Char;
begin
  q := #0;

  for var i := AStart to Length(AString) do
    if q <> #0 then
    begin
      if AString[i] = q then
        q := #0;
    end
    else if Pos(AString[i], AQuotes) > 0 then
      q  := AString[i]
    else if Copy(AString, i, Length(ASubString)) = ASubString then // TODO: a substring compare so we don't have to use Copy
      Exit(i);

  Result := 0;
end;

function Uppercase(const AString: String): String;
begin
  SetLength(Result, Length(AString));

  for var i := 1 to Length(AString) do
    if (AString[i] >= 'a') and (AString[i] <= 'z') then
      Result[i] := Chr(Ord(AString[i]) - 32)
    else
      Result[i] := AString[i];
end;

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

function LTrimWhitespace(const AString: String): String;
const
  Whitespace = #32#9;//#13#10;
begin
  Result := AString;

  for var i := 1 to Length(Result) do
    if Pos(Result[i], Whitespace) = 0 then
    begin
      Result := Copy(Result, i, Length(Result));
      Break;
    end;
end;

function RTrimWhitespace(const AString: String): String;
const
  Whitespace = #32#9;//#13#10;
begin
  Result := AString;

  for var i := Length(Result) downto 1 do
    if Pos(Result[i], Whitespace) = 0 then
    begin
      Result := Copy(Result, 1, i);
      Break;
    end;
end;

function TrimWhitespace(const AString: String): String;
begin
  Result := LTrimWhitespace(RTrimWhitespace(AString));
end;

end.
