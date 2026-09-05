program testpanic targets console;

{$HEAP 2k}
{$STACK 1k}

uses
  SysConst,
  System;
  
type
  PCustomException = ^TCustomException;
  TCustomException = record
    Code: Cardinal;
  end;
  
procedure OnPanic; interrupt;
var
  e: PCustomException;
begin
  Println('Caught panic %d. User code %d', SystemState^.PanicCode, SystemState^.UserCode);
  
 if SystemState^.PanicCode = 8 then
  begin
    e := PCustomException(SystemState^.UserCode);
    Println('Exception code %d', e^.Code);
  end;
  
  Halt;
end;

var
  e: TCustomException;
begin
  Interrupts[0] := @OnPanic;
  
  Println('Raising exception...');
  
  e.Code := 123;
  raise e;
end.
