{with a title}
program ExprFold targets console;

{$HEAP 0}
{$STACK 1k}

var
  i: Integer;
begin
  i := 1 + 2 + 3;
  Println('%d', i);
end.