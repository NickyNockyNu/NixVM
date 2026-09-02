program testcase targets console;

{$DESCRIPTION 'Testing "case" syntax'}
{$COPYRIGHT '(c) Nik'}
{$ICON 'GameIcon.ico'}

{$HEAP 0}
{$STACK 128}

procedure ClassifyInt(a: Integer);
begin
  Print('%d: ', a);
  
  case a of
    3, 5, 7: PrintLn('Small prime');
    13..19:  PrintLn('Teen');
  else
    PrintLn('Not classified');
  end;    
end;

var
  i: Integer;
begin
  for i := 0 to 20 do
    ClassifyInt(i);
end.