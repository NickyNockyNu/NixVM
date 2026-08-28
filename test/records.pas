program records targets Test;

{$HEAP 0}
{$STACK 128}
{$BASE $4E0}

type
  TPoint = record
  private
    fx, fy: Integer;
    
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
  i: Integer;
  p: array[0..2] of TPoint;
begin
  for i := 0 to 2 do
  begin
    p[i].Init(10 + i, 20 + i);
    
    Writeln('%d: %d, %d', i, p[i].x, p[i].y);
    
    p[i].y := p[i].x + p[i].y;
    
    Writeln('  %d', p[i].y);
  end;
end.
