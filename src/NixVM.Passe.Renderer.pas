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
  private
    FOwner: TPasseHarness;

    FDeviceContext: HDC;
    FRenderContext: HGLRC;

    FTexture: GLuint;

    FRegisters:   PVideoRegisters;
    FFrameBuffer: PFrameBuffer;
    FPalette:     PPalette;
  public
    Buffer: packed array[0..(TFrameBuffer.Width * TFrameBuffer.Height) - 1] of Cardinal;

    constructor Create(AOwner: TPasseHarness);
    destructor  Destroy; override;

    procedure UpdatePointers;

    procedure Render;
    procedure Paint;

    procedure RenderFrameBufferSimple;

    property Owner: TPasseHarness read FOwner;

    property DeviceContext: HDC   read FDeviceContext;
    property RenderContext: HGLRC read FRenderContext;

    property Texture: GLuint  read FTexture;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Passe;

{$REGION 'Renderer'}
constructor TRenderer.Create(AOwner: TPasseHarness);
var
  PixelFormatDesc: TPixelFormatDescriptor;
  PixelFormat:     Integer;
begin
  inherited Create;

  FOwner := AOwner;

  FRegisters := FOwner.Memory.Ptr[SizeOf(TCoreSystemMemory) + TPasseMemory.VideoRegistersAddress];

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

procedure TRenderer.UpdatePointers;
begin
  FFrameBuffer := FOwner.Memory.GetSpan(FRegisters^.DisplayBuffer, SizeOf(TFrameBuffer));
  FPalette     := FOwner.Memory.GetSpan(FRegisters^.Palette,       SizeOf(TPalette));
end;

procedure TRenderer.Render;
begin
  UpdatePointers;

  RenderFrameBufferSimple;

  glBindTexture(GL_TEXTURE_2D, FTexture);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, TFrameBuffer.Width, TFrameBuffer.Height, GL_RGBA, GL_UNSIGNED_BYTE, @Buffer);
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

procedure TRenderer.RenderFrameBufferSimple;
begin
  if (FPalette = nil) or (FFrameBuffer = nil) then
    Exit;

  for var i := 0 to SizeOf(TFrameBuffer) - 1 do
    Buffer[i] := FPalette.Colours[FFrameBuffer.Pixels[i]].RGBA;
end;
{$ENDREGION}

end.
