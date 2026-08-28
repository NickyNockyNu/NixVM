program TestArgs;

{$HEAP 0}
{$STACK 1k}
{$BASE $4E0}

procedure Test(a, b, c, d, e, f, g: Integer);
begin
  Writeln('%d %d %d %d %d %d %d', a, b, c, d, e, f, g);
end;

begin
  Test(1, 2, 3, 4, 5, 6, 7);
end.