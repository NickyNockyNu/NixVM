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
    Volume:     Single;
    CutoffFreq: Single;
    DelayTime:  Single;
    Feedback:   Single;
    DelayMix:   Single;
    DelayGlide: Single;

    Flags:  TFlags;

    OutLevel:  Byte;
    OutLevelL: Byte;
    OutLevelR: Byte;

    Padding: packed array[0..3] of Byte;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'Synth channels'}
  PSynthChannels = ^TSynthChannels;
  TSynthChannels = packed record
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

        function  GetModWaveform: TWaveform;            inline;
        procedure SetModWaveform(AWaveform: TWaveform); inline;
      public
        property Waveform:    TWaveform read GetWaveform    write SetWaveform;
        property ModWaveform: TWaveform read GetModWaveform write SetModWaveform;
      end;
      {$ENDREGION}
    public
      Volume: Byte;
      Pan:    ShortInt;

      Frequency:   Single;
      PulseWidth:  Single;
      GlideSpeed:  Single;

      Attack:  Single;
      Decay:   Single;
      Sustain: Single;
      Release: Single;

      ModRatio:    Single;
      ModDepth:    Single;
      ModFeedback: Single;

      ModAttack:  Single;
      ModDecay:   Single;
      ModSustain: Single;
      ModRelease: Single;

      Flags: TFlags;

      OutLevel: Byte;

      Padding: packed array[0..3] of Byte;
    end;
    {$ENDREGION}
  public
    Channels: packed array[0..Count - 1] of TChannel;

    procedure Reset;
  end;
  {$ENDREGION}

  {$REGION 'PCM channels'}
  PPCMChannels = ^TPCMChannels;
  TPCMChannels = packed record
  const
    Count = 4;
  type
    PChannel = ^TChannel;
    TChannel = packed record
    type
      {$REGION 'Flags'}
      TFlags = type Byte;

      TFlagsHelper = record helper for TFlags
      const
        MaskLoop      = %00000001;
        MaskDeclicker = %00000010;
      private
        function  GetFlag(AMask: Integer): Boolean;          inline;
        procedure SetFlag(AMask: Integer; AEnable: Boolean); inline;
      public
        property Loop:      Boolean index MaskLoop      read GetFlag write SetFlag;
        property Declicker: Boolean index MaskDeclicker read GetFlag write SetFlag;
      end;
      {$ENDREGION}
    public
      Address:    Cardinal;
      Length:     Cardinal;
      SampleRate: Cardinal;

      Volume: Byte;
      Pan:    ShortInt;

      Position: Cardinal;
      Pitch:    Single;

      Flags: TFlags;

      OutLevel: Byte;

      Padding: packed array[0..7] of Byte;
    end;
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

{$REGION 'Synth channels'}

{$REGION 'Flags'}
function TSynthChannels.TChannel.TFlagsHelper.GetFlag(AMask: Integer): Boolean;
begin
  Result := (Self and AMask) <> 0
end;

procedure TSynthChannels.TChannel.TFlagsHelper.SetFlag(AMask: Integer; AEnable: Boolean);
begin
  if AEnable then
    Self := Self or AMask
  else
    Self := Self and not AMask;
end;

function TSynthChannels.TChannel.TFlagsHelper.GetWaveform: TWaveform;
begin
  Result := TWaveform(Self and %00000111);
end;

procedure TSynthChannels.TChannel.TFlagsHelper.SetWaveform(AWaveform: TWaveform);
begin
  Self := (Self and %11111000) or (Byte(AWaveform) and %111);
end;

function TSynthChannels.TChannel.TFlagsHelper.GetModWaveform: TWaveform;
begin
  Result := TWaveform((Self and %00111000) shr 3);
end;

procedure TSynthChannels.TChannel.TFlagsHelper.SetModWaveform(AWaveform: TWaveform);
begin
  Self := (Self and %11000111) or ((Byte(AWaveform) and %111) shl 3);
end;
{$ENDREGION}

procedure TSynthChannels.Reset;
begin
  FillChar(Self, SizeOf(Self), 0);

  for var i := 0 to Count - 1 do
    with Channels[i] do
    begin
      Volume     := 32;
      Pan        := 0;
      Frequency  := 440.0;
      PulseWidth := 0.5;
      ModRatio   := 0;
      ModDepth   := 0;
      GlideSpeed := 0.005;

      Attack  := 0.01;
      Decay   := 0.0;
      Sustain := 1.0;
      Release := 0.05;

      Flags.Waveform := TWaveform.Sine;
    end;
end;
{$ENDREGION}

{$REGION 'PCM channels'}

{$REGION 'Flags'}
function TPCMChannels.TChannel.TFlagsHelper.GetFlag(AMask: Integer): Boolean;
begin
  Result := (Self and AMask) <> 0
end;

procedure TPCMChannels.TChannel.TFlagsHelper.SetFlag(AMask: Integer; AEnable: Boolean);
begin
  if AEnable then
    Self := Self or AMask
  else
    Self := Self and not AMask;
end;
{$ENDREGION}

procedure TPCMChannels.Reset;
begin
  FillChar(Self, SizeOF(Self), 0);

  for var i := 0 to Count - 1 do
    with Channels[i] do
    begin
      Volume := 64;
    end;
end;
{$ENDREGION}

end.
