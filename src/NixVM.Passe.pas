{
  NixVM.Passe.pas
    The Passe VM

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

unit NixVM.Passe;

{
  TODO:
    System flag to switch between PollRate=FrameRate and PollRate=YieldRate
    May as well profile that (Yields per second - Yields:Frame ratio)
    We could probably even try to implement some kind of smart CPU batch size based on
    instruction count between yields - or at least have some interesting profiling stats

    if Yield=Poll then do we switch keyboard reading methods to read from the message queue?

    Fullscreen switch (Part of TCustomWindow harness or here?)

    Panic screen

    SysRq key

    Screen capture

    Console capture (Ctrl+C -> to clipboard)

    Debug layer

    Audio PCM channel
    Audio Beep channel

    AudioRegisters.Level = Current audio level

    Sprite raster operations
      normal
      add, sub
      colour/mask (PaletteOfs becomes a the absolute palette index of the colour)

    DrawBuffer
      Scroll(x, y)
      DrawText(x, y, text, colour)
      DrawTextEx(x, y, text, colour, scalex, scaley, flipx, flipy, bold, italic, (font?))
      DrawSprite(atlasid, x, y, scalex, scaley)
      DrawSpriteEx(atlasid, x, y, scalex, scaley, pivetx, pivety, angle, rasterop)

    Console
      A way of supporting all characters in print (probably an escape code)
      Scroll(x, y)
}

{$INCLUDE 'NixVM.Options.inc'}
{.$DEFINE BUILD_HELPER}

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  Winapi.MultiMon,
  Winapi.OpenGL,
  Winapi.OpenGLext,

  NixVM.Core.System,
  NixVM.Core.Memory,

  NixVM.Harness,
  NixVM.Harness.PE,
  NixVM.Harness.Timing,
  NixVM.Harness.Window,
  NixVM.Harness.Passe,

  NixVM.Passe.Memory,
  NixVM.Passe.Input,
  NixVM.Passe.Input.HID,
  NixVM.Passe.Audio,
  NixVM.Passe.Audio.SID,
  NixVM.Passe.Video,
  NixVM.Passe.Video.VDU,
  NixVM.Passe.Renderer;

type
  {$REGION 'Passe'}
  TPasse = class(TPasseHarness)
  private
    FClientWidth:  Integer;
    FClientHeight: Integer;
    FViewport:     TRect;
    FScale:        Single;

    FHID: THID;
    FSID: TSID;
    FVDU: TVDU;

    FRenderer: TRenderer;

    procedure SetScale(AScale: Single);
  protected
    procedure Initialize; override;
    procedure Finalize;   override;

    procedure CreateWindow;  override;
    procedure DestroyWindow; override;

    procedure Started; override;
    procedure Stopped; override;

    procedure Update(const ADelta: TTicks); override;

    procedure Resized;

    procedure HandleYield; override;

    function HandleSysCall(ASysCall: TSysCalls.ID): Boolean; override;

    property Renderer: TRenderer read FRenderer;
  protected
    procedure WMWindowPosChanged(var AMessage: TWMWindowPosChanged); message WM_WINDOWPOSCHANGED;
    procedure WMSize            (var AMessage: TWMSize);             message WM_SIZE;
    procedure WMChar            (var AMessage: TWMChar);             message WM_CHAR;
    procedure WMMouseWheel      (var AMessage: TWMMouseWheel);       message WM_MOUSEWHEEL;
  public
    class procedure CError(const AMessage: String; AErrorCode: Integer = 0); override;

    procedure HandleMessage(var AMessage: TMessage); override;

    function HandleScanlineIRQ: Boolean;

    procedure DebugPrint(const AString: AnsiString); override;

    property ClientWidth:  Integer read FClientWidth;
    property ClientHeight: Integer read FClientHeight;

    property Viewport: TRect read FViewport;

    property Scale: Single read FScale write SetScale;

    property HID: THID read FHID;
    property SID: TSID read FSID;
    property VDU: TVDU read FVDU;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Core.Strings;

{$REGION 'Passe'}
procedure TPasse.SetScale(AScale: Single);
var
  HMon: HMONITOR;
  MI:   TMonitorInfo;

  MonW: Integer;
  MonH: Integer;

  MaxW: Integer;
  MaxH: Integer;
  MaxS: Integer;

  Style:   Integer;
  ExStyle: Integer;

  Rect:   TRect;
  Border: Integer;
begin
  HMon := MonitorFromWindow(Handle, MONITOR_DEFAULTTOPRIMARY);
  MI.cbSize := SizeOf(MI);

  if GetMonitorInfo(HMon, @MI) then
  begin
    MonW := MI.rcWork.Right  - MI.rcWork.Left;
    MonH := MI.rcWork.Bottom - MI.rcWork.Top;
  end
  else
  begin
    MonW := GetSystemMetrics(SM_CXSCREEN);
    MonH := GetSystemMetrics(SM_CYSCREEN);
  end;

  Style   := GetWindowLong(Handle, GWL_STYLE);
  ExStyle := GetWindowLong(Handle, GWL_EXSTYLE);

  Border := 0;//GetSystemMetrics(SM_CYCAPTION);

  Rect := TRect.Create(0, 0, 0, 0);
  AdjustWindowRectEx(Rect, Style, False, ExStyle);

  Rect.Width  := Rect.Width  + (Border * 2);
  Rect.Height := Rect.Height +  Border;

  MaxW := MonW - Rect.Width;
  MaxH := MonH - Rect.Height;

  MaxS := MaxW div TFrameBuffer.Width;

  if (MaxH div TFrameBuffer.Height) < MaxS then
    MaxS := MaxH div TFrameBuffer.Height;

  if MaxS < 1 then
    MaxS := 1;

  if (AScale < 1) or (AScale > MaxS) then
    AScale := MaxS;

  Rect.Width  := Rect.Width  + Round(TFrameBuffer.Width  * AScale);
  Rect.Height := Rect.Height + Round(TFrameBuffer.Height * AScale);

  Rect.SetLocation(
    (MonW div 2) - (Rect.Width  div 2),
    (MonH div 2) - (Rect.Height div 2)
  );

  SetWindowPos(Handle, 0, Rect.Left, Rect.Top, Rect.Width, Rect.Height, 0);
end;

procedure TPasse.Initialize;
begin
{$IF DEFINED(BUILD_HELPER)}
  Writeln('  _Addr_KeyStates      = $', IntToHex(TPasseMemory.KeyStatesAddress), ';');
  Writeln('  _Addr_KeyboardBuffer = $', IntToHex(TPasseMemory.KeyboardBufferAddress), ';');
  Writeln('  _Addr_Mouse          = $', IntToHex(TPasseMemory.MouseAddress), ';');
  Writeln('  _Addr_Gamepads       = $', IntToHex(TPasseMemory.GamepadsAddress), ';');
  Writeln('  _Addr_VideoRegisters = $', IntToHex(TPasseMemory.VideoRegistersAddress), ';');
  Writeln('  _Addr_Stickers       = $', IntToHex(TPasseMemory.StickersAddress), ';');
  Writeln('  _Addr_Atlas          = $', IntToHex(TPasseMemory.SpritesAddress), ';');
  Writeln('  _Addr_Sprites        = $', IntToHex(TPasseMemory.SpritesAddress + (SizeOf(TSprites.TAtlasEntry) * TSprites.AtlasCount)), ';');

  Writeln('  _Addr_AudioRegisters = $', IntToHex(TPasseMemory.AudioRegistersAddress), ';');
  Writeln('  _Addr_AudioChannels  = $', IntToHex(TPasseMemory.AudioChannelsAddress), ';');

  Writeln('D:\NixVM\bin\nvm.exe stamp D:\NixVM\bin\harness.passe.exe -base $' + IntToHex(Memory.UserAddress, 0) + ' -oem ' + IntToStr(SizeOf(TPasseMemory)));
{$ENDIF}

  if Assigned(Passe) then
    Error('An instance of passe already exists');

  //StopOnHalt := True;

  Passe := Self;

  inherited;

  FHID := THID.Create(Self);
  FVDU := TVDU.Create(Self);
  FSID := TSID.Create(Self);

  FRenderer := TRenderer.Create(Self);

  SetScale(0);
end;

procedure TPasse.Finalize;
begin
  inherited;

  FRenderer.Free;

  FSID.Free;
  FHID.Free;
  FVDU.Free;

  Passe := nil;
end;

procedure TPasse.CreateWindow;
begin
  inherited;
end;

procedure TPasse.DestroyWindow;
begin
  inherited;
end;

procedure TPasse.Started;
begin
  Memory.System.Reset;

  FVDU.Reset;
  FHID.Reset;
  FSID.Reset;

  FSID.Start;

  inherited;
end;

procedure TPasse.Stopped;
begin
  FSID.Stop;

  inherited;
end;

procedure TPasse.Update(const ADelta: TTicks);
begin
  inherited;

  FHID.PollMouse;

  if not Memory.System.VideoRegisters.Flags.HardwareBuffered then
     FRenderer.Render;

  FRenderer.Paint;
end;

procedure TPasse.Resized;
var
  Border:   Integer;
  Rect:     TRect;
  W, H:     Integer;
  SrcRatio: Single;
  DstRatio: Single;
begin
  GetClientRect(Handle, Rect);

  Border := 0;//GetSystemMetrics(SM_CYCAPTION);

  FClientWidth  := Rect.Width;
  FClientHeight := Rect.Height;

  W := FClientWidth  - (Border * 2);
  H := FClientHeight -  Border;

  if W < 1 then W := 1;
  if H < 1 then H := 1;

  SrcRatio := TFrameBuffer.Width / TFrameBuffer.Height;
  DstRatio := W / H;

  if DstRatio > SrcRatio then
    FScale := H / TFrameBuffer.Height
  else
    FScale := W / TFrameBuffer.Width;

  W := Round(TFrameBuffer.Width  * FScale);
  H := Round(TFrameBuffer.Height * FScale);

  FViewport.Left   := ((FClientWidth  - W) div 2);
  FViewport.Top    := ((FClientHeight - H - Border) div 2);
  FViewport.Width  := W;
  FViewport.Height := H;

  if Running then
    FRenderer.Paint;
end;

procedure TPasse.HandleYield;
begin
  inherited;

  FHID.PollKeys;
  FHID.PollMouse;
  FHID.UpdateDeltas;

  if Memory.System.VideoRegisters.Flags.HardwareBuffered then
     FRenderer.Render;
end;

function TPasse.HandleSysCall(ASysCall: TSysCalls.ID): Boolean;
begin
  Result := inherited;

  if Result then
    Exit;

  Result := True;

  with CPU.Registers do
    case ASysCall of
      TVDU.TSysCalls.Reset: FVDU.Reset;
      TVDU.TSysCalls.Clear: FVDU.Clear(R0);

      TVDU.TSysCalls.GetPixel: R0 := FVDU.GetPixel(R0, R1);
      TVDU.TSysCalls.SetPIxel:       FVDU.SetPixel(R0, R1, R2);

      TVDU.TSysCalls.HLine: FVDU.HLine(R0, R1, R2, R3);
      TVDU.TSysCalls.VLine: FVDU.VLine(R0, R1, R2, R3);

      TVDU.TSysCalls.Line: FVDU.Line(R0, R1, R2, R3, R4);

      TVDU.TSysCalls.DrawRectangle: FVDU.DrawRectangle(R0, R1, R2, R3, R4);
      TVDU.TSysCalls.FillRectangle: FVDU.FillRectangle(R0, R1, R2, R3, R4);

      TVDU.TSysCalls.DrawCircle: FVDU.DrawCircle(R0, R1, R2, R3);
      TVDU.TSysCalls.FillCircle: FVDU.FillCircle(R0, R1, R2, R3);

      TVDU.TSysCalls.DrawEllipse: FVDU.DrawEllipse(R0, R1, R2, R3, R4);
      TVDU.TSysCalls.FillEllipse: FVDU.FillEllipse(R0, R1, R2, R3, R4);

      TVDU.TSysCalls.DrawTriangle: FVDU.DrawTriangle(R0, R1, R2, R3, R4, R5, R6);
      TVDU.TSysCalls.FillTriangle: FVDU.FillTriangle(R0, R1, R2, R3, R4, R5, R6);

      TVDU.TSysCalls.Cls:    FVDU.Cls;
      TVDU.TSysCalls.Write:  FVDU.Write(R0, R1, Memory.ReadString(R2), R3);
      TVDU.TSysCalls.Print:  FVDU.Print(Memory.ReadString(R0));
      TVDU.TSysCalls.Locate: FVDU.Locate(R0, R1);
      TVDU.TSysCalls.Colour: FVDU.Colour(R0, R1, (R2 <> 0));

      TSID.TSysCalls.Reset:   FSID.Reset;
      TSID.TSysCalls.NoteOn:  FSID.NoteOn (R0, (R1 <> 0));
      TSID.TSysCalls.NoteOff: FSID.NoteOff(R0);
      TSID.TSysCalls.Beep:    FSID.Beep(PSingle(@R0)^, PSingle(@R1)^);
    else
      Result:= False;
    end;
end;

procedure TPasse.HandleMessage(var AMessage: TMessage);
begin
  case AMessage.Msg of
    WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN: SetCapture(Handle);
    WM_LBUTTONUP,   WM_RBUTTONUP,   WM_MBUTTONUP:   ReleaseCapture;
  end;

  inherited;
end;

procedure TPasse.WMWindowPosChanged(var AMessage: TWMWindowPosChanged);
begin
  if (AMessage.WindowPos.flags and SWP_NOSIZE) = 0 then
    Resized;
end;

procedure TPasse.WMSize(var AMessage: TWMSize);
begin
  Resized;
end;

procedure TPasse.WMChar(var AMessage: TWMChar);
begin
  if Assigned(FHID) then
    FHID.PushChar(AnsiChar(AMessage.CharCode));
end;

procedure TPasse.WMMouseWheel(var AMessage: TWMMouseWheel);
begin
  if Assigned(FHID) then
    FHID.HandleScroll(AMessage.WheelDelta div WHEEL_DELTA);
end;

class procedure TPasse.CError(const AMessage: String; AErrorCode: Integer);
begin
  if Assigned(Passe) then
    Passe.Error(AMessage, AErrorCode)
  else
    inherited;
end;

function TPasse.HandleScanlineIRQ: Boolean;
begin
  // TODO: Work out a good instruction budget size for scanline interrupts
  Result := CPU.Interrupt(TPasseMemory.ScanlineIRQID, 10000);
end;

procedure TPasse.DebugPrint(const AString: AnsiString);
begin
  if Assigned(FVDU) and Running then
    FVDU.Print(AString)
  else
    inherited;
end;
{$ENDREGION}

end.
