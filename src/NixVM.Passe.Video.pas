{
  NixVM.Passe.Video.pas
    Passe video display unit

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

unit NixVM.Passe.Video;

{$INCLUDE 'NixVM.Options.inc'}

interface

type
  {$REGION 'Colour'}
  PColour = ^TColour;
  TColour = packed record case Cardinal of
    0: (RGBA: Cardinal);
    1: (R, G, B, A: Byte);
  end;
  {$ENDREGION}

  {$REGION 'VideoRegisters'}
  PVideoRegisters = ^TVideoRegisters;
  TVideoRegisters = packed record
  type
    {$REGION 'Flags'}
    TFlags = type Byte;

    TFlagsHelper = record helper for TFlags
    const
      MaskFlipX = $01;
      MaskFlipY = $02;
    private
      function  GetFlag(AMask: Integer):         Boolean;  inline;
      procedure SetFlag(AMask: Integer; AEnable: Boolean); inline;
    public
      property FlipX: Boolean index MaskFlipX read GetFlag write SetFlag;
      property FlipY: Boolean index MaskFlipY read GetFlag write SetFlag;
    end;
    {$ENDREGION}
  public
    DisplayBuffer: Cardinal;
    DrawBuffer:    Cardinal;
    Palette:       Cardinal;
    BorderColour:  TColour;
    TintColour:    TColour;
    OffsetX:       SmallInt;
    OffsetY:       SmallInt;
    Flags:         TFlags;

    Reserved: array[0..6] of Byte;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'Palette'}
  PPalette = ^TPalette;
  TPalette = packed record
  public
    Colours: packed array[Byte] of TColour;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'FrameBuffer'}
  PFrameBuffer = ^TFrameBuffer;
  TFrameBuffer = packed record
  const
    Width  = 320;
    Height = 180;
  public
    Pixels: packed array[0..(Width * Height) - 1] of Byte;

    procedure Clear(AColour: Byte);
  end;
  {$ENDREGION}

implementation

{$REGION 'VideoRegisters'}
{$REGION 'Flags'}
function TVideoRegisters.TFlagsHelper.GetFlag(AMask: Integer): Boolean;
begin
  Result := (Self and AMask) <> 0;
end;

procedure TVideoRegisters.TFlagsHelper.SetFlag(AMask: Integer; AEnable: Boolean);
begin
  if AEnable then
    Self := Self or AMask
  else
    Self := Self and not AMask;
end;
{$ENDREGION}

procedure TVideoRegisters.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);

  BorderColour.RGBA := $00000000;
  TintColour.RGBA   := $FFFFFFFF;
end;
{$ENDREGION}

{$REGION 'Palette'}
procedure TPalette.Reset;
const
  DefAlpha = 255;

{$REGION 'StdColours'}
  StdColours: array[0..15] of TColour = (
    (R: $00; G: $00; B: $00; A: $00),      // Black / Transparent
    (R: $00; G: $00; B: $AA; A: DefAlpha), // Dark Blue
    (R: $00; G: $AA; B: $00; A: DefAlpha), // Dark Green
    (R: $00; G: $AA; B: $AA; A: DefAlpha), // Dark Cyan
    (R: $AA; G: $00; B: $00; A: DefAlpha), // Dark Red
    (R: $AA; G: $00; B: $AA; A: DefAlpha), // Dark Magenta
    (R: $AA; G: $55; B: $00; A: DefAlpha), // Brown
    (R: $AA; G: $AA; B: $AA; A: DefAlpha), // Light Gray
    (R: $55; G: $55; B: $55; A: DefAlpha), // Dark Gray
    (R: $55; G: $55; B: $FF; A: DefAlpha), // Light Blue
    (R: $55; G: $FF; B: $55; A: DefAlpha), // Light Green
    (R: $55; G: $FF; B: $FF; A: DefAlpha), // Light Cyan
    (R: $FF; G: $55; B: $55; A: DefAlpha), // Light Red
    (R: $FF; G: $55; B: $FF; A: DefAlpha), // Light Magenta
    (R: $FF; G: $FF; B: $55; A: DefAlpha), // Yellow
    (R: $FF; G: $FF; B: $FF; A: DefAlpha)  // White
  );
{$ENDREGION}
var
  i: Integer;
begin
  for i := 0 to 15 do
    Colours[i] := StdColours[i];

  i := 16;

  for var r := 0 to 5 do
    for var g := 0 to 5 do
      for var b := 0 to 5 do
      begin
        Colours[i].R := r * 51;
        Colours[i].G := g * 51;
        Colours[i].B := b * 51;
        Colours[i].A := DefAlpha;

        Inc(i);
      end;

  for var j := 0 to 23 do
  begin
    var l := (j * 255) div 23;

    Colours[i].R := l;
    Colours[i].G := l;
    Colours[i].B := l;
    Colours[i].A := DefAlpha;

    Inc(i);
  end;
end;
{$ENDREGION}

{$REGION 'FrameBuffer'}
procedure TFrameBuffer.Clear;
begin
  FillChar(Pixels, SizeOf(Pixels), AColour);
end;
{$ENDREGION}

end.
