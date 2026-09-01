{
  NixVM.Tools.Params.pas
    Command line parameters helper

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

unit NixVM.Tools.Params;

{$INCLUDE 'NixVM.Options.inc'}

interface

type
  {$REGION 'TParams'}
  TParams = class abstract
  type
    {$REGION 'TOption'}
    TOption = record
    type
      TKind = (Str, Bool, Num);
    public
      ShortName: ShortString;
      LongName:  ShortString;
      Specified: Boolean;

      case Kind: TKind of
        TKind.Str:  (ValueStr:  ShortString);
        TKind.Bool: (ValueBool: Boolean);
        TKind.Num:  (ValueNum:  Cardinal);
    end;
    {$ENDREGION}
  private
    class var FOptions: array of TOption;
    class var FParams:  array of String;

    class function FindOption(const AOptStr: String): Integer;

    class function GetParamCount:             Integer; inline; static;
    class function GetParam(AIndex: Integer): String;  inline; static;
  public
    class procedure Process(AAllowUnknown: Boolean = False; AStart: Integer = 1);

    class function AddOpt(AKind: TOption.TKind; const AShortName: String; ALongName: String = ''): Integer;

    class function IsOpt(const AOptStr: String): Boolean;

    class function GetOpt(const AOptStr: String; const ADefault: String   = ''):    String;   overload;
    class function GetOpt(const AOptStr: String; const ADefault: Boolean  = False): Boolean;  overload;
    class function GetOpt(const AOptStr: String; const ADefault: Cardinal = 0):     Cardinal; overload;

    class property ParamCount:              Integer read GetParamCount;
    class property Params[AIndex: Integer]: String  read GetParam;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Core.Strings;

{$REGION 'TParams'}
class function TParams.FindOption(const AOptStr: String): Integer;
begin
  for var i := 0 to Length(FOptions) - 1 do
    with FOptions[i] do
      if ((Length(ShortName) > 0) and (AOptStr = ( '-' + String(ShortName))))
      or ((Length(LongName)  > 0) and (AOptStr = ('--' + String(LongName )))) then
        Exit(i);

  Result := -1;
end;

class function TParams.GetParamCount: Integer;
begin
  Result := Length(FParams);
end;

class function TParams.GetParam(AIndex: Integer): String;
begin
  if (AIndex < 0) or (AIndex >= Length(FParams)) then
    Result := ''
  else
    Result := FParams[AIndex];
end;

class procedure TParams.Process(AAllowUnknown: Boolean; AStart: Integer);
var
  i: Integer;
  o: Integer;
  p: String;
  v: Cardinal;
  n: Boolean;
begin
  SetLength(FParams, 0);

  i := AStart;

  while i <= System.ParamCount do
  begin
    p := ParamStr(i);

    if (Length(p) > 1) and (p[1] = '-') then
    begin
       n := (p[Length(p)] = '-') and (Length(p) > 2);

      if n then
        p := Copy(p, 1, Length(p) - 1);

      o := FindOption(Lowercase(p));

      if o = -1 then
      begin
        if AAllowUnknown then
        begin
          Inc(i);
          Continue;
        end
        else
        begin
          Writeln('Unknown option: ', p);
          Halt(1);
        end;
      end;

      FOptions[o].Specified := True;

      case FOptions[o].Kind of
        TOption.TKind.Str:
          if n then
            FOptions[o].ValueStr := ''
          else
          begin
            Inc(i);

            if i > System.ParamCount then
            begin
              Writeln('Required value: ', p, ' <value>');
              Halt(1);
            end;

            FOptions[o].ValueStr := ShortString(ParamStr(i));
          end;

        TOption.TKind.Bool:
          FOptions[o].ValueBool := not n;

        TOption.TKind.Num:
          if n then
            FOptions[o].ValueNum := 0
          else
          begin
            Inc(i);

            if i > System.ParamCount then
            begin
              Writeln('Required value: ', p, ' <value>');
              Halt(1);
            end;

            if not ParseNumber(ParamStr(i), v) then
            begin
              Writeln('Option ', p, ' must be a valid number.');
              Halt(1);
            end;

            FOptions[o].ValueNum := v;
          end;
      end;
    end
    else
    begin
      if p <> '-' then
      begin
        SetLength(FParams, Length(FParams) + 1);
        FParams[High(FParams)] := p;
      end;
    end;

    Inc(i);
  end;
end;

class function TParams.AddOpt(AKind: TOption.TKind; const AShortName: String; ALongName: String = ''): Integer;
begin
  Result := FindOption(AShortName);

  if Result > -1 then
    Exit;

  SetLength(FOptions, Length(FOptions) + 1);

  Result := High(FOptions);

  with FOptions[Result] do
  begin
    ShortName := ShortString(Lowercase(AShortName));
    LongName  := ShortString(Lowercase(ALongName));

    Specified := False;

    Kind := AKind;
  end;
end;

class function TParams.IsOpt(const AOptStr: String): Boolean;
var
  i: Integer;
begin
  i := FindOption(Lowercase(AOptStr));

  if i = -1 then
    Exit(False);

  with FOptions[i] do
    case Kind of
      TOption.TKind.Str:  Result := Specified and (Length(ValueStr) > 0);
      TOption.TKind.Bool: Result := Specified and ValueBool;
    else
      Result := Specified;
    end;
end;

class function TParams.GetOpt(const AOptStr: String; const ADefault: String): String;
var
  i: Integer;
begin
  i := FindOption(Lowercase(AOptStr));

  if i = -1 then
    Exit(ADefault);

  with FOptions[i] do
  begin
    if Kind <> TOption.TKind.Str then
      Exit(ADefault);

    if Specified and (Length(ValueStr) > 0) then
      Result := String(ValueStr)
    else
      Result := ADefault;
  end;
end;

class function TParams.GetOpt(const AOptStr: String; const ADefault: Boolean): Boolean;
var
  i: Integer;
begin
  i := FindOption(Lowercase(AOptStr));

  if i = -1 then
    Exit(ADefault);

  with FOptions[i] do
  begin
    if Kind <> TOption.TKind.Bool then
      Exit(ADefault);

    if Specified then
      Result := ValueBool
    else
      Result := ADefault;
  end;
end;

class function TParams.GetOpt(const AOptStr: String; const ADefault: Cardinal): Cardinal;
var
  i: Integer;
begin
  i := FindOption(Lowercase(AOptStr));

  if i = -1 then
    Exit(ADefault);

  with FOptions[i] do
  begin
    if Kind <> TOption.TKind.Num then
      Exit(ADefault);

    if Specified then
      Result := ValueNum
    else
      Result := ADefault;
  end;
end;
{$ENDREGION}

end.
