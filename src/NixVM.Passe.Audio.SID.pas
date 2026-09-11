{
  NixVM.Passe.Audio.SID.pas
    Sound interface device

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

unit NixVM.Passe.Audio.SID;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  Winapi.Windows,
  Winapi.MMSystem,

  NixVM.Core.Memory,

  NixVM.Harness.Passe,

  NixVM.Passe.Memory,
  NixVM.Passe.Audio;

{$REGION 'WASAPI'}
const
  CLSID_MMDeviceEnumerator: TGUID = '{BCDE0395-E52F-467C-8E3D-C4579291692E}';

  IID_IMMDeviceEnumerator:  TGUID = '{A95664D2-9614-4F35-A746-DE8DB63617E6}';
  IID_IAudioClient:         TGUID = '{1CB9AD4C-DBFA-4c32-B178-C2F568A703B2}';
  IID_IAudioRenderClient:   TGUID = '{F294ACFC-3146-4483-A7BF-ADDCA7C260E2}';

  AUDCLNT_SHAREMODE_SHARED           = 0;
  AUDCLNT_STREAMFLAGS_EVENTCALLBACK  = $00040000;
  AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM = $80000000;

type
  {$REGION 'IMMDevice'}
  IMMDevice = interface(IUnknown)['{D666063F-1587-4E43-81F1-B948E807363F}']
    function Activate(const iid: TGUID; dwClsCtx: LongWord; pActivationParams: PNativeUInt; ppInterface: Pointer): HRESULT; stdcall;
    function OpenPropertyStore(stgmAccess: LongWord; out ppProperties: IUnknown): HRESULT; stdcall;
    function GetId(out ppstrId: PWideChar): HRESULT; stdcall;
    function GetState(out pdwState: LongWord): HRESULT; stdcall;
  end;
  {$ENDREGION}

  {$REGION 'IMMDeviceEnumerator'}
  IMMDeviceEnumerator = interface(IUnknown)['{A95664D2-9614-4F35-A746-DE8DB63617E6}']
    function EnumAudioEndpoints(dataFlow: Integer; dwStateMask: LongWord; out ppDevices: IUnknown): HRESULT; stdcall;
    function GetDefaultAudioEndpoint(dataFlow: Integer; role: Integer; out ppEndpoint: IMMDevice): HRESULT; stdcall;
    function GetDevice(pwstrId: PWideChar; out ppDevice: IMMDevice): HRESULT; stdcall;
    function RegisterEndpointNotificationCallback(pClient: IUnknown): HRESULT; stdcall;
    function UnregisterEndpointNotificationCallback(pClient: IUnknown): HRESULT; stdcall;
  end;
  {$ENDREGION}

  {$REGION 'IAudioClient'}
  IAudioClient = interface(IUnknown)['{1CB9AD4C-DBFA-4c32-B178-C2F568A703B2}']
    function Initialize(ShareMode: Integer; StreamFlags: LongWord; hnsBufferDuration: Int64; hnsPeriodicity: Int64; pFormat: PWaveFormatEx; AudioSessionGuid: PGUID): HRESULT; stdcall;
    function GetBufferSize(out pNumBufferFrames: Cardinal): HRESULT; stdcall;
    function GetStreamLatency(out phnsLatency: Int64): HRESULT; stdcall;
    function GetCurrentPadding(out pNumPaddingFrames: Cardinal): HRESULT; stdcall;
    function IsFormatSupported(ShareMode: Integer; pFormat: PWaveFormatEx; out ppClosestMatch: PWaveFormatEx): HRESULT; stdcall;
    function GetMixFormat(out ppDeviceFormat: PWaveFormatEx): HRESULT; stdcall;
    function GetDevicePeriod(out phnsDefaultDevicePeriod: Int64; out phnsMinimumDevicePeriod: Int64): HRESULT; stdcall;
    function Start: HRESULT; stdcall;
    function Stop: HRESULT; stdcall;
    function Reset: HRESULT; stdcall;
    function SetEventHandle(eventHandle: THandle): HRESULT; stdcall;
    function GetService(const riid: TGUID; ppv: Pointer): HRESULT; stdcall;
  end;
  {$ENDREGION}

  {$REGION 'IAudioRenderClient'}
  IAudioRenderClient = interface(IUnknown)['{F294ACFC-3146-4483-A7BF-ADDCA7C260E2}']
    function GetBuffer(NumFramesRequested: Cardinal; out ppData: PByte): HRESULT; stdcall;
    function ReleaseBuffer(NumFramesWritten: Cardinal; dwFlags: LongWord): HRESULT; stdcall;
  end;
  {$ENDREGION}
{$ENDREGION}

type
  {$REGION 'SID'}
  TSID = class
  const
    SampleRate = 48000;
  type
    {$REGION 'SysCalls'}
    TSysCalls = class abstract
    const
      SID = $D0;

      Reset   = SID + 0;
      NoteOn  = SID + 1;
      Noteoff = SID + 2;
      Play    = SID + 3;
      Stop    = SID + 4;
      Beep    = SID + 5;
    end;
    {$ENDREGION}

    {$REGION 'TEnvelopeState'}
    TEnvelopeState = (
      Idle,
      Attack,
      Decay,
      Sustain,
      Release
    );
    {$ENDREGION}

    {$REGION 'Synth channel'}
    TSynthChannel = record
      Registers:   PAudioRegisters;
      Channel:     TSynthChannels.PChannel;
      Phase:       Double;
      Frequency:   Double;
      Volume:      Double;
      NoiseVal:    Double;
      EnvState:    TEnvelopeState;
      EnvValue:    Double;
      ModPhase:    Double;
      ModRatio:    Double;
      ModDepth:    Double;
      ModPrev:     Double;
      ModEnvState: TEnvelopeState;
      ModEnvValue: Double;

      Playing:   Boolean;

      procedure Process(ABuffer: PSingle; ASampleCount, ASampleRate: Integer);

      procedure Reset;

      procedure Play(AReset: Boolean = True);
      procedure Stop;

      procedure NoteOff;

      procedure ResetPhase;
    end;
    {$ENDREGION}

    {$REGION 'PCM channel'}
    TPCMChannel = record
      Registers:   PAudioRegisters;
      Channel:     TPCMChannels.PChannel;
      Position:    Double;
      SyncedPos:   Cardinal;
      Playing:     Boolean;
      FadeVol:     Single;
      FadeState:   Integer;
      Samples:     PSmallInt;

      procedure Process(ABuffer: PSingle; ASampleCount, ASampleRate: Integer);

      procedure Reset;

      procedure Play(AReset: Boolean = True);
      procedure Stop;
    end;
    {$ENDREGION}
  private
    FOwner: TPasseHarness;

    FAudioClient:  IAudioClient;
    FRenderClient: IAudioRenderClient;

    FBufferFrames: Cardinal;
    FTargetFrames: Cardinal;

    FEvent:        THandle;
    FThreadHandle: THandle;
    FThreadID:     LongWord;
    FTerminated:   Boolean;

    FRegisters: PAudioRegisters;
    FSChannels: PSynthChannels;
    FWChannels: PPCMChannels;

    FSynthChannels: array[0..TSynthChannels.Count - 1] of TSynthChannel;
    FPCMChannels:   array[0..TSynthChannels.Count - 1] of TPCMChannel;

    FBuffer: array of Single;

    FPrevSampleL:  Single;
    FPrevSampleR:   Single;
    FDelayBufferL:  array of Single;
    FDelayBufferR:  array of Single;
    FDelayIndex:    Integer;
    FCurrentDelay:  Single;
    FCurrentMix:    Single;

    FBeepPhase:     Single;
    FBeepTime:      Single;
    FBeepLength:    Single;
    FBeepFrequency: Single;
    FBeepVolume:    Single;
    FBeepPlaying:   Boolean;

    class function AudioThreadProc(AParameter: Pointer): Integer; stdcall; static;
  protected
    procedure FillBuffer(AOutBuffer: PSmallInt; ASampleCount: Integer; ASampleRate: Integer);

    procedure ProcessSynth  (ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
    procedure ProcessPCM    (ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
    procedure ProcessEffects(ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
    procedure ProcessBeep   (ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
  public
    constructor Create(AOwner: TPasseHarness);
    destructor  Destroy; override;

    procedure Reset;

    function  Start(AWantErrors: Boolean = True): Boolean;
    procedure Stop;
    procedure Update;

    procedure NoteOn (AChannel: Integer; AReset: Boolean = True);
    procedure NoteOff(AChannel: Integer);

    procedure PCMPlay(AChannel: Integer; AReset: Boolean = True);
    procedure PCMStop(AChannel: Integer);

    procedure BeepReset;
    procedure Beep(AFrequency: Single = 400; ATime: Single = 0.6);

    property Owner: TPasseHarness read FOwner;

    property AudioClient:  IAudioClient       read FAudioClient;
    property RenderClient: IAudioRenderClient read FRenderClient;

    property Registers:     PAudioRegisters read FRegisters;
    property SynthChannels: PSynthChannels  read FSChannels;
    property PCMChannels:   PPCMChannels    read FWChannels;
  end;
  {$ENDREGION}

const
  PI2 = PI * 2;

implementation

uses
  Winapi.ActiveX;

{$REGION 'Synth channel'}
procedure TSID.TSynthChannel.Process(ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
var
  PhaseStep:     Double;
  ModPhaseStep:  Double;
  ModValue:      Double;
  ModPhaseValue: Double;
  ModPhaseEff:   Double;
  TimeStep:      Double;
  OutPtr:        PSingle;
  SampleVal:     Single;
  Level:         Single;
  NormPhase:     Double;
  NormTime:      Double;
  Val:           Double;
  Attack:        Double;
  Release:       Double;
  PanF:          Single;
  LeftGain:      Single;
  RightGain:     Single;

  function PolyBLEP(t, dt: Double): Double; inline;
  begin
    if t < dt then
    begin
      t      := t / dt;
      Result := t + t - t * t - 1;
    end
    else if t > (1 - dt) then
    begin
      t      := (t - 1) / dt;
      Result := t * t + t + t + 1;
    end
    else
      Result := 0;
  end;
begin
  Level := 0;

  if (not Playing) or (Channel.Volume = 0) or (Channel.Frequency <= 0) then
  begin
    Stop;
    Exit;
  end;

  PanF := Channel.Pan / 100;

  if PanF < -1 then
    PanF := -1
  else if PanF > 1 then
    PanF := 1;

  LeftGain  := 1 - PanF;

  if LeftGain > 1 then
    LeftGain := 1;

  RightGain := 1 + PanF;

  if RightGain > 1 then
    RightGain := 1;

  TimeStep := 1 / ASampleRate;
  OutPtr   := ABuffer;

  for var i := 0 to ASampleCount - 1 do
  begin
    Frequency := Frequency + (Channel.Frequency      - Frequency) * Channel.GlideSpeed;
    Volume    := Volume    + ((Channel.Volume / $FF) - Volume)    * Channel.GlideSpeed;

    ModRatio := ModRatio + (Channel.ModRatio - ModRatio) * Channel.GlideSpeed;
    ModDepth := ModDepth + (Channel.ModDepth - ModDepth) * Channel.GlideSpeed;

    PhaseStep    := (Frequency * PI2) / ASampleRate;
    ModPhaseStep := (Frequency * ModRatio * PI2) / ASampleRate;

    {$REGION 'Envelope (carrier)'}
    Attack  := Channel.Attack;
    Release := Channel.Release;

    if Attack  < 0.001 then Attack  := 0.001;
    if Release < 0.001 then Release := 0.001;

    case EnvState of
      TEnvelopeState.Attack:
      begin
        EnvValue := EnvValue + (TimeStep / Attack);

        if EnvValue >= 1 then
        begin
          EnvValue := 1;
          EnvState := TEnvelopeState.Decay;
        end;
      end;

      TEnvelopeState.Decay:
        if Channel.Decay > 0 then
        begin
          EnvValue := EnvValue - (TimeStep / Channel.Decay) * (1 - Channel.Sustain);

          if EnvValue <= Channel.Sustain then
          begin
            EnvValue := Channel.Sustain;
            EnvState := TEnvelopeState.Sustain;
          end;
        end
        else
        begin
          EnvValue := Channel.Sustain;
          EnvState := TEnvelopeState.Sustain;
        end;

      TEnvelopeState.Sustain:
        EnvValue := Channel.Sustain;

      TEnvelopeState.Release:
      begin
        EnvValue := EnvValue - (TimeStep / Release);

        if EnvValue <= 0 then
        begin
          EnvValue := 0;
          EnvState := TEnvelopeState.Idle;

          Stop;
          Exit;
        end;
      end
    end;
    {$ENDREGION}

    {$REGION 'Envelope (modulator)'}
    Attack  := Channel.ModAttack;
    Release := Channel.ModRelease;

    if Attack  < 0.001 then Attack  := 0.001;
    if Release < 0.001 then Release := 0.001;

    case ModEnvState of
      TEnvelopeState.Attack:
      begin
        ModEnvValue := ModEnvValue + (TimeStep / Attack);

        if ModEnvValue >= 1 then
        begin
          ModEnvValue := 1;
          ModEnvState := TEnvelopeState.Decay;
        end;
      end;

      TEnvelopeState.Decay:
        if Channel.ModDecay > 0 then
        begin
          ModEnvValue := ModEnvValue - (TimeStep / Channel.ModDecay) * (1 - Channel.ModSustain);

          if ModEnvValue <= Channel.ModSustain then
          begin
            ModEnvValue := Channel.ModSustain;
            ModEnvState := TEnvelopeState.Sustain;
          end;
        end
        else
        begin
          ModEnvValue := Channel.ModSustain;
          ModEnvState := TEnvelopeState.Sustain;
        end;

      TEnvelopeState.Sustain:
        ModEnvValue := Channel.ModSustain;

      TEnvelopeState.Release:
      begin
        ModEnvValue := ModEnvValue - (TimeStep / Release);

        if ModEnvValue <= 0 then
        begin
          ModEnvValue := 0;
          ModEnvState := TEnvelopeState.Idle;
        end;
      end;
    end;
    {$ENDREGION}

    {$REGION 'Modulator'}
    if ModDepth > 0.001 then
    begin
      ModPhaseEff := ModPhase + (ModPrev * Channel.ModFeedback);

      case Channel.Flags.ModWaveform of
        TSynthChannels.TWaveform.Sine:
          ModValue := Sin(ModPhaseEff);

        TSynthChannels.TWaveform.Triangle:
        begin
          Val := ModPhaseEff / PI2;
          Val := Val - Trunc(Val);

          if Val < 0 then
            Val := Val + 1;

          ModValue := 1 - (4 * Abs(Val - 0.5));
        end;

        TSynthChannels.TWaveform.Square:
          ModValue := 0.78 * (Sin(ModPhaseEff) + (0.333 * Sin(ModPhaseEff * 3)) + (0.2 * Sin(ModPhaseEff * 5)));

        TSynthChannels.TWaveform.Sawtooth:
          ModValue := 0.6 * (Sin(ModPhaseEff) - (0.5 * Sin(ModPhaseEff * 2)) + (0.333 * Sin(ModPhaseEff * 3)) - (0.25 * Sin(ModPhaseEff * 4)));

        TSynthChannels.TWaveform.Noise:
          ModValue := NoiseVal;
      else
        ModValue := 0;
      end;

      ModPrev := ModValue;

      ModPhaseValue := Phase + (ModValue * ModDepth * ModEnvValue);

      case Channel.Flags.Waveform of
        TSynthChannels.TWaveform.Sine:
          SampleVal := Sin(ModPhaseValue);

        TSynthChannels.TWaveform.Triangle:
        begin
          Val := ModPhaseValue / PI2;

          Val := Val - Trunc(Val);

          if Val < 0 then
            Val := Val + 1;

          SampleVal := 1 - (4 * Abs(Val - 0.5));
        end;
      else
        SampleVal := Sin(ModPhaseValue);
      end;
    end
    else
    {$ENDREGION}
    begin
      NormPhase := Phase / PI2;
      NormTime  := Frequency / ASampleRate;

      case Channel.Flags.Waveform of
        TSynthChannels.TWaveform.Sine:
          SampleVal := Sin(Phase);

        TSynthChannels.TWaveform.Square:
        begin
          if NormPhase < Channel.PulseWidth then
            SampleVal := 1
          else
            SampleVal := -1;

          SampleVal := SampleVal + PolyBLEP(NormPhase, NormTime);

          Val := NormPhase - Channel.PulseWidth;

          if Val < 0 then
            Val := Val + 1;

          SampleVal := SampleVal - PolyBLEP(Val, NormTime);
        end;

        TSynthChannels.TWaveform.Sawtooth:
        begin
          SampleVal := (2 * NormPhase) - 1;
          SampleVal := SampleVal - PolyBLEP(NormPhase, NormTime);
        end;

        TSynthChannels.TWaveform.Triangle:
          SampleVal := 1 - (4 * Abs(NormPhase - 0.5));

        TSynthChannels.TWaveform.Noise:
          if NormPhase < Channel.PulseWidth then
            SampleVal := NoiseVal
          else
            SampleVal := -NoiseVal;
      else
        SampleVal := 0;
      end;
    end;

    SampleVal := SampleVal * Volume * EnvValue;

    OutPtr^ := OutPtr^ + (SampleVal * LeftGain);  Inc(OutPtr);
    OutPtr^ := OutPtr^ + (SampleVal * RightGain); Inc(OutPtr);

    SampleVal := Abs(SampleVal);

    if SampleVal > Level then
      Level := SampleVal;

    Phase    := Phase    + PhaseStep;
    ModPhase := ModPhase + ModPhaseStep;

    if (Phase >= PI2) or (Phase < 0) then
    begin
      NoiseVal := (Random - 0.5) * 2;

      while Phase >= PI2 do
        Phase := Phase - PI2;

      while Phase < 0 do
        Phase := Phase + PI2;
    end;

    if (ModPhase >= PI2) or (ModPhase < 0) then
    begin
      while ModPhase >= PI2 do
        ModPhase := ModPhase - PI2;

      while ModPhase < 0 do
        ModPhase := ModPhase + PI2;
    end;
  end;

  Channel.OutLevel := Round($FF * Level);
end;

procedure TSID.TSynthChannel.Reset;
begin
  Stop;

  ResetPhase;

  ModPrev  := 0;
  EnvValue := 0;
end;

procedure TSID.TSynthChannel.Play(AReset: Boolean = True);
begin
  if AReset then
  begin
    if EnvValue < 0.005 then
    begin
      Frequency := Channel.Frequency;
      Volume    := Channel.Volume;

      ModRatio  := Channel.ModRatio;
      ModDepth  := Channel.ModDepth;
    end;

    Reset;
  end;

  EnvState    := TEnvelopeState.Attack;
  ModEnvState := TEnvelopeState.Attack;

  Playing := True;
end;

procedure TSID.TSynthChannel.Stop;
begin
  Playing := False;

  Channel.OutLevel := 0;

  EnvState := TEnvelopeState.Idle;
  EnvValue := 0;

  ModEnvState := TEnvelopeState.Idle;
  ModEnvValue := 0;
end;

procedure TSID.TSynthChannel.NoteOff;
begin
  if EnvState <> TEnvelopeState.Idle then
    EnvState := TEnvelopeState.Release;

  if ModEnvState <> TEnvelopeState.Idle then
    ModEnvState := TEnvelopeState.Release;
end;

procedure TSID.TSynthChannel.ResetPhase;
begin
  case Channel.Flags.Waveform of
    TSynthChannels.TWaveform.Sine:     Phase := 0;
    TSynthChannels.TWaveform.Square:   Phase := 0;
    TSynthChannels.TWaveform.Sawtooth: Phase := PI;
    TSynthChannels.TWaveform.Triangle: Phase := PI / 2;
    TSynthChannels.TWaveform.Noise:
    begin
      Phase    := 0;
      NoiseVal := (Random - 0.5) * 2;
    end;
  end;

  case Channel.Flags.ModWaveform of
    TSynthChannels.TWaveform.Sine:     ModPhase := 0;
    TSynthChannels.TWaveform.Square:   ModPhase := 0;
    TSynthChannels.TWaveform.Sawtooth: ModPhase := PI;
    TSynthChannels.TWaveform.Triangle: ModPhase := PI / 2;
    TSynthChannels.TWaveform.Noise:    ModPhase := 0;
  end;
end;
{$ENDREGION}

{$REGION 'PCM channel}
procedure TSID.TPCMChannel.Process(ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
var
  Step:      Double;
  Index:     Integer;
  OutPtr:    PSingle;
  FadeStep:  Single;
  SampleVal: Single;
  Level:     Single;
  PanF:      Single;
  LeftGain:  Single;
  RightGain: Single;
begin
  Level := 0;

  if Channel.Position <> SyncedPos then
  begin
    Position := Channel.Position;

    if Position >= Channel.Length then
      Position := Channel.Length - 1;
  end;

  if not Playing or (Channel.Pitch = 0) then
    Exit;

  PanF := Channel.Pan / 100;

  if PanF < -1 then
    PanF := -1
  else if PanF > 1 then
    PanF := 1;

  LeftGain  := 1 - PanF;

  if LeftGain > 1 then
    LeftGain := 1;

  RightGain := 1 + PanF;

  if RightGain > 1 then
    RightGain := 1;

  Step     := (Channel.SampleRate / ASampleRate) * Channel.Pitch;
  OutPtr   := ABuffer;
  FadeStep := 1.0 / (ASampleRate * 0.005);

  for var i := 0 to ASampleCount - 1 do
  begin
    if Channel.Flags.Declicker then
    begin
      if FadeState = 1 then
      begin
        FadeVol := FadeVol - FadeStep;

        if FadeVol <= 0.0 then
        begin
          FadeVol := 0.0;
          Reset;
          FadeState := 2;
        end;
      end
      else if FadeState = 2 then
      begin
        FadeVol := FadeVol + FadeStep;

        if FadeVol >= 1.0 then
        begin
          FadeVol   := 1.0;
          FadeState := 0;
        end;
      end;
    end
    else
      FadeVol := 1;

    Index := Trunc(Position);

    if (Index >= Integer(Channel.Length)) or (Index < 0) then
    begin
      if Channel.Flags.Loop then
      begin
        if Step > 0 then
          Position := 0
        else
          Position := Channel.Length - 1;

        Index := Trunc(Position);
      end
      else
      begin
        Stop;
        Exit;
      end;
    end;

    SampleVal := (Samples[Index] / 32768) * (Channel.Volume / $FF) * FadeVol;

    if SampleVal > Level then
      Level := SampleVal;

    OutPtr^ := OutPtr^ + (SampleVal * LeftGain);  Inc(OutPtr);
    OutPtr^ := OutPtr^ + (SampleVal * RightGain); Inc(OutPtr);

    Position := Position + Step;
  end;

  Channel.Position := Trunc(Position);
  SyncedPos        := Channel.Position;

  Channel^.OutLevel := Round($FF * Level);
end;

procedure TSID.TPCMChannel.Reset;
begin
  if Channel.Pitch < 0 then
    Position := Channel.Length - 1
  else
    Position := 0;
end;

procedure TSID.TPCMChannel.Play(AReset: Boolean = True);
begin
  if Channel.Flags.Declicker then
  begin
    if AReset then
    begin
      if Playing and (FadeVol > 0.01) then
        FadeState := 1
      else
      begin
        Reset;

        FadeVol   := 0.0;
        FadeState := 2;
      end;
    end;
  end
  else
  begin
    if AReset then
      Reset;
  end;

  Playing := True;
end;

procedure TSID.TPCMChannel.Stop;
begin
  Channel^.OutLevel := 0;
  Playing := False;
end;
{$ENDREGION}

{$REGION 'SID'}
class function TSID.AudioThreadProc(AParameter: Pointer): Integer;
var
  Self: TSID;
begin
  Self := TSID(AParameter);

  if not Assigned(Self) then
    Exit(0);

  CoInitializeEx(nil, COINIT_MULTITHREADED);

  try
    while not Self.FTerminated do
      if WaitForSingleObject(Self.FEvent, 1000) = WAIT_OBJECT_0 then
        if not Self.FTerminated then
          Self.Update;
  finally
    CoUninitialize;
  end;

  Result := 0;
end;

procedure TSID.FillBuffer(AOutBuffer: PSmallInt; ASampleCount: Integer; ASampleRate: Integer);
var
  LevelL: Single;
  LevelR: Single;
  LevelM: Single;
  ASamp:  Single;
  Gain:   Single;
  InPtr:  PSingle;
begin
  if Length(FBuffer) < (ASampleCount * 2) then
    SetLength(FBuffer, ASampleCount * 2);

  FillChar(FBuffer[0],  (ASampleCount * 2) * SizeOf(Single), 0);

  ProcessSynth  (@FBuffer[0], ASampleCount, ASampleRate);
  ProcessPCM    (@FBuffer[0], ASampleCount, ASampleRate);
  ProcessEffects(@FBuffer[0], ASampleCount, ASampleRate);
  ProcessBeep   (@FBuffer[0], ASampleCount, ASampleRate);

  LevelL := 0;
  LevelR := 0;
  LevelM := 0;

  InPtr := @FBuffer[0];

  for var i := 0 to ASampleCount - 1 do
  begin
    ASamp := Abs(InPtr^); Inc(InPtr);
    if ASamp > LevelL then LevelL := ASamp;
    if ASamp > LevelM then LevelM := ASamp;

    ASamp := Abs(InPtr^); Inc(InPtr);
    if ASamp > LevelR then LevelR := ASamp;
    if ASamp > LevelM then LevelM := ASamp;
  end;

  if LevelM > 1 then
  begin
    Gain := 1 / LevelM;

    for var i := 0 to (ASampleCount * 2) - 1 do
    begin
      AOutBuffer^ := Round(32767 * (FBuffer[i] * Gain));
      Inc(AOutBuffer);
    end;

    LevelM := 1;
  end
  else
    for var i := 0 to (ASampleCount * 2) - 1 do
    begin
      AOutBuffer^ := Round(32767 * FBuffer[i]);
      Inc(AOutBuffer);
    end;

  FRegisters.OutLevel  := Round($FF * LevelM);
  FRegisters.OutLevelL := Round($FF * LevelL);
  FRegisters.OutLevelR := Round($FF * LevelR);
end;

procedure TSID.ProcessSynth(ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
begin
  for var i := 0 to TSynthChannels.Count - 1 do
    if FSynthChannels[i].Playing then
      FSynthChannels[i].Process(ABuffer, ASampleCount, ASampleRate);
end;

procedure TSID.ProcessPCM(ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
begin
  for var i := 0 to TPCMChannels.Count - 1 do
    with FPCMChannels[i] do
      if Playing then
      begin
        Samples := FOwner.Memory.GetSpan(Channel.Address, Channel.Length);

        if Assigned(Samples) then
          Process(ABuffer, ASampleCount, ASampleRate);
      end;
end;

procedure TSID.ProcessEffects(ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
var
  Alpha:         Single;
  DelayedSample: Single;
  CurrentSample: Single;
  TargetMix:     Single;
  TargetDelay:   Single;
  OutPtr:        PSingle;
begin
  if FRegisters.Flags.EffectsEnabled then
  begin
    Alpha := (PI2 * FRegisters.CutoffFreq) / ASampleRate;

    if Alpha > 1 then
      Alpha := 1
    else if Alpha < 0 then
      Alpha := 0;

    OutPtr := ABuffer;

    for var i := 0 to ASampleCount - 1 do
    begin
      FPrevSampleL := FPrevSampleL + Alpha * (OutPtr^ - FPrevSampleL);
      OutPtr^ := FPrevSampleL;
      Inc(OutPtr);

      FPrevSampleR := FPrevSampleR + Alpha * (OutPtr^ - FPrevSampleR);
      OutPtr^ := FPrevSampleR;
      Inc(OutPtr);
    end;
  end;

  if FRegisters.Flags.DelayEnabled then
  begin
    if Length(FDelayBufferL) <> (ASampleRate * 2) then
    begin
      SetLength(FDelayBufferL, ASampleRate * 2);
      FillChar(FDelayBufferL[0], Length(FDelayBufferL) * SizeOf(Single), 0);

      SetLength(FDelayBufferR, ASampleRate * 2);
      FillChar(FDelayBufferR[0], Length(FDelayBufferR) * SizeOf(Single), 0);
    end;

    if FRegisters.Flags.DelayEnabled then
      TargetMix := FRegisters.DelayMix
    else
      TargetMix := 0;

    TargetDelay := FRegisters.DelayTime * ASampleRate;

    if TargetDelay < 1 then
      TargetDelay := 1;

    if TargetDelay >= Length(FDelayBufferL) - 2 then
      TargetDelay := Length(FDelayBufferL) - 2;

    if FCurrentDelay < 0 then
      FCurrentDelay := TargetDelay;

    OutPtr := ABuffer;

for var i := 0 to ASampleCount - 1 do
    begin
      FCurrentMix := FCurrentMix + (TargetMix - FCurrentMix) * 0.005;

      if FCurrentMix > 0.0001 then
      begin
        FCurrentDelay := FCurrentDelay + (TargetDelay - FCurrentDelay) * 0.002;

        var ReadPos: Single := FDelayIndex - FCurrentDelay;

        while ReadPos < 0 do
          ReadPos := ReadPos + Length(FDelayBufferL);

        while ReadPos >= Length(FDelayBufferL) do
          ReadPos := ReadPos - Length(FDelayBufferL);

        var Index1: Integer := Trunc(ReadPos);
        var Index2: Integer := Index1 + 1;
        if Index2 >= Length(FDelayBufferL) then
          Index2 := 0;

        var Frac: Single := ReadPos - Index1;

        {$REGION 'Delay left'}
        CurrentSample := OutPtr^;
        DelayedSample := FDelayBufferL[Index1] + Frac * (FDelayBufferL[Index2] - FDelayBufferL[Index1]);

        if Abs(DelayedSample) < 1.0E-6 then
          DelayedSample := 0;

        FDelayBufferL[FDelayIndex] := CurrentSample + (DelayedSample * FRegisters.Feedback);
        OutPtr^ := CurrentSample + (DelayedSample * FCurrentMix);

        Inc(OutPtr);
        {$ENDREGION}

        {$REGION 'Delay right'}
        CurrentSample := OutPtr^;
        DelayedSample := FDelayBufferR[Index1] + Frac * (FDelayBufferR[Index2] - FDelayBufferR[Index1]);

        if Abs(DelayedSample) < 1.0E-6 then
          DelayedSample := 0;

        FDelayBufferR[FDelayIndex] := CurrentSample + (DelayedSample * FRegisters.Feedback);
        OutPtr^ := CurrentSample + (DelayedSample * FCurrentMix);

        Inc(OutPtr);
        {$ENDREGION}
      end
      else
      begin
        FDelayBufferL[FDelayIndex] := 0;
        FDelayBufferR[FDelayIndex] := 0;

        Inc(OutPtr, 2);
      end;

      Inc(FDelayIndex);

      if FDelayIndex >= Length(FDelayBufferL) then
        FDelayIndex := 0;
    end;
  end;
end;

procedure TSID.ProcessBeep(ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
var
  PhaseStep: Double;
  OutPtr:    PSingle;
  SampleVal: Single;
begin
  if not FBeepPlaying then
    Exit;

  OutPtr := ABuffer;

  PhaseStep := (FBeepFrequency * PI2) / ASampleRate;

  for var i := 0 to ASampleCount - 1 do
  begin
    if FBeepTime > (FBeepLength * 1000) then
      FBeepPlaying := False;

    if not FBeepPlaying then
      Break;

    if FBeepPhase < PI then
      SampleVal := FBeepVolume
    else
      SampleVal := -FBeepVolume;

    OutPtr^ := OutPtr^ + SampleVal; Inc(OutPtr);
    OutPtr^ := OutPtr^ + SampleVal; Inc(OutPtr);

    FBeepPhase := FBeepPhase + PhaseStep;
    FBeepTime  := FBeepTime  + PhaseStep;

    if (FBeepPhase >= PI2) or (FBeepPhase < 0) then
    begin
      while FBeepPhase >= PI2 do
        FBeepPhase := FBeepPhase - PI2;

      while FBeepPhase < 0 do
        FBeepPhase := FBeepPhase + PI2;
    end;
  end;
end;

constructor TSID.Create(AOwner: TPasseHarness);
var
  Enumerator: IMMDeviceEnumerator;
  Device:     IMMDevice;
  WaveFormat: TWaveFormatEx;
  DefPeriod:  Int64;
  MinPeriod:  Int64;
begin
  inherited Create;

  FOwner := AOwner;

  FRegisters := FOwner.Memory.Ptr[TPasseMemory.AudioRegistersAddress];
  FSChannels := FOwner.Memory.Ptr[TPasseMemory.SynthChannelsAddress];
  FWChannels := FOwner.Memory.Ptr[TPasseMemory.PCMChannelsAddress];

  FEvent := CreateEvent(nil, False, False, nil);

  CoInitialize(nil);

 if Failed(CoCreateInstance(CLSID_MMDeviceEnumerator, nil, CLSCTX_ALL, IID_IMMDeviceEnumerator, Enumerator)) then
  begin
    FOwner.Error('Failed to create MMDeviceEnumerator');
    Exit;
  end;

  if Failed(Enumerator.GetDefaultAudioEndpoint(0, 0, Device)) then
  begin
    FOwner.Error('Failed to get default audio endpoint');
    Exit;
  end;

  if Failed(Device.Activate(IID_IAudioClient, CLSCTX_ALL, nil, @FAudioClient)) then
  begin
    FOwner.Error('Failed to activate IAudioClient');
    Exit;
  end;

  FillChar(WaveFormat, SizeOf(WaveFormat), 0);

  with WaveFormat do
  begin
    wFormatTag      := WAVE_FORMAT_PCM;
    nChannels       := 2;
    nSamplesPerSec  := SampleRate;
    wBitsPerSample  := 16;
    nBlockAlign     := (nChannels * wBitsPerSample) div 8;
    nAvgBytesPerSec := nSamplesPerSec * nBlockAlign;
  end;

  if Failed(FAudioClient.Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_EVENTCALLBACK or AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM, 0, 0, @WaveFormat, nil)) then
  begin
    FOwner.Error('WASAPI Initialize failed');
    Exit;
  end;

  FAudioClient.SetEventHandle(FEvent);

  FAudioClient.GetDevicePeriod(DefPeriod, MinPeriod);

  FTargetFrames := Round((DefPeriod / 10000000) * SampleRate);
  FTargetFrames := FTargetFrames + ((SampleRate * 5) div 1000);

  FAudioClient.GetBufferSize(FBufferFrames);

  if FTargetFrames > FBufferFrames then
    FTargetFrames := FBufferFrames;

  if Failed(FAudioClient.GetService(IID_IAudioRenderClient, @FRenderClient)) then
  begin
    FOwner.Error('Failed to get audio render client');
    Exit;
  end;
end;

destructor TSID.Destroy;
begin
  Stop;

  if FEvent <> 0 then
    CloseHandle(FEvent);

  FRenderClient := nil;
  FAudioClient  := nil;

  inherited;
end;

procedure TSID.Reset;
begin
  FRegisters.Reset;
  FSChannels.Reset;

  FPrevSampleL  :=  0;
  FPrevSampleR  :=  0;
  FCurrentDelay := -1;
  FCurrentMix   :=  0;

  for var i := 0 to TSynthChannels.Count - 1 do
    with FSynthChannels[i] do
    begin
      Registers := FRegisters;
      Channel   := @FSChannels^.Channels[i];

      Phase     := 0;
      Frequency := Channel.Frequency;

      EnvState := TEnvelopeState.Idle;
      EnvValue := 0;

      Reset;
    end;

  for var i := 0 to TPCMChannels.Count - 1 do
    with FPCMChannels[i] do
    begin
      Registers := FRegisters;
      Channel   := @FWChannels^.Channels[i];

      Position := 0;

      Reset;
    end;

  BeepReset;
end;

function TSID.Start(AWantErrors: Boolean): Boolean;
begin
  if FThreadHandle <> 0 then
    Exit(True);

  Result := False;

  Reset;

  if Failed(FAudioClient.Start) then
  begin
    if AWantErrors then
      FOwner.Error('Failed to start audio client');

    Exit;
  end;

  IsMultiThread := True;
  FTerminated   := False;

  FThreadHandle := CreateThread(nil, 0, @AudioThreadProc, Self, 0, FThreadID);

  if FThreadHandle = 0 then
  begin
    FAudioClient.Stop;

    if AWantErrors then
      FOwner.Error('Failed to create audio thread');

    Exit;
  end;

  SetThreadPriority(FThreadHandle, THREAD_PRIORITY_TIME_CRITICAL);

  Result := True;
end;

procedure TSID.Stop;
begin
  for var i := 0 to TSynthChannels.Count - 1 do
    FSynthChannels[i].Stop;

  for var i := 0 to TSynthChannels.Count - 1 do
    FPCMChannels[i].Stop;

  if FThreadHandle <> 0 then
  begin
    FTerminated := True;

    SetEvent(FEvent);

    WaitForSingleObject(FThreadHandle, INFINITE);

    CloseHandle(FThreadHandle);
    FThreadHandle := 0;
  end;

  if Assigned(FAudioClient) then
    FAudioClient.Stop;
end;

procedure TSID.Update;
var
  Padding:         Cardinal;
  AvailableFrames: Cardinal;
  PData:           PByte;
begin
  if (FAudioClient = nil) or (FRenderClient = nil) then
    Exit;

  FAudioClient.GetCurrentPadding(Padding);

  if Padding < FTargetFrames then
    AvailableFrames := FTargetFrames - Padding
  else
    AvailableFrames := 0;

  if AvailableFrames > (FBufferFrames - Padding) then
    AvailableFrames := FBufferFrames - Padding;

  if AvailableFrames > 0 then
    if Succeeded(FRenderClient.GetBuffer(AvailableFrames, PData)) then
    begin
      FillBuffer(PSmallInt(PData), AvailableFrames, SampleRate);
      FRenderClient.ReleaseBuffer(AvailableFrames, 0);
    end;
end;

procedure TSID.NoteOn(AChannel: Integer; AReset: Boolean);
begin
  FSynthChannels[AChannel mod TSynthChannels.Count].Play(AReset);
end;

procedure TSID.NoteOff(AChannel: Integer);
begin
  FSynthChannels[AChannel mod TSynthChannels.Count].NoteOff;
end;

procedure TSID.PCMPlay(AChannel: Integer; AReset: Boolean = True);
begin
  FPCMChannels[AChannel mod TPCMChannels.Count].Play(AReset);
end;

procedure TSID.PCMStop(AChannel: Integer);
begin
  FPCMChannels[AChannel mod TPCMChannels.Count].Stop;
end;

procedure TSID.BeepReset;
begin
  FBeepPhase   := 0;
  FBeepPlaying := False;
end;

procedure TSID.Beep(AFrequency: Single; ATime: Single);
begin
  FBeepTime      := 0;
  FBeepFrequency := AFrequency;
  FBeepVolume    := 1 / (TSynthChannels.Count + 1);
  FBeepLength    := ATime;
  FBeepPlaying   := True;
end;
{$ENDREGION}

end.
