program testinput targets passe;

{$HEAP 2k}
{$STACK 1k}

var
  c: Char;
begin
  Println('Press any key to start');
  c := WaitKey;
  Println('(You pressed "%c")', c);

  while True do
  begin 
    if KeyStates[32].WasPressed then 
      Print('SPA')
    else if KeyStates[32].IsHeld then 
      Print('A')
    else if KeyStates[32].WasReleased then 
     Println('CE!')
    else
      with Mouse^ do
        Println('%d, %d, %d  -  %d, %d, %d', X, Y, Z, DeltaX, DeltaY, DeltaZ);
        
    Yield;
  end;
end.
