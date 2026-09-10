program testaudio targets passe;

{$HEAP 2k}
{$STACK 1k}

begin
  Print('\a');
  
  AudioRegisters^.Flags := %11;
  
  with AudioChannels[0] do
  begin
    Waveform    := TWaveform.wfSquare;
    ModWaveform := TWaveform.wfSquare;
    
    ModRatio    := 1.0;
    ModDepth    := 4.0;
    ModFeedback := 0.0;
    
    ModAttack  := 0.01;
    ModDecay   := 0.1; 
    ModSustain := 0.2;
    ModRelease := 0.5;
    
    Attack  := 0.05;
    Decay   := 0.1;
    Sustain := 0.9;
    Release := 0.5;
  end;
  
  repeat
    DrawHLine(10, 160, 128, 28);
    DrawHLine(10, 160, AudioRegisters^.OutLevel div 2, 10);

    for var i := 0 to AudioChannelCount - 1 do
    begin
      DrawHLine(10, 164 + (i * 2), 128, 28);
      DrawHLine(10, 164 + (i * 2), AudioChannels[i].OutLevel div 2, 10);
    end;    
  
    if Keys[32].WasPressed then
      Beep;
  
    if Keys[1].WasPressed then
      NoteOn(0, False)
    else if Keys[1].WasReleased then
      NoteOff(0);
     
    if Keys[1].IsDown then
    begin
      AudioChannels[0].Frequency := 100 + (Mouse^.X * 2);
      AudioChannels[0].Volume := (Mouse^.Y / FrameBufferHeight) + 0.000001;
    end;
    
    Yield;
  until False;
end.