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

function SizeToStr(ASize: Cardinal; APrec: Integer = 2; ATrim: Boolean = True): String;

function TrimWhitespace(const AString: String): String;

function ParseNumber(const S: String; out AValue: Cardinal): Boolean;

function Sanitise(const AString: String): String;

function ExtractFilePath(const AFileName: String): String;
function ExtractFileName(const AFileName: String; ARemoveExt: Boolean = True): String;

function Unescape(const AString: AnsiString): AnsiString;

{$IF DEFINED(MSWINDOWS)}
function  ClipboardToStr(const ADefault: String = ''): String;
procedure StrToClipboard(const AValue: String; AUnicode: Boolean = True);
{$ENDIF}

implementation

{$IF DEFINED(MSWINDOWS)}
uses
  Winapi.Windows;
{$ENDIF}

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

function SizeToStr(ASize: Cardinal; APrec: Integer = 2; ATrim: Boolean = True): String;
var
  RSize: Double;
  SIdx:  Integer;
begin
  SIdx  := 0;
  RSize := ASize;

  while RSize > 900 do
  begin
    RSize := RSize / 1024;

    Inc(SIdx);

    if SIdx = 2 then
      Break;
  end;

  Result := FloatToStr(RSize, APrec, ATrim);

  case SIdx of
    0: Result := Result + 'B';
    1: Result := Result + 'K';
    2: Result := Result + 'M';
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

function Sanitise(const AString: String): String;
const
  ValidChars = '_0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
begin
  Result := '';

  for var c in AString do
    if Pos(c, ValidChars) > 0 then
      Result := Result + c;
end;

function ExtractFilePath(const AFileName: String): String;
begin
  Result := '';

  for var i := Length(AFileName) downto 1 do
    if (AFileName[i] = '\') or (AFileName[i] = '/') then
    begin
      Result := Copy(AFileName, 1, i);
      Break;
    end;

  if Length(Result) = 0 then
    Result := '.\';
end;

function ExtractFileName(const AFileName: String; ARemoveExt: Boolean = True): String;
begin
  Result := AFileName;

  for var i := Length(Result) downto 1 do
    if (Result[i] = '\') or (Result[i] = '/') then
    begin
      Result := Copy(Result, i + 1, Length(Result));
      Break;
    end;

  if ARemoveExt then
    for var i := Length(Result) downto 1 do
      if Result[i] = '.' then
      begin
        Result := Copy(Result, 1, i - 1);
        Break;
      end;
end;

function Unescape(const AString: AnsiString): AnsiString;
var
  Src:   PAnsiChar;
  Dst:   PAnsiChar;
  Val:   Integer;
  Count: Integer;

  function TryGetHex(p: PAnsiChar; out b: Byte): Boolean; inline;
  var
    h1: Word;
    h2: Word;
  begin
    h1 := Ord(p[0]);
    h2 := Ord(p[1]);

    b := 0;

    case h1 of
      48..57:  b := (h1 - 48) shl 4;
      65..70:  b := (h1 - 55) shl 4;
      97..102: b := (h1 - 87) shl 4;
    else
      Exit(False);
    end;

    case h2 of
      48..57:  b := b or (h2 - 48);
      65..70:  b := b or (h2 - 55);
      97..102: b := b or (h2 - 87);
    else
      Exit(False);
    end;

    Result := True;
  end;
begin
  if Length(AString) = 0 then
    Exit('');

  SetLength(Result, Length(AString));

  Src := PAnsiChar(AString);
  Dst := PAnsiChar(Result);

  while Src^ <> #0 do
  begin
    if Src^ = '\' then
    begin
      Inc(Src);

      if Src^ = #0 then
      begin
        Dst^ := '\';
        Inc(Dst);
        Break;
      end;

      case Src^ of
        'a': Dst^ := #7;
        'b': Dst^ := #8;
        't': Dst^ := #9;
        'n': Dst^ := #10;
        'v': Dst^ := #11;
        'f': Dst^ := #12;
        'r': Dst^ := #13;
        'e': Dst^ := #27;

        '?': Dst^ := '?';
        '\': Dst^ := '\';

        '"':  Dst^ := '"';
        '''': Dst^ := '''';

        'x':
        begin
          Inc(Src);

          var b: Byte;
          var HexCount := 0;

          while TryGetHex(Src, b) do
          begin
            Dst^ := AnsiChar(b);

            Inc(Dst);
            Inc(Src, 2);
            Inc(HexCount);
          end;

          if HexCount > 0 then
          begin
            Dec(Src);
            Dec(Dst);
          end
          else
            Dst^ := 'x';
        end;

        '0'..'9':
        begin
          Val   := 0;
          Count := 0;

          while (Src^ >= '0') and (Src^ <= '9') and (Count < 3) do
          begin
            Val := (Val * 10) + (Ord(Src^) - 48);

            Inc(Src);
            Inc(Count);
          end;

          if Val > 255 then
            Val := 255;

          Dst^ := AnsiChar(Val);
          Dec(Src);
        end;
      else
        Dst^ := Src^;
      end;
    end
    else
      Dst^ := Src^;

    Inc(Src);
    Inc(Dst);
  end;

  SetLength(Result, Dst - PAnsiChar(Result));
end;

{$IF DEFINED(MSWINDOWS)}
function ClipboardToStr(const ADefault: String = ''): String;
var
  h: THandle;
  s: AnsiString;
begin
  if not OpenClipboard(0) then
    Exit(ADefault);

  try
    if IsClipboardFormatAvailable(CF_UNICODETEXT) then
    begin
      h := GetClipboardData(CF_UNICODETEXT);

      if h = 0 then
        Exit(ADefault);

      Result := PChar(GlobalLock(h));
      GlobalUnlock(h);
    end
    else if IsClipboardFormatAvailable(CF_TEXT) then
    begin
      h := GetClipboardData(CF_TEXT);

      if h = 0 then
        Exit(ADefault);

      s := PAnsiChar(GlobalLock(h));
      GlobalUnlock(h);

      Result := String(s);
    end
    else
      Result := ADefault;
  finally
    CloseClipboard;
  end;
end;

procedure StrToClipboard(const AValue: String; AUnicode: Boolean = True);
var
  h:   THandle;
  ptr: Pointer;
  sw:  String;
  sa:  AnsiString;
  l:   Integer;
  f:   Cardinal;
begin
  if AUnicode then
  begin
    sw := AValue + #0;
    l  := Length(sw) * SizeOf(Char);
    f  := CF_UNICODETEXT;
  end
  else
  begin
    sa := AnsiString(AValue) + AnsiChar(#0);
    l  := Length(sa);
    f  := CF_TEXT;
  end;

  h := GlobalAlloc(GMEM_MOVEABLE, l);
  if h = 0 then
    Exit;

  ptr := GlobalLock(h);
  if ptr = nil then
  begin
    GlobalFree(h);
    Exit;
  end;

  try
    if AUnicode then
      Move(PChar(sw)^, ptr^, l)
    else
      Move(PAnsiChar(sa)^, ptr^, l);
  finally
    GlobalUnlock(h);
  end;

  if OpenClipboard(0) then
  begin
    try
      EmptyClipboard;

      if SetClipboardData(f, h) <> 0 then
        h := 0;
    finally
      CloseClipboard;
    end;
  end;

  if h <> 0 then
    GlobalFree(h);
end;
{$ENDIF}

end.
