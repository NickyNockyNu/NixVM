{
  NixVM.Tools.GenUnits.pas
    System generated units

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

unit NixVM.Tools.GenUnits;

interface

uses
  System.SysUtils;

type
  TGenUnits = class abstract
    class function GetSysConst: String;
  end;

implementation

uses
  NixVM.Core.System;

class function TGenUnits.GetSysConst: String;
  procedure AddLn(const ALine: String = '');
  begin
    Result := Result + ALine + #13#10;
  end;

  procedure AddAddrDef(AName: String; AValue: Integer; APad: Integer = 16);
  begin
    while Length(AName) < APad do
      AName := AName + ' ';

    AddLn('  _Addr_' + AName + ' = $' + IntToHex(AValue, 8) + ';');
  end;

  procedure AddIntDef(AName: String; AValue: Integer; APad: Integer = 20);
  begin
    while Length(AName) < APad do
      AName := AName + ' ';

    AddLn('  ' + AName + ' = $' + IntToHex(AValue, 2) + ';');
  end;
var
  s: String;
begin
  AddLn('unit SysConst;');
  AddLn;
  AddLn('interface');

  AddLn;
  AddLn('const');
  AddLn('  // System addresses');
  AddAddrDef('Interrupts',      TCoreSystemMemory.InterruptsAddress);
  AddAddrDef('SysCalls',        TCoreSystemMemory.SysCallsAddress);
  AddAddrDef('SystemState',     TCoreSystemMemory.SystemStateAddress);
  AddAddrDef('MemoryMap',       TCoreSystemMemory.MemoryMapAddress);
  AddAddrDef('Timers',          TCoreSystemMemory.TimersAddress);
  AddAddrDef('SystemRegisters', TCoreSystemMemory.RegistersAddress);
  AddAddrDef('OEM',             SizeOf(TCoreSystemMemory));

  AddLn;
  AddLn('const');
  AddLn('  // Interrupt ID''s');
  for var i := 0 to 15 do
  begin
    s := TInterrupts.ID(i).ToString;

    if Length(s) > 0 then
      AddIntDef(s, i, 15);
  end;

  AddLn;
  AddLn('const');
  AddLn('  // SysCall ID''s');
  for var i := 0 to 255 do
  begin
    s := TSysCalls.ID(i).ToString;

    if Length(s) > 0 then
      AddIntDef(s, i, 25);
  end;

  AddLn;
  AddLn('implementation');
  AddLn;
  AddLn('end.');
end;

end.
