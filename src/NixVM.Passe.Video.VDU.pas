{
  NixVM.Passe.Video.VDU.pas
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

unit NixVM.Passe.Video.VDU;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  NixVM.Core.Memory,

  NixVM.Harness.Passe,

  NixVM.Passe.Memory,
  NixVM.Passe.Video;

type
  {$REGION 'VDU'}
  TVDU = class
  type
    {$REGION 'SysCalls'}
    TSysCalls = class abstract
    const
      VDU = $A0;

      Reset = VDU + 0;
      Clear = VDU + 1;

      GetPixel = VDU + 2;
      SetPixel = VDU + 3;

      HLine = VDU + 4;
      VLine = VDU + 5;

      Line  = VDU + 6;

      DrawRectangle = VDU + 7;
      FillRectangle = VDU + 8;

      DrawCircle = VDU + 9;
      FillCircle = VDU + 10;

      DrawEllipse = VDU + 11;
      FillEllipse = VDU + 12;

      DrawTriangle = VDU + 13;
      FillTriangle = VDU + 14;

      CON = $C0;

      Cls    = CON + 0;
      Write  = CON + 1;
      Print  = CON + 2;
      Locate = CON + 3;
      Colour = CON + 4;
    end;
    {$ENDREGION}
  private
    FOwner: TPasseHarness;

    FRegisters: PVideoRegisters;

    FDrawBuffer: PFrameBuffer;
    FPalette:    PPalette;
    FScanlines:  PScanlines;
    FFont:       PFont;
    FConsole:    PConsole;
    FStickers:   PStickers;
    FSprites:    PSprites;
  private
    {$REGION 'Internal draw'}
    procedure _SetPixel(X, Y: Integer; AColour: Byte); inline;

    procedure _HLine(X, Y: Integer; ALen: Integer; AColour: Byte);
    procedure _VLine(X, Y: Integer; ALen: Integer; AColour: Byte);

    function  ClipLine(var X1, Y1, X2, Y2: Integer): Boolean;
    procedure _Line(X1, Y1, X2, Y2: Integer; AColour: Byte);
    {$ENDREGION}
  public
    constructor Create(AOwner: TPasseHarness);

    procedure NeedsDrawBuffer; inline;
    procedure NeedsPalette;    inline;
    procedure NeedsScanlines;  inline;
    procedure NeedsFont;       inline;
    procedure NeedsConsole;    inline;

    procedure Reset;
    procedure Clear(AColour: Byte = 0);

    {$REGION 'Draw'}
    function  GetPixel(X, Y: Integer): Byte;          inline;
    procedure SetPixel(X, Y: Integer; AColour: Byte); inline;

    procedure HLine(X, Y: Integer; ALen: Integer; AColour: Byte); inline;
    procedure VLine(X, Y: Integer; ALen: Integer; AColour: Byte); inline;

    procedure Line(X1, Y1, X2, Y2: Integer; AColour: Byte); inline;

    procedure DrawRectangle(X, Y, W, H: Integer; AColour: Byte);
    procedure FillRectangle(X, Y, W, H: Integer; AColour: Byte);

    procedure DrawCircle(CX, CY, R: Integer; AColour: Byte);
    procedure FillCircle(CX, CY, R: Integer; AColour: Byte);

    procedure DrawEllipse(CX, CY, RX, RY: Integer; AColour: Byte);
    procedure FillEllipse(CX, CY, RX, RY: Integer; AColour: Byte);

    procedure DrawTriangle(X1, Y1, X2, Y2, X3, Y3: Integer; AColour: Byte);
    procedure FillTriangle(X1, Y1, X2, Y2, X3, Y3: Integer; AColour: Byte);
    {$ENDREGION'}

    {$REGION 'Console'}
    procedure Cls;
    procedure Write(X, Y: Integer; const AText: AnsiString; AAttr: Byte);
    procedure Print(const AText: AnsiString);
    procedure Locate(X, Y: Integer); // Do we really need this? The users can set the location in VideoRegisters
    procedure Colour(AInk, APaper: Byte; ABold: Boolean);
    {$ENDREGION}

    property Owner: TPasseHarness read FOwner;

    property Registers: PVideoRegisters read FRegisters;
  end;
  {$ENDREGION}

implementation

{$REGION 'VDU'}
constructor TVDU.Create(AOwner: TPasseHarness);
begin
  inherited Create;

  FOwner := AOwner;

  FRegisters := FOwner.Memory.Ptr[TPasseMemory.VideoRegistersAddress];
  FStickers  := FOwner.Memory.Ptr[TPasseMemory.StickersAddress];
  FSprites   := FOwner.Memory.Ptr[TPasseMemory.SpritesAddress];
end;

procedure TVDU.NeedsDrawBuffer;
begin
  FDrawBuffer := FOwner.Memory.GetSpan(FRegisters^.DrawBuffer, SizeOf(TFrameBuffer));

  if FDrawBuffer = nil then
    FDrawBuffer := FOwner.Memory.GetSpan(FRegisters^.DisplayBuffer, SizeOf(TFrameBuffer));

  if FDrawBuffer = nil then
    FDrawBuffer := FOwner.Memory.Ptr[TPasseMemory.FrameBufferAddress];
end;

procedure TVDU.NeedsPalette;
begin
  FPalette := FOwner.Memory.GetSpan(FRegisters^.Palette, SizeOf(TPalette));

  if FPalette = nil then
    FPalette := FOwner.Memory.Ptr[TPasseMemory.PaletteAddress];
end;

procedure TVDU.NeedsScanlines;
begin
  FScanlines := FOwner.Memory.GetSpan(FRegisters^.Scanlines, SizeOf(TScanlines));

  if FScanlines = nil then
    FScanlines := FOwner.Memory.Ptr[TPasseMemory.ScanlinesAddress];
end;

procedure TVDU.NeedsFont;
begin
  FFont := FOwner.Memory.GetSpan(FRegisters^.Font, SizeOf(TFont));

  if FFont = nil then
    FFont := FOwner.Memory.Ptr[TPasseMemory.FontAddress];
end;

procedure TVDU.NeedsConsole;
begin
  FConsole := FOwner.Memory.GetSpan(FRegisters^.Console, SizeOf(TConsole));

  if FConsole = nil then
    FConsole := FOwner.Memory.Ptr[TPasseMemory.ConsoleAddress];
end;

procedure TVDU.Reset;
begin
  with FRegisters^ do
  begin
    Reset;

    DisplayBuffer := TPasseMemory.FrameBufferAddress;
    DrawBuffer    := DisplayBuffer;
    Palette       := TPasseMemory.PaletteAddress;
    Scanlines     := TPasseMemory.ScanlinesAddress;
    Font          := TPasseMemory.FontAddress;
    Console       := TPasseMemory.ConsoleAddress;
  end;

  NeedsDrawBuffer;
  NeedsPalette;
  NeedsScanlines;
  NeedsFont;
  NeedsConsole;

  FPalette.Reset;
  FScanlines.Reset;
  FFont.Reset;
  FConsole.Reset;
  FStickers.Reset;
  FSprites.Reset;

  Clear(1);
  Cls;
end;

procedure TVDU.Clear(AColour: Byte);
begin
  NeedsDrawBuffer;

  FillChar(FDrawBuffer^, SizeOf(TFrameBuffer), AColour);
end;

{$REGION 'Internal draw'}
procedure TVDU._SetPixel(X, Y: Integer; AColour: Byte);
begin
  if (Cardinal(X) < TFrameBuffer.Width) and (Cardinal(Y) < TFrameBuffer.Height) then
    FDrawBuffer.Pixels[(Y * TFrameBuffer.Width) + X] := AColour;
end;

procedure TVDU._HLine(X, Y: Integer; ALen: Integer; AColour: Byte);
var
  Addr: PByte;
begin
  if Cardinal(Y) >= TFrameBuffer.Height then
    Exit;

  if ALen <= 0 then
    Exit;

  if X < 0 then
  begin
    ALen := ALen + X;
    X    := 0;
  end;

  if (X + ALen) > TFrameBuffer.Width then
    ALen := TFrameBuffer.Width - X;

  if ALen <= 0 then
    Exit;

  Addr := @FDrawBuffer^.Pixels[(Y * TFrameBuffer.Width) + X];

  FillChar(Addr^, ALen, AColour);
end;

procedure TVDU._VLine(X, Y: Integer; ALen: Integer; AColour: Byte);
var
  Addr: PByte;
begin
  if Cardinal(X) >= TFrameBuffer.Width then
    Exit;

  if ALen <= 0 then
    Exit;

  if Y < 0 then
  begin
    ALen := ALen + Y;
    Y := 0;
  end;

  if (Y + ALen) > TFrameBuffer.Height then
    ALen := TFrameBuffer.Height - Y;

  if ALen <= 0 then
    Exit;

  Addr := @FDrawBuffer^.Pixels[(Y * TFrameBuffer.Width) + X];

  for var i := 0 to ALen - 1 do
  begin
    Addr^ := AColour;

    Inc(Addr, TFrameBuffer.Width);
  end;
end;

function TVDU.ClipLine(var X1, Y1, X2, Y2: Integer): Boolean;
const
  CLIP_INSIDE = 0;
  CLIP_LEFT   = 1;
  CLIP_RIGHT  = 2;
  CLIP_BOTTOM = 4;
  CLIP_TOP    = 8;

  function GetOutCode(X, Y: Integer): Integer;
  begin
    Result := CLIP_INSIDE;

    if X < 0 then
      Result := Result or CLIP_LEFT
    else if X >= TFrameBuffer.Width then
      Result := Result or CLIP_RIGHT;

    if Y < 0 then
      Result := Result or CLIP_TOP
    else if Y >= TFrameBuffer.Height then
      Result := Result or CLIP_BOTTOM;
  end;
var
  Code1:   Integer;
  Code2:   Integer;
  CodeOut: Integer;
  X, Y:    Integer;
begin
  X := 0;
  Y := 0;

  Code1 := GetOutCode(X1, Y1);
  Code2 := GetOutCode(X2, Y2);

  Result := False;

  while True do
  begin
    if (Code1 or Code2) = 0 then
    begin
      Result := True;
      Break;
    end

    else if (Code1 and Code2) <> 0 then
      Break
    else
    begin
      if Code1 <> 0 then
        CodeOut := Code1
      else
        CodeOut := Code2;

      if (CodeOut and CLIP_TOP) <> 0 then
      begin
        X := X1 + (X2 - X1) * (0 - Y1) div (Y2 - Y1);
        Y := 0;
      end
      else if (CodeOut and CLIP_BOTTOM) <> 0 then
      begin
        X := X1 + (X2 - X1) * (TFrameBuffer.Height - 1 - Y1) div (Y2 - Y1);
        Y := TFrameBuffer.Height - 1;
      end
      else if (CodeOut and CLIP_RIGHT) <> 0 then
      begin
        Y := Y1 + (Y2 - Y1) * (TFrameBuffer.Width - 1 - X1) div (X2 - X1);
        X := TFrameBuffer.Width - 1;
      end
      else if (CodeOut and CLIP_LEFT) <> 0 then
      begin
        Y := Y1 + (Y2 - Y1) * (0 - X1) div (X2 - X1);
        X := 0;
      end;

      if CodeOut = Code1 then
      begin
        X1 := X;
        Y1 := Y;

        Code1 := GetOutCode(X1, Y1);
      end
      else
      begin
        X2 := X;
        Y2 := Y;

        Code2 := GetOutCode(X2, Y2);
      end;
    end;
  end;
end;

procedure TVDU._Line(X1, Y1, X2, Y2: Integer; AColour: Byte);
var
  DX, DY:  Integer;
  SX, SY:  Integer;
  E,  ES:  Integer;
  Addr:    PByte;
  RowStep: Integer;
begin
  DX := Abs(X2 - X1);
  DY := Abs(Y2 - Y1);

  if X1 < X2 then SX := 1 else SX := -1;
  if Y1 < Y2 then SY := 1 else SY := -1;

  RowStep := SY * TFrameBuffer.Width;

  if DX > DY then
    E := DX
  else
    E := -DY;

  E := E div 2;

  Addr := @FDrawBuffer^.Pixels[Y1 * TFrameBuffer.Width + X1];

  repeat
    Addr^ := AColour;

    if (X1 = X2) and (Y1 = Y2) then
      Break;

    ES := E;

    if ES > -DX then
    begin
      E  := E  - DY;
      X1 := X1 + SX;

      Inc(Addr, SX);
    end;

    if ES < DY then
    begin
      E  := E  + DX;
      Y1 := Y1 + SY;

      Inc(Addr, RowStep);
    end;
  until False;
end;
{$ENDREGION}

{$REGION 'Draw'}
function TVDU.GetPixel(X, Y: Integer): Byte;
begin
  NeedsDrawBuffer;

  if (Cardinal(X) < TFrameBuffer.Width) and (Cardinal(Y) < TFrameBuffer.Height) then
    Result := FDrawBuffer.Pixels[(Y * TFrameBuffer.Width) + X]
  else
    Result := 0;
end;

procedure TVDU.SetPixel(X, Y: Integer; AColour: Byte);
begin
  NeedsDrawBuffer;
  _SetPIxel(X, Y, AColour);
end;

procedure TVDU.HLine(X, Y: Integer; ALen: Integer; AColour: Byte);
begin
  NeedsDrawBuffer;
  _HLine(X, Y, ALen,AColour);
end;

procedure TVDU.VLine(X, Y: Integer; ALen: Integer; AColour: Byte);
begin
  NeedsDrawBuffer;
  _VLine(X, Y,Alen, AColour);
end;

procedure TVDU.Line(X1, Y1, X2, Y2: Integer; AColour: Byte);
begin
  if not ClipLine(X1, Y1, X2, Y2) then
    Exit;

  NeedsDrawBuffer;
  _Line(X1, Y1, X2, Y2, AColour);
end;

procedure TVDU.DrawRectangle(X, Y, W, H: Integer; AColour: Byte);
begin
  NeedsDrawBuffer;

  _HLine(X,         Y,         W, AColour);
  _HLine(X,         Y + H - 1, W, AColour);
  _VLine(X,         Y,         H, AColour);
  _VLine(X + W - 1, Y,         H, AColour);
end;

procedure TVDU.FillRectangle(X, Y, W, H: Integer; AColour: Byte);
begin
  NeedsDrawBuffer;

  for var i := Y to Y + H - 1 do
    _HLine(X, i, W, AColour)
end;

procedure TVDU.DrawCircle(CX, CY, R: Integer; AColour: Byte);
var
  X, Y, P: Integer;
begin
  NeedsDrawBuffer;

  X := 0;
  Y := R;
  P := 3 - 2 * R;

  while Y >= X do
  begin
    _SetPixel(CX - X, CY - Y, AColour);
    _SetPixel(CX - Y, CY - X, AColour);
    _SetPixel(CX + Y, CY - X, AColour);
    _SetPixel(CX + X, CY - Y, AColour);
    _SetPixel(CX - X, CY + Y, AColour);
    _SetPixel(CX - Y, CY + X, AColour);
    _SetPixel(CX + Y, CY + X, AColour);
    _SetPixel(CX + X, CY + Y, AColour);

		if P < 0 then
    begin
      P := P + (4 * X) + 6;
      X := X + 1;
    end
    else
    begin
      P := P + 4 * (X - Y) + 10;
      X := X + 1;
      Y := Y - 1;
    end;
  end;
end;

procedure TVDU.FillCircle(CX, CY, R: Integer; AColour: Byte);
var
  X, Y, P: Integer;
begin
  NeedsDrawBuffer;

  X := 0;
  Y := R;
  P := 3 - 2 * R;

  while Y >= X do
  begin
    _HLine(CX - X, CY - Y, 1 + X * 2, AColour);
    _HLine(CX - Y, CY - X, 1 + Y * 2, AColour);
    _HLine(CX - X, CY + Y, 1 + X * 2, AColour);
    _HLine(CX - Y, CY + X, 1 + Y * 2, AColour);

		if P < 0 then
    begin
      P := P + (4 * X) + 6;
      X := X + 1;
    end
    else
    begin
      P := P + 4 * (X - Y) + 10;
      X := X + 1;
      Y := Y - 1;
    end;
  end;
end;

procedure TVDU.DrawEllipse(CX, CY, RX, RY: Integer; AColour: Byte);
var
  XX, YY: Integer;
  X2:     Integer;
begin
  NeedsDrawBuffer;

  if (RX = 0) or (RY = 0) then
    Exit;

  if RY = 1 then
  begin
    _HLine(CX, CY, 1 + RX, AColour);
    Exit;
  end;

  if RX = 1 then
  begin
    _VLine(CX, CY, 1 + RY, AColour);
    Exit;
  end;

  XX := 0;
  X2 := RX;

  for YY := 0 to RY - 1 do
  begin
    XX := Round(RX / (RY - 1) * Sqrt(Sqr(RY - 1) - Sqr(YY - 0.5)));

    for var j := xx to x2 do
    begin
      _SetPixel(CX + j, CY + YY, AColour);
      _SetPixel(CX - j, CY + YY, AColour);
      _SetPixel(CX + j, CY - YY, AColour);
      _SetPixel(CX - j, CY - YY, AColour);
    end;

    X2 := XX;
  end;

  for var j := 0 to XX - 1 do
  begin
    _SetPixel(CX + j, CY + RY, AColour);
    _SetPixel(CX - j, CY + RY, AColour);
    _SetPixel(CX + j, CY - RY, AColour);
    _SetPixel(CX - j, CY - RY, AColour);
  end;
end;

procedure TVDU.FillEllipse(CX, CY, RX, RY: Integer; AColour: Byte);
var
  XX, YY: Integer;
begin
  if (RX = 0) or (RY = 0) then
    Exit;

  if RY = 1 then
  begin
    _HLine(CX, CY, 1 + RX, AColour);
    Exit;
  end;

  if RX = 1 then
  begin
    _VLine(CX, CY, 1 + RY, AColour);
    Exit;
  end;

  _HLine(CX - RX, CY, 1 + (RX * 2), AColour);

  for YY := 0 to RY do
  begin
    XX := Round(RX / RY * Sqrt((Sqr(RY)) - Sqr(YY - 0.5)));

    _HLine(CX - XX, CY + YY, 1 + (XX * 2), AColour);
    _HLine(CX - XX, CY - YY, 1 + (XX * 2), AColour);
  end;
end;

procedure TVDU.DrawTriangle(X1, Y1, X2, Y2, X3, Y3: Integer; AColour: Byte);
begin
  Line(X1, Y1, X2, Y2, AColour);
  Line(X2, Y2, X3, Y3, AColour);
  Line(X3, Y3, X1, Y1, AColour);
end;

procedure TVDU.FillTriangle(X1, Y1, X2, Y2, X3, Y3: Integer; AColour: Byte);
var
  Left:   Boolean;
  SL, SR: Integer;
  Y:      Integer;
  CL, CR: Integer;
  XL, XR: Integer;
  H:      Integer;
  Addr:   PByte;

  procedure Sort(var AX, AY, BX, BY: Integer);
  var
    Tmp:    Integer;
  begin
    if AY > BY then
    begin
      Tmp := AY;
      AY  := BY;
      BY  := Tmp;

      Tmp := AX;
      AX  := BX;
      BX  := Tmp;
    end;
  end;
begin
  NeedsDrawBuffer;

  Sort(X1, Y1, X2, Y2);
  Sort(X1, Y1, X3, Y3);
  Sort(X2, Y2, X3, Y3);

  if (Y3 < 0) or (Y1 >= TFrameBuffer.Height) or (Y1 = Y3) then
    Exit;

  Left := (Int64(X2) - X1) * (Y3 - Y1) < (Int64(Y2) - Y1) * (X3 - X1);

  H := Y2 - Y1;
  if H > 0 then
  begin
    if Left then
    begin
      SL := (Int64(X2 - X1) shl 16) div H;
      SR := (Int64(X3 - X1) shl 16) div (Y3 - Y1);
    end
    else
    begin
      SL := (Int64(X3 - X1) shl 16) div (Y3 - Y1);
      SR := (Int64(X2 - X1) shl 16) div H;
    end;

    CL := X1 shl 16;
    CR := X1 shl 16;

    Addr := @FDrawBuffer^.Pixels[Y1 * TFrameBuffer.Width];

    for Y := Y1 to Y2 - 1 do
    begin
      if (Cardinal(Y) < TFrameBuffer.Height) then
      begin
        XL := CL div 65536;
        XR := CR div 65536;

        if XL < 0 then
          XL := 0;

        if XR >= TFrameBuffer.Width then
          XR := TFrameBuffer.Width - 1;

        if XL <= XR then
          FillChar(Addr[XL], (XR - XL + 1), AColour);
      end;

      Inc(CL, SL);
      Inc(CR, SR);

      Inc(Addr, TFrameBuffer.Width);
    end;
  end;

  H := Y3 - Y2;
  if H > 0 then
  begin
    if Left then
    begin
      SL := (Int64(X3 - X2) shl 16) div H;
      SR := (Int64(X3 - X1) shl 16) div (Y3 - Y1);

      CL :=  X2 shl 16;
      CR := (X1 shl 16) + SR * (Y2 - Y1);
    end
    else
    begin
      SL := (Int64(X3 - X1) shl 16) div (Y3 - Y1);
      SR := (Int64(X3 - X2) shl 16) div H;

      CL := (X1 shl 16) + SL * (Y2 - Y1);
      CR :=  X2 shl 16;
    end;

    Addr := @FDrawBuffer^.Pixels[Y2 * TFrameBuffer.Width];

    for Y := Y2 to Y3 do
    begin
      if (Cardinal(Y) < TFrameBuffer.Height) then
      begin
        XL := CL div 65536;
        XR := CR div 65536;

        if XL < 0 then
          XL := 0;

        if XR >= TFrameBuffer.Width then
          XR := TFrameBuffer.Width - 1;

        if XL <= XR then
          FillChar(Addr[XL], XR - XL + 1, AColour);
      end;

      Inc(CL, SL);
      Inc(CR, SR);

      Inc(Addr, TFrameBuffer.Width);
    end;
  end;
end;
{$ENDREGION'}

{$REGION 'Console'}
procedure TVDU.Cls;
begin
  NeedsConsole;

  FillChar(FConsole^.Chars,   SizeOf(FConsole^.Chars),   0); // or 32?
  FillChar(FConsole^.Attribs, SizeOf(FConsole^.Attribs), FRegisters.CaretAttrib);

  FRegisters.CaretX := 0;
  FRegisters.CaretY := 0;
end;

procedure TVDU.Write(X, Y: Integer; const AText: AnsiString; AAttr: Byte);
var
  StartX: Integer;
  Offset: Integer;
begin
  if (Cardinal(Y) >= TConsole.Height) or (X >= TConsole.Width) then
    Exit;

  StartX := X;
  Offset := 1;

  if StartX < 0 then
  begin
    Offset := Offset - StartX;
    StartX := 0;
  end;

  NeedsConsole;

  with FConsole^ do
    for var i := 0 to Length(AText) - Offset do
    begin
      if (StartX + i) >= Width then
        Break;

      Chars  [Y, StartX + i] := AText[Offset + i];
      Attribs[Y, StartX + i] := AAttr;
    end;
end;

procedure TVDU.Print(const AText: AnsiString);
  procedure CheckScroll;
  begin
    with FRegisters^, FConsole^ do
      if CaretY >= Height then
      begin
        CaretY := Height - 1;

        Move(Chars  [1, 0], Chars  [0, 0], ((Height - 1) * Width));
        Move(Attribs[1, 0], Attribs[0, 0], ((Height - 1) * Width));

        FillChar(Chars  [Height - 1, 0], Width, 0); // or 32?
        FillChar(Attribs[Height - 1, 0], Width, CaretAttrib);
      end;
  end;

  procedure NewLine;
  begin
    FRegisters.CaretX := 0;
    Inc(FRegisters^.CaretY);

    CheckScroll;
  end;
var
  Tab: Byte;
begin
  NeedsConsole;

  with FRegisters^, FConsole^ do
  begin
    Tab := CaretTabStop;

    if Tab = 0 then
      Tab := 8;

    if CaretX >= Width  then CaretX := Width  - 1;
    if CaretY >= Height then CaretY := Height - 1;

    for var c in AText do
      case c of
        #$00: ;
        #$07: ; // TODO: Bleep

        #$08:
          if CaretX > 0 then
          begin
            Dec(CaretX);

            Chars  [CaretY, CaretX] := #0;
            Attribs[CaretY, CaretX] := CaretAttrib;
          end;

        #$09:
        begin
          CaretX := CaretX + (Tab - (CaretX mod Tab));

          if CaretX >= Width then
            NewLine;
        end;

        #$0A: NewLine;

        #$0B:
        begin
          Inc(CaretY);
          CheckScroll;
        end;

        #$0D: CaretX := 0;
        #$1B: ; // TODO: Simple ANSI sequences support?
      else
        Chars  [CaretY, CaretX] := c;
        Attribs[CaretY, CaretX] := CaretAttrib;

        Inc(CaretX);

        if CaretX >= Width then
          NewLine;
      end;
  end;
end;

procedure TVDU.Locate(X, Y: Integer);
begin
  with FRegisters^ do
  begin
    if X < 0 then
      CaretX := 0
    else if X >= TConsole.Width then
      CaretX := TConsole.Width - 1
    else
      CaretX := X;

    if Y < 0 then
      CaretY := 0
    else if Y >= TConsole.Height then
      CaretY := TConsole.Height - 1
    else
      CaretY := Y;
  end;
end;

procedure TVDU.Colour(AInk, APaper: Byte; ABold: Boolean);
begin
  FRegisters.CaretAttrib := (AInk and %1111) or ((APaper and %111) shl 4) or (Ord(ABold) shl 7);
end;
{$ENDREGION}

{$ENDREGION}

end.
