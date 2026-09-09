program testfb targets passe;

{$HEAP 0}
{$STACK 2k}

 function CalcPattern(x, y: Integer): Byte;
 begin
   Exit((x and $FF) xor (y and $FF));
 end;

procedure DrawPattern;
begin
  for var y := 0 to FrameBufferHeight - 1 do
    for var x := 0 to FrameBufferWidth - 1 do
      SetPixel(x, y, CalcPattern(x, y));
end;

var
  i: Integer;

procedure Update;
begin 
  VideoRegisters^.OffsetX := VideoRegisters^.OffsetX + 1;

  i := i + 1;
  if i > 100 then
  begin
    i := 0;
    VideoRegisters^.Flags := VideoRegisters^.Flags xor %00000011;
  end;
end;

begin
  PrintLn('Hello\nWorld\n');
  i := 0;
  
  //DrawPattern;
  
  repeat
    //Update;
    Yield;
  until False;
end.
