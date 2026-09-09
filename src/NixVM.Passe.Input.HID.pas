{
  NixVM.Passe.Input.HID.pas
    Keyboard, mouse and XInput

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

unit NixVM.Passe.Input.HID;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  Winapi.Windows,

  NixVM.Core.Memory,

  NixVM.Harness.Passe,

  NixVM.Passe.Memory,
  NixVM.Passe.Video,
  NixVM.Passe.Input;

type
  {$REGION 'HID'}
  THID = class
  private
    FOwner: TPasseHarness;

    FMouseHidden: Boolean;

    FOldX: SmallInt;
    FOldY: SmallInt;
    FOldZ: SmallInt;

    FKeyStates:      PKeyStates;
    FKeyboardBuffer: PKeyboardBuffer;
    FMouse:          PMouse;
    FGamepads:       PGamepads;
  public
    constructor Create(AOwner: TPasseHarness);

    procedure Reset;

    procedure PollKeys;
    procedure PollMouse;

    procedure UpdateDeltas;

    procedure HandleScroll(AScroll: SmallInt);

    procedure PushChar(AChar: AnsiChar);

    property Owner: TPasseHarness read FOwner;

    property KeyStates:      PKeyStates      read FKeyStates;
    property KeyboardBuffer: PKeyboardBuffer read FKeyboardBuffer;
    property Mouse:          PMouse          read FMouse;
    property Gamepads:       PGamepads       read FGamepads;
  end;
  {$ENDREGION}

  {$REGION 'XInput'}

  {$REGION 'Gamepad'}
  TXGamepad = packed record
  private
    FButtons:  Word;
    FLTrigger: Byte;
    FRTrigger: Byte;
    FLThumbX:  SmallInt;
    FLThumbY:  SmallInt;
    FRThumbX:  SmallInt;
    FRThumbY:  SmallInt;

    function GetButton(AButtonMask: Integer): Boolean; inline;

    function GetTrigger(ATrigger: Integer): Single;
    function GetThumb  (AThumb:   Integer): Single;
  public
    property Up:    Boolean index $0001 read GetButton;
    property Down:  Boolean index $0002 read GetButton;
    property Left:  Boolean index $0004 read GetButton;
    property Right: Boolean index $0008 read GetButton;

    property Start: Boolean index $0010 read GetButton;
    property Back:  Boolean index $0020 read GetButton;

    property LThumb: Boolean index $0040 read GetButton;
    property RThumb: Boolean index $0080 read GetButton;

    property LShoulder: Boolean index $0100 read GetButton;
    property RShoulder: Boolean index $0200 read GetButton;

    property A: Boolean index $1000 read GetButton;
    property B: Boolean index $2000 read GetButton;
    property X: Boolean index $4000 read GetButton;
    property Y: Boolean index $8000 read GetButton;

    property LTrigger: Single index 0 read GetTrigger;
    property RTrigger: Single index 1 read GetTrigger;

    property LThumbX: Single index 0 read GetThumb;
    property LThumbY: Single index 1 read GetThumb;

    property RThumbX: Single index 2 read GetThumb;
    property RThumbY: Single index 3 read GetThumb;
  end;

  TXGamepadState = packed record
    PacketNumber: Cardinal;
    Gamepad:      TXGamepad;
  end;

  TXGamepadVibration = packed record
    LeftMotorSpeed:  Word;
    RightMotorSpeed: Word;
  end;
  {$ENDREGION}

  TXInput = class abstract
  private
    const
      DLLs: array[0..2] of PChar = (
        'XInput1_4.dll',   // Windows 8+
        'XInput9_1_0.dll', // Windows 7/Vista
        'XInput1_3.dll'    // DirectX fallback
      );

    type
      TGetStateProc = function(AIndex: Cardinal; var   AState:     TXGamepadState):     Cardinal; stdcall;
      TSetStateProc = function(AIndex: Cardinal; const AVibration: TXGamepadVibration): Cardinal; stdcall;

    class var FHandle:   HMODULE;

    class var FGetState: TGetStateProc;
    class var FSetState: TSetStateProc;

    class constructor Create;
    class destructor  Destroy;

    class function GetAvailable: Boolean; static; inline;
  public
    class function GetGamepad  (AIndex: Cardinal; out AGamepad: TXGamepad): Boolean; static;
    class function SetVibration(AIndex: Cardinal; ALeft, ARight: Single):   Boolean; static;

    class property Handle:    HMODULE read FHandle;
    class property Available: Boolean read GetAvailable;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Passe;

{$REGION 'HID'}
constructor THID.Create(AOwner: TPasseHarness);
begin
  inherited Create;

  FOwner := AOwner;

  FKeyStates      := FOwner.Memory.Ptr[TPasseMemory.KeyStatesAddress];
  FKeyboardBuffer := FOwner.Memory.Ptr[TPasseMemory.KeyboardBufferAddress];
  FMouse          := FOwner.Memory.Ptr[TPasseMemory.MouseAddress];
  FGamepads       := FOwner.Memory.Ptr[TPasseMemory.GamepadsAddress];
end;

procedure THID.Reset;
begin
  FKeyStates.Reset;
  FKeyboardBuffer.Reset;
  FMouse.Reset;
  FGamepads.Reset;
end;

procedure THID.PollKeys;
var
//  KeyboardState: TKeyboardState;
  KeysDown: array[Byte] of Boolean;
  XGamepad: TXGamepad;
begin
  if GetForegroundWindow <> FOwner.Handle then
  begin
    FillChar(KeysDown, SizeOf(KeysDown), 0);

    for var i := 0 to TGamepads.Count - 1 do
      TXInput.SetVibration(i, 0, 0);
  end
  else
  begin
    for var i := 0 to 255 do
      KeysDown[i] := (GetAsyncKeyState(i) and $8000) <> 0;

//    if GetKeyboardState(KeyboardState) then
//      for var i := 0 to 255 do
//        KeysDown[i] := (KeyboardState[i] and 128) <> 0
//    else
//      FillChar(KeysDown, SizeOf(KeysDown), 0);

    for var i := 0 to TGamepads.Count - 1 do
      with FGamepads^.Gamepads[i] do
      begin
        if TXInput.Available and TXInput.GetGamepad(i, XGamepad) then
        begin
          Availible := 1;

          if Map.Up    > 0 then KeysDown[Map.Up]    := KeysDown[Map.Up]    or XGamepad.Up;
          if Map.Down  > 0 then KeysDown[Map.Down]  := KeysDown[Map.Down]  or XGamepad.Down;
          if Map.Left  > 0 then KeysDown[Map.Left]  := KeysDown[Map.Left]  or XGamepad.Left;
          if Map.Right > 0 then KeysDown[Map.Right] := KeysDown[Map.Right] or XGamepad.Right;

          if Map.Start > 0 then KeysDown[Map.Start] := KeysDown[Map.Start] or XGamepad.Start;
          if Map.Back  > 0 then KeysDown[Map.Back]  := KeysDown[Map.Back]  or XGamepad.Back;

          if Map.LThumb > 0 then KeysDown[Map.LThumb] := KeysDown[Map.LThumb] or XGamepad.LThumb;
          if Map.RThumb > 0 then KeysDown[Map.RThumb] := KeysDown[Map.RThumb] or XGamepad.RThumb;

          if Map.LShoulder > 0 then KeysDown[Map.LShoulder] := KeysDown[Map.LShoulder] or XGamepad.LShoulder;
          if Map.RShoulder > 0 then KeysDown[Map.RShoulder] := KeysDown[Map.RShoulder] or XGamepad.RShoulder;

          if Map.A > 0 then KeysDown[Map.A] := KeysDown[Map.A] or XGamepad.A;
          if Map.B > 0 then KeysDown[Map.B] := KeysDown[Map.B] or XGamepad.B;
          if Map.X > 0 then KeysDown[Map.X] := KeysDown[Map.X] or XGamepad.X;
          if Map.Y > 0 then KeysDown[Map.Y] := KeysDown[Map.Y] or XGamepad.Y;

          LTrigger := XGamepad.LTrigger;
          RTrigger := XGamepad.RTrigger;

          LThumbX := XGamepad.LThumbX;
          LThumbY := XGamepad.LThumbY;

          RThumbX := XGamepad.RThumbX;
          RThumbY := XGamepad.RThumbY;

          TXInput.SetVibration(i, LVibrate, RVibrate);
        end
        else
        begin
          Availible := 0;

          LTrigger := 0;
          RTrigger := 0;

          LThumbX := 0;
          LThumbY := 0;

          RThumbX := 0;
          RThumbY := 0;

          TXInput.SetVibration(i, 0, 0);
        end;
      end;
  end;

  for var i := 0 to 255 do
  begin
    FKeyStates^.Keys[i].Update(KeysDown[i]);

    //if i = 32 then
    //  Write(FKeyStates^.Keys[i], ' ');
  end;
end;

procedure THID.PollMouse;
const
  FMouseEnabled = True;
var
  cp:    TPoint;
  Over:  Boolean;
begin
  if GetForegroundWindow <> FOwner.Handle then
  begin
    if FMouseHidden then
    begin
      ShowCursor(True);
      FMouseHidden := False;
    end;

    Exit;
  end;

  with FOwner as TPasse do
  begin
    // TODO: Get mouse enabled flag (FMouseEnabled)

    if Scale <= 0 then
      Exit;

    GetCursorPos(cp);
    ScreenToClient(Handle, cp);

    Over := Viewport.Contains(cp);

    //if Over then
    begin
      FMouse.X := Trunc((cp.x - Viewport.Left) / Scale);
      FMouse.Y := Trunc((cp.y - Viewport.Top)  / Scale);

      if FMouse.X < 0 then
        FMouse.X := 0
      else if FMouse.X >= TFrameBuffer.Width then
        FMouse.X := TFrameBuffer.Width - 1;

      if FMouse.Y < 0 then
        FMouse.Y := 0
      else if FMouse.Y >= TFrameBuffer.Height then
        FMouse.Y := TFrameBuffer.Height - 1;
    end;

    if FMouseEnabled then
    begin
      // TODO: Update mouse sprite coord
    end;

    Over := Over and FMouseEnabled;

    if Over <> FMouseHidden then
    begin
      FMouseHidden := Over;
      ShowCursor(not Over);
    end;
  end;
end;

procedure THID.UpdateDeltas;
begin
  FMouse.DeltaX := FMouse.X - FOldX;
  FMouse.DeltaY := FMouse.Y - FOldY;
  FMouse.DeltaZ := FMouse.Z - FOldZ;

  FOldX := FMouse.X;
  FOldY := FMouse.Y;
  FOldZ := FMouse.Z;
end;

procedure THID.HandleScroll(AScroll: SmallInt);
begin
  FMouse.Z := FMouse.Z + AScroll;
end;

procedure THID.PushChar(AChar: AnsiChar);
begin
  // TODO: Check for input buffer overrun - beep?
  FKeyboardBuffer.PushChar(AChar);
end;
{$ENDREGION}

{$REGION 'XInput'}

{$REGION 'Gamepad'}
function TXGamepad.GetButton(AButtonMask: Integer): Boolean;
begin
  Result := (FButtons and AButtonMask) <> 0;
end;

function TXGamepad.GetTrigger(ATrigger: Integer): Single;
var
  TrigVal: Byte;
begin
  if ATrigger = 0 then
    TrigVal := FLTrigger
  else
    TrigVal := FRTrigger;

  Result := TrigVal / 255;
end;

function TXGamepad.GetThumb(AThumb:   Integer): Single;
var
  ThumbVal: SmallInt;
  DeadZone: Integer;
begin
  if AThumb < 2 then
    DeadZone := 7849
  else
    DeadZone := 8689;

  case AThumb of
    0: ThumbVal := FLThumbX;
    1: ThumbVal := FLThumbY;
    2: ThumbVal := FRThumbX;
    3: ThumbVal := FRThumbY;
  else
    ThumbVal := DeadZone;
  end;

  if (ThumbVal > -DeadZone) and (ThumbVal < DeadZone) then
    Exit(0);

  if ThumbVal > 0 then
    Result := (ThumbVal - DeadZone) / (32767 - DeadZone)
  else
    Result := (ThumbVal + DeadZone) / (32768 - DeadZone);

  if Result < -1.0 then Result := -1.0;
  if Result >  1.0 then Result :=  1.0;
end;
{$ENDREGION}

class constructor TXInput.Create;
begin
  for var i := Low(DLLs) to High(DLLs) do
  begin
    FHandle := LoadLibrary(DLLs[i]);

    if FHandle <> 0 then
      Break;
  end;

  FGetState := GetProcAddress(FHandle, 'XInputGetState');
  FSetState := GetProcAddress(FHandle, 'XInputSetState');
end;

class destructor TXInput.Destroy;
begin
  if FHandle <> 0 then
    FreeLibrary(FHandle);

  FHandle := 0;
end;

class function TXInput.GetAvailable: Boolean;
begin
  Result := Assigned(FGetState);
end;

class function TXInput.GetGamepad(AIndex: Cardinal; out AGamepad: TXGamepad): Boolean;
var
  GamepadState: TXGamepadState;
begin
  if not Available then
    Exit(False);

  Result := FGetState(AIndex, GamepadState) = ERROR_SUCCESS;

  if Result then
    AGamepad := GamepadState.Gamepad;
end;

class function TXInput.SetVibration(AIndex: Cardinal; ALeft, ARight: Single): Boolean;
var
  GamepadVibration: TXGamepadVibration;
begin
  if not Available then
    Exit(False);

  GamepadVibration.LeftMotorSpeed  := Round(65535 * ALeft);
  GamepadVibration.RightMotorSpeed := Round(65535 * ARight);

  Result := FSetState(AIndex, GamepadVibration) = ERROR_SUCCESS;
end;
{$ENDREGION}


end.
