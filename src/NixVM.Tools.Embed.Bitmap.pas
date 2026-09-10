{
  NixVM.Tools.Embed.Bitmap.pas
    Image file embed helper

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

unit NixVM.Tools.Embed.Bitmap;

{$INCLUDE 'NixVM.Options.inc'}

{$IF NOT DEFINED(MSWINDOWS)}
  {$ERROR FATAL 'Platform not supported'}
{$ENDIF}

interface

uses
  Winapi.Windows,

  System.SysUtils,
  System.Classes,

  NixVM.Passe.Video;

type
  {$REGION 'TBitmapData'}
  TBitmapData = record
    Width:       Cardinal;
    Height:      Cardinal;
    Stride:      Integer;
    PixelFormat: Integer;
    Scan0:       Pointer;
    Reserved:    Cardinal;
  end;
  {$ENDREGION}

  {$REGION 'TImage'}
  TImage = class
  const
    PixelFormat = $26200A;
  private
    FImage: Pointer;

    FWidth:  Integer;
    FHeight: Integer;

    class constructor Create;
    class destructor  Destroy;

    {$REGION 'GDI+'}
    type
      TGdiplusStartupInput = record
        GdiplusVersion:           Cardinal;
        DebugEventCallback:       Pointer;
        SuppressBackgroundThread: BOOL;
        SuppressExternalCodecs:   BOOL;
      end;

    class var
      FGdipModule: HMODULE;
      FGdipToken:  ULONG_PTR;

      FGdipStartup:      function(out AToken: ULONG_PTR; const AInput: TGdiplusStartupInput; AOutput: Pointer): Integer; stdcall;
      FGdipShutdown:     procedure(AToken: ULONG_PTR); stdcall;
      FGdipLoadFromFile: function(AFilename: PWideChar; out AImage: Pointer): Integer; stdcall;
      FGdipSaveToFile:   function(AImage: Pointer; AFilename: PWideChar; AEncoder: PGUID; AEncoderParams: Pointer): Integer; stdcall;
      FGdipCreateBitmap: function(AWidth, AHeight, AStride, APixelFormat: Integer; AScan0: Pointer; out ABitmap: Pointer): Integer; stdcall;
      FGdipGetWidth:     function(AImage: Pointer; out AWidth: Cardinal): Integer; stdcall;
      FGdipGetHeight:    function(AImage: Pointer; out AHeight: Cardinal): Integer; stdcall;
      FGdipLockBits:     function(AImage: Pointer; const ARect: TRect; AFlags: Cardinal; AFormat: Integer; out ALockedBitmapData: TBitmapData): Integer; stdcall;
      FGdipUnlockBits:   function(AImage: Pointer; const ALockedBitmapData: TBitmapData): Integer; stdcall;
      FGdipDispose:      function(AImage: Pointer): Integer; stdcall;
    {$ENDREGION}
  public
    class var DefaultPalette: TPalette;

    class function LoadEmbed(const AFileName: String; out AData: TBytes; AErrors: TStrings = nil; APalette: PPalette = nil): Boolean;

    class function  LoadGDIPlus(AErrors: TStrings = nil): Boolean;
    class procedure UnloadGDIPlus;

    constructor Create(const AFileName: String; AErrors: TStrings = nil);
    destructor  Destroy; override;

    function LockBits(const ARect: TRect; out ALockedBitmapData: TBitmapData; AFlags: Cardinal = 1; APixelFormat: Integer = PixelFormat): Boolean;
    function UnlockBits(const ALockedBitmapData: TBitmapData): Boolean;

    property Width:  Integer read FWidth;
    property Height: Integer read FHeight;
  end;
  {$ENDREGION}

implementation

{$REGION 'TImage'}
class constructor TImage.Create;
begin
  DefaultPalette.Reset;
end;

class destructor TImage.Destroy;
begin
  UnloadGDIPlus;
end;

class function TImage.LoadEmbed(const AFileName: String; out AData: TBytes; AErrors: TStrings = nil; APalette: PPalette = nil): Boolean;
var
  Image:   TImage;
  BmpData: TBitmapData;
  Rect:    TRect;
  Addr:    PByte;
  Pixel:   TColour;
  Dist:    Integer;
  MinDist: Integer;
  BestIdx: Integer;
  R, G, B: Integer;
begin
  Result := False;

  Image := TImage.Create(AFileName, AErrors);

  try
    if Image.Width = 0 then
      Exit;

    SetLength(AData, Image.Width * Image.Height);

    Rect := TRect.Create(0, 0, Image.Width, Image.Height);

    if not Image.LockBits(Rect, BmpData) then
    begin
      if Assigned(AErrors) then
        AErrors.Add('Failed to get bitmap data');

      Exit;
    end;

    try
      for var y := 0 to Image.Height - 1 do
      begin
        Addr  := PByte(BmpData.Scan0) + (y * BmpData.Stride);

        for var x := 0 to Image.Width - 1 do
        begin
          Pixel := PColour(Addr + (x * 4))^;

          if APalette = nil then
            AData[(y * Image.Width) + x] := Pixel.R
          else
          begin
            MinDist := High(Integer);
            BestIdx := 0;

            for var i := 0 to 255 do
            begin
              R := Integer(Pixel.B) - APalette.Colours[i].R;
              G := Integer(Pixel.G) - APalette.Colours[i].G;
              B := Integer(Pixel.R) - APalette.Colours[i].B;

              Dist := (R * R) + (G * G) + (B * B);

              if Dist < MinDist then
              begin
                MinDist := Dist;
                BestIdx := i;

                if MinDist = 0 then
                  Break;
              end;
            end;

            AData[(y * Image.Width) + x] := BestIdx;
          end;
        end;
      end;
    finally
      Image.UnlockBits(BmpData);
    end;
  finally
    Image.Free;
  end;

  Result := True;
end;

{$REGION 'GDI+}
class function TImage.LoadGDIPlus(AErrors: TStrings = nil): Boolean;
var
  Input: TGdiplusStartupInput;
begin
  if FGdipModule <> 0 then
    Exit(True);

  Result := False;

  FGdipModule := LoadLibrary('gdiplus.dll');

  if FGdipModule = 0 then
  begin
    if Assigned(AErrors) then
      AErrors.Add('GDI+ library not found');

    Exit;
  end;

  FGdipStartup      := GetProcAddress(FGdipModule, 'GdiplusStartup');
  FGdipShutdown     := GetProcAddress(FGdipModule, 'GdiplusShutdown');
  FGdipLoadFromFile := GetProcAddress(FGdipModule, 'GdipLoadImageFromFile');
  FGdipSaveToFile   := GetProcAddress(FGdipModule, 'GdipSaveImageToFile');
  FGdipCreateBitmap := GetProcAddress(FGdipModule, 'GdipCreateBitmapFromScan0');
  FGdipGetWidth     := GetProcAddress(FGdipModule, 'GdipGetImageWidth');
  FGdipGetHeight    := GetProcAddress(FGdipModule, 'GdipGetImageHeight');
  FGdipLockBits     := GetProcAddress(FGdipModule, 'GdipBitmapLockBits');
  FGdipUnlockBits   := GetProcAddress(FGdipModule, 'GdipBitmapUnlockBits');
  FGdipDispose      := GetProcAddress(FGdipModule, 'GdipDisposeImage');

  if not Assigned(FGdipStartup) then
  begin
    UnloadGDIPlus;

    if Assigned(AErrors) then
      AErrors.Add('GDI+ entry points missing');

    Exit;
  end;

  FillChar(Input, SizeOf(Input), 0);
  Input.GdiplusVersion := 1;

  if FGdipStartup(FGdipToken, Input, nil) <> 0 then
  begin
    UnloadGDIPlus;

    if Assigned(AErrors) then
      AErrors.Add('Failed to startup GDI+');

    Exit;
  end;

  Result := True;
end;

class procedure TImage.UnloadGDIPlus;
begin
  if FGdipModule = 0 then
    Exit;

  if Assigned(FGdipShutdown) and (FGdipToken <> 0) then
    FGdipShutdown(FGdipToken);

  FreeLibrary(FGdipModule);

  FGdipModule := 0;
  FGdipToken  := 0;

  FGdipStartup      := nil;
  FGdipShutdown     := nil;
  FGdipLoadFromFile := nil;
  FGdipSaveToFile   := nil;
  FGdipCreateBitmap := nil;
  FGdipGetWidth     := nil;
  FGdipGetHeight    := nil;
  FGdipLockBits     := nil;
  FGdipUnlockBits   := nil;
  FGdipDispose      := nil;
end;
{$ENDREGION}

constructor TImage.Create(const AFileName: String; AErrors: TStrings);
var
  CTemp: Cardinal;
begin
  inherited Create;

  if not LoadGDIPlus(AErrors) then
    Exit;

  if FGdipLoadFromFile(PWideChar(WideString(AFileName)), FImage) <> 0 then
  begin
    if Assigned(AErrors) then
      AErrors.Add('Failed to load  "' + AFileName + '"');

    FWidth  := 0;
    FHeight := 0;

    FImage := nil;

    Exit;
  end;

  FGdipGetWidth (FImage, CTemp); FWidth  := CTemp;
  FGdipGetHeight(FImage, CTemp); FHeight := CTemp;
end;

destructor TImage.Destroy;
begin
  if Assigned(FImage) then
    FGdipDispose(FImage);

  inherited;
end;

function TImage.LockBits(const ARect: TRect; out ALockedBitmapData: TBitmapData; AFlags: Cardinal; APixelFormat: Integer): Boolean;
begin
  if Assigned(FImage) then
    Result := FGdipLockBits(FImage, ARect, AFlags, APixelFormat, ALockedBitmapData) = 0
  else
    Result := False;
end;

function TImage.UnlockBits(const ALockedBitmapData: TBitmapData): Boolean;
begin
  if Assigned(FImage) then
    Result := FGdipUnlockBits(FImage, ALockedBitmapData) = 0
  else
    Result := False;
end;
{$ENDREGION}

end.
