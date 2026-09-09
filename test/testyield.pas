program testyield targets passe;

{$HEAP 2k}
{$STACK 1k}
  
begin
  while True do
  begin
    PrintLn('V');
    Yield;
  end;
end.
