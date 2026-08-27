program HelloWorld targets Test;

{$HEAP 0}
{$STACK 128}
{$BASE $4E0}

uses
  System;

begin
  Writeln('Hello, World!');
end.
