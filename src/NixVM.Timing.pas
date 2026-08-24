{
  NixVM.Timing.pas
    NixVM - System tick provider and stopwatch (should be moved to a general purpose library)
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

unit NixVM.Timing;

{$INCLUDE 'NixVM.Options.inc'}

interface

type
  TTicks = type Int64;

  {$REGION 'TicksHelper'}
  TTicksHelper = record helper for TTicks
  private
    class var FPerSecond:  TTicks;
    class var FResolution: Cardinal;

    class constructor Create;
    class destructor  Destroy;
  public
    class procedure SetResolution(AResolution: Cardinal); static;
    class procedure ResetResolution; static;

    class function SysElapsed: TTicks; static;

    class property PerSecond:  TTicks   read FPerSecond;
    class property Resolution: Cardinal read FResolution write SetResolution;  // 0 = System default (15ms)

    function InSeconds:      Double; inline;
    function InMilliseconds: Int64;  inline;
  end;
  {$ENDREGION}

  {$REGION 'Stopwatch'}
  TStopwatch = record
  private
    FStart: TTicks;
  public
    procedure Start; inline;

    function Elapsed: TTicks; inline;
    function Update:  TTicks;

    procedure WaitUntil(const ASeconds: Double);
  end;
  {$ENDREGION}

procedure YieldCPU;
procedure Sleep(AMilliseconds: Cardinal); inline;
procedure SleepSeconds(const ASeconds: Double);

implementation

{$IF DEFINED(MSWINDOWS)}
uses
  WinApi.Windows,
  WinApi.MMSystem;
{$ELSEIF DEFINED(POSIX)}
uses
  {$IF DEFINED(MACOS)}
  Macapi.Mach,
  {$ENDIF}
  Posix.Time,
  Posix.Unistd,
  Posix.Sched;
{$ELSE}
  {$MESSAGE FATAL 'Platform not supported'}
{$ENDIF}

{$REGION 'Utils'}
procedure YieldCPU;
{$IF DEFINED(CPUX86) OR DEFINED(CPUX64)}
asm
  PAUSE
end;
{$ELSEIF DEFINED(MSWINDOWS)}
begin
  if not SwitchToThread then
    Winapi.Windows.Sleep(0);
end;
{$ELSEIF DEFINED(POSIX)}
begin
  sched_yield;
end;
{$ELSE}
begin
  YieldProcessor;
end;
{$ENDIF}

procedure Sleep(AMilliseconds: Cardinal);
{$IF DEFINED(MSWINDOWS)}
begin
  Winapi.Windows.Sleep(AMilliseconds);
end;
{$ELSEIF DEFINED(POSIX)}
  {$IF DECLARED(nanosleep)}
  var
    Req, Rem: timespec;
  begin
    Req.tv_sec  :=  AMilliseconds div 1000;
    Req.tv_nsec := (AMilliseconds mod 1000) * 1000000;
    nanosleep(Req, Rem);
  end;
  {$ELSE}
  begin
    if AMilliseconds >= 1000 then
      Posix.Unistd.sleep(AMilliseconds div 1000);

    if (AMilliseconds mod 1000) > 0 then
      usleep(useconds_t(AMilliseconds mod 1000) * 1000);
  end;
  {$ENDIF}
{$ELSE}
begin

end;
{$ENDIF}

procedure SleepSeconds(const ASeconds: Double);
var
  SW: TStopwatch;
begin
  SW.Start;
  SW.WaitUntil(ASeconds);
end;
{$ENDREGION}

{$REGION 'TicksHelper'}
class constructor TTicksHelper.Create;
begin
{$IF DEFINED(MSWINDOWS)}
  if not QueryPerformanceFrequency(Int64(FPerSecond)) then
    FPerSecond := 1000;
{$ELSEIF DEFINED(MACOS)}
  var TimebaseInfo: mach_timebase_info_data_t;
  mach_timebase_info(TimebaseInfo);
  FPerSecond := (Int64(1000000000) * Int64(TimebaseInfo.denom)) div Int64(TimebaseInfo.numer);
{$ELSEIF DEFINED(POSIX)}
  FPerSecond := 1000000000;
{$ENDIF}
end;

class destructor TTicksHelper.Destroy;
begin
  ResetResolution;
end;

class procedure TTicksHelper.SetResolution(AResolution: Cardinal);
begin
  ResetResolution;

{$IF DEFINED(MSWINDOWS)}
  if timeBeginPeriod(AResolution) = TIMERR_NOERROR then
    FResolution := AResolution;
{$ELSE}
  FResolution := AResolution;
{$ENDIF}
end;

class procedure TTicksHelper.ResetResolution;
begin
  if FResolution > 0 then
  begin
{$IF DEFINED(MSWINDOWS)}
    timeEndPeriod(FResolution);
{$ENDIF}

    FResolution := 0;
  end;
end;

class function TTicksHelper.SysElapsed: TTicks;
begin
{$IF DEFINED(MSWINDOWS)}
  if not QueryPerformanceCounter(Int64(Result)) then
    Result := GetTickCount64;
{$ELSEIF DEFINED(MACOS)}
  Result := TTicks(mach_absolute_time);
{$ELSEIF DEFINED(POSIX)}
  var Res: timespec;
  clock_gettime(CLOCK_MONOTONIC, @Res);
  Result := (Int64(Res.tv_sec) * 1000000000) + Int64(Res.tv_nsec);
{$ENDIF}
end;

function TTicksHelper.InSeconds: Double;
begin
  Result := Self / FPerSecond;
end;

function TTicksHelper.InMilliseconds: Int64;
begin
   Result := (Self div FPerSecond) * 1000 + ((Self mod FPerSecond) * 1000) div FPerSecond;
end;
{$ENDREGION}

{$REGION 'Stopwatch'}
procedure TStopwatch.Start;
begin
  FStart := TTicks.SysElapsed;
end;

function TStopwatch.Elapsed: TTicks;
begin
  Result := TTicks.SysElapsed - FStart;
end;

function TStopwatch.Update: TTicks;
var
  Now: TTicks;
begin
  Now    := TTicks.SysElapsed;
  Result := Now - FStart;
  FStart := Now;
end;

procedure TStopwatch.WaitUntil(const ASeconds: Double);
var
  TargetTick:     TTicks;
  RemainingTicks: TTicks;
  RemainingMs:    Int64;
  Resolution:     Cardinal;
begin
  TargetTick := FStart + Round(ASeconds * TTicks.PerSecond);

  Resolution := TTicks.Resolution;
  if Resolution = 0 then
{$IF DEFINED(MSWINDOWS)}
    Resolution := 15;
{$ELSE}
    Resolution := 1;
{$ENDIF}

  repeat
    RemainingTicks := TargetTick - TTicks.SysElapsed;

    if RemainingTicks <= 0 then
      Break;

    RemainingMs := (RemainingTicks * 1000) div TTicks.PerSecond;

    if RemainingMs > Resolution then
      Sleep(RemainingMs - Resolution)
    else
      YieldCPU;
  until False;
end;
{$ENDREGION}

end.
