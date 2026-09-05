{
  NixVM.Harness.Window.pas
    Window GUI harness

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

unit NixVM.Harness.Window;

{$INCLUDE 'NixVM.Options.inc''}

{$IF NOT DEFINED(MSWINDOWS)}
  {$MESSAGE FATAL 'NixVM window harness is designed for windows'}
{$ENDIF}

interface

uses
  Winapi.Windows,
  Winapi.Messages,

  NixVM.Harness,
  NixVM.Harness.PE,
  NixVM.Harness.Timing;

type
  {$REGION 'CustomWindowHarness'}
  TCustomWindowHarness<TSystemMemory: record> = class(TCustomPEHarness<TSystemMemory>)
  private
    FHandle: HWND;

    FShowFPS: Boolean;
    FShowIPS: Boolean;

    FColour: COLORREF;

    {$REGION 'Class'}
    class var FClassAtom: ATOM;

    class constructor Create;
    class destructor  Destroy;

    class function WindowProc(hWnd: HWND; Msg: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall; static;
    {$ENDREGION}
  protected
    function  GetColour: COLORREF;          virtual;
    procedure SetColour(AColour: COLORREF); virtual;

    procedure Initialize; override;
    procedure Finalize;   override;

    procedure Started; override;
    procedure Stopped; override;

    procedure CreateWindow;  virtual;
    procedure DestroyWindow; virtual;

    procedure Update(const ADelta: TTicks); override;

    procedure UpdateTitleBar;

    procedure EverySecond; override;
  protected
    procedure WMClose  (var AMessage: TWMClose);   message WM_CLOSE;
    procedure WMDestroy(var AMessage: TWMDestroy); message WM_DESTROY;
  public
    class procedure CError(const AMessage: String; AErrorCode: Integer = 0); override;
          procedure  Error(const AMessage: String; AErrorCode: Integer = 0); override;

    procedure ProcessMessages(AWait: Boolean = False);
    procedure HandleMessage  (var AMessage: TMessage); virtual;
    procedure DefaultHandler (var AMessage);           override;

    property Handle: HWND read FHandle;

    property ShowFPS: Boolean read FShowFPS write FShowFPS;
    property ShowIPS: Boolean read FShowIPS write FShowIPS;

    property Colour: COLORREF read GetColour write SetColour;
  end;
  {$ENDREGION}

{$REGION 'DWM'}
const
  DWMWA_CAPTION_COLOR = 35;
  DWMWA_TEXT_COLOR    = 36;

function DwmFlush: HRESULT; stdcall; external 'DWMAPI.DLL';
function DwmSetWindowAttribute(hwnd: HWND; dwAttribute: DWORD; pvAttribute: LPCVOID; cbAttribute: DWORD): HRESULT; stdcall; external 'DWMAPI.DLL';
{$ENDREGION}

implementation

uses
  NixVM.Core.ROM,
  NixVM.Core.Strings;

{$REGION 'CustomWindowHarness'}
{$REGION 'Class'}
class constructor TCustomWindowHarness<TSystemMemory>.Create;
var
  WndClass: TWndClassEx;
begin
  FillChar(WndClass, SizeOf(WndClass), 0);

  with WndClass do
  begin
    cbSize := SizeOf(WndClass);

    style := CS_OWNDC;

    hInstance     := SysInit.HInstance;
    lpszClassName := PChar(ClassName);
    lpfnWndProc   := @WindowProc;

    hCursor := LoadCursor(0, PChar(IDC_ARROW));
    hIcon   := LoadIcon(hInstance, 'MAINICON');

    hbrBackground := GetStockObject(BLACK_BRUSH);
  end;

  FClassAtom := RegisterClassEx(WndClass);

  if FClassAtom = 0 then
    CError('Failed to register window class');
end;

class destructor TCustomWindowHarness<TSystemMemory>.Destroy;
begin
  if FClassAtom <> 0 then
    UnregisterClass(PChar(FClassAtom), HInstance);
end;

class function TCustomWindowHarness<TSystemMemory>.WindowProc(hWnd: HWND; Msg: Integer; WParam: WPARAM; LParam: LPARAM): LRESULT;
var
  Self:   TCustomWindowHarness<TSystemMemory>;
  WndMsg: TMessage;
begin
  Self := TCustomWindowHarness<TSystemMemory>(GetWindowLongPtr(hWnd, GWL_USERDATA));

  if not Assigned(Self) then
    Exit(DefWindowProc(hWnd, Msg, wParam, lParam));

  WndMsg.Msg    := Msg;
  WndMsg.WParam := WParam;
  WndMsg.LParam := LParam;
  WndMsg.Result := 0;

  Self.HandleMessage(WndMsg);

  Result := WndMsg.Result;
end;
{$ENDREGION}

function TCustomWindowHarness<TSystemMemory>.GetColour: COLORREF;
begin
  Result := FColour;
end;

procedure TCustomWindowHarness<TSystemMemory>.SetColour(AColour: COLORREF);
begin
  FColour := AColour and $FFFFFF;

  var NewBrush := CreateSolidBrush(FColour);
  var OldBrush := SetClassLongPtr(FHandle, GCL_HBRBACKGROUND, NewBrush);

  if OldBrush <> 0 then
    DeleteObject(HGDIOBJ(OldBrush));

  DwmSetWindowAttribute(FHandle, DWMWA_CAPTION_COLOR, @FColour, SizeOf(FColour));
end;

procedure TCustomWindowHarness<TSystemMemory>.Initialize;
begin
  FShowFPS := True;
  FShowIPS := True;

  FColour := 0;

  CreateWindow;

  inherited;
end;

procedure TCustomWindowHarness<TSystemMemory>.Finalize;
begin
  inherited;

  DestroyWindow;
end;

procedure TCustomWindowHarness<TSystemMemory>.Started;
begin
  inherited;

  UpdateTitleBar;
  ShowWindow(FHandle, SW_SHOW);
end;

procedure TCustomWindowHarness<TSystemMemory>.Stopped;
begin
  ShowWindow(FHandle, SW_HIDE);

  inherited;
end;

procedure TCustomWindowHarness<TSystemMemory>.CreateWindow;
begin
  if FHandle <> 0 then
    Exit;

  FHandle := CreateWindowEx(0, PChar(FClassAtom), PChar(ClassName), WS_OVERLAPPEDWINDOW, Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT), 0, 0, HInstance, Self);

  if FHandle = 0 then
    Error('Failed to create window');

  SetWindowLongPtr(FHandle, GWL_USERDATA, NativeInt(Self));

  SetColour(FColour);
end;

procedure TCustomWindowHarness<TSystemMemory>.DestroyWindow;
begin
  if FHandle <> 0 then
    Winapi.Windows.DestroyWindow(FHandle);

  FHandle := 0;
end;

procedure TCustomWindowHarness<TSystemMemory>.Update(const ADelta: TTicks);
begin
  inherited;

  ProcessMessages(False);
end;

procedure TCustomWindowHarness<TSystemMemory>.UpdateTitleBar;
var
  Caption: String;
begin
  Caption := Memory.CoreSystem.Environment.ROM.Name;

  if Length(Caption) = 0 then
    Caption := ClassName;

  if FShowFPS then
    Caption := Caption  + ' - ' + IntToStr(FPS) + ' FPS';

  if FShowIPS then
  begin
    if MIPS < 0.01 then
      Caption := Caption + ' - ' + IntToStr(IPS) + ' IPS'
    else
      Caption := Caption + ' - ' + FloatToStr(MIPS, 2, False) + ' MIPS';

  end;

  SetWindowText(FHandle, PChar(Caption));
end;

procedure TCustomWindowHarness<TSystemMemory>.EverySecond;
begin
  inherited;

  UpdateTitleBar;
end;

procedure TCustomWindowHarness<TSystemMemory>.WMClose(var AMessage: TWMClose);
begin
  Stop;
end;

procedure TCustomWindowHarness<TSystemMemory>.WMDestroy(var AMessage: TWMDestroy);
begin
  PostQuitMessage(0);
end;

class procedure TCustomWindowHarness<TSystemMemory>.CError(const AMessage: String; AErrorCode: Integer = 0);
begin
  MessageBox(0, PChar(AMessage), 'Error', MB_OK or MB_ICONERROR or MB_SYSTEMMODAL);
  Halt(AErrorCode);
end;

procedure TCustomWindowHarness<TSystemMemory>.Error(const AMessage: String; AErrorCode: Integer = 0);
begin
  if Running then
  begin
    DebugPrint(AnsiString(AMessage));
    CPU.Halt;
  end
  else
  begin
    MessageBox(0, PChar(AMessage), 'Error', MB_OK or MB_ICONERROR or MB_SYSTEMMODAL);
    Halt(AErrorCode);
  end;
end;

procedure TCustomWindowHarness<TSystemMemory>.ProcessMessages(AWait: Boolean = False);
var
  Msg: TMsg;
begin
  if AWait then
    WaitMessage();

  while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
  begin
    if Msg.Message = WM_QUIT then
    begin
      Stop;
      Break;
    end;

    TranslateMessage(Msg);
    DispatchMessage (Msg);
  end;
end;

procedure TCustomWindowHarness<TSystemMemory>.HandleMessage(var AMessage: TMessage);
begin
  Dispatch(AMessage);
end;

procedure TCustomWindowHarness<TSystemMemory>.DefaultHandler(var AMessage);
begin
  with TMessage(AMessage) do
    Result := DefWindowProc(FHandle, Msg, WParam, LParam);
end;

{$ENDREGION}

end.
