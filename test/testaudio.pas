program testaudio targets passe;

{$HEAP 2k}
{$STACK 1k}

begin
  Print('\a');
  
  with AudioChannels[0] do
  begin
    Waveform := TWaveform.wfSine;
    
    GlideSpeed := 1.0;
    
    Attack  := 0.05;
    Decay   := 0.1;
    Sustain := 0.6;
    Release := 0.5;
  end;
  
  repeat
    DrawHLine(10, 160, 100, 28);
    DrawHLine(10, 160, Round(100 * AudioRegisters^.OutLevel), 10);

    for var i := 0 to AudioChannelCount - 1 do
    begin
      DrawHLine(10, 164 + (i * 2), 100, 28);
      DrawHLine(10, 164 + (i * 2), Round(100 * AudioChannels[i].OutLevel), 10);
    end;    
  
    if Keys[32].WasPressed then
      Beep;
  
    if Keys[1].WasPressed then
      NoteOn(0, False)
    else if Keys[1].WasReleased then
      NoteOff(0);
     
    if Keys[1].IsDown then
    begin
      AudioChannels[0].Frequency := 440 + Mouse^.X;
      AudioChannels[0].Volume := (Mouse^.Y / FrameBufferHeight) + 0.000001;
    end;
    
    Yield;
  until False;
end.