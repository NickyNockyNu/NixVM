program sets targets console;

{$HEAP 0}
{$STACK 128}

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
    Println('Weekend!');
    
  Work := [TDays.Tue..TDays.Wed, TDays.Fri, TDays.Sun];
  Work := Work - [TDays.Sun];
  
  if not (TDays.Sun in Work) then
    Println('we dont work sundays!');
        
  case Day of
    TDays.Mon: 
      Println('YAWN! Monday');
    
    TDays.Tue..TDays.Fri: 
      Println('Week day');
      
     TDays.Sat, TDays.Sun:
       Println('Weekend');
  else
    Println('Time and space is broken');
  end;
end;

begin
  Test;
end.
