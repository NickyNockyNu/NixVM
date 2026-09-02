program TestInlineFor targets console;

{$HEAP 32k}
{$STACK 16k}

function HeapAvailable: Cardinal; syscall $24;

type
  TPoint = record
    x, y: Integer;
  end;

var
  points: array[0..2] of TPoint;

procedure TestForStrAlloc;
var
  ss: array[0..5] of String;
begin
  for var i := 0 to 5 do
    ss[i] := Format('Str:%d', i);

  for var s in ss do
    Println('%s', s);
end;

procedure PrintMem;
begin
  Println('%d bytes', HeapAvailable);
end;

begin
  PrintMem;
  
  for var i := 0 to 2 do
  begin
    points[i].x := (i + 1) * 10;
    points[i].y := (i + 1) * 20;
  end;

  for var j: Integer := 2 downto 0 do
    Println('Downto j = %d', j);

  for var pt in points do
    Println('Point: %d, %d', pt.x, pt.y);

  for var ch in 'Nix' do
    Println('Char: %c', ch);
    
  TestForStrAlloc;
  
  PrintMem;
end.