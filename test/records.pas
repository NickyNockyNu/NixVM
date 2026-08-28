program records targets Test;

{$HEAP 0}
{$STACK 128}
{$BASE $4E0}

type
  TUnused = record
    a: Integer;
    
    function GetA: Integer;
    begin
      Result := a;
    end;
    
    property AA: Integer read GetA;
  end;

  TPoint = record
  private
    fx, fy: Integer;
    
    u: TUnused;
    
    function GetY: Integer;
    begin
      Result := fy;
    end;
    
    procedure SetY(AValue: Integer);
  public 
    procedure Init(x, y: Integer);
    begin
      fx := x;
      fy := y;
    end;
    
    property x: Integer read fx   write fx;
    property y: Integer read GetY write SetY;
  end;
  
procedure TPoint.SetY(AValue: Integer);
begin
  fy := AValue;
end;

var
  c: TPoint;
  i: Integer;
  p: array[0..2] of TPoint;
begin
  for i := 0 to 2 do
  begin
    with p[i] do
    begin
      Init(10 + i, 20 + i);
    
      Writeln('%d: %d, %d', i, x, y);
    
      with u do
        a := i;
        
      y := x + y;
    
      Writeln('  %d', y);
    end;
   end;

  for i := 0 to 2 do
    with p[i] do
      Writeln('%d: %d, %d, %d', i, fx, fy, u.a);
      
  c := p[1];
  
  Writeln('%d, %d', c.x, c.y);
end.
