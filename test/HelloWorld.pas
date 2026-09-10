program HelloWorld targets passe;

{$HEAP 2k}
{$STACK 2k}

uses
  System;
  
const
  Hello = 'Hello';
  World = 'World';

procedure Main;
var
  Msg: String;
begin
  Msg := Format('%s, %s!', Hello, World);
  Println(Msg);
  Halt(123);
end;

begin
  Main;
end.
