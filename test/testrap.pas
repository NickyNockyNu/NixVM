program testrap targets console;

{$HEAP 0}
{$STACK 256}

type
  PPoint = ^TPoint;
  TPoint = record
    x, y: Integer;
  end;

  TEntity = record
    id: Integer;
    pos: TPoint;
    stats: array[0..2] of Integer;
  end;

var
  points: array[0..2] of TPoint;
  ptPtr: PPoint;
  hero: TEntity;
  grid: array[0..2, 0..2] of Integer;

procedure ScalePoint(var pt: TPoint; factor: Integer);
begin
  with pt do
  begin
    x := x * factor;
    y := y * factor;
  end;
end;

begin
  for var i := 0 to 2 do
  begin
    points[i].x := (i + 1) * 10;
    points[i].y := (i + 1) * 20;
  end;

  ScalePoint(points[1], 2); 
  Println('ScalePoint var test: %d, %d', points[1].x, points[1].y);

  ptPtr := @points[0];
  Println('Ptr[0]: %d, %d', ptPtr^.x, ptPtr^.y);
  
  Inc(ptPtr); 
  Println('Ptr[1] after Inc: %d, %d', ptPtr^.x, ptPtr^.y);

  with hero do
  begin
    id := 999;
    pos.x := 100;
    pos.y := 200;
    stats[0] := 50;
    stats[1] := 25;
    stats[2] := 10;
  end;

  Println('Hero ID=%d, Pos=(%d, %d), HP=%d, ATK=%d', 
          hero.id, hero.pos.x, hero.pos.y, hero.stats[0], hero.stats[2]);


  for var i := 0 to 2 do
    for var j := 0 to 2 do
      grid[i, j] := (i * 10) + j;

  Println('Grid[1, 2] = %d', grid[1, 2]);
  Println('Grid[2, 0] = %d', grid[2, 0]);

end.
