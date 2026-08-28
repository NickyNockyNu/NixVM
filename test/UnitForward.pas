unit UnitForward;

interface

procedure CountDownA(n: Integer);

procedure Unused;

implementation

procedure Unused;
begin
  Writeln('Im unused');
end;

procedure CountDownB(n: Integer); forward;

procedure CountDownA(n: Integer);
begin
  if n > 0 then
  begin
    Writeln('A: %d', n);
    CountDownB(n - 1);
  end;
end;

procedure CountDownB(n: Integer);
begin
  if n > 0 then
  begin
    Writeln('B: %d', n);
    CountDownA(n - 1);
  end;
end;

end.
