{
  NixVM.Passe.Video.pas
    Passe video memory records

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
      MaskFrameBuffer = %00000001;
      MaskConsole     = %00000010;
      MaskStickers    = %00000100;
      MaskSprites     = %00001000;
      MaskFlipX       = %00010000;
      MaskFlipY       = %00100000;
      MaskPersist     = %01000000;
      MaskBuffered    = %10000000;
    private
      function  GetFlag(AMask: Integer):         Boolean;  inline;
      procedure SetFlag(AMask: Integer; AEnable: Boolean); inline;
    public

      property FrameBufferEnabled: Boolean index MaskFrameBuffer read GetFlag write SetFlag;
      property ConsoleEnabled:     Boolean index MaskConsole     read GetFlag write SetFlag;
      property StickersEnabled:    Boolean index MaskStickers    read GetFlag write SetFlag;
      property SpritesEnabled:     Boolean index MaskSprites     read GetFlag write SetFlag;

      property FlipX: Boolean index MaskFlipX read GetFlag write SetFlag;
      property FlipY: Boolean index MaskFlipY read GetFlag write SetFlag;

      property BufferPersist:    Boolean index MaskPersist  read GetFlag write SetFlag;
      property HardwareBuffered: Boolean index MaskBuffered read GetFlag write SetFlag;
    end;
    {$ENDREGION}
  public
    DisplayBuffer: Cardinal;
    DrawBuffer:    Cardinal;
    Palette:       Cardinal;
    Scanlines:     Cardinal;
    Font:          Cardinal;
    Console:       Cardinal;

    BorderColour: TColour;
    TintColour:   TColour;

    OffsetX: SmallInt;
    OffsetY: SmallInt;

    Flags: TFlags;

    ScanlineIRQ: Byte;

    CaretX:         Byte;
    CaretY:         Byte;
    CaretChar:      AnsiChar;
    CaretBlinkRate: Byte;
    CaretAttrib:    Byte;
    CaretTabStop:   Byte;

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

  {$REGION 'Scanlines'}
  PScanlines = ^TScanlines;
  TScanlines = packed record
  type
    {$REGION 'Scanline'}
    PScanline = ^TScanline;
    TScanline = packed record
      Source: Byte;

      HorizontalOffset: SmallInt;
      HorizontalScale:  Single;

      PaletteOffset: ShortInt;
    end;
    {$ENDREGION}
  public
    Lines: packed array[0..TFrameBuffer.Height - 1] of TScanline;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'Font'}
  PFont = ^TFont;
  TFont = packed record
  const
    CharHeight = 8;
  type
    TData = packed array[Byte, 0..CharHeight - 1] of Byte;
  public
    Data: TData;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'Console'}
  PConsole = ^TConsole;
  TConsole = packed record
  const
    Width  = TFrameBuffer.Width  div 8;
    Height = TFrameBuffer.Height div TFont.CharHeight;
  public
    Chars:   array[0..Height - 1, 0..Width - 1] of AnsiChar;
    Attribs: array[0..Height - 1, 0..Width - 1] of Byte;

    procedure Reset;

    function ToString: AnsiString;
  end;
  {$ENDREGION}

  {$REGION 'Stickers'}
  PStickers = ^TStickers;
  TStickers = packed record
  const
    Count = 64; // Is this too many for stickers?
  type
    PSticker = ^TSticker;
    TSticker = packed record
    type
      {$REGION 'Flags'}
      TFlags = type Byte;

      TFlagsHelper = record helper for TFlags
      const
        MaskFlipX    = %00000001;
        MaskFlipY    = %00000010;
        MaskScaleX   = %00001100;
        MaskScaleY   = %00110000;
        MaskInvert   = %01000000;
        MaskXOR      = %10000000;

        LocScaleX = 2;
        LocScaleY = 4;
      private
        function  GetFlag(AMask: Integer): Boolean;          inline;
        procedure SetFlag(AMask: Integer; AEnable: Boolean); inline;

        function  Get2bOpt(ALoc: Integer): Byte; inline;
        procedure Set2bOpt(ALoc: Integer; AValue: Byte); inline;
      public
        property FlipX: Boolean index MaskFlipX read GetFlag write SetFlag;
        property FlipY: Boolean index MaskFlipY read GetFlag write SetFlag;

        property ScaleX: Byte index LocScaleX read Get2bOpt write Set2bOpt;
        property ScaleY: Byte index LocScaleY read Get2bOpt write Set2bOpt;

        property Invert: Boolean index MaskInvert read GetFlag write SetFlag;
        property &XOR:   Boolean index MaskXOR    read GetFlag write SetFlag;
      end;
      {$ENDREGION}

      {$REGION 'Anchor'}
      TAnchor = type Byte;

      TAnchorHelper = record helper for TAnchor
      const
        RelativeScreen = Count; // or any other value between Count and RelativeMouse
        RelativeMouse  = 127;
      private
        function  GetPriority: Boolean;            inline;
        procedure SetPriority(APriority: Boolean); inline;

        function  GetRelative: Byte;            inline;
        procedure SetRelative(ARelative: Byte); inline;
      public
        property Priority: Boolean read GetPriority write SetPriority;
        property Relative: Byte    read GetRelative write SetRelative;
      end;
      {$ENDREGION}
    public
      X: SmallInt;
      Y: SmallInt;

      Colour: Byte;
      Glyph:  AnsiChar;

      Flags:  TFlags;
      Anchor: TAnchor;
    end;
  public
    Stickers: packed array[0..Count - 1] of TSticker;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'Sprites'}
  PSprites = ^TSprites;
  TSprites = packed record
  const
    AtlasCount  = 128;
    SpriteCount = 32;
  type
    {$REGION 'AtlasEntry'}
    PAtlasEntry = ^TAtlasEntry;
    TAtlasEntry = packed record
      Address: Cardinal;
      Stride:  Integer;  // Strides can be negative

      Width:  Word;
      Height: Word;

      Reserved: Cardinal;
    end;
    {$ENDREGION}

    {$REGION 'Sprite'}
    PSprite = ^TSprite;
    TSprite = packed record
    type
      {$REGION 'Flags'}
      TFlags = type Byte;

      TFlagsHelper = record helper for TFlags
      const
        MaskEnabled = %00000001;
        MaskFlipX   = %00000010;
        MaskFlipY   = %00000100;
      private
        function  GetFlag(AMask: Integer): Boolean;          inline;
        procedure SetFlag(AMask: Integer; AEnable: Boolean); inline;
      public
        property Enabled: Boolean index MaskEnabled read GetFlag write SetFlag;

        property FlipX: Boolean index MaskFlipX read GetFlag write SetFlag;
        property FlipY: Boolean index MaskFlipY read GetFlag write SetFlag;
      end;
      {$ENDREGION}
    public
      AtlasID: Byte;

      X: Single;
      Y: Single;
      Z: Byte;

      ScaleX: Single;
      ScaleY: Single;

      Angle:  Single;
      PivotX: Single;
      PivotY: Single;

      PaletteOffset: ShortInt;

      Flags: TFlags;
    end;
    {$ENDREGION}
  public
    Atlas:   packed array[0..AtlasCount  - 1] of TAtlasEntry;
    Sprites: packed array[0..SpriteCount - 1] of TSprite;

    procedure Reset;
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

  Flags := TFlags.MaskFrameBuffer or TFlags.MaskConsole or TFlags.MaskStickers or TFlags.MaskSprites;

  CaretChar      := '_';
  CaretBlinkRate := 30;
  CaretAttrib    := $07;
  CaretTabStop   := 8;
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

{$REGION 'Scanlines'}
procedure TScanlines.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);

  for var i := 0 to Length(Lines) - 1 do
    with Lines[i] do
    begin
      Source := i;

      HorizontalOffset := 0;
      HorizontalScale  := 1;

      PaletteOffset := 0;
    end;
end;
{$ENDREGION}

{$REGION 'Font'}
procedure TFont.Reset;
{$INCLUDE 'NixVM.Passe.Font.Thin.inc'}
begin
  Move(FontData, Data, SizeOf(Data));
end;
{$ENDREGION}

{$REGION 'Console'}
procedure TConsole.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);
end;

function TConsole.ToString: AnsiString;
var
  Line: AnsiString;
  C:    AnsiChar;
begin
  Result := '';

  for var y := 0 to Height - 1 do
  begin
    Line := '';

    for var x := 0 to Width - 1 do
    begin
      C := Chars[y, x];

      if (C < #32) or (C > #128) then
        C := #32;

      Line := Line + C;
    end;

    for var x := Length(Line) downto 1 do
      if (Line[x] <> #32) then
      begin
        Result := Result + Copy(Line, 1, x);
        Break;
      end;

    Result := Result + #13#10;
  end;

  for var x := Length(Result) downto 1 do
    case Result[x] of
      #13, #10, #32: ;
    else
      Result := Copy(Result, 1, x);
      Break;
    end;
end;
{$ENDREGION}

{$REGION 'Stickers'}

{$REGION 'Flags'}
function TStickers.TSticker.TFlagsHelper.GetFlag(AMask: Integer): Boolean;
begin
  Result := (Self and AMask) <> 0
end;

procedure TStickers.TSticker.TFlagsHelper.SetFlag(AMask: Integer; AEnable: Boolean);
begin
  if AEnable then
    Self := Self or AMask
  else
    Self := Self and not AMask;
end;

function TStickers.TSticker.TFlagsHelper.Get2bOpt(ALoc: Integer): Byte;
begin
  Result := (Self shr ALoc) and %11;
end;

procedure TStickers.TSticker.TFlagsHelper.Set2bOpt(ALoc: Integer; AValue: Byte);
begin
  Self := (Self and not (%11 shl ALoc)) or ((AValue and %11) shl ALoc);
end;
{$ENDREGION}

{$REGION 'Anchor'}
function TStickers.TSticker.TAnchorHelper.GetPriority: Boolean;
begin
  Result := (Self and %10000000) <> 0;
end;

procedure TStickers.TSticker.TAnchorHelper.SetPriority(APriority: Boolean);
begin
  if APriority then
    Self := Self or  %10000000
  else
    Self := Self and %01111111;
end;

function TStickers.TSticker.TAnchorHelper.GetRelative: Byte;
begin
  Result := (Self and %01111111);
end;

procedure TStickers.TSticker.TAnchorHelper.SetRelative(ARelative: Byte);
begin
  Self := (Self and %10000000) or (ARelative and %01111111);
end;
{$ENDREGION}

procedure TStickers.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);

  for var i := 0 to Count - 1 do
    Stickers[0].Anchor.Relative := TSticker.TAnchor.RelativeScreen;

  with Stickers[0] do
  begin
    Glyph  := #28;
    Colour := 15;

    Flags.&XOR := True;

    Anchor.Relative := TAnchor.RelativeMouse;
    Anchor.Priority := True;
  end;
end;
{$ENDREGION}

{$REGION 'Sprites'}

{$REGION 'Flags'}
function TSprites.TSprite.TFlagsHelper.GetFlag(AMask: Integer): Boolean;
begin
  Result := (Self and AMask) <> 0
end;

procedure TSprites.TSprite.TFlagsHelper.SetFlag(AMask: Integer; AEnable: Boolean);
begin
  if AEnable then
    Self := Self or AMask
  else
    Self := Self and not AMask;
end;
{$ENDREGION}

procedure TSprites.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);

  for var i := 0 to SpriteCount do
    with Sprites[i] do
    begin
      Z := i;

      AtlasID := i;

      ScaleX := 1.0;
      ScaleY := 1.0;

      PivotX := 0.5;
      PivotY := 0.5;
    end;
end;
{$ENDREGION}

end.
