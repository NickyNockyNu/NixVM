program TestStringLen targets console;

{$HEAP 32k}
{$STACK 16k}

function HeapAvailable: Cardinal; syscall $24;

procedure TestStrSetLength;
var
  s: String;
begin
  SetLength(s, 10);

  for var i := 1 to 10 do
    s[i] := Chr(64 + i); // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'

  Println('Buffer: "%s" (Length=%d)', s, Length(s));

  SetLength(s, 5);
  Println('Shrunk: "%s" (Length=%d)', s, Length(s));
end;

begin
  Println('Initial Free Heap: %d bytes', HeapAvailable);
  TestStrSetLength;
  Println('Final Free Heap: %d bytes', HeapAvailable);
end.