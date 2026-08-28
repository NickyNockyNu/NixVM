program testrap targets Test;

{$HEAP 0}
{$STACK 256}
{$BASE $4E0}

type
  TPoint = record
    x, y: Integer;
  end;
  PPoint = ^TPoint;

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
  i, j: Integer;

procedure ScalePoint(var pt: TPoint; factor: Integer);
begin
  with pt do
  begin
    x := x * factor;
    y := y * factor;
  end;
end;

begin
  for i := 0 to 2 do
  begin
    points[i].x := (i + 1) * 10;
    points[i].y := (i + 1) * 20;
  end;

  ScalePoint(points[1], 2); 
  Writeln('ScalePoint var test: %d, %d', points[1].x, points[1].y);

  ptPtr := @points[0];
  Writeln('Ptr[0]: %d, %d', ptPtr^.x, ptPtr^.y);
  
  Inc(ptPtr); 
  Writeln('Ptr[1] after Inc: %d, %d', ptPtr^.x, ptPtr^.y);

  with hero do
  begin
    id := 999;
    pos.x := 100;
    pos.y := 200;
    stats[0] := 50;
    stats[1] := 25;
    stats[2] := 10;
  end;

  Writeln('Hero ID=%d, Pos=(%d, %d), HP=%d, ATK=%d', 
          hero.id, hero.pos.x, hero.pos.y, hero.stats[0], hero.stats[2]);

  for i := 0 to 2 do
    for j := 0 to 2 do
      grid[i, j] := (i * 10) + j;

  Writeln('Grid[1, 2] = %d', grid[1, 2]);
  Writeln('Grid[2, 0] = %d', grid[2, 0]);
end.
