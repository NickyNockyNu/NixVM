program testfb targets passe;

{$HEAP 0}
{$STACK 256}

uses
  Passe;
  
procedure SetPixel(x, y: Integer; c: Byte);
var
  Addr: Cardinal;
begin
  Addr := (y * FrameBufferWidth) + x;
  VideoRegisters^.DisplayBuffer^[Addr] := c;
end;

var
  i: Integer;

procedure Main;
begin 
  VideoRegisters^.OffsetX := VideoRegisters^.OffsetX + 1;

  for var i := 0 to 255 do
    SetPixel(10 + i, 10, i);

  i := i + 1;
  if i > 100 then
  begin
    i := 0;
    VideoRegisters^.Flags := not VideoRegisters^.Flags;
  end;

  Yield;
end;

begin
  i := 0;
  
  repeat
    Main;
  until False;
end.
