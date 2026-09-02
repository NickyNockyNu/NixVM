.target "console", 1, 0
.name "TestInlineFor"
.version 1, 0
.base   $4E0
.heap   32768
.stack  16384

	call	__program_begin_
	halt


; testinlinefor.pas(16): procedure TestForStrAlloc;
TestForStrAlloc:
	enter	0, $24

	; testinlinefor.pas(20): for var i := 0 to 5 do
	mov	r0, 0
	sto	bp, r0, -28
@for_1:
	ldo	r0, bp, -28
	cmp	r0, 5
	jg	@endfor_3

	; testinlinefor.pas(21): ss[i] := Format('Str:%d', i);
	ldo	r0, bp, -28
	push	r0
	push	_strconst_1
	popr	2
	syscall	$37	; _SysCall_StringFormat
	push	r0
	ldo	r0, bp, -28
	shl	r0, 2
	add	r0, bp
	add	r0, -24
	mov	r1, r0
	pop	r0
	st	r1, r0
	ldo	r0, bp, -28
	add	r0, 1
	sto	bp, r0, -28
	jmp	@for_1
@endfor_3:

	; testinlinefor.pas(23): for var s in ss do
	mov	r0, 0
	sto	bp, r0, -36
@forin_start_4:
	ldo	r0, bp, -36
	cmp	r0, 5
	jg	@forin_end_6
	ldo	r0, bp, -36
	shl	r0, 2
	add	r0, bp
	add	r0, -24
	ld	r0, r0
	sto	bp, r0, -32

	; testinlinefor.pas(24): Println('%s', s);
	ldo	r0, bp, -32
	push	r0
	push	_strconst_2
	popr	2
	syscall	$1	; _SysCall_DebugPrint
	ldo	r0, bp, -36
	add	r0, 1
	sto	bp, r0, -36
	jmp	@forin_start_4
@forin_end_6:

	; end (TestForStrAlloc)
	lea	r1, bp, -24
	mov	r2, 6
@finalize_arr_7:
	ld	r0, r1
	syscall	$32	; _SysCall_StringDispose
	add	r1, 4
	loop	r2, @finalize_arr_7
	leave
	ret


; testinlinefor.pas(27): procedure PrintMem;
PrintMem:

	; testinlinefor.pas(29): Println('%d bytes', HeapAvailable);
	syscall	$24	; _SysCall_HeapAvailable
	push	r0
	push	_strconst_3
	popr	2
	syscall	$1	; _SysCall_DebugPrint

	; end (PrintMem)
	ret


; testinlinefor.pas(32): begin
__program_begin_:
	enter	0, $24

	; testinlinefor.pas(33): PrintMem;
	call	PrintMem

	; testinlinefor.pas(35): for var i := 0 to 2 do
	mov	r0, 0
	sto	bp, r0, -4
@for_8:
	ldo	r0, bp, -4
	cmp	r0, 2
	jg	@endfor_10

	; testinlinefor.pas(37): points[i].x := (i + 1) * 10;
	ldo	r0, bp, -4
	add	r0, 1
	mul	r0, 10
	push	r0
	ldo	r0, bp, -4
	shl	r0, 3
	lea	r0, r0, _var_points
	mov	r1, r0
	pop	r0
	st	r1, r0

	; testinlinefor.pas(38): points[i].y := (i + 1) * 20;
	ldo	r0, bp, -4
	add	r0, 1
	mul	r0, 20
	push	r0
	ldo	r0, bp, -4
	shl	r0, 3
	lea	r0, r0, _var_points + 4
	mov	r1, r0
	pop	r0
	st	r1, r0
	ldo	r0, bp, -4
	add	r0, 1
	sto	bp, r0, -4
	jmp	@for_8
@endfor_10:

	; testinlinefor.pas(41): for var j: Integer := 2 downto 0 do
	mov	r0, 2
	sto	bp, r0, -8
@for_11:
	ldo	r0, bp, -8
	cmp	r0, 0
	jl	@endfor_13

	; testinlinefor.pas(42): Println('Downto j = %d', j);
	ldo	r0, bp, -8
	push	r0
	push	_strconst_4
	popr	2
	syscall	$1	; _SysCall_DebugPrint
	ldo	r0, bp, -8
	sub	r0, 1
	sto	bp, r0, -8
	jmp	@for_11
@endfor_13:

	; testinlinefor.pas(44): for var pt in points do
	mov	r0, 0
	sto	bp, r0, -24
@forin_start_14:
	ldo	r0, bp, -24
	cmp	r0, 2
	jg	@forin_end_16
	ldo	r0, bp, -24
	shl	r0, 3
	lea	r0, r0, _var_points
	mov	r1, r0
	lea	r0, bp, -16
	push	r0
	mov	r0, r1
	push	r0
	popr	2
	mov	r2, 8
	syscall	$11	; _SysCall_MemoryCopy

	; testinlinefor.pas(45): Println('Point: %d, %d', pt.x, pt.y);
	lea	r0, bp, -16
	ldo	r0, r0, 4
	push	r0
	lea	r0, bp, -16
	ldo	r0, r0, 0
	push	r0
	push	_strconst_5
	popr	3
	syscall	$1	; _SysCall_DebugPrint
	ldo	r0, bp, -24
	add	r0, 1
	sto	bp, r0, -24
	jmp	@forin_start_14
@forin_end_16:

	; testinlinefor.pas(47): for var ch in 'Nix' do
	mov	r0, _strconst_6
	sto	bp, r0, -28
	syscall	$33	; _SysCall_StringLength
	sto	bp, r0, -32
	mov	r0, 1
	sto	bp, r0, -36
@forin_start_17:
	ldo	r0, bp, -36
	ldo	r1, bp, -32
	cmp	r0, r1
	jg	@forin_end_19
	ldo	r0, bp, -36
	sub	r0, 1
	ldo	r1, bp, -28
	add	r0, r1
	ldb	r0, r0
	stob	bp, r0, -20

	; testinlinefor.pas(48): Println('Char: %c', ch);
	ldob	r0, bp, -20
	push	r0
	push	_strconst_7
	popr	2
	syscall	$1	; _SysCall_DebugPrint
	ldo	r0, bp, -36
	add	r0, 1
	sto	bp, r0, -36
	jmp	@forin_start_17
@forin_end_19:

	; testinlinefor.pas(50): TestForStrAlloc;
	call	TestForStrAlloc

	; testinlinefor.pas(52): PrintMem;
	call	PrintMem
	leave
	ret


_var_points:
	.res	24

_strconst_3:
	.str	"%d bytes", 13, 10, 0

_strconst_6:
	.str	"Nix", 0

_strconst_5:
	.str	"Point: %d, %d", 13, 10, 0

_strconst_1:
	.str	"Str:%d", 0

_strconst_2:
	.str	"%s", 13, 10, 0

_strconst_4:
	.str	"Downto j = %d", 13, 10, 0

_strconst_7:
	.str	"Char: %c", 13, 10, 0
