program testheapfile targets console;

{$HEAP 32k}
{$STACK 16k}

function HeapAlloc(ASize: Cardinal): Pointer; syscall $20;
procedure HeapFree(AData: Pointer); syscall $22;
function HeapAvailable: Cardinal; syscall $24;
function HeapLoad(AFileName: String): Pointer; syscall $25;
function HeapSave(AFileName: String; AData: Pointer): Cardinal; syscall $26;

type
  PData = ^TData;
  TData = record
    a, b, c, d: Integer;
  end;
 
function MakeOrLoad(AFileName: String): PData;
begin
  Print('loading...');
  Result := HeapLoad(AFileName);
  
  if not Assigned(Result) then
  begin
    Println('[failed]');
    
    Print('allocating...'); 
    Result := HeapAlloc(SizeOf(TData));

    if not Assigned(Result) then
    begin
      Println('[failed]');
      Exit;
    end
    else
      Println('[ok]');
     
    Result^.a := 11;
    Result^.b := 22;
    Result^.c := 33;
    Result^.d := 44;
    
    Print('saving...');
    if HeapSave(AFileName, Result) = SizeOf(TData) then
      Println('[ok]')
    else
    begin
      Println('[failed]');
      HeapFree(Result);
      Result := nil;
      Exit;
    end;
  end
  else
    Println('[ok]');
end;

var
  Data: PData;
begin
  Data := MakeOrLoad('test');
  
  if Assigned(Data) then
    Println('%d %d %d %d', Data^.a, Data^.b, Data^.c, Data^.d);
end.
