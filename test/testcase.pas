program testcase targets console;

{$HEAP 0}
{$STACK 128}
{$BASE $4E0}

procedure classifyint(a: Integer);
begin
  Print('%d: ', a);
  
  case a of
    3, 5, 7: Println('Small prime');
    13..19:  Println('Teen');
  else
    Println('Not classified');
  end;    
end;

var
  i: Integer;
begin
  for i := 0 to 20 do
    classifyint(i);
end.