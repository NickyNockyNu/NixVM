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
      Beep    = SID + 3;
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

    {$REGION 'Channel'}
    TChannel = record
      Registers:   PAudioRegisters;
      Channel:     TAudioChannels.PChannel;
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
    FAChannels: PAudioChannels;

    FChannels: array[0..TAudioChannels.Count - 1] of TChannel;

    FBuffer: array of Single;

    FPrevSample:   Single;
    FDelayBuffer:  array of Single;
    FDelayIndex:   Integer;
    FCurrentDelay: Single;
    FCurrentMix:   Single;

    FBeepPhase:     Single;
    FBeepTime:      Single;
    FBeepLength:    Single;
    FBeepFrequency: Single;
    FBeepVolume:    Single;
    FBeepPlaying:   Boolean;

    class function AudioThreadProc(AParameter: Pointer): Integer; stdcall; static;
  protected
    procedure FillBuffer(AOutBuffer: PSmallInt; ASampleCount: Integer; ASampleRate: Integer);

    procedure ProcessEffects(ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
    procedure ProcessMix    (ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
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

    procedure BeepReset;
    procedure Beep(AFrequency: Single = 400; ATime: Single = 0.6);

    property Owner: TPasseHarness read FOwner;

    property AudioClient:  IAudioClient       read FAudioClient;
    property RenderClient: IAudioRenderClient read FRenderClient;

    property Registers: PAudioRegisters read FRegisters;
    property Channels:  PAudioChannels  read FAChannels;
  end;
  {$ENDREGION}

const
  PI2 = PI * 2;

implementation

uses
  Winapi.ActiveX;

{$REGION 'Channel'}
procedure TSID.TChannel.Process(ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
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

  if (not Playing) or (Channel.Volume <= 0) or (Channel.Frequency <= 0) then
  begin
    Stop;
    Exit;
  end;

  TimeStep := 1 / ASampleRate;
  OutPtr   := ABuffer;

  for var i := 0 to ASampleCount - 1 do
  begin
    Frequency := Frequency + (Channel.Frequency - Frequency) * Channel.GlideSpeed;
    Volume    := Volume    + (Channel.Volume    - Volume)    * Channel.GlideSpeed;

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
        TAudioChannels.TWaveform.Sine:
          ModValue := Sin(ModPhaseEff);

        TAudioChannels.TWaveform.Triangle:
        begin
          Val := ModPhaseEff / PI2;
          Val := Val - Trunc(Val);

          if Val < 0 then
            Val := Val + 1;

          ModValue := 1 - (4 * Abs(Val - 0.5));
        end;

        TAudioChannels.TWaveform.Square:
          ModValue := 0.78 * (Sin(ModPhaseEff) + (0.333 * Sin(ModPhaseEff * 3)) + (0.2 * Sin(ModPhaseEff * 5)));

        TAudioChannels.TWaveform.Sawtooth:
          ModValue := 0.6 * (Sin(ModPhaseEff) - (0.5 * Sin(ModPhaseEff * 2)) + (0.333 * Sin(ModPhaseEff * 3)) - (0.25 * Sin(ModPhaseEff * 4)));

        TAudioChannels.TWaveform.Noise:
          ModValue := NoiseVal;
      else
        ModValue := 0;
      end;

      ModPrev := ModValue;

      ModPhaseValue := Phase + (ModValue * ModDepth * ModEnvValue);

      case Channel.Flags.Waveform of
        TAudioChannels.TWaveform.Sine:
          SampleVal := Sin(ModPhaseValue);

        TAudioChannels.TWaveform.Triangle:
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
        TAudioChannels.TWaveform.Sine:
          SampleVal := Sin(Phase);

        TAudioChannels.TWaveform.Square:
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

        TAudioChannels.TWaveform.Sawtooth:
        begin
          SampleVal := (2 * NormPhase) - 1;
          SampleVal := SampleVal - PolyBLEP(NormPhase, NormTime);
        end;

        TAudioChannels.TWaveform.Triangle:
          SampleVal := 1 - (4 * Abs(NormPhase - 0.5));

        TAudioChannels.TWaveform.Noise:
          if NormPhase < Channel.PulseWidth then
            SampleVal := NoiseVal
          else
            SampleVal := -NoiseVal;
      else
        SampleVal := 0;
      end;
    end;

    SampleVal := SampleVal * Volume * EnvValue;

    OutPtr^ := OutPtr^ + SampleVal;

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

    Inc(OutPtr);
  end;

  Channel.OutLevel := Round($FF * Level);
end;

procedure TSID.TChannel.Reset;
begin
  Stop;

  ResetPhase;

  ModPrev  := 0;
  EnvValue := 0;
end;

procedure TSID.TChannel.Play(AReset: Boolean = True);
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

procedure TSID.TChannel.Stop;
begin
  Playing := False;

  Channel.OutLevel := 0;

  EnvState := TEnvelopeState.Idle;
  EnvValue := 0;

  ModEnvState := TEnvelopeState.Idle;
  ModEnvValue := 0;
end;

procedure TSID.TChannel.NoteOff;
begin
  if EnvState <> TEnvelopeState.Idle then
    EnvState := TEnvelopeState.Release;

  if ModEnvState <> TEnvelopeState.Idle then
    ModEnvState := TEnvelopeState.Release;
end;

procedure TSID.TChannel.ResetPhase;
begin
  case Channel.Flags.Waveform of
    TAudioChannels.TWaveform.Sine:     Phase := 0;
    TAudioChannels.TWaveform.Square:   Phase := 0;
    TAudioChannels.TWaveform.Sawtooth: Phase := PI;
    TAudioChannels.TWaveform.Triangle: Phase := PI / 2;
    TAudioChannels.TWaveform.Noise:
    begin
      Phase    := 0;
      NoiseVal := (Random - 0.5) * 2;
    end;
  end;

  case Channel.Flags.ModWaveform of
    TAudioChannels.TWaveform.Sine:     ModPhase := 0;
    TAudioChannels.TWaveform.Square:   ModPhase := 0;
    TAudioChannels.TWaveform.Sawtooth: ModPhase := PI;
    TAudioChannels.TWaveform.Triangle: ModPhase := PI / 2;
    TAudioChannels.TWaveform.Noise:    ModPhase := 0;
  end;
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
  Level: Single;
  ASamp: Single;
  Gain:  Single;
begin
  if Length(FBuffer) < ASampleCount then
    SetLength(FBuffer, ASampleCount);

  FillChar(FBuffer[0], ASampleCount * SizeOf(Single), 0);

  ProcessEffects(@FBuffer[0], ASampleCount, ASampleRate);
  ProcessBeep   (@FBuffer[0], ASampleCount, ASampleRate);

  Level := 0;

  for var i := 0 to ASampleCount - 1 do
  begin
    ASamp := Abs(FBuffer[i]);

    if ASamp > Level then
      Level := ASamp;
  end;

  if Level > 1 then
  begin
    Gain := 1 / Level;

    for var i := 0 to ASampleCount - 1 do
    begin
      AOutBuffer^ := Round(32767 * (FBuffer[i] * Gain));
      Inc(AOutBuffer);
    end;

    Level := 1;
  end
  else
    for var i := 0 to ASampleCount - 1 do
    begin
      AOutBuffer^ := Round(32767 * FBuffer[i]);
      Inc(AOutBuffer);
    end;

  FRegisters.OutLevel := Round($FF * Level);
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
  ProcessMix(ABuffer, ASampleCount, ASampleRate);

  if FRegisters.Flags.EffectsEnabled then
  begin
    Alpha := (PI2 * FRegisters.CutoffFreq) / ASampleRate;

    if Alpha > 1 then
      Alpha := 1;

    OutPtr := ABuffer;

    for var i := 0 to ASampleCount - 1 do
    begin
      FPrevSample := FPrevSample + Alpha * (OutPtr^ - FPrevSample);
      OutPtr^ := FPrevSample;
      Inc(OutPtr);
    end;
  end;

  if FRegisters.Flags.DelayEnabled then
  begin
    if Length(FDelayBuffer) <> (ASampleRate * 2) then
    begin
      SetLength(FDelayBuffer, ASampleRate * 2);
      FillChar(FDelayBuffer[0], Length(FDelayBuffer) * SizeOf(Single), 0);
    end;

    if FRegisters.Flags.DelayEnabled then
      TargetMix := FRegisters.DelayMix
    else
      TargetMix := 0;

    TargetDelay := FRegisters.DelayTime * ASampleRate;

    if TargetDelay < 1 then
      TargetDelay := 1;

    if TargetDelay >= Length(FDelayBuffer) - 2 then
      TargetDelay := Length(FDelayBuffer) - 2;

    if FCurrentDelay < 0 then
      FCurrentDelay := TargetDelay;

    OutPtr := ABuffer;

    for var i := 0 to ASampleCount - 1 do
    begin
      CurrentSample := OutPtr^;

      FCurrentMix := FCurrentMix + (TargetMix - FCurrentMix) * 0.005;

      if FCurrentMix > 0.0001 then
      begin
        FCurrentDelay := FCurrentDelay + (TargetDelay - FCurrentDelay) * 0.002;

        var ReadPos: Single := FDelayIndex - FCurrentDelay;

        while ReadPos < 0 do
          ReadPos := ReadPos + Length(FDelayBuffer);

        while ReadPos >= Length(FDelayBuffer) do
          ReadPos := ReadPos - Length(FDelayBuffer);

        var Index1: Integer := Trunc(ReadPos);
        var Index2: Integer := Index1 + 1;

        if Index2 >= Length(FDelayBuffer) then
          Index2 := 0;

        var Frac: Single := ReadPos - Index1;

        DelayedSample := FDelayBuffer[Index1] + Frac * (FDelayBuffer[Index2] - FDelayBuffer[Index1]);

        if Abs(DelayedSample) < 1.0E-6 then
          DelayedSample := 0;

        FDelayBuffer[FDelayIndex] := CurrentSample + (DelayedSample * FRegisters.Feedback);
        OutPtr^ := CurrentSample + (DelayedSample * FCurrentMix);
      end
      else
        FDelayBuffer[FDelayIndex] := 0;

      Inc(FDelayIndex);

      if FDelayIndex >= Length(FDelayBuffer) then
        FDelayIndex := 0;

      Inc(OutPtr);
    end;
  end;
end;

procedure TSID.ProcessMix(ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
begin
  for var i := 0 to TAudioChannels.Count - 1 do
    if FChannels[i].Playing then
      FChannels[i].Process(ABuffer, ASampleCount, ASampleRate);
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

    OutPtr^ := OutPtr^ + SampleVal;

    FBeepPhase := FBeepPhase + PhaseStep;
    FBeepTime  := FBeepTime  + PhaseStep;

    if (FBeepPhase >= PI2) or (FBeepPhase < 0) then
    begin
      while FBeepPhase >= PI2 do
        FBeepPhase := FBeepPhase - PI2;

      while FBeepPhase < 0 do
        FBeepPhase := FBeepPhase + PI2;
    end;

    Inc(OutPtr);
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
  FAChannels := FOwner.Memory.Ptr[TPasseMemory.AudioChannelsAddress];

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
    nChannels       := 1;
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
  FAChannels.Reset;

  FPrevSample   :=  0;
  FCurrentDelay := -1;
  FCurrentMix   :=  0;

  for var i := 0 to TAudioChannels.Count - 1 do
    with FChannels[i] do
    begin
      Registers := FRegisters;
      Channel   := @FAChannels^.Channels[i];

      Phase     := 0;
      Frequency := Channel.Frequency;

      EnvState := TEnvelopeState.Idle;
      EnvValue := 0;

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
  for var i := 0 to TAudioChannels.Count - 1 do
    FChannels[i].Stop;

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
  FChannels[AChannel mod TAudioChannels.Count].Play(AReset);
end;

procedure TSID.NoteOff(AChannel: Integer);
begin
  FChannels[AChannel mod TAudioChannels.Count].NoteOff;
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
  FBeepVolume    := 1 / (TAudioChannels.Count + 1);
  FBeepLength    := ATime;
  FBeepPlaying   := True;
end;
{$ENDREGION}

end.
