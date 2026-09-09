program testfont targets passe;

{$HEAP 2k}
{$STACK 1k}

var
	c: Integer;
begin
	for var i := 0 to 7 do
	begin
		c := i * 32;
		
		if c < $0A then
			Print('0');
		
		Print('%x: ', c);
		
		for var j := 0 to 31 do
		begin
			c := (i * 32) + j;
			
      Print('\e%c', c);
			
			if j = 15 then
				Print(' - ');
		end;
		
		PrintLn;
	end;
end.
