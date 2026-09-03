program testpanic targets console;

{$HEAP 2k}
{$STACK 2k}

uses
  SysConst,
  System;
  
type
  PException = ^TException;
  TException = record
    Code: Cardinal;
  end;
  
procedure OnPanic; interrupt;
var
  e: PException;
begin
  Println('Caught panic %d. User code %d', SystemState^.PanicCode, SystemState^.UserCode);
  
  if SystemState^.PanicCode = 8 then
  begin
    e := PException(SystemState^.UserCode);
    Println('Exception code %d', e^.Code);
  end;
  
  Halt;
end;

var
  e: TException;
begin
  SystemState^.PanicCode := 8;

  Interrupts[0] := @OnPanic;
  
  Println('Raising exception...');
  
  e.Code := 123;
  raise e;
end.
