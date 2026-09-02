program TestDynArray targets console;

{$HEAP 32k}
{$STACK 16k}

function HeapAvailable: Cardinal; syscall $24;

type
  TPoint = record
    x, y: Integer;
  end;

procedure TestDynamicArray;
var
  numbers: array of Integer;
  pts: array of TPoint;
begin
  Println('Allocating 5 integers...');
  SetLength(numbers, 5);

  for var i := 0 to High(numbers) do
    numbers[i] := (i + 1) * 100;

  for var i := 0 to High(numbers) do
    Println('numbers[%d] = %d', i, numbers[i]);

  Println('Length: %d, High: %d, Low: %d', Length(numbers), High(numbers), Low(numbers));

  // Expanding array to 8 elements (preserves existing 5, zeroes new 3!)
  SetLength(numbers, 8);
  numbers[5] := 600;
  numbers[6] := 700;
  numbers[7] := 800;

  Println('Expanded length: %d', Length(numbers));
  for var i := 0 to High(numbers) do
    Println('numbers[%d] = %d', i, numbers[i]);

  // Array of Records
  SetLength(pts, 2);
  pts[0].x := 11; pts[0].y := 22;
  pts[1].x := 33; pts[1].y := 44;
  Println('pts[1] = (%d, %d)', pts[1].x, pts[1].y);
end;

begin
  Println('Initial Free Heap: %d bytes', HeapAvailable);
  TestDynamicArray;
  Println('Final Free Heap (after auto-cleanup): %d bytes', HeapAvailable);
end.