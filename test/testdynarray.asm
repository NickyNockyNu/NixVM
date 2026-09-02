.target "console", 1, 0
.name "TestDynArray"
.version 1, 0
.base   $4E0
.heap   32768
.stack  16384

	call	__program_begin_
	halt


; testdynarray.pas(13): procedure TestDynamicArray;
TestDynamicArray:
	enter	0, $C

	; testdynarray.pas(18): Println('Allocating 5 integers...');
	mov	r0, _strconst_1
	syscall	$1	; _SysCall_DebugPrint

	; testdynarray.pas(19): SetLength(numbers, 5);
	ldo	r0, bp, -4
	push	r0
	mov	r0, 5
	mov	r1, r0
	pop	r0
	mov	r2, 4
	syscall	$43	; ArraySetLength
	sto	bp, r0, -4

	; testdynarray.pas(21): for var i := 0 to High(numbers) do
	mov	r0, 0
	sto	bp, r0, -12
@for_1:
	ldo	r0, bp, -4
	cmp	r0, 0
	jnz	@da_high_4
	mov	r0, -1
	jmp	@dn_high_end_5
@da_high_4:
	ldo	r0, r0, -4
	sub	r0, 1
@dn_high_end_5:
	mov	r1, r0
	ldo	r0, bp, -12
	cmp	r0, r1
	jg	@endfor_3

	; testdynarray.pas(22): numbers[i] := (i + 1) * 100;
	ldo	r0, bp, -12
	add	r0, 1
	mul	r0, 100
	push	r0
	ldo	r0, bp, -12
	shl	r0, 2
	mov	r1, r0
	ldo	r0, bp, -4
	add	r0, r1
	mov	r1, r0
	pop	r0
	st	r1, r0
	ldo	r0, bp, -12
	add	r0, 1
	sto	bp, r0, -12
	jmp	@for_1
@endfor_3:

	; testdynarray.pas(24): for var i := 0 to High(numbers) do
	mov	r0, 0
	sto	bp, r0, -12
@for_6:
	ldo	r0, bp, -4
	cmp	r0, 0
	jnz	@da_high_9
	mov	r0, -1
	jmp	@dn_high_end_10
@da_high_9:
	ldo	r0, r0, -4
	sub	r0, 1
@dn_high_end_10:
	mov	r1, r0
	ldo	r0, bp, -12
	cmp	r0, r1
	jg	@endfor_8

	; testdynarray.pas(25): Println('numbers[%d] = %d', i, numbers[i]);
	ldo	r0, bp, -12
	shl	r0, 2
	mov	r1, r0
	ldo	r0, bp, -4
	add	r0, r1
	ld	r0, r0
	push	r0
	ldo	r0, bp, -12
	push	r0
	push	_strconst_2
	popr	3
	syscall	$1	; _SysCall_DebugPrint
	ldo	r0, bp, -12
	add	r0, 1
	sto	bp, r0, -12
	jmp	@for_6
@endfor_8:

	; testdynarray.pas(27): Println('Length: %d, High: %d, Low: %d', Length(numbers), High(numbers), Low(numbers));
	push	$0
	ldo	r0, bp, -4
	cmp	r0, 0
	jnz	@da_high_11
	mov	r0, -1
	jmp	@dn_high_end_12
@da_high_11:
	ldo	r0, r0, -4
	sub	r0, 1
@dn_high_end_12:
	push	r0
	ldo	r0, bp, -4
	cmp	r0, 0
	jnz	@da_len_13
	mov	r0, 0
	jmp	@da_len_end_14
@da_len_13:
	ldo	r0, r0, -4
@da_len_end_14:
	push	r0
	push	_strconst_3
	popr	4
	syscall	$1	; _SysCall_DebugPrint

	; testdynarray.pas(30): SetLength(numbers, 8);
	ldo	r0, bp, -4
	push	r0
	mov	r0, 8
	mov	r1, r0
	pop	r0
	mov	r2, 4
	syscall	$43	; ArraySetLength
	sto	bp, r0, -4

	; testdynarray.pas(31): numbers[5] := 600;
	push	$258
	mov	r0, 5
	shl	r0, 2
	mov	r1, r0
	ldo	r0, bp, -4
	add	r0, r1
	mov	r1, r0
	pop	r0
	st	r1, r0

	; testdynarray.pas(32): numbers[6] := 700;
	push	$2BC
	mov	r0, 6
	shl	r0, 2
	mov	r1, r0
	ldo	r0, bp, -4
	add	r0, r1
	mov	r1, r0
	pop	r0
	st	r1, r0

	; testdynarray.pas(33): numbers[7] := 800;
	push	$320
	mov	r0, 7
	shl	r0, 2
	mov	r1, r0
	ldo	r0, bp, -4
	add	r0, r1
	mov	r1, r0
	pop	r0
	st	r1, r0

	; testdynarray.pas(35): Println('Expanded length: %d', Length(numbers));
	ldo	r0, bp, -4
	cmp	r0, 0
	jnz	@da_len_15
	mov	r0, 0
	jmp	@da_len_end_16
@da_len_15:
	ldo	r0, r0, -4
@da_len_end_16:
	push	r0
	push	_strconst_4
	popr	2
	syscall	$1	; _SysCall_DebugPrint

	; testdynarray.pas(36): for var i := 0 to High(numbers) do
	mov	r0, 0
	sto	bp, r0, -12
@for_17:
	ldo	r0, bp, -4
	cmp	r0, 0
	jnz	@da_high_20
	mov	r0, -1
	jmp	@dn_high_end_21
@da_high_20:
	ldo	r0, r0, -4
	sub	r0, 1
@dn_high_end_21:
	mov	r1, r0
	ldo	r0, bp, -12
	cmp	r0, r1
	jg	@endfor_19

	; testdynarray.pas(37): Println('numbers[%d] = %d', i, numbers[i]);
	ldo	r0, bp, -12
	shl	r0, 2
	mov	r1, r0
	ldo	r0, bp, -4
	add	r0, r1
	ld	r0, r0
	push	r0
	ldo	r0, bp, -12
	push	r0
	push	_strconst_2
	popr	3
	syscall	$1	; _SysCall_DebugPrint
	ldo	r0, bp, -12
	add	r0, 1
	sto	bp, r0, -12
	jmp	@for_17
@endfor_19:

	; testdynarray.pas(40): SetLength(pts, 2);
	ldo	r0, bp, -8
	push	r0
	mov	r0, 2
	mov	r1, r0
	pop	r0
	mov	r2, 8
	syscall	$43	; ArraySetLength
	sto	bp, r0, -8

	; testdynarray.pas(41): pts[0].x := 11; pts[0].y := 22;
	push	$B
	mov	r0, 0
	shl	r0, 3
	mov	r1, r0
	ldo	r0, bp, -8
	add	r0, r1
	mov	r1, r0
	pop	r0
	st	r1, r0
	push	$16
	mov	r0, 0
	shl	r0, 3
	mov	r1, r0
	ldo	r0, bp, -8
	add	r0, r1
	add	r0, 4
	mov	r1, r0
	pop	r0
	st	r1, r0

	; testdynarray.pas(42): pts[1].x := 33; pts[1].y := 44;
	push	$21
	mov	r0, 1
	shl	r0, 3
	mov	r1, r0
	ldo	r0, bp, -8
	add	r0, r1
	mov	r1, r0
	pop	r0
	st	r1, r0
	push	$2C
	mov	r0, 1
	shl	r0, 3
	mov	r1, r0
	ldo	r0, bp, -8
	add	r0, r1
	add	r0, 4
	mov	r1, r0
	pop	r0
	st	r1, r0

	; testdynarray.pas(43): Println('pts[1] = (%d, %d)', pts[1].x, pts[1].y);
	mov	r0, 1
	shl	r0, 3
	mov	r1, r0
	ldo	r0, bp, -8
	add	r0, r1
	ldo	r0, r0, 4
	push	r0
	mov	r0, 1
	shl	r0, 3
	mov	r1, r0
	ldo	r0, bp, -8
	add	r0, r1
	ldo	r0, r0, 0
	push	r0
	push	_strconst_5
	popr	3
	syscall	$1	; _SysCall_DebugPrint

	; end (TestDynamicArray)
	ldo	r0, bp, -4
	syscall	$41	; ArrayDispose
	ldo	r0, bp, -8
	syscall	$41	; ArrayDispose
	leave
	ret


; testdynarray.pas(46): begin
__program_begin_:

	; testdynarray.pas(47): Println('Initial Free Heap: %d bytes', HeapAvailable);
	syscall	$24	; _SysCall_HeapAvailable
	push	r0
	push	_strconst_6
	popr	2
	syscall	$1	; _SysCall_DebugPrint

	; testdynarray.pas(48): TestDynamicArray;
	call	TestDynamicArray

	; testdynarray.pas(49): Println('Final Free Heap (after auto-cleanup): %d bytes', HeapAvailable);
	syscall	$24	; _SysCall_HeapAvailable
	push	r0
	push	_strconst_7
	popr	2
	syscall	$1	; _SysCall_DebugPrint
	ret


_strconst_5:
	.str	"pts[1] = (%d, %d)", 13, 10, 0

_strconst_3:
	.str	"Length: %d, High: %d, Low: %d", 13, 10, 0

_strconst_2:
	.str	"numbers[%d] = %d", 13, 10, 0

_strconst_4:
	.str	"Expanded length: %d", 13, 10, 0

_strconst_7:
	.str	"Final Free Heap (after auto-cleanup): %d bytes", 13, 10, 0

_strconst_1:
	.str	"Allocating 5 integers...", 13, 10, 0

_strconst_6:
	.str	"Initial Free Heap: %d bytes", 13, 10, 0
