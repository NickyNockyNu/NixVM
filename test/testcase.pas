program testcase targets Test;

{$HEAP 0}
{$STACK 128}
{$BASE $4E0}

type
  TState = (Idle, Running, Paused, Dead);

procedure classifyint(a: Integer);
begin
  Write('%d: ', a);
  case a of
    3, 5, 7: Writeln('Small prime');
    13..19:  Writeln('Teen');
  else
    Writeln('Not classified');
  end;    

end;

var
  i: Integer;
begin
  for i := 0 to 20 do
    classifyint(i);
end.