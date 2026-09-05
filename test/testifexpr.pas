program TestIfExpr targets console;

{$HEAP 0}
{$STACK 128}

var
  score: Integer;
  status: String;
  bonus: Single;

begin
  score := 85;

  status := if score >= 50 then 'PASS' else 'FAIL';
  Println('Score: %d -> Status: %s', score, status);

  bonus := if score > 80 then 10.5 else 0;
  Println('Bonus: %f', bonus);

  for var i := 1 to 5 do
    Println('Num %d is %s', i, if (i mod 2) = 0 then 'Even' else 'Odd');

  score := -5;
  Println('Sign: %s', if score > 0 then 'Positive' else if score < 0 then 'Negative' else 'Zero');
end.