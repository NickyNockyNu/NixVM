program ProgName targets passe;

{$DESCRIPTION 'An example program'}
{$COPYRIGHT   '(c) My Name 2026'}

{.$ICON 'ProgIcon.ico'}

{$HEAP  128k}
{$STACK 16k}

{$REGION Program startup}
// --------------------------------------------------------------
// Program startup
// --------------------------------------------------------------
procedure StartUp;
begin

end;
{$ENDREGION}

{$REGION Program update}
// --------------------------------------------------------------
// Program main loop
// --------------------------------------------------------------
procedure Update(Delta: Single);
begin

end;
{$ENDREGION}

{$REGION Program entry point}
// --------------------------------------------------------------
// Program entry point
// --------------------------------------------------------------
begin
  StartUp;
  
  repeat
    yield;
    Update(SystemRegisters^.Delta);
  until False;
end.
{$ENDREGION}