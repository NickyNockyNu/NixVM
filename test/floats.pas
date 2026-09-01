program floats targets Test;

{$HEAP 0}
{$STACK 128}
{$BASE $4E0}

var
  fa, fb: Single;
  ia, ib: Integer;

begin
  fa := 9.876;
  ia := 1234;
  
  println('%f %d', fa, ia);
  
  fb := Single(ia);
  ib := Integer(fa);
  
  println('%f %d', fb, ib);
  
  ia := trunc(fa);
  ib := round(fa);

  println('%d %d', ia, ib);
end.
