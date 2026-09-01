{
  NixVM.Tools.Compiler.pas
    Pascal compiler

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

unit NixVM.Tools.Compiler;

{$INCLUDE 'NixVM.Options.inc'}

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,

  NixVM.Core.ROM,
  NixVM.Core.Memory,
  NixVM.Core.System,

  NixVM.Tools.IR,

  NixVM.Tools.Compiler.Lexer,
  NixVM.Tools.Compiler.Parser,
  NixVM.Tools.Compiler.Semantics,
  NixVM.Tools.Compiler.AST,
  NixVM.Tools.Compiler.CodeGen,
  NixVM.Tools.Compiler.Optimiser;

type
  TGetUnitSource = function(const AUnitName: String; out ASource, AFileName: String): Boolean of object;

  {$REGION 'Compiler'}
  TCompiler = class
  private
    FIR:     TIRList;
    FErrors: TStrings;

    FSearchPaths:     TList<String>;
    FOnGetUnitSource: TGetUnitSource;
    FLoadedUnits:     TObjectDictionary<String, TASTUnit>;
    FCompileOrder:    TList<TASTUnit>;
    FLoadingStack:    TList<String>;

    FOptimise: Boolean;

    FSizeBeforeOpt: Integer;
    FSizeAfterOpt:  Integer;

    function  LoadUnitRecursive(const AUnitName: String): TASTUnit;
    function  ResolveUnitSource(const AUnitName: String; out ASource, AFilePath: String): Boolean;
  public
    ROMHeader: TROMHeader;

    constructor Create;
    destructor  Destroy; override;

    procedure AddPath(const APath: String);
    procedure AddDefaultSearchPaths;

    function Compile(const ASource: String; const AName: String = ''): Boolean;
    function CompileFile(const AFileName: String): Boolean;

    function Link(AMemory: TMemory;        AResize:     Boolean = True): Boolean; overload;
    function Link(AStream: TStream;        AWithHeader: Boolean = True): Boolean; overload;
    function Link(const AFileName: String; AWithHeader: Boolean = True): Boolean; overload;

    function ToAsmString: String;

    property IR:     TIRList  read FIR;
    property Errors: TStrings read FErrors;

    property SearchPaths:     TList<String>  read FSearchPaths;
    property OnGetUnitSource: TGetUnitSource read FOnGetUnitSource write FOnGetUnitSource;

    property Optimise: Boolean read FOptimise write FOptimise;

    property SizeBeforeOpt: Integer read FSizeBeforeOpt;
    property SizeAfterOpt:  Integer read FSizeAfterOpt;
  end;
  {$ENDREGION}

implementation

{$REGION 'Compiler'}
function TCompiler.ResolveUnitSource(const AUnitName: String; out ASource, AFilePath: String): Boolean;
begin
  ASource   := '';
  AFilePath := '';

  if Assigned(FOnGetUnitSource) and FOnGetUnitSource(AUnitName, ASource, AFilePath) then
    Exit(True);

  for var Path in FSearchPaths do
  begin
    var Candidate := TPath.Combine(Path, AUnitName + '.pas');

    if FileExists(Candidate) then
    begin
      ASource   := TFile.ReadAllText(Candidate);
      AFilePath := Candidate;

      Exit(True);
    end;
  end;

  Result := False;
end;

function TCompiler.LoadUnitRecursive(const AUnitName: String): TASTUnit;
var
  UnitKey:  String;
  Source:   String;
  FilePath: String;
begin
  UnitKey := LowerCase(AUnitName);

  if FLoadedUnits.TryGetValue(UnitKey, Result) then
    Exit;

  if FLoadingStack.IndexOf(UnitKey) >= 0 then
  begin
    FErrors.Add(Format('Circular unit dependency detected: "%s"', [AUnitName]));
    Exit(nil);
  end;

  if not ResolveUnitSource(AUnitName, Source, FilePath) then
  begin
    FErrors.Add(Format('Unit not found: "%s.pas"', [AUnitName]));
    Exit(nil);
  end;

  FLoadingStack.Add(UnitKey);
  try
    var Parser := TParser.Create(Source, FilePath, FErrors);
    try
      var UnitAST := Parser.ParseUnit;

      if (FErrors.Count > 0) or (UnitAST = nil) then
        Exit(nil);

      FLoadedUnits.Add(UnitKey, UnitAST);

      for var Dep in UnitAST.InterfaceUses do
        LoadUnitRecursive(Dep);

      for var Dep in UnitAST.ImplementationUses do
        LoadUnitRecursive(Dep);

      FCompileOrder.Add(UnitAST);
      Result := UnitAST;
    finally
      Parser.Free;
    end;
  finally
    FLoadingStack.Delete(FLoadingStack.IndexOf(UnitKey));
  end;
end;

constructor TCompiler.Create;
begin
  inherited;

  FErrors       := TStringList.Create;
  FSearchPaths  := TList<String>.Create;
  FLoadedUnits  := TObjectDictionary<String, TASTUnit>.Create;
  FCompileOrder := TList<TASTUnit>.Create;
  FLoadingStack := TList<String>.Create;

  ROMHeader.Reset;

  AddDefaultSearchPaths;

  FOptimise := True;
end;

destructor TCompiler.Destroy;
begin
  if Assigned(FIR) then
    FIR.Free;

  FErrors.Free;
  FSearchPaths.Free;
  FLoadedUnits.Free;
  FCompileOrder.Free;
  FLoadingStack.Free;

  inherited;
end;

procedure TCompiler.AddPath(const APath: String);
begin
  FSearchPaths.Add(APath);
end;

procedure TCompiler.AddDefaultSearchPaths;
begin
  AddPath('.\');
  AddPath('..\rtl\');
  AddPath(TPath.GetDirectoryName(ParamStr(0)) + '\..\rtl\');
  AddPath(TPath.GetDirectoryName(ParamStr(0)));
end;

function TCompiler.Compile(const ASource: String; const AName: String): Boolean;
var
  Parser:   TParser;
  Analyzer: TSemanticAnalyzer;
  CodeGen:  TCodeGenerator;
  ProgAST:  TASTProgram;
  Shaker:   TTreeShaker;
begin
  Result := False;

  FErrors.Clear;
  FLoadedUnits.Clear;
  FCompileOrder.Clear;
  FLoadingStack.Clear;

  Parser  := TParser.Create(ASource, AName, FErrors);
  ProgAST := Parser.ParseProgram;

  try
    if FErrors.Count > 0 then
      Exit;

    ROMHeader := ProgAST.Header;

    for var UnitName in ProgAST.UsesUnits do
      if LoadUnitRecursive(UnitName) = nil then
        Exit;

    Analyzer := TSemanticAnalyzer.Create(FErrors);
    try
      for var U in FCompileOrder do
        if not Analyzer.AnalyzeUnit(U) then
          Exit;

      if not Analyzer.Analyze(ProgAST) then
        Exit;

      Shaker := TTreeShaker.Create(ProgAST, FCompileOrder);

      try
        Shaker.Execute;
      finally
        Shaker.Free;
      end;

      CodeGen := TCodeGenerator.Create(ProgAST, FCompileOrder, Analyzer, ASource, AName);

      try
        if Assigned(FIR) then
          FIR.Free;

        FIR := CodeGen.Generate;

        FSizeBeforeOpt := FIR.Size;

        if FOptimise then
          TPeepholeOptimiser.Optimise(FIR);

        FSizeAfterOpt := FIR.Size;
      finally
        CodeGen.Free;
      end;
    finally
      Analyzer.Free;
    end;
  finally
    ProgAST.Free;
    Parser.Free;
  end;

  Result := True;
end;

function TCompiler.CompileFile(const AFileName: String): Boolean;
var
  SourceText:   String;
  FullFilePath: String;
  BaseDir:      String;
begin
  if not FileExists(AFileName) then
  begin
    FErrors.Clear;
    FErrors.Add(Format('File not found: "%s"', [AFileName]));

    Exit(False);
  end;

  FullFilePath := TPath.GetFullPath(AFileName);
  BaseDir      := ExtractFilePath(FullFilePath);

  if (Length(BaseDir) > 0) and (FSearchPaths.IndexOf(BaseDir) < 0) then
    AddPath(BaseDir);

  SourceText := TFile.ReadAllText(FullFilePath);
  Result     := Compile(SourceText, FullFilePath);
end;

function TCompiler.Link(AMemory: TMemory; AResize: Boolean): Boolean;
begin
  Result := False;

  FErrors.Clear;

  if not Assigned(FIR) then
    Exit;

  if AResize then
    AMemory.Resize(FIR.Size, ROMHeader.HeapSize, ROMHeader.StackSize)
  else
  begin
    ROMHeader.HeapSize  := AMemory.Heap.Size;
    ROMHeader.StackSize := AMemory.Stack.Size;
  end;

  if not FIR.ResolveLabels(AMemory.UserAddress, FErrors) then
    Exit;

  ROMHeader.UserAddress := AMemory.UserAddress;
  ROMHeader.UserSize    := FIR.Emit(AMemory, AMemory.UserAddress);

  Result := True;
end;

function TCompiler.Link(AStream: TStream; AWithHeader: Boolean): Boolean;
var
  CodeBytes: TBytes;
  BaseAddr:  Cardinal;
begin
  Result := False;

  FErrors.Clear;

  if not Assigned(FIR) then
    Exit;

  if ROMHeader.UserAddress > 0 then
    BaseAddr := ROMHeader.UserAddress
  else
    BaseAddr := (SizeOf(TCoreSystemMemory) + 3) and not Cardinal(3);

  if not FIR.ResolveLabels(BaseAddr, FErrors) then
    Exit;

  CodeBytes          := FIR.EmitToBytes;
  ROMHeader.UserSize := Length(CodeBytes);

  if AWithHeader then
    AStream.WriteBuffer(ROMHeader, SizeOf(TROMHeader));

  if Length(CodeBytes) > 0 then
    AStream.WriteBuffer(CodeBytes[0], Length(CodeBytes));

  Result := True;
end;

function TCompiler.Link(const AFileName: String; AWithHeader: Boolean): Boolean;
var
  FS: TFileStream;
begin
  try
    FS := TFileStream.Create(AFileName, fmCreate);
  except
    on E: EFCreateError do
    begin
      FErrors.Add(E.Message);
      Exit(False);
    end;
  end;

  try
    Result := Link(FS, AWithHeader);
  finally
    FS.Free;
  end;
end;

function TCompiler.ToAsmString: String;
var
  SB: TStringBuilder;
begin
  if not Assigned(FIR) then
    Exit('');

  SB := TStringBuilder.Create;
  try
    if Length(ROMHeader.Harness.Name) > 0 then
      SB.AppendLine(Format('.target "%s", %d, %d', [ROMHeader.Harness.Name, ROMHeader.Harness.Major, ROMHeader.Harness.Minor]));

    if Length(ROMHeader.ROM.Name) > 0 then
      SB.AppendLine(Format('.name   "%s"', [ROMHeader.ROM.Name]));

    SB.AppendLine(Format('.version %d, %d', [ROMHeader.ROM.Major, ROMHeader.ROM.Minor]));
    SB.AppendLine(Format('.base   $%x', [ROMHeader.UserAddress]));
    SB.AppendLine(Format('.heap   %d', [ROMHeader.HeapSize]));
    SB.AppendLine(Format('.stack  %d', [ROMHeader.StackSize]));

    SB.AppendLine;

    SB.Append(FIR.ToString);

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;
{$ENDREGION}

end.
