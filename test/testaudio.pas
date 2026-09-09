program testaudio targets passe;

{$HEAP 2k}
{$STACK 1k}

begin
  NoteOn(0);
  
  repeat
    AudioChannels[0].Frequency := 440 + Mouse^.X;
    AudioChannels[0].Volume    := Mouse^.Y / FrameBufferHeight;
    //Yield;
  until False;
end.