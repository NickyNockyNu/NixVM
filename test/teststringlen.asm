.target "console", 1, 0
.name "TestStringLen"
.version 1, 0
.base   $4E0
.heap   32768
.stack  16384

	call	__program_begin_
	halt


; teststringlen.pas(8): procedure TestStrSetLength;
TestStrSetLength:
	zenter	0, $8

	; teststringlen.pas(13): SetLength(s, 10);
	ldo	r0, bp, -4
	push	r0
	mov	r0, 10
	mov	r1, r0
	pop	r0
	syscall	$34	; _SysCall_StringSetLength
	sto	bp, r0, -4

	; teststringlen.pas(14): for var i := 1 to 10 do
	mov	r0, 1
	sto	bp, r0, -8
@for_1:
	ldo	r0, bp, -8
	cmp	r0, 10
	jg	@endfor_3

	; teststringlen.pas(15): s[i] := Chr(64 + i); // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'
	push	$40
	ldo	r1, bp, -8
	pop	r0
	add	r0, r1
	and	r0, 255
	push	r0
	ldo	r0, bp, -8
	sub	r0, 1
	mov	r1, r0
	ldo	r0, bp, -4
	add	r0, r1
	mov	r1, r0
	pop	r0
	stb	r1, r0
	ldo	r0, bp, -8
	add	r0, 1
	sto	bp, r0, -8
	jmp	@for_1
@endfor_3:

	; teststringlen.pas(17): Println('Buffer: "%s" (Length=%d)', s, Length(s));
	ldo	r0, bp, -4
	syscall	$33	; _SysCall_StringLength
	push	r0
	ldo	r0, bp, -4
	push	r0
	push	_strconst_1
	popr	3
	syscall	$1	; _SysCall_DebugPrint

	; teststringlen.pas(20): SetLength(s, 5);
	ldo	r0, bp, -4
	push	r0
	mov	r0, 5
	mov	r1, r0
	pop	r0
	syscall	$34	; _SysCall_StringSetLength
	sto	bp, r0, -4

	; teststringlen.pas(21): Println('Shrunk: "%s" (Length=%d)', s, Length(s));
	ldo	r0, bp, -4
	syscall	$33	; _SysCall_StringLength
	push	r0
	ldo	r0, bp, -4
	push	r0
	push	_strconst_2
	popr	3
	syscall	$1	; _SysCall_DebugPrint

	; end (TestStrSetLength)
	ldo	r0, bp, -4
	syscall	$32	; _SysCall_StringDispose
	leave
	ret


; teststringlen.pas(24): begin
__program_begin_:

	; teststringlen.pas(25): Println('Initial Free Heap: %d bytes', HeapAvailable);
	syscall	$24	; _SysCall_HeapAvailable
	push	r0
	push	_strconst_3
	popr	2
	syscall	$1	; _SysCall_DebugPrint

	; teststringlen.pas(26): TestStrSetLength;
	call	TestStrSetLength

	; teststringlen.pas(27): Println('Final Free Heap: %d bytes', HeapAvailable);
	syscall	$24	; _SysCall_HeapAvailable
	push	r0
	push	_strconst_4
	popr	2
	syscall	$1	; _SysCall_DebugPrint
	ret


_strconst_1:
	.str	"Buffer: ""%s"" (Length=%d)", 13, 10, 0

_strconst_3:
	.str	"Initial Free Heap: %d bytes", 13, 10, 0

_strconst_4:
	.str	"Final Free Heap: %d bytes", 13, 10, 0

_strconst_2:
	.str	"Shrunk: ""%s"" (Length=%d)", 13, 10, 0
