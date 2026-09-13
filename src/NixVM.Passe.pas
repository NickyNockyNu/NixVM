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
    Skipped frames counter (Frames rendered between yields)

    if Yield=Poll then do we switch keyboard reading methods to read from the message queue?

    Screen capture

    Embed font and palette protocols
    Multi-platform the embed protocols (Use TBitmap?)

    Channel "playing" flag

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

  NixVM.Core.Registers,
  NixVM.Core.Instructions,
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
  const
    SYSMENU_SCALEAUTO   = 3;
    SYSMENU_SCALECOUNT  = 5;
    SYSMENU_DEBUG       = SYSMENU_SCALEAUTO + SYSMENU_SCALECOUNT + 1;
    SYSMENU_COPYCONSOLE = SYSMENU_DEBUG + 5;
  private
    FClientWidth:  Integer;
    FClientHeight: Integer;
    FViewport:     TRect;
    FScale:        Single;

    FHID: THID;
    FSID: TSID;
    FVDU: TVDU;

    FRenderer: TRenderer;

    FDebugMenu: HMENU;

    procedure SetScale(AScale: Single);
  protected
    procedure Initialize; override;
    procedure Finalize;   override;

    procedure UpdateDebugMenu;

    procedure CreateWindow;  override;
    procedure DestroyWindow; override;

    procedure Started; override;
    procedure Stopped; override;

    procedure Update(const ADelta: TTicks); override;

    procedure Resized;

    procedure HandlePanic; override;
    procedure HandleYield; override;

    function HandleSysCall(ASysCall: TSysCalls.ID): Boolean; override;
  protected
    procedure WMWindowPosChanged(var AMessage: TWMWindowPosChanged); message WM_WINDOWPOSCHANGED;
    procedure WMSize            (var AMessage: TWMSize);             message WM_SIZE;
    procedure WMChar            (var AMessage: TWMChar);             message WM_CHAR;
    procedure WMMouseWheel      (var AMessage: TWMMouseWheel);       message WM_MOUSEWHEEL;
    procedure WMKeyDown         (var AMessage: TWMKeyDown);          message WM_KEYDOWN;
    procedure WMEraseBkgnd      (var AMessage: TWMEraseBkgnd);       message WM_ERASEBKGND;
    procedure WMSysCommand      (var AMessage: TWMSysCommand);       message WM_SYSCOMMAND;
  public
    class procedure CError(const AMessage: String; AErrorCode: Integer = 0); override;

    procedure Reset; override;

    procedure HandleMessage(var AMessage: TMessage); override;

    function HandleScanlineIRQ: Boolean;

    procedure DebugPrintRegs(const ARegs: TRegisters);
    procedure DebugBreak;                            override;
    procedure DebugPrint(const AString: AnsiString); override;

    property ClientWidth:  Integer read FClientWidth;
    property ClientHeight: Integer read FClientHeight;

    property Viewport: TRect read FViewport;

    property Scale: Single read FScale write SetScale;

    property Renderer: TRenderer read FRenderer;

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
  WRiteln(SizeOf(TPCMChannels.TChannel), ' ', Sizeof(TSynthChannels.TChannel));

  Writeln('  _Addr_KeyStates      = $', IntToHex(TPasseMemory.KeyStatesAddress), ';');
  Writeln('  _Addr_KeyboardBuffer = $', IntToHex(TPasseMemory.KeyboardBufferAddress), ';');
  Writeln('  _Addr_Mouse          = $', IntToHex(TPasseMemory.MouseAddress), ';');
  Writeln('  _Addr_Gamepads       = $', IntToHex(TPasseMemory.GamepadsAddress), ';');
  Writeln;
  Writeln('  _Addr_AudioRegisters = $', IntToHex(TPasseMemory.AudioRegistersAddress), ';');
  Writeln('  _Addr_SynthChannels  = $', IntToHex(TPasseMemory.SynthChannelsAddress), ';');
  Writeln('  _Addr_PCMChannels    = $', IntToHex(TPasseMemory.PCMChannelsAddress), ';');
  Writeln;
  Writeln('  _Addr_VideoRegisters = $', IntToHex(TPasseMemory.VideoRegistersAddress), ';');
  Writeln('  _Addr_Stickers       = $', IntToHex(TPasseMemory.StickersAddress), ';');
  Writeln('  _Addr_Atlas          = $', IntToHex(TPasseMemory.SpritesAddress), ';');
  Writeln('  _Addr_Sprites        = $', IntToHex(TPasseMemory.SpritesAddress + (SizeOf(TSprites.TAtlasEntry) * TSprites.AtlasCount)), ';');


  Writeln('D:\NixVM\bin\nvm.exe stamp D:\NixVM\bin\harness.passe.exe -base $' + IntToHex(Memory.UserAddress, 0) + ' -oem ' + IntToStr(SizeOf(TPasseMemory)));
{$ENDIF}

  if Assigned(Passe) then
    Error('An instance of passe already exists');

  //StopOnHalt := True;

  Passe := Self;

  inherited;

  ShowFPS := False;
  ShowIPS := False;

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

procedure TPasse.UpdateDebugMenu;
var
  MenuItem: TMenuItemInfo;
begin
  FillChar(MenuItem, SizeOf(MenuItem), 0);
  MenuItem.cbSize := SizeOf(MenuItem);
  MenuItem.fMask  := MIIM_STATE;

  for var i := 0 to 4 do
  begin
    if FRenderer.Debug = i then
      MenuItem.fState := MFS_CHECKED
    else
      MenuItem.fState := MFS_UNCHECKED;

    SetMenuItemInfo(FDebugMenu, i, True, MenuItem);
  end;
end;

procedure TPasse.CreateWindow;
var
  SysMenu:  HMENU;
  SubMenu:  HMENU;
  MenuItem: TMenuItemInfo;
begin
  inherited;

  SysMenu := GetSystemMenu(Handle, False);

  FillChar(MenuItem, SizeOf(MenuItem), 0);
  MenuItem.cbSize := SizeOf(MenuItem);

  MenuItem.fMask := MIIM_FTYPE or MIIM_ID or MIIM_STRING;
  MenuItem.fType := MF_STRING;

  SubMenu := CreatePopupMenu;

  MenuItem.dwTypeData := 'Best fit';
  MenuItem.wID        := SYSMENU_SCALEAUTO;
  InsertMenuItem(SubMenu, 0, False, MenuItem);

  for var i := 1 to SYSMENU_SCALECOUNT do
  begin
    MenuItem.dwTypeData := PChar('x' + IntToStr(i));
    MenuItem.wID        := SYSMENU_SCALEAUTO + i;
    InsertMenuItem(SubMenu, 0, False, MenuItem);
  end;

  MenuItem.fMask      := MIIM_FTYPE or MIIM_STRING or MIIM_SUBMENU;
  MenuItem.fType      := MF_STRING;
  MenuItem.dwTypeData := 'Set scale';
  MenuItem.hSubMenu   := SubMenu;
  InsertMenuItem(SysMenu, 6, True, MenuItem);


  MenuItem.fMask      := MIIM_FTYPE;
  MenuItem.fType      := MF_SEPARATOR;
  InsertMenuItem(SysMenu, 7, True, MenuItem);

  MenuItem.fMask      := MIIM_FTYPE or MIIM_STRING or MIIM_ID;
  MenuItem.fType      := MF_STRING;
  MenuItem.wID        := SYSMENU_COPYCONSOLE;
  MenuItem.dwTypeData := 'Copy console'#9'Ctrl+C';
  InsertMenuItem(SysMenu, 8, True, MenuItem);

  FDebugMenu := CreatePopupMenu;
  MenuItem.fMask      := MIIM_FTYPE or MIIM_ID or MIIM_STRING or MIIM_STATE;
  MenuItem.fType      := MF_STRING;

  MenuItem.dwTypeData := 'Off';
  MenuItem.fState     := MFS_CHECKED;
  MenuItem.wID        := SYSMENU_DEBUG;
  InsertMenuItem(FDebugMenu, 0, False, MenuItem);

  MenuItem.dwTypeData := 'Top left';
  MenuItem.fState     := MFS_UNCHECKED;
  MenuItem.wID        := SYSMENU_DEBUG + 1;
  InsertMenuItem(FDebugMenu, 0, False, MenuItem);

  MenuItem.dwTypeData := 'Top right';
  MenuItem.wID        := SYSMENU_DEBUG + 2;
  InsertMenuItem(FDebugMenu, 0, False, MenuItem);

  MenuItem.dwTypeData := 'Bottom right';
  MenuItem.wID        := SYSMENU_DEBUG + 3;
  InsertMenuItem(FDebugMenu, 0, False, MenuItem);

  MenuItem.dwTypeData := 'Bottom left';
  MenuItem.wID        := SYSMENU_DEBUG + 4;
  InsertMenuItem(FDebugMenu, 0, False, MenuItem);

  MenuItem.fMask      := MIIM_FTYPE or MIIM_STRING or MIIM_SUBMENU;
  MenuItem.fType      := MF_STRING;
  MenuItem.dwTypeData := 'Debug information';
  MenuItem.hSubMenu   := FDebugMenu;
  InsertMenuItem(SysMenu, 10, True, MenuItem);
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

procedure TPasse.HandlePanic;
begin
  CPU.Halt;

  FHID.Reset;
  FVDU.Reset;
  FSID.Reset;

  //FVDU.Clear(4);
  FVDU.Registers.BorderColour := FVDU.Palette.Colours[4];

  FVDU.Registers.Flags.StickersEnabled    := False;
  FVDU.Registers.Flags.SpritesEnabled     := False;
  FVDU.Registers.Flags.FrameBufferEnabled := False;

  FVDU.Registers.CaretChar := #0;

  FSID.Beep(300, 1);

  //FVDU.Registers.CaretAttrib := $07;
  //DebugPrint(#13#10#32#27#2' SYSTEM PANIC '#27#2#13#10);

  FVDU.Registers.CaretAttrib := $0F or $80;
  DebugPrint(AnsiString(#13#10#32 + TSystemState.TPanicCode(Memory.CoreSystem.SystemState.PanicCode).ToString + #13#10));

  FVDU.Registers.CaretAttrib := $07;
  inherited;
  DebugPrint(#13#10);
  DebugPrint(AnsiString('  Heap:' + SizeToStr(Memory.Heap.Size - Memory.Heap.GetAvailable) + ' / ' + SizeToStr(Memory.Heap.Size)  + #13#10));
  DebugPrint(AnsiString(' Stack:' + SizeToStr(Memory.Size - CPU.Registers.SP)              + ' / ' + SizeToStr(Memory.Stack.Size) + #13#10));
  DebugPrint(#13#10);
  DebugPrint(AnsiString('  Code:' + IntToStr(Memory.CoreSystem.SystemState.UserCode) + #13#10));
  DebugPrint(#13#10);

  DebugPrint(' Bytes at PC:'#13#10#13#10'  ');
  for var i := 0 to 9 do
  begin
    DebugPrint(AnsiString(' ' + IntToHex(Memory.ReadByte(CPU.Registers.PC + i), 2)));
    if (i = 1) or (i = 5) then DebugPrint(' -');
  end;

  var Addr := CPU.Registers.PC;
  DebugPrint(#13#10'   ' + AnsiString(CPU.DecodeInstr(Addr)));
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

      TSID.TSysCalls.Play:    FSID.PCMPlay(R0, (R1 <> 0));
      TSID.TSysCalls.Stop:    FSID.PCMStop(R0);

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

procedure TPasse.WMKeyDown(var AMessage: TWMKeyDown);
begin
  case AMessage.CharCode of
    VK_F12:
    begin
      inherited;

      if AMessage.Result = 0 then
      begin
        FRenderer.Debug := (FRenderer.Debug + 1) mod 5;
        UpdateDebugMenu;
      end;
    end;

    Ord('C'):
    begin
      if (GetAsyncKeyState(VK_CONTROL) and $8000) <> 0 then
      begin
        FVDU.NeedsConsole;
        StrToClipboard(String(FVDU.Console.ToString), False);
      end
      else
        inherited;
    end
  else
    inherited;
  end;
end;

procedure TPasse.WMEraseBkgnd(var AMessage: TWMEraseBkgnd);
begin
  if Running then
    AMessage.Result := 1
  else
    inherited;
end;

procedure TPasse.WMSysCommand(var AMessage: TWMSysCommand);
begin
  case AMessage.CmdType of
    SYSMENU_SCALEAUTO..SYSMENU_SCALEAUTO + SYSMENU_SCALECOUNT:
      SetScale(AMessage.CmdType - SYSMENU_SCALEAUTO);

    SYSMENU_DEBUG..SYSMENU_DEBUG + 4:
    begin
      FRenderer.Debug := AMessage.CmdType - SYSMENU_DEBUG;
      UpdateDebugMenu;
    end;

    SYSMENU_COPYCONSOLE:
    begin
      FVDU.NeedsConsole;
      StrToClipboard(String(FVDU.Console.ToString), False);
    end;
  else
    inherited;
  end;
end;

class procedure TPasse.CError(const AMessage: String; AErrorCode: Integer);
begin
  if Assigned(Passe) then
    Passe.Error(AMessage, AErrorCode)
  else
    inherited;
end;

procedure TPasse.Reset;
begin
  inherited;

  FHID.Reset;
  FSID.Reset;
  FVDU.Reset;
end;

function TPasse.HandleScanlineIRQ: Boolean;
begin
  // TODO: Work out a good instruction budget size for scanline interrupts
  Result := CPU.Interrupt(TPasseMemory.ScanlineIRQID, 10000);
end;

procedure TPasse.DebugPrintRegs(const ARegs: TRegisters);
begin
  with ARegs do
  begin
    DebugPrint(' r0:' + AnsiString(IntToHex(R[ 0], 8)) + ' ');
    DebugPrint(' r1:' + AnsiString(IntToHex(R[ 1], 8)) + ' ');
    DebugPrint(' r2:' + AnsiString(IntToHex(R[ 2], 8)) + #13#10);
    DebugPrint(' r3:' + AnsiString(IntToHex(R[ 3], 8)) + ' ');
    DebugPrint(' r4:' + AnsiString(IntToHex(R[ 4], 8)) + ' ');
    DebugPrint(' r5:' + AnsiString(IntToHex(R[ 5], 8)) + #13#10);
    DebugPrint(' r6:' + AnsiString(IntToHex(R[ 6], 8)) + ' ');
    DebugPrint(' r7:' + AnsiString(IntToHex(R[ 7], 8)) + ' ');
    DebugPrint(' r8:' + AnsiString(IntToHex(R[ 8], 8)) + #13#10);
    DebugPrint(' r9:' + AnsiString(IntToHex(R[ 9], 8)) + ' ');
    DebugPrint('r10:' + AnsiString(IntToHex(R[10], 8)) + ' ');
    DebugPrint('r11:' + AnsiString(IntToHex(R[11], 8)) + #13#10);
    DebugPrint('r12:' + AnsiString(IntToHex(R[12], 8)) + ' ');
    DebugPrint('Imm:' + AnsiString(IntToHex(R[13], 8)) + ' ');
    DebugPrint(' BP:' + AnsiString(IntToHex(R[14], 8)) + #13#10);
    DebugPrint(' SP:' + AnsiString(IntToHex(R[15], 8)) + ' ');
    DebugPrint(' PC:' + AnsiString(IntToHex(PC,    8)) + ' ');
    DebugPrint('  F:' + AnsiString(Flags.ToString)     + #13#10);
  end;
end;


procedure TPasse.DebugBreak;
begin
  inherited;

  DebugPrint(#13#10);
  DebugPrintRegs(CPU.Registers);
  DebugPrint(#13#10);

  DebugPrint(' CPU state:');
  if CPU.HaltState  then DebugPrint(' halt');
  if CPU.YieldState then DebugPrint(' yield');
  if CPU.PanicState then DebugPrint(' panic');

  DebugPrint(#13#10);
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
