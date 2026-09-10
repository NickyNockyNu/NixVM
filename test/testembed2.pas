program testembed2 targets passe;

{$HEAP 2k}
{$STACK 1k}

const
  Screen: PFrameBuffer in 'img:passe.png';
  Ring:   Pointer      in 'wav:ring01.wav';

begin
  VideoRegisters^.DisplayBuffer := Screen;

  with PCMChannels[0] do
  begin
    Address    := Ring;
    Length     := 124556;
    SampleRate := 22050;
    
    Volume := 1.0;
    Pitch  := 1.0;
    
    Flags := %10;
  end;
  
  repeat
    if Keys[32].WasPressed then
      PlaySound(0, True);
      
    //else if Keys[32].WasReleased then
    //  StopSound(0);
  
    Yield;
  until False;


end.