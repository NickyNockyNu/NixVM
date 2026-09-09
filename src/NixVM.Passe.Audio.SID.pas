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
      Registers: PAudioRegisters;
      Channel:   TAudioChannels.PChannel;
      Phase:     Double;
      Frequency: Single;
      Volume:    Single;
      NoiseVal:  Single;
      EnvState:  TEnvelopeState;
      EnvValue:  Single;
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

    procedure Start;
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

implementation

uses
  Winapi.ActiveX;

{$REGION 'Channel'}
procedure TSID.TChannel.Process(ABuffer: PSingle; ASampleCount, ASampleRate: Integer);
var
  PhaseStep: Double;
  TimeStep:  Double;
  OutPtr:    PSingle;
  SampleVal: Single;
  P:         Double;
  Level:     Single;
begin
  Level := 0;

  if (not Playing) or (Channel.Volume <= 0) or (Channel.Frequency <= 0) then
  begin
    Stop;
    Exit;
  end;

  TimeStep  := 1.0 / ASampleRate;
  OutPtr    := ABuffer;

  for var i := 0 to ASampleCount - 1 do
  begin
    Frequency := Frequency + (Channel.Frequency - Frequency) * Channel.GlideSpeed;
    PhaseStep := (Frequency * 2.0 * Pi) / ASampleRate;

    Volume := Volume + (Channel.Volume - Volume) * Channel.GlideSpeed;

    case EnvState of
      TEnvelopeState.Attack:
        if Channel.Attack > 0 then
        begin
          EnvValue := EnvValue + (TimeStep / Channel.Attack);

          if EnvValue >= 1.0 then
          begin
            EnvValue := 1.0;
            EnvState := TEnvelopeState.Decay;
          end;
        end
        else
        begin
          EnvValue := 1.0;
          EnvState := TEnvelopeState.Decay;
        end;

      TEnvelopeState.Decay:
        if Channel.Decay > 0 then
        begin
          EnvValue := EnvValue - (TimeStep / Channel.Decay) * (1.0 - Channel.Sustain);

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
        if Channel.Release > 0 then
        begin
          EnvValue := EnvValue - (TimeStep / Channel.Release);

          if EnvValue <= 0.0 then
          begin
            EnvValue := 0.0;
            EnvState := TEnvelopeState.Idle;

            Stop;
            Exit;
          end;
        end
        else
        begin
          EnvValue := 0.0;
          EnvState := TEnvelopeState.Idle;

          Stop;
          Exit;
        end;
    end;

    case Channel.Flags.Waveform of
      TAudioChannels.TWaveform.Sine:
        SampleVal := Sin(Phase);

      TAudioChannels.TWaveform.Square:
        if Phase <  (2.0 * Pi * Channel.PulseWidth) then
          SampleVal := 1.0
        else
          SampleVal := -1.0;

      TAudioChannels.TWaveform.Sawtooth:
        SampleVal := (Phase / Pi) - 1.0;

      TAudioChannels.TWaveform.Triangle:
      begin
        P := Phase / (2.0 * Pi);
        SampleVal := 1.0 - (4.0 * Abs(P - 0.5));
      end;

      TAudioChannels.TWaveform.Noise:
        if Phase < (2.0 * Pi * Channel.PulseWidth) then
          SampleVal := NoiseVal
        else
          SampleVal := -NoiseVal;
    else
      SampleVal := 0.0;
    end;

    SampleVal := SampleVal * Volume * EnvValue;

    OutPtr^ := OutPtr^ + SampleVal;

    SampleVal := Abs(SampleVal);

    if SampleVal > Level then
      Level := SampleVal;

    Phase := Phase + PhaseStep;

    if (Phase >= (2.0 * Pi)) or (Phase < 0.0) then
    begin
      NoiseVal := (Random - 0.5) * 2.0;

      while Phase >= (2.0 * Pi) do
      begin
        Phase    := Phase - (2.0 * Pi);
        NoiseVal := (Random - 0.5) * 2.0;
      end;

      while Phase < 0.0 do
      begin
        Phase := Phase + (2.0 * Pi);
        NoiseVal := (Random - 0.5) * 2.0;
      end;
    end;

    Inc(OutPtr);
  end;

  Channel.OutLevel := Level;
end;

procedure TSID.TChannel.Reset;
begin
  Stop;

  Phase    := 0.0;
  EnvValue := 0.0;
end;

procedure TSID.TChannel.Play(AReset: Boolean = True);
begin
  if AReset then
  begin
    if EnvValue < 0.005 then
    begin
      ResetPhase;

      EnvValue  := 0.0;
      Frequency := Channel.Frequency;
      Volume    := Channel.Volume;
    end;

    Reset;
  end;

  EnvState := TEnvelopeState.Attack;

  Playing := True;
end;

procedure TSID.TChannel.Stop;
begin
  Playing := False;

  Channel.OutLevel := 0;

  EnvState := TEnvelopeState.Idle;
  EnvValue := 0.0;
end;

procedure TSID.TChannel.NoteOff;
begin
  if EnvState <> TEnvelopeState.Idle then
    EnvState := TEnvelopeState.Release;
end;

procedure TSID.TChannel.ResetPhase;
begin
  case Channel.Flags.Waveform of
    TAudioChannels.TWaveform.Sine:     Phase := 0.0;
    TAudioChannels.TWaveform.Square:   Phase := 0.0;
    TAudioChannels.TWaveform.Sawtooth: Phase := Pi;
    TAudioChannels.TWaveform.Triangle: Phase := Pi / 2.0;
    TAudioChannels.TWaveform.Noise:
    begin
      Phase    := 0.0;
      NoiseVal := (Random - 0.5) * 2.0;
    end;
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
begin
  if Length(FBuffer) < ASampleCount then
    SetLength(FBuffer, ASampleCount);

  FillChar(FBuffer[0], ASampleCount * SizeOf(Single), 0);

  ProcessEffects(@FBuffer[0], ASampleCount, ASampleRate);
  ProcessBeep   (@FBuffer[0], ASampleCount, ASampleRate);

  Level := 0;

  for var i := 0 to ASampleCount - 1 do
    if Abs(FBuffer[i]) > Level then
        Level := Abs(FBuffer[i]);

  if Level > 1 then
  begin
    for var i := 0 to ASampleCount - 1 do
    begin
      AOutBuffer^ := Round((FBuffer[i] * (1 / Level)) * 32767.0);
      Inc(AOutBuffer);
    end;

    Level := 1;
  end
  else
    for var i := 0 to ASampleCount - 1 do
    begin
      AOutBuffer^ := Round(FBuffer[i] * 32767.0);
      Inc(AOutBuffer);
    end;

  FRegisters.OutLevel := Level;
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
    Alpha := (2.0 * Pi * FRegisters.CutoffFreq) / ASampleRate;
    if Alpha > 1.0 then
      Alpha := 1.0;

    OutPtr := ABuffer;

    for var i := 0 to ASampleCount - 1 do
    begin
      FPrevSample := FPrevSample + Alpha * (OutPtr^ - FPrevSample);
      OutPtr^ := FPrevSample;
      Inc(OutPtr);
    end;
  end;

  //if FRegisters.Flags.DelayEnabled then
  begin
    if Length(FDelayBuffer) <> (ASampleRate * 2) then
    begin
      SetLength(FDelayBuffer, ASampleRate * 2);
      FillChar(FDelayBuffer[0], Length(FDelayBuffer) * SizeOf(Single), 0);
    end;

    if FRegisters.Flags.DelayEnabled then
      TargetMix := FRegisters.DelayMix
    else
      TargetMix := 0.0;

    TargetDelay := FRegisters.DelayTime * ASampleRate;

    if TargetDelay < 1 then
      TargetDelay := 1;

    if TargetDelay >= Length(FDelayBuffer) - 2 then
      TargetDelay := Length(FDelayBuffer) - 2;

    if FCurrentDelay < 0.0 then
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

        if Index2 >= Length(FDelayBuffer) then Index2 := 0;

        var Frac: Single := ReadPos - Index1;

        DelayedSample := FDelayBuffer[Index1] + Frac * (FDelayBuffer[Index2] - FDelayBuffer[Index1]);

        if Abs(DelayedSample) < 1.0E-6 then
          DelayedSample := 0.0;

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

  PhaseStep := (FBeepFrequency * 2.0 * Pi) / ASampleRate;

  for var i := 0 to ASampleCount - 1 do
  begin
    if FBeepTime > (FBeepLength * 1000) then
      FBeepPlaying := False;

    if not FBeepPlaying then
      Break;

    if FBeepPhase <  (2.0 * Pi * 0.5) then
      SampleVal := FBeepVolume
    else
      SampleVal := -FBeepVolume;

    OutPtr^ := OutPtr^ + SampleVal;

    FBeepPhase := FBeepPhase + PhaseStep;
    FBeepTime  := FBeepTime  + PhaseStep;

    if (FBeepPhase >= (2.0 * Pi)) or (FBeepPhase < 0.0) then
    begin
      while FBeepPhase >= (2.0 * Pi) do
        FBeepPhase := FBeepPhase - (2.0 * Pi);

      while FBeepPhase < 0.0 do
        FBeepPhase := FBeepPhase + (2.0 * Pi);
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
    FOwner.Error('Failed to create MMDeviceEnumerator');

  if Failed(Enumerator.GetDefaultAudioEndpoint(0, 0, Device)) then
    FOwner.Error('Failed to get default audio endpoint');

  if Failed(Device.Activate(IID_IAudioClient, CLSCTX_ALL, nil, @FAudioClient)) then
    FOwner.Error('Failed to activate IAudioClient');

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
    FOwner.Error('WASAPI Initialize failed');

  FAudioClient.SetEventHandle(FEvent);

  FAudioClient.GetDevicePeriod(DefPeriod, MinPeriod);

  FTargetFrames := Round((DefPeriod / 10000000) * SampleRate);
  FTargetFrames := FTargetFrames + ((SampleRate * 5) div 1000);

  FAudioClient.GetBufferSize(FBufferFrames);

  if FTargetFrames > FBufferFrames then
    FTargetFrames := FBufferFrames;

  FAudioClient.GetService(IID_IAudioRenderClient, @FRenderClient);
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

  for var i := 0 to TAudioChannels.Count - 1 do
    with FChannels[i] do
    begin
      Registers := FRegisters;
      Channel   := @FAChannels^.Channels[i];

      Phase     := 0.0;
      Frequency := Channel.Frequency;

      EnvState := TEnvelopeState.Idle;
      EnvValue := 0.0;

      Reset;
    end;

  BeepReset;
end;

procedure TSID.Start;
begin
  if FThreadHandle = 0 then
  begin
    Reset;

    IsMultiThread := True;
    FTerminated   := False;

    FThreadHandle := CreateThread(nil, 0, @AudioThreadProc, Self, 0, FThreadID);

    if FThreadHandle <> 0 then
      SetThreadPriority(FThreadHandle, THREAD_PRIORITY_TIME_CRITICAL);
  end;

  FAudioClient.Start;
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
