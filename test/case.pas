{
 This is a title comment
}

program intrinsics targets Test;

{$HEAP 0}
{$STACK 128}
{$BASE $4E0}

type
  TState = (Idle, Running, Paused, Dead);

var
  Arr: array[10..20] of Integer;
  i: Integer;
  c: Char;
  s: TState;
  p: ^Integer;

begin
  i := 100;
  Inc(i);        // 101
  Inc(i, 9);     // 110
  Dec(i, 10);    // 100
  
  c := Chr(65);  // 'A'
  c := Succ(c);  // 'B'
  
  s := TState.Running;
  s := Succ(s);  // Paused (2)
  
  Println('i=%d, c=%c, Ord(c)=%d, s=%d', i, c, Ord(c), Ord(s));
  Println('Low(Arr)=%d, High(Arr)=%d, Length(Arr)=%d', Low(Arr), High(Arr), Length(Arr));
  
  p := nil;
  if not Assigned(p) then
    Writeln('Assigned check OK');
end.