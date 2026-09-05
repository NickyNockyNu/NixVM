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

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  Winapi.MultiMon,
  Winapi.OpenGL,
  Winapi.OpenGLext,

  NixVM.Core.System,

  NixVM.Harness,
  NixVM.Harness.PE,
  NixVM.Harness.Timing,
  NixVM.Harness.Window,
  NixVM.Harness.Passe,

  NixVM.Passe.Memory,
  NixVM.Passe.Video,
  NixVM.Passe.Renderer;

type
  {$REGION 'Passe'}
  TPasse = class(TPasseHarness)
  private
    FClientWidth:  Integer;
    FClientHeight: Integer;
    FViewport:     TRect;
    FScale:        Single;

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

    property Renderer: TRenderer read FRenderer;
  protected
    procedure WMWindowPosChanged(var AMessage: TWMWindowPosChanged); message WM_WINDOWPOSCHANGED;
    procedure WMSize            (var AMessage: TWMSize);             message WM_SIZE;
  public
    class procedure CError(const AMessage: String; AErrorCode: Integer = 0); override;

    property ClientWidth:  Integer read FClientWidth;
    property ClientHeight: Integer read FClientHeight;

    property Viewport: TRect read FViewport;

    property Scale: Single read FScale write SetScale;
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
  Writeln('D:\NixVM\bin\nvm.exe stamp D:\NixVM\bin\harness.passe.exe -base $' + IntToHex(Memory.UserAddress, 0) + ' -oem ' + IntToStr(SizeOf(TPasseMemory)));

  if Assigned(Passe) then
    Error('An instance of passe already exists');

  Passe := Self;

  inherited;

  SetScale(0);
end;

procedure TPasse.Finalize;
begin
  inherited;

  Passe := nil;
end;

procedure TPasse.CreateWindow;
begin
  inherited;

  FRenderer := TRenderer.Create(Self);
end;

procedure TPasse.DestroyWindow;
begin
  FRenderer.Free;

  inherited;
end;

procedure TPasse.Started;
begin
  Memory.System.Reset;

  inherited;
end;

procedure TPasse.Stopped;
begin
  inherited;
end;

procedure TPasse.Update(const ADelta: TTicks);
begin
  inherited;

  FRenderer.Render;
  FRenderer.Paint;

  ProcessMessages(False);
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

procedure TPasse.WMWindowPosChanged(var AMessage: TWMWindowPosChanged);
begin
  if (AMessage.WindowPos.flags and SWP_NOSIZE) = 0 then
    Resized;
end;

procedure TPasse.WMSize(var AMessage: TWMSize);
begin
  Resized;
end;

class procedure TPasse.CError(const AMessage: String; AErrorCode: Integer = 0);
begin
  if Assigned(Passe) then
    Passe.Error(AMessage, AErrorCode)
  else
    inherited;
end;
{$ENDREGION}

end.
