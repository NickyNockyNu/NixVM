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
  NixVM.Harness.Timing;

type
  {$REGION 'CustomWindowHarness'}
  TCustomWindowHarness<TSystemMemory: record> = class(TCustomHarness<TSystemMemory>)
  private
    FHandle: HWND;

    {$REGION 'Class'}
    class var FClassAtom: ATOM;

    class constructor Create;
    class destructor  Destroy;

    class function WindowProc(hWnd: HWND; Msg: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall; static;
    {$ENDREGION}
  protected
    procedure Initialize; override;
    procedure Finalize;   override;

    procedure Update(const ADelta: TTicks); override;
  public
    procedure ProcessMessages(AWait: Boolean = False);

    property Handle: HWND read FHandle;
  end;
  {$ENDREGION}

implementation

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

  // TODO: Check FClassAtom is valid
end;

class destructor TCustomWindowHarness<TSystemMemory>.Destroy;
begin
  if FClassAtom <> 0 then
    UnregisterClass(PChar(FClassAtom), HInstance);
end;

class function TCustomWindowHarness<TSystemMemory>.WindowProc(hWnd: HWND; Msg: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT;
var
  Self: TCustomWindowHarness<TSystemMemory>;
begin
  Self := TCustomWindowHarness<TSystemMemory>(GetWindowLongPtr(hWnd, GWL_USERDATA));

  if not Assigned(Self) then
    Exit(DefWindowProc(hWnd, Msg, wParam, lParam));

  Result := LRESULT(-1);

  case Msg of
    WM_CLOSE:   Self.Stop;
    WM_DESTROY: PostQuitMessage(0);
  else
    Result := DefWindowProc(hWnd, Msg, wParam, lParam);;
  end;
end;
{$ENDREGION}

procedure TCustomWindowHarness<TSystemMemory>.Initialize;
begin
  inherited;

  FHandle := CreateWindowEx(0, PChar(FClassAtom), PChar(ClassName), WS_OVERLAPPEDWINDOW or WS_VISIBLE, Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT), 0, 0, HInstance, Self);

  // TODO: Check handle is valid

  SetWindowLongPtr(FHandle, GWL_USERDATA, NativeInt(Self));
end;

procedure TCustomWindowHarness<TSystemMemory>.Finalize;
begin
  if FHandle <> 0 then
    DestroyWindow(FHandle);

  inherited;
end;

procedure TCustomWindowHarness<TSystemMemory>.Update(const ADelta: TTicks);
begin
  inherited;

  ProcessMessages(False);
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
{$ENDREGION}

end.
