program TestExit targets console;

{$HEAP 0}
{$STACK 128}

function Max(a, b: Integer): Integer;
begin
  if a > b then
    Exit(a);

  Exit(b);
end;

function DescribeScore(score: Integer): String;
begin
  if score >= 90 then Exit('Excellent');
  if score >= 50 then Exit('Passed');
  Exit('Failed');
end;

begin
  Println('Max(10, 20) = %d', Max(10, 20));
  Println('Max(50, 30) = %d', Max(50, 30));

  Println('Score 95: %s', DescribeScore(95));
  Println('Score 65: %s', DescribeScore(65));
  Println('Score 40: %s', DescribeScore(40));
end.
