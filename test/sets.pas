program sets targets Test;

{$HEAP 0}
{$STACK 128}
{$BASE $4E0}

type
  TDays = (Mon, Tue, Wed, Thu, Fri, Sat, Sun);
  TWeek = set of TDays;

const
  Weekend = [TDays.Sat, TDays.Sun];

procedure Test;
var
  Day:  TDays;
  Work: TWeek;
begin
  Day := TDays.Mon;
  
  if Day in Weekend then
    Writeln('Weekend!');
    
  Work := [TDays.Tue..TDays.Wed, TDays.Fri, TDays.Sun];
  Work := Work - [TDays.Sun];
  
  if not (TDays.Sun in Work) then
    Writeln('we dont work sundays!');
        
  case Day of
    TDays.Mon: 
      Writeln('YAWN! Monday');
    
    TDays.Tue..TDays.Fri: 
      Writeln('Week day');
      
     TDays.Sat, TDays.Sun:
       Writeln('Weekend');
  else
    Writeln('Time and space is broken');
  end;
end;

begin
  Test;
end.
