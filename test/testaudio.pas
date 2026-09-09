program testaudio targets passe;

{$HEAP 2k}
{$STACK 1k}

begin
  with AudioChannels[0] do
  begin
    Waveform := TWaveform.wfSine;
    
    Attack  := 0.01;
    Decay   := 0.0;
    Sustain := 1.0;
    Release := 0.2;
  end;
  
  repeat
    DrawHLine(10, 10, 100, 7);
    DrawHLine(10, 10, Round(100 * AudioRegisters^.OutLevel), 15);

    for var i := 0 to AudioChannelCount - 1 do
    begin
      DrawHLine(10, 14 + (i * 2), 100, 7);
      DrawHLine(10, 14 + (i * 2), Round(100 * AudioChannels[i].OutLevel), 15);
    end;    
  
    if Keys[32].WasPressed then
      Beep;
  
    if Keys[1].WasPressed then
      NoteOn(0, False)
    else if Keys[1].WasReleased then
      NoteOff(0);
     
    if Keys[1].IsDown then
      AudioChannels[0].Frequency := 440 + Mouse^.X;
    
    AudioChannels[0].Volume := (Mouse^.Y / FrameBufferHeight) + 0.000001;
    
    Yield;
  until False;
end.