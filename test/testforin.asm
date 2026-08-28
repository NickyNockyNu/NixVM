	call	Main
	halt

Main:
	enter	0, $18

	; testforin.pas(26): for i := 0 to 2 do
	mov	r0, 0
	mov	r1, _var_i
	st	r1, r0
@for_1:
	ld	r0, _var_i
	cmp	r0, 2
	jg	@endfor_3

	; testforin.pas(28): points[i].x := (i + 1) * 10;
	ld	r0, _var_i
	add	r0, 1
	mul	r0, 10
	push	r0
	ld	r0, _var_i
	shl	r0, 3
	lea	r0, r0, _var_points
	mov	r1, r0
	pop	r0
	st	r1, r0

	; testforin.pas(29): points[i].y := (i + 1) * 20;
	ld	r0, _var_i
	add	r0, 1
	mul	r0, 20
	push	r0
	ld	r0, _var_i
	shl	r0, 3
	lea	r0, r0, _var_points
	add	r0, 4
	mov	r1, r0
	pop	r0
	st	r1, r0
	ld	r0, _var_i
	add	r0, 1
	mov	r1, _var_i
	st	r1, r0
	jmp	@for_1
@endfor_3:

	; testforin.pas(32): for pt in points do
	mov	r0, 0
	sto	bp, r0, -4
@forin_start_4:
	ldo	r0, bp, -4
	cmp	r0, 2
	jg	@forin_end_6
	ldo	r0, bp, -4
	shl	r0, 3
	lea	r0, r0, _var_points
	mov	r1, r0
	mov	r0, _var_pt
	push	r0
	mov	r0, r1
	push	r0
	popr	2
	mov	r2, 8
	syscall	$11	; _SysCall_MemoryCopy

	; testforin.pas(33): Writeln('Point: %d, %d', pt.x, pt.y);
	mov	r0, _var_pt
	ldo	r0, r0, 4
	push	r0
	mov	r0, _var_pt
	ldo	r0, r0, 0
	push	r0
	mov	r0, _strconst_1
	push	r0
	popr	3
	syscall	$1	; _SysCall_DebugPrint
	ldo	r0, bp, -4
	add	r0, 1
	sto	bp, r0, -4
	jmp	@forin_start_4
@forin_end_6:

	; testforin.pas(35): for day in Weekend do
	mov	r0, 96
	sto	bp, r0, -8
	mov	r0, 0
	sto	bp, r0, -12
@forin_start_7:
	ldo	r0, bp, -12
	cmp	r0, 32
	jge	@forin_end_9
	mov	r1, 1
	shl	r1, r0
	ldo	r0, bp, -8
	btst	r0, r1
	je	@forin_next_8
	ldo	r0, bp, -12
	mov	r1, _var_day
	stb	r1, r0

	; testforin.pas(36): Writeln('Weekend Day Index: %d', Ord(day));
	mov	r1, _var_day
	ldb	r0, r1
	push	r0
	mov	r0, _strconst_2
	push	r0
	popr	2
	syscall	$1	; _SysCall_DebugPrint
@forin_next_8:
	ldo	r0, bp, -12
	add	r0, 1
	sto	bp, r0, -12
	jmp	@forin_start_7
@forin_end_9:

	; testforin.pas(38): for ch in 'NixVM' do
	mov	r0, _strconst_3
	sto	bp, r0, -16
	syscall	$33	; _SysCall_StringLength
	sto	bp, r0, -20
	mov	r0, 1
	sto	bp, r0, -24
@forin_start_10:
	ldo	r0, bp, -24
	ldo	r1, bp, -20
	cmp	r0, r1
	jg	@forin_end_12
	ldo	r0, bp, -24
	sub	r0, 1
	ldo	r1, bp, -16
	add	r0, r1
	ldb	r0, r0
	mov	r1, _var_ch
	stb	r1, r0

	; testforin.pas(39): Writeln('Char: %c (Ord=%d)', ch, Ord(ch));
	ldb	r0, _var_ch
	push	r0
	mov	r1, _var_ch
	ldb	r0, r1
	push	r0
	mov	r0, _strconst_4
	push	r0
	popr	3
	syscall	$1	; _SysCall_DebugPrint
	ldo	r0, bp, -24
	add	r0, 1
	sto	bp, r0, -24
	jmp	@forin_start_10
@forin_end_12:
	leave
	ret


_var_points:
	.res	24

_var_pt:
	.res	8

_var_day:
	.res	4

_var_ch:
	.res	4

_var_i:
	.res	4

_strconst_1:
	.str	"Point: %d, %d", 13, 10, 0

_strconst_2:
	.str	"Weekend Day Index: %d", 13, 10, 0

_strconst_3:
	.str	"NixVM", 0

_strconst_4:
	.str	"Char: %c (Ord=%d)", 13, 10, 0
