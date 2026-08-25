{
  NixVM.Core.Memory.pas
    System memory/heap/stack

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

unit NixVM.Core.Memory;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  NixVM.Core.Registers,
  NixVM.Core.System;

type
  TString = type Cardinal;

  {$REGION 'CustomMemory'}
  TCustomMemory = class
  private
    FData: Pointer;
    FSize: Cardinal;
    FMask: Cardinal;
  public
    constructor Create(ASize: Cardinal = 0);
    destructor  Destroy; override;

    procedure Resize(ASize: Cardinal);

    procedure Reset; virtual;

    procedure Fill(AAddress, ASize: Cardinal; AValue: Byte); inline;
    procedure Copy(ASource, ADest, ASize: Cardinal);         inline;
    function  Compare(ALeft, ARight, ASize: Cardinal): Integer;

    function ReadByte    (AAddress: Cardinal): Byte;     inline;
    function ReadWord    (AAddress: Cardinal): Word;     inline;
    function ReadDWord   (AAddress: Cardinal): Cardinal; inline;
    function ReadShortInt(AAddress: Cardinal): ShortInt; inline;
    function ReadSmallInt(AAddress: Cardinal): SmallInt; inline;
    function ReadInteger (AAddress: Cardinal): Integer;  inline;
    function ReadSingle  (AAddress: Cardinal): Single;   inline;

    procedure WriteByte    (AAddress: Cardinal; AValue: Byte);     inline;
    procedure WriteWord    (AAddress: Cardinal; AValue: Word);     inline;
    procedure WriteDWord   (AAddress: Cardinal; AValue: Cardinal); inline;
    procedure WriteShortInt(AAddress: Cardinal; AValue: ShortInt); inline;
    procedure WriteSmallInt(AAddress: Cardinal; AValue: SmallInt); inline;
    procedure WriteInteger (AAddress: Cardinal; AValue: Integer);  inline;
    procedure WriteSingle  (AAddress: Cardinal; AValue: Single);   inline;

    function  ReadString (AAddress: Cardinal): AnsiString;
    procedure WriteString(AAddress: Cardinal; const AString: AnsiString);

    function ReadData (AAddress: Cardinal; var   AData; ASize: Cardinal): Cardinal;
    function WriteData(AAddress: Cardinal; const AData; ASize: Cardinal): Cardinal;

    function AddressToPointer(AAddress: Cardinal): Pointer; inline;

    function GetSpan(AAddress, ARequiredSize: Cardinal): Pointer; inline;

    property Data: Pointer  read FData;
    property Size: Cardinal read FSize;
    property Mask: Cardinal read FMask;

    property Bytes    [AAddress: Cardinal]: Byte     read ReadByte     write WriteByte;
    property Words    [AAddress: Cardinal]: Word     read ReadWord     write WriteWord;
    property DWords   [AAddress: Cardinal]: Cardinal read ReadDWord    write WriteDWord;
    property ShortInts[AAddress: Cardinal]: ShortInt read ReadShortInt write WriteShortInt;
    property SmallInts[AAddress: Cardinal]: SmallInt read ReadSmallInt write WriteSmallInt;
    property Integers [AAddress: Cardinal]: Integer  read ReadInteger  write WriteInteger;
    property Singles  [AAddress: Cardinal]: Single   read ReadSingle   write WriteSingle;

    property Ptr[AAddress: Cardinal]: Pointer read AddressToPointer; default;
  end;
  {$ENDREGION}

  {$REGION 'Heap'}
  THeap = class
  type
    TBlock = record
      Address:     Cardinal;
      AlignedSize: Cardinal;
      Size:        Cardinal;
      IsFree:      Boolean;
    end;

    TBlocks = array of TBlock;

    {$REGION 'StringManager'}
    TStringManager = class
    type
      TFormatArgs = array[0..15] of Cardinal;
    private
      FHeap: THeap;
    public
      constructor Create(AHeap: THeap);

      function Format(AFormat: AnsiString; const AArgs: TFormatArgs; AArgsStart: Integer = 0): AnsiString; overload;

      function  New(ALength: Integer): TString; overload;
      function  New(const AString: AnsiString): TString; overload;
      procedure Dispose(AString: TString);
      function  Length(AString: TString): Integer;
      function  Concat(ALeft, ARight: TString): TString;
      function  Copy(AString: TString; AStart, ACount: Integer): TString;
      function  Compare(ALeft, ARight: TString): Integer;
      function  Format(AString: TString; const AArgs: TFormatArgs; AArgsStart: Integer = 0): TString; overload;

      property Heap: THeap read FHeap;
    end;
    {$ENDREGION}
  private
    FMemory:  TCustomMemory;
    FBlocks:  TBlocks;
    FStrings: TStringManager;

    FAddress: Cardinal;
    FSize:    Cardinal;
  protected
    procedure Initialize(AAddress, ASize: Cardinal);
  public
    constructor Create(const AMemory: TCustomMemory; AAddress, ASize: Cardinal);
    destructor  Destroy; override;

    procedure Reset;

    function  Alloc(ASize: Cardinal): Cardinal;
    function  Realloc(AAddress, ANewSize: Cardinal): Cardinal;
    procedure Dealloc(AAddress: Cardinal);
    function  GetSize(AAddress: Cardinal): Cardinal;
    function  GetAvailable: Cardinal;

    property Memory:  TCustomMemory  read FMemory;
    property Strings: TStringManager read FStrings;

    property Address: Cardinal read FAddress;
    property Size:    Cardinal read FSize;
  end;
  {$ENDREGION}

  {$REGION 'Stack'}
  TStack = class
  private
    FMemory: TCustomMemory;

    FAddress: Cardinal;
    FSize:    Cardinal;
  protected
    procedure Initialize(AAddress, ASize: Cardinal);
  public
    constructor Create(const AMemory: TCustomMemory; AAddress, ASize: Cardinal);

    procedure Reset;

    property Memory: TCustomMemory read FMemory;

    property Address: Cardinal read FAddress;
    property Size:    Cardinal read FSize;
  end;
  {$ENDREGION}

  TArgs = array of Cardinal;

  {$REGION 'Memory'}
  TMemory = class(TCustomMemory)
  private
    FHeap:  THeap;
    FStack: TStack;

    FCoreSystemMemory: PCoreSystemMemory;

    FUserAddress: Cardinal;
    FUserSize:    Cardinal;
  protected
    procedure InitSystemMemoryPointers;      virtual;
    function  GetSystemMemorySize: Cardinal; virtual;
  public
    constructor Create(AUserSize, AHeapSize, AStackSize: Cardinal);
    destructor  Destroy; override;

    procedure Resize(AUserSize, AHeapSize, AStackSize: Cardinal); reintroduce;

    procedure Reset; override;

    function IsAddressExecutable(AAddress: Cardinal): Boolean; inline;

    function  HeapAlloc(ASize: Cardinal): Cardinal; inline;
    function  HeapRealloc(AAddress, ANewSize: Cardinal): Cardinal; inline;
    procedure HeapFree(AAddress: Cardinal); inline;
    function  HeapSize(AAddress: Cardinal): Cardinal; inline;
    function  HeapAvailable: Cardinal; inline;

    function  StringNew(ALength: Cardinal): TString; overload; inline;
    function  StringNew(const AString: AnsiString): TString; overload; inline;
    procedure StringDispose(AString: TString); inline;
    function  StringLength(AString: TString): Integer; inline;
    function  StringConcat(ALeft, ARight: TString): TString; inline;
    function  StringCopy(AString: TString; AStart, ACount: Integer): TString; inline;
    function  StringCompare(ALeft, ARight: TString): Integer; inline;
    function  StringFormat(AString: TString; AArgs: THeap.TStringManager.TFormatArgs; AArgsStart: Integer = 0): TString; inline;


    property Heap:  THeap  read FHeap;
    property Stack: TStack read FStack;

    property CoreSystem: PCoreSystemMemory read FCoreSystemMemory;

    property UserAddress: Cardinal read FUserAddress;
    property UserSize:    Cardinal read FUserSize;
  end;
  {$ENDREGION}

  {$REGION 'TMemory<TSystemMemory>'}
  TMemory<TSystemMemory: record> = class(TMemory)
  type
    PSystemMemory = ^TSystemMemory;
  private
    FSystemMemory: PSystemMemory;

    FSystemAddress: Cardinal;
    FSystemSize:    Cardinal;
  protected
    procedure InitSystemMemoryPointers;      override;
    function  GetSystemMemorySize: Cardinal; override;
  public
    procedure Reset; override;

    property System: PSystemMemory read FSystemMemory;

    property SystemAddress: Cardinal read FSystemAddress;
    property SystemSize:    Cardinal read FSystemSize;
  end;
  {$ENDREGION}

implementation

uses
  NixVM.Core.Strings;

{$REGION 'CustomMemory'}
constructor TCustomMemory.Create(ASize: Cardinal);
begin
  inherited Create;

  if ASize > 0 then
    Resize(ASize);
end;

destructor TCustomMemory.Destroy;
begin
  Resize(0);

  inherited;
end;

procedure TCustomMemory.Resize(ASize: Cardinal);
const
  SafetyPadding = 16;

  function NextPowerOfTwo(AValue: Cardinal): Cardinal; inline;
  begin
    if AValue <= 1 then
      Exit(1);

    Dec(AValue);
    AValue := AValue or (AValue shr  1);
    AValue := AValue or (AValue shr  2);
    AValue := AValue or (AValue shr  4);
    AValue := AValue or (AValue shr  8);
    AValue := AValue or (AValue shr 16);
    Result := AValue + 1;
  end;
begin
  if ASize = 0 then
  begin
    if Assigned(FData) then
    begin
      FreeMemory(FData);
      FData := nil;
    end;

    FSize := 0;
    FMask := 0;

    Exit;
  end;

  ASize := NextPowerOfTwo(ASize);

  if ASize = FSize then
    Exit;

  if not Assigned(FData) then
    FData := GetMemory(ASize + SafetyPadding)
  else
    FData := ReallocMemory(FData, ASize + SafetyPadding);

  if Assigned(FData) then
  begin
    if ASize > FSize then
      FillChar(Pointer(NativeUInt(FData) + FSize)^, (ASize - FSize) + SafetyPadding, 0);

    FSize := ASize;
    FMask := ASize - 1;
  end
  else
  begin
    // TODO: Error / Out of memory
  end;
end;

procedure TCustomMemory.Reset;
begin

end;

procedure TCustomMemory.Fill(AAddress, ASize: Cardinal; AValue: Byte);
begin
  if (AAddress >= FSize) or (ASize = 0) then
    Exit;

  if ASize > FSize - AAddress then
    ASize := FSize - AAddress;

  FillChar(AddressToPointer(AAddress)^, ASize, AValue);
end;

procedure TCustomMemory.Copy(ASource, ADest, ASize: Cardinal);
begin
  if (ASource >= FSize) or (ADest >= FSize) or (ASize = 0) then
    Exit;

  if ASize > FSize - ASource then
    ASize := FSize - ASource;

  if ASize > FSize - ADest then
    ASize := FSize - ADest;

  Move(AddressToPointer(ASource)^, AddressToPointer(ADest)^, ASize);
end;

{$IF DEFINED(MSWINDOWS)}
function memcmp(Buf1, Buf2: Pointer; Count: NativeUInt): Integer; cdecl; external 'ntdll.dll';
{$ENDIF}

function TCustomMemory.Compare(ALeft, ARight, ASize: Cardinal): Integer;
begin
  if (ALeft >= FSize) or (ARight >= FSize) or (ASize = 0) then
    Exit(0);

  if ASize > FSize - ALeft then
    ASize := FSize - ALeft;

  if ASize > FSize - ARight then
    ASize := FSize - ARight;

{$IF DEFINED(MSWINDOWS)}
  Result := memcmp(AddressToPointer(ALeft), AddressToPointer(ARight), ASize);
{$ELSE}
  var L: PByte := AddressToPointer(ALeft);
  var R: PByte := AddressToPointer(ARight);

  while ASize >= SizeOf(Cardinal) do
  begin
    if PCardinal(L)^ <> PCardinal(R)^ then
      Break;

    Inc(L, SizeOf(Cardinal));
    Inc(R, SizeOf(Cardinal));

    Dec(ASize, SizeOf(Cardinal));
  end;

  while ASize > 0 do
  begin
    Result := L^ - R^;

    if Result <> 0 then
      Exit;

    Inc(L);
    Inc(R);

    Dec(ASize);
  end;

  Result := 0;
{$ENDIF}
end;

function TCustomMemory.ReadByte(AAddress: Cardinal): Byte;
begin
  Result := PByte(AddressToPointer(AAddress))^;
end;

function TCustomMemory.ReadWord(AAddress: Cardinal): Word;
begin
  Result := PWord(AddressToPointer(AAddress))^;
end;

function TCustomMemory.ReadDWord(AAddress: Cardinal): Cardinal;
begin
  Result := PCardinal(AddressToPointer(AAddress))^;
end;

function TCustomMemory.ReadShortInt(AAddress: Cardinal): ShortInt;
begin
  Result := PShortInt(AddressToPointer(AAddress))^;
end;

function TCustomMemory.ReadSmallInt(AAddress: Cardinal): SmallInt;
begin
  Result := PSmallInt(AddressToPointer(AAddress))^;
end;

function TCustomMemory.ReadInteger(AAddress: Cardinal): Integer;
begin
  Result := PInteger(AddressToPointer(AAddress))^;
end;

function TCustomMemory.ReadSingle(AAddress: Cardinal): Single;
begin
  Result := PSingle(AddressToPointer(AAddress))^;
end;

function TCustomMemory.ReadString(AAddress: Cardinal): AnsiString;
var
  Offset: Cardinal;
  Start:  PAnsiChar;
  Limit:  PAnsiChar;
  Curr:   PAnsiChar;

begin
  Offset := AAddress and FMask;
  Start := PAnsiChar(NativeUInt(FData) + Offset);
  Limit := PAnsiChar(NativeUInt(FData) + FSize);
  Curr  := Start;

  while (Curr < Limit) and (Curr^ <> #0) do
    Inc(Curr);

  SetString(Result, Start, Curr - Start);
end;

procedure TCustomMemory.WriteString(AAddress: Cardinal; const AString: AnsiString);
var
  Offset:   Cardinal;
  MaxBytes: Cardinal;
  Len:      Cardinal;
  Dest:     PAnsiChar;
begin
  Offset   := AAddress and FMask;
  MaxBytes := FSize - Offset;

  if MaxBytes = 0 then
    Exit;

  Len := System.Length(AString);

  if Len >= MaxBytes then
    Len := MaxBytes - 1;

  Dest := PAnsiChar(NativeUInt(FData) + Offset);

  if Len > 0 then
    Move(PAnsiChar(AString)^, Dest^, Len);

  PAnsiChar(Dest + Len)^ := #0;
end;

function TCustomMemory.ReadData(AAddress: Cardinal; var AData; ASize: Cardinal): Cardinal;
var
  Offset: Cardinal;
begin
  if ASize = 0 then
    Exit(0);

  Offset := AAddress and FMask;
  Result := ASize;

  if Offset + Result > FSize then
    Result := FSize - Offset;

  Move(Pointer(NativeUInt(FData) + Offset)^, AData, Result);
end;

function TCustomMemory.WriteData(AAddress: Cardinal; const AData; ASize: Cardinal): Cardinal;
var
  Offset: Cardinal;
begin
  if ASize = 0 then
    Exit(0);

  Offset := AAddress and FMask;
  Result := ASize;

  if Offset + Result > FSize then
    Result := FSize - Offset;

  Move(AData, Pointer(NativeUInt(FData) + Offset)^, Result);
end;

procedure TCustomMemory.WriteByte(AAddress: Cardinal; AValue: Byte);
begin
  PByte(AddressToPointer(AAddress))^ := AValue;
end;

procedure TCustomMemory.WriteWord(AAddress: Cardinal; AValue: Word);
begin
  PWord(AddressToPointer(AAddress))^ := AValue;
end;

procedure TCustomMemory.WriteDWord(AAddress: Cardinal; AValue: Cardinal);
begin
  PCardinal(AddressToPointer(AAddress))^ := AValue;
end;

procedure TCustomMemory.WriteShortInt(AAddress: Cardinal; AValue: ShortInt);
begin
  PShortInt(AddressToPointer(AAddress))^ := AValue;
end;

procedure TCustomMemory.WriteSmallInt(AAddress: Cardinal; AValue: SmallInt);
begin
  PSmallInt(AddressToPointer(AAddress))^ := AValue;
end;

procedure TCustomMemory.WriteInteger(AAddress: Cardinal; AValue: Integer);
begin
  PInteger(AddressToPointer(AAddress))^ := AValue;
end;

procedure TCustomMemory.WriteSingle(AAddress: Cardinal; AValue: Single);
begin
  PSingle(AddressToPointer(AAddress))^ := AValue;
end;

function TCustomMemory.AddressToPointer(AAddress: Cardinal): Pointer;
begin
  Result := Pointer(NativeUInt(FData) + (AAddress and FMask));
end;

function TCustomMemory.GetSpan(AAddress, ARequiredSize: Cardinal): Pointer;
begin
  if (AAddress and FMask) + ARequiredSize > FSize then
    Exit(nil);

  Result := AddressToPointer(AAddress);
end;
{$ENDREGION}

{$REGION 'Heap'}
{$REGION 'StringManager'}
constructor THeap.TStringManager.Create(AHeap: THeap);
begin
  inherited Create;

  FHeap := AHeap;
end;

function THeap.TStringManager.Format(AFormat: AnsiString; const AArgs: TFormatArgs; AArgsStart: Integer = 0): AnsiString;
var
  ArgIdx: Integer;
  i:      Integer;
  C:      AnsiChar;
begin
  Result := '';
  ArgIdx := AArgsStart;
  i      := 1;

  while i <= System.Length(AFormat) do
  begin
    C := AFormat[i];

    if (C = '%') and (i + 1 <= System.Length(AFormat)) then
    begin
      Inc(i);

      var Spec := AFormat[i];

      case Spec of
        '%': Result := Result + '%';

        'd', 'i':
        begin
          if ArgIdx < System.Length(AArgs) then
          begin
            Result := Result + AnsiString(IntToStr(Integer(AArgs[ArgIdx])));
            Inc(ArgIdx);
          end;
        end;

        'u':
        begin
          if ArgIdx < System.Length(AArgs) then
          begin
            Result := Result + AnsiString(IntToStr(AArgs[ArgIdx]));
            Inc(ArgIdx);
          end;
        end;

        'x':
        begin
          if ArgIdx < System.Length(AArgs) then
          begin
            Result := Result + AnsiString(IntToHex(AArgs[ArgIdx], 0));
            Inc(ArgIdx);
          end;
        end;

        'X':
        begin
          if ArgIdx < System.Length(AArgs) then
          begin
            Result := Result + AnsiString(IntToHex(AArgs[ArgIdx], 8));
            Inc(ArgIdx);
          end;
        end;

        's':
        begin
          if ArgIdx < System.Length(AArgs) then
          begin
            Result := Result + FHeap.FMemory.ReadString(AArgs[ArgIdx]);
            Inc(ArgIdx);
          end;
        end;

        'f', 'F':
        begin
          if ArgIdx < System.Length(AArgs) then
          begin
            Result := Result + AnsiString(FloatToStr(PSingle(@AArgs[ArgIdx])^, 7, Spec = 'f'));
            Inc(ArgIdx);
          end;
        end;

        'c':
        begin
          if ArgIdx < System.Length(AArgs) then
          begin
            Result := Result + AnsiChar(AArgs[ArgIdx] and $FF);
            Inc(ArgIdx);
          end;
        end;
      else
        Result := Result + '%' + Spec;
      end;
    end
    else
      Result := Result + AnsiString(C);

    Inc(i);
  end;
end;

function THeap.TStringManager.New(ALength: Integer): TString;
begin
  if ALength < 0 then
    Exit(0);

  Result := FHeap.Alloc(ALength + 5);

  if Result = 0 then
    Exit;

  FHeap.Memory.WriteDWord(Result, ALength);
  FHeap.Memory.WriteByte (Result + 4 + Cardinal(ALength), 0);

  Inc(Result, 4);
end;

function THeap.TStringManager.New(const AString: AnsiString): TString;
var
  Len: Integer;
begin
  Len    := System.Length(AString);
  Result := New(Len);

  if (Result <> 0) and (Len > 0) then
    FHeap.Memory.WriteData(Result, AString[1], Len);
end;

procedure THeap.TStringManager.Dispose(AString: TString);
begin
  if AString >= 4 then
    if (AString >= FHeap.Address) and (AString < (FHeap.Address + FHeap.Size)) then
      FHeap.Dealloc(AString - 4);
end;

function THeap.TStringManager.Length(AString: TString): Integer;
begin
  if AString = 0 then
    Exit(0);

  if (AString >= FHeap.Address) and (AString < (FHeap.Address + FHeap.Size)) then
    Exit(FHeap.Memory.ReadDWord(AString - 4));

  Result := System.Length(FHeap.Memory.ReadString(AString));
end;

function THeap.TStringManager.Concat(ALeft, ARight: TString): TString;
var
  S:   AnsiString;
  Len: Integer;
begin
  S   := FHeap.Memory.ReadString(ALeft) + FHeap.Memory.ReadString(ARight);
  Len := System.Length(s);

  Result := New(Len);

  if (Result <> 0) and (Len > 0) then
    FHeap.Memory.WriteData(Result, S[1], Len);
end;

function THeap.TStringManager.Copy(AString: TString; AStart, ACount: Integer): TString;
var
  S: AnsiString;
  Len:  Integer;
begin
  S   := System.Copy(FHeap.Memory.ReadString(AString), AStart, ACount);
  Len := System.Length(S);

  Result := New(Len);

  if (Result <> 0) and (Len > 0) then
    FHeap.Memory.WriteData(Result, S[1], Len);
end;

function THeap.TStringManager.Compare(ALeft, ARight: TString): Integer;
var
  L, R: AnsiString;
begin
  L := FHeap.Memory.ReadString(ALeft);
  R := FHeap.Memory.ReadString(ARight);

  if L < R then
    Result := -1
  else if L > R then
    Result := 1
  else
    Result := 0;
end;

function THeap.TStringManager.Format(AString: TString; const AArgs: TFormatArgs; AArgsStart: Integer = 0): TString;
begin
  Result := New(Format(FHeap.FMemory.ReadString(AString), AArgs, AArgsStart));
end;
{$ENDREGION}

procedure THeap.Initialize(AAddress, ASize: Cardinal);
begin
  FAddress := AAddress;
  FSize    := ASize;

  Reset;
end;

constructor THeap.Create(const AMemory: TCustomMemory; AAddress, ASize: Cardinal);
begin
  inherited Create;

  FMemory  := AMemory;
  FStrings := TStringManager.Create(Self);

  Initialize(AAddress, ASize);
end;

destructor THeap.Destroy;
begin
  FStrings.Free;

  inherited;
end;

procedure THeap.Reset;
begin
  SetLength(FBlocks, 1);

  FBlocks[0].Address     := FAddress;
  FBlocks[0].AlignedSize := FSize;
  FBlocks[0].IsFree      := True;

  if FSize > 0 then
    FillChar(FMemory[FAddress]^, FSize, 0);
end;

function THeap.Alloc(ASize: Cardinal): Cardinal;
var
  AllocSize: Cardinal;
  LeftOver:  Cardinal;
begin
  if ASize = 0 then
    Exit(0);

  AllocSize := (ASize + 3) and $FFFFFFFC;

  for var i := 0 to High(FBlocks) do
  begin
    if FBlocks[i].IsFree and (FBlocks[i].AlignedSize >= AllocSize) then
    begin
      LeftOver := FBlocks[i].AlignedSize - AllocSize;

      if LeftOver > 0 then
      begin
        Insert(Default(TBlock), FBlocks, i + 1);

        FBlocks[i + 1].Address     := FBlocks[i].Address + AllocSize;
        FBlocks[i + 1].AlignedSize := LeftOver;
        FBlocks[i + 1].IsFree      := True;
      end;

      FBlocks[i].AlignedSize := AllocSize;
      FBlocks[i].IsFree      := False;
      FBlocks[i].Size        := ASize;

      Exit(FBlocks[i].Address);
    end;
  end;

  // TODO: Error / Out of memory
  Result := 0;
end;

function THeap.Realloc(AAddress, ANewSize: Cardinal): Cardinal;
var
  AllocSize: Cardinal;
  LeftOver:  Cardinal;
begin
  if AAddress = 0 then
    Exit(Alloc(ANewSize));

  if ANewSize = 0 then
  begin
    Dealloc(AAddress);
    Exit(0);
  end;

  AllocSize := (ANewSize + 3) and $FFFFFFFC;

  for var i := 0 to High(FBlocks) do
  begin
    if (FBlocks[i].Address = AAddress) and (not FBlocks[i].IsFree) then
    begin
      if FBlocks[i].AlignedSize >= AllocSize then
      begin
        FBlocks[i].Size := ANewSize;
        Exit(AAddress);
      end;

      if (i < High(FBlocks)) and FBlocks[i + 1].IsFree and ((FBlocks[i].AlignedSize + FBlocks[i + 1].AlignedSize) >= AllocSize) then
      begin
        LeftOver := (FBlocks[i].AlignedSize + FBlocks[i + 1].AlignedSize) - AllocSize;
        FBlocks[i].AlignedSize := AllocSize;
        FBlocks[i].Size        := ANewSize;

        if LeftOver > 0 then
        begin
          FBlocks[i + 1].Address     := FBlocks[i].Address + AllocSize;
          FBlocks[i + 1].AlignedSize := LeftOver;
          FBlocks[i + 1].IsFree      := True;
        end
        else
          Delete(FBlocks, i + 1, 1);

        Exit(AAddress);
      end;

      LeftOver := FBlocks[i].Size;
      Result   := Alloc(ANewSize);

      if Result <> 0 then
      begin
        if LeftOver > ANewSize then
          LeftOver := ANewSize;

        FMemory.Copy(AAddress, Result, LeftOver);
        Dealloc(AAddress);
      end;

      Exit;
    end;
  end;

  Result := Alloc(ANewSize);
end;

procedure THeap.Dealloc(AAddress: Cardinal);
begin
  if AAddress = 0 then
    Exit;

  for var i := 0 to High(FBlocks) do
  begin
    if FBlocks[i].Address = AAddress then
    begin
      if FBlocks[i].IsFree then
        Exit;

      FMemory.Fill(FBlocks[i].Address, FBlocks[i].AlignedSize, 0);

      FBlocks[i].IsFree := True;

      while (i < High(FBlocks)) and FBlocks[i + 1].IsFree do
      begin
        FBlocks[i].AlignedSize := FBlocks[i].AlignedSize + FBlocks[i + 1].AlignedSize;
        Delete(FBlocks, i + 1, 1);
      end;

      if (i > 0) and FBlocks[i - 1].IsFree then
      begin
        FBlocks[i - 1].AlignedSize := FBlocks[i - 1].AlignedSize + FBlocks[i].AlignedSize;
        Delete(FBlocks, i, 1);
      end;

      Exit;
    end;
  end;

  // TODO: Invalid address
end;

function THeap.GetSize(AAddress: Cardinal): Cardinal;
begin
  for var i := 0 to High(FBlocks) do
    if FBlocks[i].Address = AAddress then
      Exit(FBlocks[i].Size);

  Result := 0;
end;

function THeap.GetAvailable: Cardinal;
begin
  Result := 0;

  for var i := 0 to High(FBlocks) do
    if FBlocks[i].IsFree then
      Inc(Result, FBlocks[i].AlignedSize);
end;
{$ENDREGION}

{$REGION 'Stack'}
procedure TStack.Initialize(AAddress, ASize: Cardinal);
begin
  FAddress := AAddress;
  FSize    := ASize;

  Reset;
end;

constructor TStack.Create(const AMemory: TCustomMemory; AAddress, ASize: Cardinal);
begin
  inherited Create;

  FMemory := AMemory;

  Initialize(AAddress, ASize);
end;

procedure TStack.Reset;
begin

end;
{$ENDREGION}

{$REGION 'Memory'}
procedure TMemory.InitSystemMemoryPointers;
begin
  FCoreSystemMemory := FData;
end;

function TMemory.GetSystemMemorySize: Cardinal;
begin
  Result := 0;
end;

constructor TMemory.Create(AUserSize, AHeapSize, AStackSize: Cardinal);
begin
  inherited Create(0);

  Resize(AUserSize, AHeapSize, AStackSize);
end;

destructor TMemory.Destroy;
begin
  if Assigned(FHeap) then
    FHeap.Free;

  if Assigned(FStack) then
    FStack.Free;

  inherited;
end;

procedure TMemory.Resize(AUserSize, AHeapSize, AStackSize: Cardinal);
var
  HeapAddress: Cardinal;
begin
  FUserAddress := (SizeOf(TCoreSystemMemory) + GetSystemMemorySize + 3) and not Cardinal(3);
  FUserSize    := (AUserSize                                       + 3) and not Cardinal(3);
  AHeapSize    := (AHeapSize                                       + 3) and not Cardinal(3);
  AStackSize   := (AStackSize                                      + 3) and not Cardinal(3);

  inherited Resize(FUserAddress + FUserSize + AHeapSize + AStackSize);

  InitSystemMemoryPointers;

  HeapAddress := FUserAddress + FUserSize;

  if FSize > (HeapAddress + AStackSize) then
    AHeapSize := FSize - HeapAddress - AStackSize;

  if not Assigned(FHeap) then
    FHeap := THeap.Create(Self, HeapAddress, AHeapSize)
  else
    FHeap.Initialize(HeapAddress, AHeapSize);

  if not Assigned(FStack) then
    FStack := TStack.Create(Self, FSize, AStackSize)
  else
    FStack.Initialize(FSize, AStackSize);
end;

procedure TMemory.Reset;
begin
  inherited;

  if Assigned(FCoreSystemMemory) then
    FCoreSystemMemory.Reset;

  // Removed - Don't clear the user data on reset (soft reset)
  //if FUserSize > 0 then
  //  Fill(FUserAddress, FUserSize, 0);

  if Assigned(FHeap) then
    FHeap.Reset;

  if Assigned(FStack) then
    FStack.Reset;

  FCoreSystemMemory.MemoryMap.OEMAddress := SizeOf(TCoreSystemMemory);
  FCoreSystemMemory.MemoryMap.OEMSize    := 0;

  FCoreSystemMemory.MemoryMap.UserAddress := FUserAddress;
  FCoreSystemMemory.MemoryMap.UserSize    := FUserSize;

  FCoreSystemMemory.MemoryMap.HeapAddress := FHeap.Address;
  FCoreSystemMemory.MemoryMap.HeapSize    := FHeap.Size;

  FCoreSystemMemory.MemoryMap.StackAddress := FStack.Address - FStack.Size;
  FCoreSystemMemory.MemoryMap.StackSize    := FStack.Size;
end;

function TMemory.IsAddressExecutable(AAddress: Cardinal): Boolean;
begin
  Result := (AAddress >= FUserAddress) and (AAddress < (FHeap.Address + FHeap.Size));
end;

function TMemory.HeapAlloc(ASize: Cardinal): Cardinal;
begin
  Result := FHeap.Alloc(ASize);
end;

function TMemory.HeapRealloc(AAddress, ANewSize: Cardinal): Cardinal;
begin
  Result := FHeap.Realloc(AAddress, ANewSize);
end;

procedure TMemory.HeapFree(AAddress: Cardinal);
begin
  FHeap.Dealloc(AAddress);
end;

function TMemory.HeapSize(AAddress: Cardinal): Cardinal;
begin
  Result := FHeap.GetSize(AAddress);
end;

function TMemory.HeapAvailable: Cardinal;
begin
  Result := FHeap.GetAvailable;
end;

function TMemory.StringNew(ALength: Cardinal): TString;
begin
  Result := FHeap.Strings.New(ALength);
end;

function TMemory.StringNew(const AString: AnsiString): TString;
begin
  Result := FHeap.Strings.New(AString);
end;

procedure TMemory.StringDispose(AString: TString);
begin
  FHeap.Strings.Dispose(AString);
end;

function TMemory.StringLength(AString: TString): Integer;
begin
  Result := FHeap.Strings.Length(AString);
end;

function TMemory.StringConcat(ALeft, ARight: TString): TString;
begin
  Result := FHeap.Strings.Concat(ALeft, ARight);
end;

function TMemory.StringCopy(AString: TString; AStart, ACount: Integer): TString;
begin
  Result := FHeap.Strings.Copy(AString, AStart, ACount);
end;

function TMemory.StringCompare(ALeft, ARight: TString): Integer;
begin
  Result := FHeap.Strings.Compare(ALeft, ARight);
end;

function TMemory.StringFormat(AString: TString; AArgs: THeap.TStringManager.TFormatArgs; AArgsStart: Integer): TString;
begin
  Result := FHeap.Strings.Format(AString, AArgs, AArgsStart);
end;

{$ENDREGION}

{$REGION 'TMemory<TSystemMemory>'}
procedure TMemory<TSystemMemory>.InitSystemMemoryPointers;
begin
  inherited;

  FSystemAddress := SizeOf(TCoreSystemMemory);
  FSystemSize    := SizeOf(TSystemMemory);

  FSystemMemory := PSystemMemory(NativeUInt(FCoreSystemMemory) + SizeOf(TCoreSystemMemory));
end;

function TMemory<TSystemMemory>.GetSystemMemorySize: Cardinal;
begin
  Result := SizeOf(TSystemMemory);
end;

procedure TMemory<TSystemMemory>.Reset;
begin
  inherited;

  FCoreSystemMemory.MemoryMap.OEMSize := SizeOf(TSystemMemory);
end;
{$ENDREGION}

end.
