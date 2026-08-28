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
  
  Writeln('%f %d', fa, ia);
  
  fb := Single(ia);
  ib := Integer(fa);
  
  Writeln('%f %d', fb, ib);
  
  ia := trunc(fa);
  ib := round(fa);

  Writeln('%d %d', ia, ib);
end.
