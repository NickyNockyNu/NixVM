program testsprite targets passe;

{$HEAP 2k}
{$STACK 1k}

type
  PSpriteData = ^TSpriteData;
  TSpriteData = array[0..31, 0..31] of Byte;

function MakeSprite: PSpriteData;
begin
  Result := GetMem(SizeOf(TSpriteData));
  
  if not Assigned(Result) then
  begin
    Println('Failed to alloc sprite');
    Halt(1);
  end;
  
  for var y := 0 to 31 do
    for var x := 0 to 31 do
      Result[y, x] := (y xor x);
end;

begin
  Randomize;

  SpriteAtlas[0].Address := MakeSprite;
  SpriteAtlas[0].Stride  := 32;
  SpriteAtlas[0].Width   := 32;
  SpriteAtlas[0].Height  := 32;
  
  Sprites[0].AtlasID := 0;
  Sprites[0].X := 160;
  Sprites[0].Y := 90;
  Sprites[0].Z := 100;
  Sprites[0].ScaleX := 3.0;
  Sprites[0].ScaleY := 3.0;
  Sprites[0].PivotX := 0.5;
  Sprites[0].PivotY := 0.5;
  Sprites[0].Flags  := %00000001;

  for var i := 1 to SpriteCount - 1 do
    with Sprites[i] do
    begin
      AtlasID := 0;
      Flags   := %00000001;
      
      X := Random(320);
      Y := Random(180);
      
      ScaleX := 0.5 + (2 * RandomF);
      ScaleY := 0.5 + (2 * RandomF);
      
      Angle := 360 * RandomF;
    end;
   
  repeat
    Println('Angle: %f', Sprites[0].Angle);
    
    Sprites[0].Angle := Sprites[0].Angle + 0.54321;
    
    if Sprites[0].Angle > 360 then
      Sprites[0].Angle := Sprites[0].Angle - 360;
      
    Yield;
  until False;
end.