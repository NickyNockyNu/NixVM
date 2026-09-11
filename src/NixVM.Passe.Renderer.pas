{
  NixVM.Passe.Renderer.pas
    VDU Renderer

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

unit NixVM.Passe.Renderer;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  Winapi.Windows,
  Winapi.OpenGL,
  Winapi.OpenGLext,

  NixVM.Core.Memory,
  NixVM.Core.System,

  NixVM.Harness.Passe,

  NixVM.Passe.Memory,
  NixVM.Passe.Video;

type
  {$REGION 'Renderer'}
  TRenderer = class
  type
    {$REGION 'Cache'}
    TCacheEntry = record
      CX, CY:   SmallInt;
      Active:   Boolean;
      Computed: Boolean;
      Visiting: Boolean;
    end;
    {$ENDREGION}
  private
    FOwner: TPasseHarness;

    FDeviceContext: HDC;
    FRenderContext: HGLRC;

    FBuffer: packed array[0..(TFrameBuffer.Width * TFrameBuffer.Height) - 1] of Cardinal;

    FSpriteOrder: array[0..TSprites.SpriteCount - 1] of Integer;

    FStickerCache: array[0..TStickers.Count - 1] of TCacheEntry;

    FTexture: GLuint;

    FRegisters: PVideoRegisters;
    FStickers:  PStickers;
    FSprites:   PSprites;

    FDebug: Byte;

    procedure SortSprites;
    procedure BuildStickerCache;
  public
    constructor Create(AOwner: TPasseHarness);
    destructor  Destroy; override;

    procedure Render;
    procedure Paint;

    procedure ClearBuffer;

    procedure RenderDisplayBuffer;
    procedure RenderConsole;
    procedure RenderSprites (APriority: Boolean);
    procedure RenderStickers(APriority: Boolean);
    procedure RenderDebug;

    property Owner: TPasseHarness read FOwner;

    property DeviceContext: HDC   read FDeviceContext;
    property RenderContext: HGLRC read FRenderContext;

    property Texture: GLuint  read FTexture;

    property Debug: Byte read FDebug write FDebug;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Core.Strings,

  NixVM.Passe;

{$REGION 'Renderer'}
procedure TRenderer.SortSprites;
var
  i, j, KeyIdx: Integer;
  KeyZ:         Byte;
begin
  for i := 0 to TSprites.SpriteCount - 1 do
    FSpriteOrder[i] := i;

  for i := 1 to TSprites.SpriteCount - 1 do
  begin
    KeyIdx := FSpriteOrder[i];
    KeyZ   := FSprites^.Sprites[KeyIdx].Z;
    j      := i - 1;

    while (j >= 0) and (FSprites^.Sprites[FSpriteOrder[j]].Z > KeyZ) do
    begin
      FSpriteOrder[j + 1] := FSpriteOrder[j];
      Dec(j);
    end;

    FSpriteOrder[j + 1] := KeyIdx;
  end;
end;

procedure TRenderer.BuildStickerCache;
  function Resolve(AIndex: Integer): Boolean;
  var
    ParentIdx: Integer;
  begin
    Result := False;

    if Cardinal(AIndex) >= TStickers.Count then
      Exit;

    with FStickerCache[AIndex], FStickers^.Stickers[AIndex] do
    begin
      if Computed then
        Exit(Active);

      if Visiting then
      begin
        Active   := False;
        Computed := True;

        Exit;
      end;

      Visiting := True;

      if Glyph = #0 then
      begin
        Active   := False;
        Computed := True;

        Exit;
      end;

      if Anchor.Relative = TStickers.TSticker.TAnchor.RelativeMouse then
      begin
        CX := FOwner.Memory.System.Mouse.X + X;
        CY := FOwner.Memory.System.Mouse.Y + Y;

        Active := True;
      end
      else if Anchor.Relative >= TStickers.Count then
      begin
        CX := X;
        CY := Y;

        Active := True;
      end
      else
      begin
        ParentIdx := Anchor.Relative;

        if Resolve(ParentIdx) then
        begin
          CX := FStickerCache[ParentIdx].CX + X;
          CY := FStickerCache[ParentIdx].CY + Y;

          Active := True;
        end
        else
          Active := False;
      end;

      Visiting := False;
      Computed := True;

      Result := Active;
    end;
  end;
begin
  FillChar(FStickerCache, SizeOf(FStickerCache), 0);

  for var i := 0 to TStickers.Count - 1 do
    Resolve(i);
end;

constructor TRenderer.Create(AOwner: TPasseHarness);
var
  PixelFormatDesc: TPixelFormatDescriptor;
  PixelFormat:     Integer;
begin
  inherited Create;

  FOwner := AOwner;

  FRegisters := FOwner.Memory.Ptr[TPasseMemory.VideoRegistersAddress];
  FStickers  := FOwner.Memory.Ptr[TPasseMemory.StickersAddress];
  FSprites   := FOwner.Memory.Ptr[TPasseMemory.SpritesAddress];

  FDeviceContext := GetDC(FOwner.Handle);

  if FDeviceContext = 0 then
    FOwner.Error('Failed to get window DC');

  FillChar(PixelFormatDesc, SizeOf(PixelFormatDesc), 0);

  with PixelFormatDesc do
  begin
    nSize        := SizeOf(PixelFormatDesc);
    nVersion     := 1;
    dwFlags      := PFD_DRAW_TO_WINDOW or PFD_SUPPORT_OPENGL or PFD_DOUBLEBUFFER;
    iPixelType   := PFD_TYPE_RGBA;
    cColorBits   := 32;
    iLayerType   := PFD_MAIN_PLANE;
  end;

  PixelFormat := ChoosePixelFormat(FDeviceContext, @PixelFormatDesc);
  if PixelFormat = 0 then
    FOwner.Error('Failed to choose pixel format');

  if not SetPixelFormat(FDeviceContext, PixelFormat, @PixelFormatDesc) then
    FOwner.Error('Failed to set pixel format');

  FRenderContext := wglCreateContext(FDeviceContext);
  if FRenderContext = 0 then
    FOwner.Error('Failed to create render context');

  if not wglMakeCurrent(FDeviceContext, FRenderContext) then
    FOwner.Error('Failed to activate render context');

  InitOpenGLext;

  glGenTextures(1, @FTexture);

  if FTexture = 0 then
    FOwner.Error('Failed to create buffer texture');

  glBindTexture(GL_TEXTURE_2D, FTexture);

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);

  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, TFrameBuffer.Width, TFrameBuffer.Height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil);
end;

destructor TRenderer.Destroy;
begin
  wglMakeCurrent(0, 0);

  if FTexture <> 0 then
    glDeleteTextures(1, @FTexture);

  if FRenderContext <> 0 then
    wglDeleteContext(FRenderContext);

  if FDeviceContext <> 0 then
    ReleaseDC(FOwner.Handle, FDeviceContext);

  inherited;
end;

procedure TRenderer.Render;
begin
  if FRegisters.Flags.FrameBufferEnabled then
    RenderDisplayBuffer;

  if FRegisters.Flags.SpritesEnabled then
  begin
    SortSprites;
    RenderSprites(False);
  end;

  if FRegisters.Flags.StickersEnabled then
  begin
    BuildStickerCache;
    RenderStickers(False);
  end;

  if FRegisters.Flags.ConsoleEnabled then
    RenderConsole;

  if FRegisters.Flags.SpritesEnabled then
    RenderSprites(True);

  if FRegisters.Flags.StickersEnabled then
    RenderStickers(True);

  if FDebug <> 0 then
    RenderDebug;

  glBindTexture(GL_TEXTURE_2D, FTexture);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, TFrameBuffer.Width, TFrameBuffer.Height, GL_RGBA, GL_UNSIGNED_BYTE, @FBuffer);
end;

procedure TRenderer.Paint;
const
  UV: array[Boolean] of Single = (0, 1);
var
  c:      TColour;
  fx, fy: Boolean;
  ox, oy: Single;
begin
  with FOwner as TPasse do
  begin
    glViewport(0, 0, ClientWidth, ClientHeight);

    c   := FRegisters.BorderColour;
    c.A := 0;

    glClearColor(c.R / 255, c.G / 255, c.B / 255, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);

    if Colour <> c.RGBA then
      Colour := c.RGBA;

    glViewport(
      Viewport.Left,
      ClientHeight - (Viewport.Top + Viewport.Height),
      Viewport.Width,
      Viewport.Height
    );
  end;

  fx := FRegisters.Flags.FlipX;
  fy := FRegisters.Flags.FlipY;

  ox := FRegisters.OffsetX / TFrameBuffer.Width;
  oy := FRegisters.OffsetY / TFrameBuffer.Height;

  c := FRegisters^.TintColour;
  glColor4ubv(@c.RGBA);

  glEnable(GL_TEXTURE_2D);
  glBindTexture(GL_TEXTURE_2D, FTexture);

  glDisable(GL_BLEND);

  glBegin(GL_QUADS);
    glTexCoord2f(UV[    fx] + ox, UV[not fy] + oy); glVertex2i(-1, -1);
    glTexCoord2f(UV[not fx] + ox, UV[not fy] + oy); glVertex2i( 1, -1);
    glTexCoord2f(UV[not fx] + ox, UV[    fy] + oy); glVertex2i( 1,  1);
    glTexCoord2f(UV[    fx] + ox, UV[    fy] + oy); glVertex2i(-1,  1);
  glEnd;

  //DwmFlush;
  SwapBuffers(FDeviceContext);
end;

procedure TRenderer.ClearBuffer;
var
  BufPtr:   PCardinal;
  ClearCol: Cardinal;
begin
  with FRegisters^.BorderColour do
    if (r = g) and (g = b) then
    begin
      FillChar(FBuffer, SizeOf(FBuffer), r);
      Exit;
    end;

  BufPtr   := @FBuffer[0];
  ClearCol := FRegisters^.BorderColour.RGBA;

  for var i := 0 to Length(FBuffer) - 1 do
  begin
    BufPtr^ := ClearCol;
    Inc(BufPtr);
  end;
end;

procedure TRenderer.RenderDisplayBuffer;
var
  DisplayBuffer: PFrameBuffer;
  Palette:       PPalette;
  Scanlines:     PScanlines;

  InPtr:  PByte;
  OutPtr: PCardinal;

  Scanline: TScanlines.PScanline;

  SrcX, SrcY: Integer;

  procedure UpdatePointers;
  begin
    DisplayBuffer := FOwner.Memory.GetSpan(FRegisters^.DisplayBuffer, SizeOf(TFrameBuffer));
    if DisplayBuffer = nil then
      DisplayBuffer := FOwner.Memory.Ptr[TPasseMemory.FrameBufferAddress];

    Palette := FOwner.Memory.GetSpan(FRegisters^.Palette, SizeOf(TPalette));
    if Palette = nil then
      Palette := FOwner.Memory.Ptr[TPasseMemory.PaletteAddress];

    Scanlines := FOwner.Memory.GetSpan(FRegisters^.Scanlines, SizeOf(TScanlines));
    //if Scanlines = nil then
    //  Scanlines := FOwner.Memory.Ptr[TPasseMemory.ScanlinesAddress];
  end;
begin
  UpdatePointers;

  OutPtr := @FBuffer;

  for var y := 0 to TFrameBuffer.Height - 1 do
  begin
    if Y = FRegisters.ScanlineIRQ then
      if TPasse(FOwner).HandleScanlineIRQ then
        UpdatePointers;

    if Scanlines = nil then
    begin
      InPtr := @DisplayBuffer^.Pixels[y * TFrameBuffer.Width];

      for var x := 0 to TFrameBuffer.Width - 1 do
      begin
        OutPtr^ := Palette.Colours[InPtr^].RGBA;

        Inc(InPtr);
        Inc(OutPtr);
      end;
    end
    else
    begin
      Scanline := @Scanlines^.Lines[Y];
      SrcY     := Scanline.Source mod TFrameBuffer.Height;

      for var x := 0 to TFrameBuffer.Width - 1 do
      begin
        SrcX := (TFrameBuffer.Width div 2) + Round((X - (TFrameBuffer.Width div 2)) * Scanline.HorizontalScale) + Scanline.HorizontalOffset;

        if (SrcX >= 0) and (SrcX < TFrameBuffer.Width) then
          OutPtr^ := Palette.Colours[DisplayBuffer.Pixels[(SrcY * TFrameBuffer.Width) + SrcX] + Scanline.PaletteOffset].RGBA
        else
          OutPtr^ := FRegisters.BorderColour.RGBA;

        Inc(OutPtr);
      end;
    end;
  end;
end;

procedure TRenderer.RenderConsole;
var
  Console: PConsole;
  Font:    PFont;
  Palette: PPalette;

  Chr:  AnsiChar;
  Attr: Byte;
  Bits: Byte;

  AddrBase: Cardinal;
  Addr:     PCardinal;

  FG, BG: Cardinal;
  IsBold: Boolean;
  DrawBG: Boolean;

  ShowCaret: Boolean;
  DrawCaret: Boolean;
begin
  Console := FOwner.Memory.GetSpan(FRegisters^.Console, SizeOf(TConsole));
  if Console = nil then
    Exit;

  Font := FOwner.Memory.GetSpan(FRegisters^.Font, SizeOf(TFont));
  if Font = nil then
    Font := FOwner.Memory.Ptr[TPasseMemory.FontAddress];

  Palette := FOwner.Memory.GetSpan(FRegisters^.Palette, SizeOf(TPalette));
  if Palette = nil then
    Palette := FOwner.Memory.Ptr[TPasseMemory.PaletteAddress];

  ShowCaret := (FRegisters.CaretBlinkRate > 0) and (FRegisters.CaretChar <> #0) and ((Round(FOwner.Elapsed * 60) mod FRegisters.CaretBlinkRate) < (FRegisters.CaretBlinkRate shr 1));

  for var Row := 0 to TConsole.Height - 1 do
  begin
    for var Col := 0 to TConsole.Width - 1 do
    begin
      Chr  := Console.Chars  [Row, Col];
      Attr := Console.Attribs[Row, Col];

      DrawCaret := (Row = FRegisters^.CaretY) and (Col = FRegisters^.CaretX) and ShowCaret;
      DrawBG    := ((Attr shr 4) and $07) <> 0;

      if (Chr = #0) and (not DrawCaret) and (not DrawBG) then
        Continue;

      FG := Palette.Colours[ Attr        and $0F].RGBA;
      BG := Palette.Colours[(Attr shr 4) and $07].RGBA;

      IsBold := (Attr and $80) <> 0;

      AddrBase := ((Row * TFont.CharHeight) * TFrameBuffer.Width) + (Col * 8);

      for var dy := 0 to 7 do
      begin
        Bits := Font.Data[Ord(Chr), dy];

        if IsBold then
          Bits := Bits or (Bits shr 1);

        if DrawCaret then
          Bits := Bits xor Font.Data[Ord(FRegisters^.CaretChar), dy];

        if (Bits = 0) and (not DrawBG) then
        begin
          Inc(AddrBase, TFrameBuffer.Width);
          Continue;
        end;

        Addr := @FBuffer[AddrBase];

        if (Bits and $80) <> 0 then Addr[0] := FG else if DrawBG then Addr[0] := BG;
        if (Bits and $40) <> 0 then Addr[1] := FG else if DrawBG then Addr[1] := BG;
        if (Bits and $20) <> 0 then Addr[2] := FG else if DrawBG then Addr[2] := BG;
        if (Bits and $10) <> 0 then Addr[3] := FG else if DrawBG then Addr[3] := BG;
        if (Bits and $08) <> 0 then Addr[4] := FG else if DrawBG then Addr[4] := BG;
        if (Bits and $04) <> 0 then Addr[5] := FG else if DrawBG then Addr[5] := BG;
        if (Bits and $02) <> 0 then Addr[6] := FG else if DrawBG then Addr[6] := BG;
        if (Bits and $01) <> 0 then Addr[7] := FG else if DrawBG then Addr[7] := BG;

        Inc(AddrBase, TFrameBuffer.Width);
      end;
    end;
  end;
end;

procedure TRenderer.RenderSprites(APriority: Boolean);
  function MinI(A, B: Integer): Integer; inline;
  begin
    if A < B then Result := A else Result := B;
  end;

  function MaxI(A, B: Integer): Integer; inline;
  begin
    if A > B then Result := A else Result := B;
  end;

  function MinF(A, B: Single): Single; inline;
  begin
    if A < B then Result := A else Result := B;
  end;

  function MaxF(A, B: Single): Single; inline;
  begin
    if A > B then Result := A else Result := B;
  end;

  function Floor(AVal: Single): Integer; inline;
  begin
    Result := Trunc(AVal);

    if (AVal < 0) and (Frac(AVal) <> 0) then
      Dec(Result);
  end;

  function Ceil(AVal: Single): Integer; inline;
  begin
    Result := Trunc(AVal);

    if (AVal > 0) and (Frac(AVal) <> 0) then
      Inc(Result);
  end;

var
  Palette: PPalette;

  procedure DrawSpriteAxisAligned(const ASprite: TSprites.TSprite; const AAtlas: TSprites.TAtlasEntry; const ASrcData: Pointer);
  var
    SrcW, SrcH:       Integer;
    DstW, DstH:       Integer;
    OffsetX, OffsetY: Integer;
    DstX1, DstY1:     Integer;
    DstX2, DstY2:     Integer;
    ClipX1, ClipY1:   Integer;
    ClipX2, ClipY2:   Integer;
    IsFlipX, IsFlipY: Boolean;
    sx, sy:           Integer;
    ColIdx, PalIdx:   Byte;
    SrcRow:           PByte;
    OutRow:           PCardinal;
  begin
    SrcW := AAtlas.Width;
    SrcH := AAtlas.Height;

    DstW := Round(SrcW * Abs(ASprite.ScaleX));
    DstH := Round(SrcH * Abs(ASprite.ScaleY));

    if (DstW <= 0) or (DstH <= 0) then
      Exit;

    OffsetX := Round(DstW * ASprite.PivotX);
    OffsetY := Round(DstH * ASprite.PivotY);

    DstX1 := Round(ASprite.X) - OffsetX;
    DstY1 := Round(ASprite.Y) - OffsetY;
    DstX2 := DstX1 + DstW - 1;
    DstY2 := DstY1 + DstH - 1;

    ClipX1 := MaxI(0, DstX1);
    ClipY1 := MaxI(0, DstY1);
    ClipX2 := MinI(TFrameBuffer.Width - 1, DstX2);
    ClipY2 := MinI(TFrameBuffer.Height - 1, DstY2);

    if (ClipX1 > ClipX2) or (ClipY1 > ClipY2) then
      Exit;

    IsFlipX := ASprite.Flags.FlipX xor (ASprite.ScaleX < 0);
    IsFlipY := ASprite.Flags.FlipY xor (ASprite.ScaleY < 0);

    for var dy := ClipY1 to ClipY2 do
    begin
      sy := ((dy - DstY1) * SrcH) div DstH;
      if IsFlipY then
        sy := (SrcH - 1) - sy;

      SrcRow := PByte(NativeInt(ASrcData) + (sy * AAtlas.Stride));
      OutRow := @FBuffer[dy * TFrameBuffer.Width];

      for var dx := ClipX1 to ClipX2 do
      begin
        sx := ((dx - DstX1) * SrcW) div DstW;

        if IsFlipX then
          sx := (SrcW - 1) - sx;

        ColIdx := PByte(NativeInt(SrcRow) + sx)^;

        if ColIdx <> 0 then
        begin
          PalIdx := Byte(ColIdx + ASprite.PaletteOffset);
          OutRow[dx] := Palette.Colours[PalIdx].RGBA;
        end;
      end;
    end;
  end;

  procedure DrawSpriteRotated(const ASprite: TSprites.TSprite; const AAtlas: TSprites.TAtlasEntry; const ASrcData: Pointer);
  var
    SrcW, SrcH:           Integer;
    Rad:                  Single;
    CosA, SinA:           Single;
    PivX, PivY:           Single;
    ScaleX, ScaleY:       Single;
    FlipSignX, FlipSignY: Single;
    du_dx, dv_dx:         Single;
    du_dy, dv_dy:         Single;
    CornersX:             array[0..3] of Single;
    CornersY:             array[0..3] of Single;
    MinX, MinY:           Integer;
    MaxX, MaxY:           Integer;
    dx0, dy0:             Single;
    u0, v0:               Single;
    u, v:                 Single;
    iu, iv:               Integer;
    ColIdx, PalIdx:       Byte;
    OutRow:               PCardinal;

    procedure RotatePoint(LX, LY: Single; out RX, RY: Single);
    begin
      RX := ASprite.X + (LX * CosA - LY * SinA);
      RY := ASprite.Y + (LX * SinA + LY * CosA);
    end;
  begin
    SrcW := AAtlas.Width;
    SrcH := AAtlas.Height;

    ScaleX := Abs(ASprite.ScaleX);
    ScaleY := Abs(ASprite.ScaleY);

    if (ScaleX < 0.0001) or (ScaleY < 0.0001) then
      Exit;

    Rad  := ASprite.Angle * (PI / 180.0);
    CosA := Cos(Rad);
    SinA := Sin(Rad);

    PivX := SrcW * ASprite.PivotX;
    PivY := SrcH * ASprite.PivotY;

    FlipSignX := 1.0;
    if ASprite.Flags.FlipX xor (ASprite.ScaleX < 0) then
      FlipSignX := -1.0;

    FlipSignY := 1.0;
    if ASprite.Flags.FlipY xor (ASprite.ScaleY < 0) then
      FlipSignY := -1.0;

    du_dx := ( CosA / ScaleX) * FlipSignX;
    dv_dx := (-SinA / ScaleY) * FlipSignY;
    du_dy := ( SinA / ScaleX) * FlipSignX;
    dv_dy := ( CosA / ScaleY) * FlipSignY;

    RotatePoint(-PivX * ScaleX,         -PivY * ScaleY,         CornersX[0], CornersY[0]);
    RotatePoint((SrcW - PivX) * ScaleX, -PivY * ScaleY,         CornersX[1], CornersY[1]);
    RotatePoint((SrcW - PivX) * ScaleX, (SrcH - PivY) * ScaleY, CornersX[2], CornersY[2]);
    RotatePoint(-PivX * ScaleX,         (SrcH - PivY) * ScaleY, CornersX[3], CornersY[3]);

    MinX := MaxI(0, Floor(MinF(MinF(CornersX[0], CornersX[1]), MinF(CornersX[2], CornersX[3]))));
    MinY := MaxI(0, Floor(MinF(MinF(CornersY[0], CornersY[1]), MinF(CornersY[2], CornersY[3]))));

    MaxX := MinI(TFrameBuffer.Width  - 1, Ceil(MaxF(MaxF(CornersX[0], CornersX[1]), MaxF(CornersX[2], CornersX[3]))));
    MaxY := MinI(TFrameBuffer.Height - 1, Ceil(MaxF(MaxF(CornersY[0], CornersY[1]), MaxF(CornersY[2], CornersY[3]))));

    if (MinX > MaxX) or (MinY > MaxY) then
      Exit;

    dx0 := (MinX + 0.5) - ASprite.X;
    dy0 := (MinY + 0.5) - ASprite.Y;

    u0 := PivX + (dx0 * du_dx) + (dy0 * du_dy);
    v0 := PivY + (dx0 * dv_dx) + (dy0 * dv_dy);

    for var dy := MinY to MaxY do
    begin
      u := u0;
      v := v0;
      OutRow := @FBuffer[dy * TFrameBuffer.Width];

      for var dx := MinX to MaxX do
      begin
        if (u >= 0) and (u < SrcW) and (v >= 0) and (v < SrcH) then
        begin
          iu := Trunc(u);
          iv := Trunc(v);

          ColIdx := PByte(NativeInt(ASrcData) + (iv * AAtlas.Stride) + iu)^;
          if ColIdx <> 0 then
          begin
            PalIdx := Byte(ColIdx + ASprite.PaletteOffset);
            OutRow[dx] := Palette.Colours[PalIdx].RGBA;
          end;
        end;

        u := u + du_dx;
        v := v + dv_dx;
      end;

      u0 := u0 + du_dy;
      v0 := v0 + dv_dy;
    end;
  end;
var
  Sprite:         TSprites.PSprite;
  Atlas:          TSprites.PAtlasEntry;
  SrcData:        Pointer;
  IsHighPriority: Boolean;
begin
  Palette := FOwner.Memory.GetSpan(FRegisters^.Palette, SizeOf(TPalette));

  if Palette = nil then
    Palette := FOwner.Memory.Ptr[TPasseMemory.PaletteAddress];

  for var i := 0 to TSprites.SpriteCount - 1 do
  begin
    Sprite := @FSprites^.Sprites[FSpriteOrder[i]];

    if not Sprite^.Flags.Enabled then
      Continue;

    IsHighPriority := (Sprite^.Z >= 128);
    if IsHighPriority <> APriority then
      Continue;

    if Sprite^.AtlasID >= TSprites.AtlasCount then
      Continue;

    Atlas := @FSprites^.Atlas[Sprite^.AtlasID];
    if (Atlas^.Width = 0) or (Atlas^.Height = 0) or (Atlas^.Address = 0) then
      Continue;

    SrcData := FOwner.Memory.GetSpan(Atlas^.Address, 1);
    if SrcData = nil then
      Continue;

    if Abs(Sprite^.Angle) < 0.001 then
      DrawSpriteAxisAligned(Sprite^, Atlas^, SrcData)
    else
      DrawSpriteRotated(Sprite^, Atlas^, SrcData);
  end;
end;

procedure TRenderer.RenderStickers(APriority: Boolean);
var
  Font:    PFont;
  Palette: PPalette;
  OutPtr:  PCardinal;
  RowBits: Byte;
  ReadBit: Byte;
  ColRGB:  Cardinal;
  DX, DY:  SmallInt;
  ScaleX:  Byte;
  ScaleY:  Byte;

begin
  Font := FOwner.Memory.GetSpan(FRegisters^.Font, SizeOf(TFont));

  if Font = nil then
    Font := FOwner.Memory.Ptr[TPasseMemory.FontAddress];

  Palette := FOwner.Memory.GetSpan(FRegisters^.Palette, SizeOf(TPalette));

  if Palette = nil then
    Palette := FOwner.Memory.Ptr[TPasseMemory.PaletteAddress];

  for var i := 0 to TStickers.Count - 1 do
    with FStickerCache[i], FStickers^.Stickers[i] do
    begin
      if (not Active) or (Anchor.Priority <> APriority) then
        Continue;

      if Glyph = #0 then
        Continue;

      ColRGB := Palette.Colours[Colour].RGBA;

      ScaleX := Flags.ScaleX + 1;
      ScaleY := Flags.ScaleY + 1;

      for var fy := 0 to TFont.CharHeight - 1 do
      begin
        if Flags.FlipY then
          RowBits := Font.Data[Ord(Glyph), (TFont.CharHeight - 1) - fy]
        else
          RowBits := Font.Data[Ord(Glyph), fy];

        if Flags.Invert then
          RowBits := not RowBits;

        for var fx := 0 to 7 do
        begin
          if Flags.FlipX then
            ReadBit := fx
          else
            ReadBit := 7 - fx;

          if (RowBits and (1 shl ReadBit)) = 0 then
            Continue;

          for var sy := 0 to ScaleY - 1 do
          begin
            DY := CY + (fy * ScaleY) + sy;

            if Word(DY) >= TFrameBuffer.Height then
              Continue;

            for var sx := 0 to ScaleX - 1 do
            begin
              DX := CX + (fx * ScaleX) + sx;

              if Word(DX) >= TFrameBuffer.Width then
                Continue;

              OutPtr := @FBuffer[(DY * TFrameBuffer.Width) + DX];

              if Flags.&XOR then
                OutPtr^ := OutPtr^ xor $FFFFFF
              else
                OutPtr^ := ColRGB;
            end;
          end;
        end;
      end;
    end;
end;

{$REGION 'Debug bitmap consts'}
type
  TDebugHeader = array[0..4]  of Cardinal;
  TDebugDigit  = array[0..4]  of Byte;
  TDebugDigits = array[0..13] of TDebugDigit;
  TDebugSizes  = array[0..2]  of TDebugHeader;

const
  DBGHEAP: TDebugHeader = (
   %10101110111011100,
   %10101000101010101,
   %11101100111011100,
   %10101000101010001,
   %10101110101010000
  );

  DBGSTACK: TDebugHeader = (
   %111011101110011010100,
   %100001001010100011001,
   %111001001110100011000,
   %001001001010100010101,
   %111001001010011010100
  );

  DBGFPS: TDebugHeader = (
   %1110111011100,
   %1000101010001,
   %1100111011100,
   %1000100000101,
   %1000100011100
  );

  DBGMIPS: TDebugHeader = (
   %10001010111011100,
   %11011010101010001,
   %10101010111011100,
   %10001010100000101,
   %10001010100011100
  );

  DBGDIGITS: TDebugDigits = (
   (
     %111,
     %101,
     %101,
     %101,
     %111
   ), (
     %010,
     %110,
     %010,
     %010,
     %111
   ), (
     %111,
     %001,
     %111,
     %100,
     %111
   ), (
     %111,
     %001,
     %011,
     %001,
     %111
   ), (
     %101,
     %101,
     %111,
     %001,
     %001
   ), (
     %111,
     %100,
     %111,
     %001,
     %111
   ), (
     %010,
     %100,
     %111,
     %101,
     %111
   ), (
     %111,
     %001,
     %010,
     %010,
     %010
   ), (
     %111,
     %101,
     %111,
     %101,
     %111
   ), (
     %111,
     %101,
     %111,
     %001,
     %001
   ), (
     %000,
     %000,
     %000,
     %000,
     %100
   ), (
     %000,
     %000,
     %000,
     %010,
     %100
   ), (
     %001,
     %001,
     %010,
     %100,
     %100
   ), (
     %000,
     %000,
     %111,
     %000,
     %000
   )
  );

  DBGSIZES: TDebugSizes = (
//    (
//      %1100101011101110111,
//      %1010101001001000100,
//      %1100010001001100111,
//      %1010010001001000001,
//      %1100010001001110111
//    ), (
    (
      %110,
      %101,
      %110,
      %101,
      %110
    ), (
      %1010110,
      %1100101,
      %1100110,
      %1010101,
      %1010110
    ), (
      %100010110,
      %110110101,
      %101010110,
      %100010101,
      %100010110
    )
  );
{$ENDREGION}

procedure TRenderer.RenderDebug;
  procedure DrawTitle(var X: Integer; Y: Integer; const ATitle: TDebugHeader; ALength: Byte = 20);
  var
    Addr: PCardinal;
    Bit:  Boolean;
  begin
    for var dy := 0 to 4 do
    begin
      Addr := @FBuffer[((Y + dy) * TFrameBuffer.Width) + X];

      for var dx := 0 to ALength do
      begin
        Bit := ((ATitle[dy] shr (ALength - dx)) and %1) = 1;

        if Bit then
          Addr^ := Addr^ xor $FFFFFF;

        Inc(Addr);
      end;
    end;

    Inc(X, ALength + 3);
  end;

  procedure DrawDigit(var X: Integer; Y: Integer; ANum: Byte);
  var
    Addr:   PCardinal;
    Bit:    Boolean;
    YOfs:   Integer;
  begin
    if ANum = 11 then
      YOFs := 1
    else
      YOfs := 0;

    for var dy := 0 to 4 do
    begin
      Addr := @FBuffer[((Y + YOfs + dy) * TFrameBuffer.Width) + X];

      for var dx := 0 to 2 do
      begin
        Bit := ((DBGDIGITS[ANum][dy] shr (2 - dx)) and %1) = 1;

        if Bit then
          Addr^ := Addr^ xor $FFFFFF;

        Inc(Addr);
      end;
    end;

    case ANum of
      10: Inc(X, 2);
      11: Inc(X, 3);
      12: Inc(X, 5);
    else
      Inc(X, 4);
    end;
  end;

  procedure DrawNumStr(var X: Integer; Y: Integer; const ANumStr: String);
  const
    Digits = '0123456789.,/-';
  begin
    for var c in ANumStr do
    begin
      var i := Pos(c, Digits);

      if i > 0 then
        DrawDigit(X, Y, i - 1);
    end;
  end;

  procedure DrawSize(var X: Integer; Y: Integer; ASize: Cardinal);
  var
    RSize: Double;
    SIdx:  Integer;
    Len:   Integer;
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

    DrawNumStr(X, Y, FloatToStr(RSize, 2, True));

    case SIdx of
      0: Len := 3;
      1: Len := 7;
      2: Len := 9;
    else
      Len := 31;
    end;

    DrawTitle(X, Y, DBGSIZES[SIdx], Len);
  end;
var
  sx, sy: Integer;
  dx, dy: Integer;
begin
  case FDebug of
    1:
    begin
      sx := 4;
      sy := 4;
    end;

    2:
    begin
      sx := 215;
      sy := 4;
    end;

    3:
    begin
      sx := 215;
      sy := 150;
    end;

    4:
    begin
      sx := 4;
      sy := 150;
    end;
  else
    Exit;
  end;

  dx := sx;
  dy := sy;

  DrawTitle (dx, dy, DBGFPS);
  DrawNumStr(dx, dy, IntToStr(FOwner.FPS));

  Inc(dy, 7);
  dx := sx;

  if FOwner.MIPS <= 0.01 then
  begin
    Inc(dx, 10);

    DrawTitle (dx, dy, DBGMIPS, 10);
    DrawNumStr(dx, dy, IntToStr(FOwner.IPS));
  end
  else
  begin
    DrawTitle (dx, dy, DBGMIPS);
    DrawNumStr(dx, dy, FloatToStr(FOwner.MIPS, 2, True));
  end;

  Inc(dy, 7);
  dx := sx;

  DrawTitle (dx, dy, DBGHEAP);
  //DrawSize(dx, dy, 1234560000);
  DrawSize  (dx, dy, FOwner.Memory.Heap.Size - FOwner.Memory.Heap.GetAvailable);
  DrawNumStr(dx, dy, '/');
  //DrawSize(dx, dy, 1234560000);
  DrawSize  (dx, dy, FOwner.Memory.Heap.Size);

  Inc(dy, 7);
  dx := sx;

  DrawTitle (dx, dy, DBGSTACK);
  DrawSize  (dx, dy, FOwner.Memory.Size - FOwner.CPU.Registers.SP);
  DrawNumStr(dx, dy, '/');
  DrawSize  (dx, dy, FOwner.Memory.Stack.Size);
end;
{$ENDREGION}

end.
