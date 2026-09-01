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

function FloatToStr(AValue: Single; APrec: Integer = 2; ATrim: Boolean = True): String;

function TrimWhitespace(const AString: String): String;

function ParseNumber(const S: String; out AValue: Cardinal): Boolean;

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

function FloatToStr(AValue: Single; APrec: Integer; ATrim: Boolean): String;
var
  S: ShortString;
begin
  Str(AValue:0:APrec, S);
  Result := String(S);

  if ATrim and (Pos('.', Result) > 0) then
  begin
    for var i := Length(Result) downto 1 do
      if Result[i] <> '0' then
      begin
        Result := Copy(Result, 1, i);
        Break;
      end;

    if (Length(Result) > 0) and (Result[Length(Result)] = '.') then
      Delete(Result, Length(Result), 1);
  end;
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

function ParseNumber(const S: String; out AValue: Cardinal): Boolean;
var
  U:          String;
  Code:       Integer;
  SingleVal:  Single;
  Multiplier: Cardinal;
begin
  Result     := False;
  AValue     := 0;
  Multiplier := 1;

  if Length(S) = 0 then
    Exit;

  U := Lowercase(TrimWhitespace(S));

  if (Length(U) > 1) and (U[Length(U)] = 'k') then
  begin
    Multiplier := 1024;

    U := Copy(U, 1, Length(U) - 1);
  end
  else if (Length(U) > 1) and (U[Length(U)] = 'm') then
  begin
    Multiplier := 1024 * 1024;

    U := Copy(U, 1, Length(U) - 1);
  end;

  if Length(U) = 0 then
    Exit;

  if (Length(U) > 2) and (U[1] = '0') and (U[2] = 'x') then
    U := '$' + Copy(U, 3, Length(U));

  if (Length(U) > 1) and (U[1] = '%') then
  begin
    AValue := 0;

    for var i := 2 to Length(U) do
    begin
      if (U[i] <> '0') and (U[i] <> '1') then
        Exit(False);

      AValue := (AValue shl 1) or Cardinal(Ord(U[i]) - Ord('0'));
    end;

    AValue := AValue * Multiplier;

    Exit(True);
  end

  else if (Length(U) > 2) and (U[1] = '0') and (U[2] = 'b') then
  begin
    AValue := 0;

    for var i := 3 to Length(U) do
    begin
      if (U[i] <> '0') and (U[i] <> '1') then
        Exit(False);

      AValue := (AValue shl 1) or Cardinal(Ord(U[i]) - Ord('0'));
    end;

    AValue := AValue * Multiplier;

    Exit(True);
  end;

  Val(U, AValue, Code);

  if Code = 0 then
  begin
    AValue := AValue * Multiplier;

    Exit(True);
  end;

  Val(U, SingleVal, Code);

  if Code = 0 then
  begin
    if Multiplier > 1 then
      SingleVal := SingleVal * Multiplier;

    AValue := PCardinal(@SingleVal)^;

    Exit(True);
  end;
end;

end.
