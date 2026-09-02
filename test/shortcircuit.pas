program TestShortCircuit targets console;

{$HEAP 0}
{$STACK 1k}

function ShouldNotBeCalled: Boolean;
begin
  Println('ERROR: Right side was evaluated!');
  Result := True;
end;

begin
  if (1 = 2) and ShouldNotBeCalled then
    Println('Unreachable');

  if (1 = 1) or ShouldNotBeCalled then
    Println('Short-circuit OR OK');
end.