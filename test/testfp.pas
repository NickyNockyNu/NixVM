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

procedure Main;
begin
  for var i := 0 to 255 do
    SetPixel(10 + i, 10, i);
end;

begin
  Main;
end.
