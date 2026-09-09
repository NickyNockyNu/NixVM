{
  NixVM.Passe.Memory.pas
    Passe OEM memory

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

unit NixVM.Passe.Memory;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  NixVM.Core.System,

  NixVM.Passe.Video,
  NixVM.Passe.Input,
  NixVM.Passe.Audio;

type
  {$REGION 'System'}
  PPasseSystem = ^TPasseMemory;
  TPasseMemory = packed record
  const
    ScanlineIRQID = 5;

    KeyStatesAddress       = SizeOf(TCoreSystemMemory);
    KeyboardBufferAddress  = KeyStatesAddress      + SizeOf(TKeyStates);
    MouseAddress           = KeyboardBufferAddress + SizeOf(TKeyboardBuffer);
    GamepadsAddress        = MouseAddress          + SizeOf(TMouse);

    AudioRegistersAddress = GamepadsAddress + SizeOf(TGamepads);
    AudioChannelsAddress  = AudioRegistersAddress + SizeOf(TAudioRegisters);

    VideoRegistersAddress = AudioChannelsAddress  + SizeOf(TAudioChannels);
    PaletteAddress        = VideoRegistersAddress + SizeOf(TVideoRegisters);
    ScanlinesAddress      = PaletteAddress        + SizeOf(TPalette);
    FontAddress           = ScanlinesAddress      + SizeOf(TScanlines);
    ConsoleAddress        = FontAddress           + SizeOf(TFont);
    StickersAddress       = ConsoleAddress        + SizeOf(TConsole);
    SpritesAddress        = StickersAddress       + SizeOf(TStickers);
    FrameBufferAddress    = SpritesAddress        + SizeOf(TSprites);
  public
    KeyStates:      TKeyStates;
    KeyboardBuffer: TKeyboardBuffer;
    Mouse:          TMouse;
    Gamepads:       TGamepads;

    AudioRegisters: TAudioRegisters;
    AudioChannels:  TAudioChannels;

    VideoRegisters: TVideoRegisters;
    Palette:        TPalette;
    Scanlines:      TScanlines;
    Font:           TFont;
    Console:        TConsole;
    Stickers:       TStickers;
    Sprites:        TSprites;
    FrameBuffer:    TFrameBuffer;

    procedure Reset;
  end;
  {$ENDREGION}

implementation

{$REGION 'Memory'}
procedure TPasseMemory.Reset;
begin
  // Video memory reset handled by VDU
  // Input memory reset handled by HID
  // Audio memory reset handled by SID
end;
{$ENDREGION}

end.
