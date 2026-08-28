program records targets Test;

{$HEAP 0}
{$STACK 128}
{$BASE $4E0}

type
  TPoint = record
  //private
    fx, fy: Integer;
    
    function GetY: Integer;
    begin
      Result := fy;
    end;
    
    procedure SetY(AValue: Integer);
  //public 
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
    with p[i] do
    begin
      Init(10 + i, 20 + i);
    
      Writeln('%d: %d, %d', i, x, y);
    
      y := x + y;
    
      Writeln('  %d', y);
    end;
   end;

  for i := 0 to 2 do
    with p[i] do
      Writeln('%d: %d, %d', i, fx, fy);
end.
