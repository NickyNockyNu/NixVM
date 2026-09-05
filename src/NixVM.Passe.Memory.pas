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

  NixVM.Passe.Video;

type
  {$REGION 'Memory'}
  PPasseMemory = ^TPasseMemory;
  TPasseMemory = packed record
  const
    VideoRegistersAddress = 0;
    PaletteAddress        = VideoRegistersAddress + SizeOf(TVideoRegisters);
    FrameBufferAddress    = PaletteAddress        + SizeOf(TPalette);
  public
    VideoRegisters: TVideoRegisters;
    Palette:        TPalette;
    FrameBuffer:    TFrameBuffer;

    procedure Reset;
  end;
  {$ENDREGION}

implementation

{$REGION 'Memory'}
procedure TPasseMemory.Reset;
begin
  with VideoRegisters do
  begin
    Reset;

    DisplayBuffer := SizeOf(TCoreSystemMemory) + TPasseMemory.FrameBufferAddress;
    DrawBuffer    := DisplayBuffer;
    Palette       := SizeOf(TCoreSystemMemory) + TPasseMemory.PaletteAddress;
  end;

  Palette.Reset;

  FrameBuffer.Clear(1);
end;
{$ENDREGION}

end.
