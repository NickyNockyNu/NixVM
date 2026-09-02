program TestForIn targets console;

{$HEAP 1k}
{$STACK 128}

type
  TDays = (Mon, Tue, Wed, Thu, Fri, Sat, Sun);
  TWeek = set of TDays;

  TPoint = record
    x, y: Integer;
  end;

const
  Weekend: TWeek = [TDays.Sat, TDays.Sun];

var
  points: array[0..2] of TPoint;
  pt: TPoint;
  day: TDays;
  ch: Char;
  i: Integer;

begin
  for i := 0 to 2 do
  begin
    points[i].x := (i + 1) * 10;
    points[i].y := (i + 1) * 20;
  end;

  for pt in points do
    Println('Point: %d, %d', pt.x, pt.y);

  for day in Weekend do
    Println('Weekend Day Index: %d', Ord(day));

  for ch in 'NixVM' do
    Println('Char: %c (Ord=%d)', ch, Ord(ch));
end.
