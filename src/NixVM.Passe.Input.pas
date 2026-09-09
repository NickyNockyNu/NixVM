{
  NixVM.Passe.Input.pas
    Keyboard, mouse and gamepad

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

unit NixVM.Passe.Input;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  Winapi.Windows;

type
  {$REGION 'Keyboard'}
  PKeyStates = ^TKeyStates;
  TKeyStates = packed record
  type
    {$REGION 'Key'}
    TKey = type Byte;

    TKeyHelper = record helper for TKey
      procedure Update(ANewState: Boolean); inline;

      function IsUp:   Boolean; inline;
      function IsDown: Boolean; inline;

      function WasPressed:  Boolean; inline;
      function WasReleased: Boolean; inline;

      function IsHeld: Boolean; inline;
    end;
    {$ENDREGION}
  public
    Keys: packed array[Byte] of TKey;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'Keyboard buffer'}
  PKeyboardBuffer = ^TKeyboardBuffer;
  TKeyboardBuffer = packed record
  public
    Head: Byte;
    Tail: Byte;

    Chars: packed array[Byte] of AnsiChar;

    procedure Reset;

    procedure PushChar(AChar: AnsiChar);
    function  PopChar: AnsiChar;
  end;
  {$ENDREGION}

  {$REGION 'Mouse'}
  PMouse = ^TMouse;
  TMouse = record
    X: SmallInt;
    Y: SmallInt;
    Z: SmallInt;

    DeltaX: SmallInt;
    DeltaY: SmallInt;
    DeltaZ: SmallInt;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'Gamepad'}
  PGamepad = ^TGamepad;
  TGamepad = packed record
  public
    Availible: Byte; // TODO: Maybe this should be flags (in registers?)

    Map: packed record
      Up:    Byte;
      Down:  Byte;
      Left:  Byte;
      Right: Byte;

      Start: Byte;
      Back:  Byte;

      LThumb: Byte;
      RThumb: Byte;

      LShoulder: Byte;
      RShoulder: Byte;

      A, B, X, Y: Byte;
    end;

    LTrigger: Single;
    RTrigger: Single;

    LThumbX: Single;
    LThumbY: Single;

    RThumbX: Single;
    RThumbY: Single;

    LVibrate: Single;
    RVibrate: Single;
  end;

  PGamepads = ^TGamepads;
  TGamepads = packed record
  const
    Count = 2;
  public
    Gamepads: packed array[0..Count - 1] of TGamepad;

    procedure Reset;
  end;
  {$ENDREGION}

implementation

{$REGION 'Keyboard'}

{$REGION 'Key'}
procedure TKeyStates.TKeyHelper.Update(ANewState: Boolean);
begin
  Self := (Self and 1) shl 1;

  if ANewState then
    Self := Self or 1;
end;

function TKeyStates.TKeyHelper.IsUp: Boolean;
begin
  Result := (Self and 1) = 0;
end;

function TKeyStates.TKeyHelper.IsDown: Boolean;
begin
  Result := (Self and 1) = 1;
end;

function TKeyStates.TKeyHelper.WasPressed: Boolean;
begin
  Result := Self = 1;
end;

function TKeyStates.TKeyHelper.WasReleased: Boolean;
begin
  Result := Self = 2;
end;

function TKeyStates.TKeyHelper.IsHeld: Boolean;
begin
  Result := Self = 3;
end;
{$ENDREGION}

procedure TKeyStates.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);
end;
{$ENDREGION}

{$REGION 'Keyboard buffer'}
procedure TKeyboardBuffer.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);
end;

procedure TKeyboardBuffer.PushChar(AChar: AnsiChar);
var
  Next: Byte;
begin
  Next := Byte(Tail + 1);

  if Next = Head then
    Exit;

  Chars[Tail] := AChar;

  Tail := Next;
end;

function TKeyboardBuffer.PopChar: AnsiChar;
var
  Next: Byte;
begin
  if Tail = Head then
    Exit(#0);

  Next := Byte(Head + 1);

  Result := Chars[Head];

  Head := Next;
end;
{$ENDREGION}

{$REGION 'Mouse'}
procedure TMouse.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);
end;
{$ENDREGION}

{$REGION 'Gamepad'}
procedure TGamepads.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);
end;
{$ENDREGION}

end.
