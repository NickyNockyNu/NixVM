{
  NixVM.Passe.Audio.pas
    Audio memory

    Copyright (c) 2026 Nicholas Smith (writetonik@gmail.com)
    https://github.com/NickyNockyNu/NixVM

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
}

unit NixVM.Passe.Audio;

{$INCLUDE 'NixVM.Options.inc'}

interface

type
  {$REGION 'Audio registers'}
  PAudioRegisters = ^TAudioRegisters;
  TAudioRegisters = packed record
  type
    {$REGION 'Flags'}
    TFlags = type Byte;

    TFlagsHelper = record helper for TFlags
    const
      MaskEffectsEnabled = %00000001;
      MaskDelayEnabled   = %00000010;
    private
      function  GetFlag(AMask: Integer): Boolean;          inline;
      procedure SetFlag(AMask: Integer; AEnable: Boolean); inline;
    public
      property EffectsEnabled: Boolean index MaskEffectsEnabled read GetFlag write SetFlag;
      property DelayEnabled:   Boolean index MaskDelayEnabled   read GetFlag write SetFlag;
    end;
    {$ENDREGION}
  public
    Volume:   Single;
    OutLevel: Single;

    CutoffFreq: Single;
    DelayTime:  Single;
    Feedback:   Single;
    DelayMix:   Single;
    DelayGlide: Single;

    Flags:  TFlags;

    // TODO: Pad
    //Padding: array[0..2] of Byte;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'Audio channels'}
  PAudioChannels = ^TAudioChannels;
  TAudioChannels = packed record
  const
    Count = 4;

  type
    {$REGION 'Waveform'}
    TWaveform = (
      Sine,
      Square,
      Triangle,
      Sawtooth,
      Noise
    );
    {$ENDREGION}

    {$REGION 'Channel'}
    PChannel = ^TChannel;
    TChannel = packed record
    type
      {$REGION 'Flags'}
      TFlags = type Byte;

      TFlagsHelper = record helper for TFlags
      private
        function  GetFlag(AMask: Integer): Boolean;          inline;
        procedure SetFlag(AMask: Integer; AEnable: Boolean); inline;

        function  GetWaveform: TWaveform;            inline;
        procedure SetWaveform(AWaveform: TWaveform); inline;
      public
        property Waveform: TWaveform read GetWaveform write SetWaveform;
      end;
      {$ENDREGION}
    public
      Frequency:  Single;
      Volume:     Single;
      PulseWidth: Single;
      GlideSpeed: Single;

      Attack:  Single;
      Decay:   Single;
      Sustain: Single;
      Release: Single;

      OutLevel: Single;

      Flags: TFlags;

      // TODO: Pad
      //Padding: array[0..2] of Byte;
    end;
    {$ENDREGION}
  public
    Channels: packed array[0..Count - 1] of TChannel;

    procedure Reset;
  end;
  {$ENDREGION}

implementation

{$REGION 'Audio registers'}
{$REGION 'Flags'}
function TAudioRegisters.TFlagsHelper.GetFlag(AMask: Integer): Boolean;
begin
  Result := (Self and AMask) <> 0
end;

procedure TAudioRegisters.TFlagsHelper.SetFlag(AMask: Integer; AEnable: Boolean);
begin
  if AEnable then
    Self := Self or AMask
  else
    Self := Self and not AMask;
end;
{$ENDREGION}

procedure TAudioRegisters.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);

  Volume        := 1.0;
  CutoffFreq    := 1500.0;
  DelayTime     := 0.15;
  Feedback      := 0.4;
  DelayMix      := 0.3;
  DelayGlide    := 0.0001;
end;
{$ENDREGION}

{$REGION 'Audio channels'}

{$REGION 'Flags'}
function TAudioChannels.TChannel.TFlagsHelper.GetFlag(AMask: Integer): Boolean;
begin
  Result := (Self and AMask) <> 0
end;

procedure TAudioChannels.TChannel.TFlagsHelper.SetFlag(AMask: Integer; AEnable: Boolean);
begin
  if AEnable then
    Self := Self or AMask
  else
    Self := Self and not AMask;
end;

function TAudioChannels.TChannel.TFlagsHelper.GetWaveform: TWaveform;
begin
  Result := TWaveform(Self and %00000111);
end;

procedure TAudioChannels.TChannel.TFlagsHelper.SetWaveform(AWaveform: TWaveform);
begin
  Self := (Self and %11111000) or (Byte(AWaveform) and %111);
end;
{$ENDREGION}

procedure TAudioChannels.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);

  for var i := 0 to Count - 1 do
    with Channels[i] do
    begin
      Frequency  := 440.0;
      Volume     := 1 / (Count + 1);
      PulseWidth := 0.5;
      GlideSpeed := 0.005;

      Attack  := 0.01;
      Decay   := 0.0;
      Sustain := 1.0;
      Release := 0.05;

      Flags.Waveform := TWaveform.Sine;
    end;
end;
{$ENDREGION}

end.
