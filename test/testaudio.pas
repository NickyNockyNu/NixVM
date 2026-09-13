program testaudio targets passe;

{$HEAP 2k}
{$STACK 1k}

const
  Ring: Pointer in 'wav:ring01.wav';

begin  
  AudioRegisters^.Flags := %11;
  
  with SynthChannels[0] do
  begin
    Waveform    := TWaveform.wfSquare;
    ModWaveform := TWaveform.wfSquare;
    
    Attack  := 0.05;
    Decay   := 0.1;
    Sustain := 0.9;
    Release := 0.5;

    ModRatio    := 1.0;
    ModDepth    := 4.0;
    ModFeedback := 0.5;
    
    ModAttack  := 0.01;
    ModDecay   := 0.1; 
    ModSustain := 0.2;
    ModRelease := 0.5;
  end;
  
  with PCMChannels[0] do
  begin
    Address    := Ring;
    Length     := 124556;
    SampleRate := 22050;
    
    Volume := 255;
    Pitch  := 1.0;
    
    Flags := %10;
  end;
  
  repeat
    DrawHLine(10, 150, 64, 28);
    DrawHLine(10, 150, AudioRegisters^.OutLevel div 4, 10);

    for var i := 0 to SynthChannelCount - 1 do
    begin
      DrawHLine(10, 154 + (i * 2), 64, 28);
      DrawHLine(10, 154 + (i * 2), SynthChannels[i].OutLevel div 4, 10);
    end;    
  
    for var i := 0 to PCMChannelCount - 1 do
    begin
      DrawHLine(10, 164 + (i * 2), 64, 28);
      DrawHLine(10, 164 + (i * 2), PCMChannels[i].OutLevel div 4, 10);
    end;
    
    DrawHLine(0, 0, FrameBufferWidth, 28);
    DrawHLine(0, 0, Round(FrameBufferWidth * (PCMChannels[0].Position / PCMChannels[0].Length)), 10);
  
    if Keys[13].WasPressed then
      PCMChannels[0].Position := PCMChannels[0].Length div 2;
  
    if Keys[32].WasPressed then
      PlaySound(0, True);
      
    if Keys[27].WasPressed then
      Beep;
  
    if Keys[1].WasPressed then
      NoteOn(0, False)
    else if Keys[1].WasReleased then
      NoteOff(0);
     
    if Keys[1].IsDown then
    begin
      SynthChannels[0].Frequency := 100 + (Mouse^.X * 2);
      SynthChannels[0].Volume := Round(255 * (Mouse^.Y / FrameBufferHeight));
    end;
    
    PCMChannels[0].Pitch := ((Mouse^.X * 4) / FrameBufferWidth) - 2;

    PCMChannels[0].Pan := Mouse^.Y - 90;

    yield;
  until False;
end.