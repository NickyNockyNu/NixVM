unit Passe;

interface

uses
  SysConst;

const
  _Addr_KeyStates      = $00000528;
  _Addr_KeyboardBuffer = $00000628;
  _Addr_Mouse          = $0000072A;
  _Addr_Gamepads       = $00000736;

  _Addr_AudioRegisters = $00000794;
  _Addr_AudioChannels  = $000007B1;

  _Addr_VideoRegisters = $00000845;
  _Addr_Stickers       = $000020F1;
  _Addr_Atlas          = $000022F1;
  _Addr_Sprites        = $00002AF1;
  
  _VDU = $A0;

  _SysCall_VDUReset = _VDU + 0;
  _SysCall_VDUClear = _VDU + 1;

  _SysCall_VDUGetPixel = _VDU + 2;
  _SysCall_VDUSetPixel = _VDU + 3;

  _SysCall_VDUHLine = _VDU + 4;
  _SysCall_VDUVLine = _VDU + 5;

  _SysCall_VDULine = _VDU + 6;

  _SysCall_VDUDrawRectangle = _VDU + 7;
  _SysCall_VDUFillRectangle = _VDU + 8;

  _SysCall_VDUDrawCircle = _VDU + 9;
  _SysCall_VDUFillCircle = _VDU + 10;

  _SysCall_VDUDrawEllipse = _VDU + 11;
  _SysCall_VDUFillEllipse = _VDU + 12;

  _SysCall_VDUDrawTriangle = _VDU + 13;
  _SysCall_VDUFillTriangle = _VDU + 14;

  _CON = $C0;

  _SysCall_CONCls    = _CON + 0;
  _SysCall_CONWrite  = _CON + 1;
  _SysCall_CONPrint  = _CON + 2;
  _SysCall_CONLocate = _CON + 3;
  _SysCall_CONColour = _CON + 4;

  _SID = $D0;
  
  _SysCall_SIDReset   = _SID + 0;
  _SysCall_SIDNoteOn  = _SID + 1;
  _SysCall_SIDNoteOff = _SID + 2;
  _SysCall_SIDBeep    = _SID + 3;

  AudioChannelCount = 4;

  FrameBufferWidth  = 320;
  FrameBufferHeight = 180;

  ConsoleCharHeight = 8;

  ConsoleWidth  = FrameBufferWidth  div 8;
  ConsoleHeight = FrameBufferHeight div ConsoleCharHeight;

  StickerCount = 64;
  
  AtlasCount  = 128;
  SpriteCount = 32;

type
  TKeyState = record
    State: Byte;
    
    function IsUp:        Boolean; begin Result := (State and 1) = 0; end;
    function IsDown:      Boolean; begin Result := (State and 1) = 1; end;
    function WasPressed:  Boolean; begin Result :=  State        = 1; end;
    function WasReleased: Boolean; begin Result :=  State        = 2; end;
    function IsHeld:      Boolean; begin Result :=  State        = 3; end;
  end;

  PKeyStates = ^TKeyStates;
  TKeyStates = array[0..255] of TKeyState;

const
  Keys: PKeyStates = _Addr_KeyStates;

type
  PKeyboardBuffer = ^TKeyboardBuffer;
  TKeyboardBuffer = record
    Head: Byte;
    Tail: Byte;
    
    Chars: array[0..255] of Char;
    
    function Pop: Char;
    begin
      if Head = Tail then
        Exit(#0);

      Result := Chars[Head];

      Head := Head + 1;
    end;
  end;
  
const
  KeyboardBuffer: PKeyboardBuffer = _Addr_KeyboardBuffer;
 
function WaitKey: Char;
 
type
  PMouse = ^TMouse;
  TMouse = record
    X: SmallInt;
    Y: SmallInt;
    Z: SmallInt;
    
    DeltaX: SmallInt;
    DeltaY: SmallInt;
    DeltaZ: SmallInt;
  end;

const
  Mouse: PMouse = _Addr_Mouse;
  
type
  PAudioRegisters = ^TAudioRegisters;
  TAudioRegisters = record
    Volume:   Single;
    OutLevel: Single;
    
    CutoffFreq: Single;
    DelayTime:  Single;
    Feedback:   Single;
    DelayMix:   Single;
    DelayGlide: Single;
    
    Flags: Byte;
  end;
  
const
  AudioRegisters: PAudioRegisters = _Addr_AudioRegisters;

type
  TWaveform = (wfSine, wfSquare, wfTriangle, wfSawtooth, wfNoise);

  TAudioChannel = record
    Frequency:  Single;
    Volume:     Single;
    PulseWidth: Single;
    GlideSpeed: Single;
    
    Attack:  Single;
    Decay:   Single;
    Sustain: Single;
    Release: Single;
    
    OutLevel: Single;

    Flags: Byte;
    
    function GetWaveform: TWaveform;
    begin
      Result := TWaveform(Flags and %00000111);
    end;
    
    procedure SetWaveform(AWaveform: TWaveform);
    begin
      Flags := (Flags and %11111000) or (Byte(AWaveform) and %00000111);
    end;

    property Waveform: TWaveform read GetWaveform write SetWaveform;    
  end;

  PAudioChannels = ^TAudioChannels;
  TAudioChannels = array[0..AudioChannelCount - 1] of TAudioChannel;
  
const
  AudioChannels: PAudioChannels = _Addr_AudioChannels;
  
procedure SIDReset; syscall _SysCall_SIDReset;

procedure NoteOn (AChannel: Integer; AReset: Boolean); syscall _SysCall_SIDNoteOn;
procedure NoteOff(AChannel: Integer);                  syscall _SysCall_SIDNoteOff;

procedure Sound(AFrequency, ATime: Single); syscall _SysCall_SIDBeep;
procedure Beep;

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

  PScanline = ^TScanline;
  TScanline = record
    Source: Byte;

    HorizontalOffset: SmallInt;
    HorizontalScale:  Single;

    PaletteOffset: ShortInt;
  end;

  PScanlines = ^TScanlines;
  TScanlines = array[0..FrameBufferHeight - 1] of TScanline;

  PFont = ^TFont;
  TFont = array[0..255, 0..ConsoleCharHeight - 1] of Byte;

  PConsole = ^TConsole;
  TConsole = record
    Chars:   array[0..ConsoleHeight - 1, 0..ConsoleWidth - 1] of Char;
    Attribs: array[0..ConsoleHeight - 1, 0..ConsoleWidth - 1] of Byte;
  end;

  PSticker = ^TSticker;
  TSticker = record
    X: SmallInt;
    Y: SmallInt;

    Colour: Byte;
    Glyph:  Char;

    Flags:  Byte;
    Anchor: Byte;
  end;

  PStickers = ^TStickers;
  TStickers = array[0..StickerCount - 1] of TSticker;

const
  Stickers: PStickers = _Addr_Stickers;
  
type
  PAtlasEntry = ^TAtlasEntry;
  TAtlasEntry = record
    Address: Pointer;
    Stride:  Integer;
    
    Width:  Word;
    Height: Word;
    
    Reserved: Cardinal;
  end;

  PSpriteAtlas = ^TSpriteAtlas;
  TSpriteAtlas = array[0..AtlasCount - 1] of TAtlasEntry;

  PSprite = ^TSprite;
  TSprite = record
    AtlasID: Byte;
    
    X: Single;
    Y: Single;
    Z: Byte;
    
    ScaleX: Single;
    ScaleY: Single;
    
    Angle:  Single;
    PivotX: Single;
    PivotY: Single;
    
    PaletteOffset: ShortInt;
    
    Flags: Byte;
  end;

  PSprites = ^TSprites;
  TSprites = array[0..SpriteCount - 1] of TSprite;
  
const
  SpriteAtlas: PSpriteAtlas = _Addr_Atlas;
  Sprites:     PSprites     = _Addr_Sprites;

type
  PVideoRegisters = ^TVideoRegisters;
  TVideoRegisters = record
    DisplayBuffer: PFrameBuffer;
    DrawBuffer:    PFrameBuffer;
    Palette:       PPalette;
    Scanlines:     PScanlines;
    Font:          PFont;
    Console:       PConsole;

    BorderColour: TColour;
    TintColour:   TColour;

    OffsetX: SmallInt;
    OffsetY: SmallInt;

    Flags: Byte;

    ScanlineIRQ: Byte;

    CaretX:         Byte;
    CaretY:         Byte;
    CaretChar:      Char;
    CaretBlinkRate: Byte;
    CaretAttrib:    Byte;
    CaretTabStop:   Byte;
  end;

const
  VideoRegisters: PVideoRegisters = _Addr_VideoRegisters;
    
procedure VDUReset; syscall _SysCall_VDUReset;

procedure Clg(AColour: Byte); syscall _SysCall_VDUClear;

function  GetPixel(X, Y: Integer): Byte;    syscall _SysCall_VDUGetPixel;
procedure SetPixel(X, Y: Integer; A: Byte); syscall _SysCall_VDUSetPixel;

procedure DrawHLine(X, Y, L: Integer; C: Byte); syscall _SysCall_VDUHLine;
procedure DrawVLine(X, Y, L: Integer; C: Byte); syscall _SysCall_VDUVLine;

procedure DrawLine(X1, Y1, X2, Y2: Integer; C: Byte); syscall _SysCall_VDULine;

procedure DrawRectangle(X, Y, W, H: Integer; C: Byte); syscall _SysCall_VDUDrawRectangle;
procedure FillRectangle(X, Y, W, H: Integer; C: Byte); syscall _SysCall_VDUFillRectangle;

procedure DrawCircle(CX, CY, R: Integer; C: Byte); syscall _SysCall_VDUDrawCircle;
procedure FillCircle(CX, CY, R: Integer; C: Byte); syscall _SysCall_VDUFillCircle;

procedure DrawEllipse(CX, CY, RX, RY: Integer; C: Byte); syscall _SysCall_VDUDrawEllipse;
procedure FillEllipse(CX, CY, RX, RY: Integer; C: Byte); syscall _SysCall_VDUFillEllipse;

procedure DrawTriangle(X1, Y1, X2, Y2, X3, Y3: Integer; C: Byte); syscall _SysCall_VDUDrawTriangle;
procedure FillTriangle(X1, Y1, X2, Y2, X3, Y3: Integer; C: Byte); syscall _SysCall_VDUFillTriangle;

procedure Cls; syscall _SysCall_CONCls;

procedure TextOut(X, Y: Integer; AText: String; AAttrib: Byte); syscall _SysCall_CONWrite;

// Not needed "Print" is handled by the compiler better (Also _SysCall_DebugPrint routes to this)
//procedure ConPrint(AText: String); syscall _SysCall_CONPrint;

procedure Locate(X, Y: Integer); syscall _SysCall_CONLocate;

procedure ConColour(AInk, APaper: Byte; ABold: Boolean); syscall _SysCall_CONColour;

implementation

function WaitKey: Char;
var
  Ch: Char;
begin
  Ch := KeyboardBuffer^.Pop;

  while Ord(Ch) = 0 do
  begin
    Yield;
    Ch := KeyboardBuffer^.Pop;
  end;

  Result := Ch;
end;

procedure Beep;
begin
  // TODO: Check param types for float
  Sound(400.0, 0.6);
end;

end.