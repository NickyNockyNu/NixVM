program HelloWorld targets console;

{$HEAP 0}
{$STACK 128}

uses
  System;

procedure Main;
begin
  Println('Hello, World!');
  Halt(123);
end;

begin
  Main;
end.
