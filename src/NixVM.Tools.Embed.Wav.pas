{
  NixVM.Tools.Embed.Wav.pas
    Audio file embed decoder

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

unit NixVM.Tools.Embed.Wav;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  Winapi.Windows,

  System.SysUtils,
  System.Classes;

type
  {$REGION 'Wav Format Structures'}
  TRIFFHeader = packed record
    ChunkID:   array[0..3] of AnsiChar;
    ChunkSize: Cardinal;
    Format:    array[0..3] of AnsiChar;
  end;

  TChunkHeader = packed record
    ChunkID:   array[0..3] of AnsiChar;
    ChunkSize: Cardinal;
  end;

  TWaveFormat = packed record
    AudioFormat:   Word;
    NumChannels:   Word;
    SampleRate:    Cardinal;
    ByteRate:      Cardinal;
    BlockAlign:    Word;
    BitsPerSample: Word;
  end;
  {$ENDREGION}

  TWav = class
  public
    class function LoadEmbed(const AFileName: String; out AData: TBytes; AVerbose: Boolean = False; AErrors: TStrings = nil): Boolean;
  end;

implementation

class function TWav.LoadEmbed(const AFileName: String; out AData: TBytes; AVerbose: Boolean; AErrors: TStrings): Boolean;
var
  FileHandle: THandle;
  BytesRead:  Cardinal;

  RIFF:   TRIFFHeader;
  Chunk:  TChunkHeader;
  Format: TWaveFormat;

  RawData:  PByte;
  DataSize: Cardinal;

  SampleCount: Integer;
  Samples:     PSmallInt;
begin
  Result := False;

  FileHandle := CreateFile(PChar(AFileName), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);

  if FileHandle = INVALID_HANDLE_VALUE then
  begin
      if Assigned(AErrors) then
        AErrors.Add('Failed to open WAV file: ' + AFileName);

    Exit;
  end;

  try
    ReadFile(FileHandle, RIFF, SizeOf(TRIFFHeader), BytesRead, nil);

    if (RIFF.ChunkID <> 'RIFF') or (RIFF.Format <> 'WAVE') then
    begin
      if Assigned(AErrors) then
        AErrors.Add('File is not a valid RIFF/WAVE: ' + AFileName);

      Exit;
    end;

    DataSize := 0;
    RawData  := nil;

    while ReadFile(FileHandle, Chunk, SizeOf(TChunkHeader), BytesRead, nil) and (BytesRead = SizeOf(TChunkHeader)) do
    begin
      if Chunk.ChunkID = 'fmt ' then
      begin
        ReadFile(FileHandle, Format, SizeOf(TWaveFormat), BytesRead, nil);

        if Chunk.ChunkSize > SizeOf(TWaveFormat) then
          SetFilePointer(FileHandle, Chunk.ChunkSize - SizeOf(TWaveFormat), nil, FILE_CURRENT);
      end
      else if Chunk.ChunkID = 'data' then
      begin
        DataSize := Chunk.ChunkSize;
        GetMem(RawData, DataSize);
        ReadFile(FileHandle, RawData^, DataSize, BytesRead, nil);

        Break;
      end
      else
        SetFilePointer(FileHandle, Chunk.ChunkSize, nil, FILE_CURRENT);
    end;

    if RawData = nil then
    begin
      if Assigned(AErrors) then
        AErrors.Add('No audio data found in WAV: ' + AFileName);

      Exit;
    end;

    try
      if Format.BitsPerSample = 16 then
      begin
        SampleCount := DataSize div 2;

        if Format.NumChannels = 2 then
          SampleCount := SampleCount div 2;

        SetLength(AData, SampleCount * 2);
        Samples := @AData[0];

        var P16: PSmallInt := PSmallInt(RawData);

        for var i := 0 to SampleCount - 1 do
        begin
          if Format.NumChannels = 1 then
          begin
            Samples[i] := P16^;
            Inc(P16);
          end
          else
          begin
            var Left  := P16^; Inc(P16);
            var Right := P16^; Inc(P16);

            Samples[i] := SmallInt(Integer(Left + Right) div 2);
          end;
        end;
      end
      else if Format.BitsPerSample = 8 then
      begin
        SampleCount := DataSize;

        if Format.NumChannels = 2 then
          SampleCount := SampleCount div 2;

        SetLength(AData, SampleCount * SizeOf(SmallInt));
        Samples := @AData[0];

        var P8: PByte := RawData;

        for var i := 0 to SampleCount - 1 do
        begin
          if Format.NumChannels = 1 then
          begin
            Samples[i] := SmallInt((Integer(P8^) - 128) shl 8);
            Inc(P8);
          end
          else
          begin
            var Left:  SmallInt := SmallInt((Integer(P8^) - 128) shl 8); Inc(P8);
            var Right: SmallInt := SmallInt((Integer(P8^) - 128) shl 8); Inc(P8);

            Samples[i] := SmallInt(Integer(Left + Right) div 2);
          end;
        end;
      end
      else
      begin
        if Assigned(AErrors) then
          AErrors.Add('Unsupported BitsPerSample in WAV: ' + AFileName);

        Exit;
      end;
    finally
      FreeMem(RawData);
    end;
  finally
    CloseHandle(FileHandle);
  end;

  if AVerbose then
    Writeln('[asset:wav] "', ExtractFileName(AFileName), '" ', Format.SampleRate, 'Hz, 16-bit, mono, ', SampleCount, ' samples (', Length(AData), ' bytes)');

  Result := True;
end;

end.
