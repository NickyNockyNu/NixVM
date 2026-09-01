{with a title}
program ExprFold;

{$HEAP 0}
{$STACK 1k}
{$BASE $4E0}

var
  i: Integer;
begin
  i := 1 + 2 + 3;
  Writeln('%d', i);
end.