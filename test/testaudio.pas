program testaudio targets passe;

{$HEAP 2k}
{$STACK 1k}

const
  Screen: PFrameBuffer in 'img:passe.png';
  
  Ring: Pointer in 'wav:ring01.wav';

begin
  Print('\a');
  
  VideoRegisters^.DisplayBuffer := Screen;
  VideoRegisters^.DrawBuffer    := Screen;
  
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
    
    Volume := 4.0;
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
      SynthChannels[0].Volume := (Mouse^.Y / FrameBufferHeight) + 0.000001;
    end;
    
    PCMChannels[0].Pitch := ((Mouse^.X * 4) / FrameBufferWidth) - 2;

    Yield;
  until False;
end.