program teststatic targets console;

type
  TTest = record
    A, B: Single;
  end;

var
  a: Integer = 10; static;
  b: Integer = 20;
  c: TTest; static;

begin
  Println('%d, %d', a, b);
  a := a + 1;
  b := b + 1;
end.