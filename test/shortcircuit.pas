program TestShortCircuit;

{$HEAP 0}
{$STACK 1k}
{$BASE $4E0}

function ShouldNotBeCalled: Boolean;
begin
  Writeln('ERROR: Right side was evaluated!');
  Result := True;
end;

begin
  // Should NOT call ShouldNotBeCalled
  if (1 = 2) and ShouldNotBeCalled then
    Writeln('Unreachable');

  // Should NOT call ShouldNotBeCalled
  if (1 = 1) or ShouldNotBeCalled then
    Writeln('Short-circuit OR OK');
end.