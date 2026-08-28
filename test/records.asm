	call	Main
	halt

TUnused_GetA:
	enter	1, $8

	; records.pas(13): Result := a;
	ldo	r0, r0, 0
	leave
	ret

TPoint_GetY:
	enter	1, $8

	; records.pas(25): Result := fy;
	ldo	r0, r0, 4
	leave
	ret

TPoint_Init:
	enter	3, $C

	; records.pas(32): fx := x;
	ldo	r0, bp, -8
	ldo	r1, bp, -4
	sto	r1, r0, 0

	; records.pas(33): fy := y;
	ldo	r0, bp, -12
	ldo	r1, bp, -4
	sto	r1, r0, 4
	leave
	ret

TPoint_SetY:
	enter	2, $8

	; records.pas(42): fy := AValue;
	ldo	r0, bp, -8
	ldo	r1, bp, -4
	sto	r1, r0, 4
	leave
	ret

Main:
	enter	0, $8

	; records.pas(50): a.a := 42;
	mov	r0, 42
	push	r0
	mov	r0, _var_a
	mov	r1, r0
	pop	r0
	st	r1, r0

	; records.pas(51): Writeln('%d', a.AA);
	mov	r0, _var_a
	call	TUnused_GetA
	push	r0
	mov	r0, _strconst_1
	push	r0
	popr	2
	syscall	$1

	; records.pas(53): for i := 0 to 2 do
	mov	r0, 0
	mov	r1, _var_i
	st	r1, r0
@for_1:
	ld	r0, _var_i
	cmp	r0, 2
	jg	@endfor_3

	; records.pas(55): with p[i] do
	ld	r0, _var_i
	shl	r0, 3
	lea	r0, r0, _var_p
	sto	bp, r0, -4

	; records.pas(57): Init(10 + i, 20 + i);
	mov	r0, 20
	push	r0
	ld	r0, _var_i
	mov	r1, r0
	pop	r0
	add	r0, r1
	push	r0
	mov	r0, 10
	push	r0
	ld	r0, _var_i
	mov	r1, r0
	pop	r0
	add	r0, r1
	push	r0
	ldo	r0, bp, -4
	push	r0
	popr	3
	call	TPoint_Init

	; records.pas(59): Writeln('%d: %d, %d', i, x, y);
	ldo	r0, bp, -4
	call	TPoint_GetY
	push	r0
	ldo	r0, bp, -4
	ldo	r0, r0, 0
	push	r0
	ld	r0, _var_i
	push	r0
	mov	r0, _strconst_2
	push	r0
	popr	4
	syscall	$1

	; records.pas(61): y := x + y;
	ldo	r0, bp, -4
	ldo	r0, r0, 0
	push	r0
	ldo	r0, bp, -4
	call	TPoint_GetY
	mov	r1, r0
	pop	r0
	add	r0, r1
	mov	r1, r0
	ldo	r0, bp, -4
	call	TPoint_SetY

	; records.pas(63): Writeln('  %d', y);
	ldo	r0, bp, -4
	call	TPoint_GetY
	push	r0
	mov	r0, _strconst_3
	push	r0
	popr	2
	syscall	$1
	ld	r0, _var_i
	add	r0, 1
	mov	r1, _var_i
	st	r1, r0
	jmp	@for_1
@endfor_3:

	; records.pas(67): for i := 0 to 2 do
	mov	r0, 0
	mov	r1, _var_i
	st	r1, r0
@for_4:
	ld	r0, _var_i
	cmp	r0, 2
	jg	@endfor_6

	; records.pas(68): with p[i] do
	ld	r0, _var_i
	shl	r0, 3
	lea	r0, r0, _var_p
	sto	bp, r0, -8

	; records.pas(69): Writeln('%d: %d, %d', i, fx, fy);
	ldo	r1, bp, -8
	ldo	r0, r1, 4
	push	r0
	ldo	r1, bp, -8
	ldo	r0, r1, 0
	push	r0
	ld	r0, _var_i
	push	r0
	mov	r0, _strconst_2
	push	r0
	popr	4
	syscall	$1
	ld	r0, _var_i
	add	r0, 1
	mov	r1, _var_i
	st	r1, r0
	jmp	@for_4
@endfor_6:
	leave
	ret


_var_a:
	.res	4

_var_i:
	.res	4

_var_p:
	.res	24

_strconst_1:
	.str	"%d", 13, 10, 0

_strconst_3:
	.str	"  %d", 13, 10, 0

_strconst_2:
	.str	"%d: %d, %d", 13, 10, 0
