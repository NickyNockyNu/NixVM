unit Passe;

interface

uses
  SysConst;

const
  FrameBufferWidth  = 320;
  FrameBufferHeight = 180;

type
  PFrameBuffer = ^TFrameBuffer;
  TFrameBuffer = array[0..(FrameBufferWidth * FrameBufferHeight) - 1] of Byte;

  PColour = ^TColour;
  TColour = record
    r, g, b, a: Byte;
    
    procedure SetRGB(ar, ag, ab: Byte);
    begin
      r := ar;
      g := ag;
      b := ab;
      a := 255;
    end;
  end;

  PPalette = ^TPalette;
  TPalette = array[0..255] of TColour;
  
  PVideoRegisters = ^TVideoRegisters;
  TVideoRegisters = record
    DisplayBuffer: PFrameBuffer;
    DrawBuffer:    PFrameBuffer;
    Palette:       PPalette;
    BorderColour:  TColour;
    TintColour:    TColour;
    OffsetX:       SmallInt;
    OffsetY:       SmallInt;
    Flags:         Byte;
    
    Reserved: array[0..6] of Byte;
  end;
  
const
  VideoRegisters: PVideoRegisters = _Addr_OEM;

implementation

end.