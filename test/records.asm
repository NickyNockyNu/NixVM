	call	Main
	halt

TPoint_GetY:
	enter	1, $8

	; records.pas(28): Result := fy;
	ldo	r1, bp, -4
	ldo	r0, r1, 4
	sto	bp, r0, -8
	leave
	ret

TPoint_Init:
	enter	3, $C

	; records.pas(35): fx := x;
	ldo	r0, bp, -8
	ldo	r1, bp, -4
	sto	r1, r0, 0

	; records.pas(36): fy := y;
	ldo	r0, bp, -12
	ldo	r1, bp, -4
	sto	r1, r0, 4
	leave
	ret

TPoint_SetY:
	enter	2, $8

	; records.pas(45): fy := AValue;
	ldo	r0, bp, -8
	ldo	r1, bp, -4
	sto	r1, r0, 4
	leave
	ret

Main:
	enter	0, $C

	; records.pas(54): for i := 0 to 2 do
	mov	r0, 0
	mov	r1, _var_i
	st	r1, r0
@for_1:
	ld	r0, _var_i
	cmp	r0, 2
	jg	@endfor_3

	; records.pas(56): with p[i] do
	ld	r0, _var_i
	mul	r0, 12
	lea	r0, r0, _var_p
	sto	bp, r0, -4

	; records.pas(58): Init(10 + i, 20 + i);
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

	; records.pas(60): Writeln('%d: %d, %d', i, x, y);
	ldo	r0, bp, -4
	call	TPoint_GetY
	push	r0
	ldo	r0, bp, -4
	ldo	r0, r0, 0
	push	r0
	ld	r0, _var_i
	push	r0
	mov	r0, _strconst_1
	push	r0
	popr	4
	syscall	$1	; _SysCall_DebugPrint

	; records.pas(62): with u do
	ldo	r0, bp, -4
	add	r0, 8
	sto	bp, r0, -8

	; records.pas(63): a := i;
	ld	r0, _var_i
	ldo	r1, bp, -8
	sto	r1, r0, 0

	; records.pas(65): y := x + y;
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

	; records.pas(67): Writeln('  %d', y);
	ldo	r0, bp, -4
	call	TPoint_GetY
	push	r0
	mov	r0, _strconst_2
	push	r0
	popr	2
	syscall	$1	; _SysCall_DebugPrint
	ld	r0, _var_i
	add	r0, 1
	mov	r1, _var_i
	st	r1, r0
	jmp	@for_1
@endfor_3:

	; records.pas(71): for i := 0 to 2 do
	mov	r0, 0
	mov	r1, _var_i
	st	r1, r0
@for_4:
	ld	r0, _var_i
	cmp	r0, 2
	jg	@endfor_6

	; records.pas(72): with p[i] do
	ld	r0, _var_i
	mul	r0, 12
	lea	r0, r0, _var_p
	sto	bp, r0, -12

	; records.pas(73): Writeln('%d: %d, %d, %d', i, fx, fy, u.a);
	ldo	r0, bp, -12
	add	r0, 8
	ldo	r0, r0, 0
	push	r0
	ldo	r1, bp, -12
	ldo	r0, r1, 4
	push	r0
	ldo	r1, bp, -12
	ldo	r0, r1, 0
	push	r0
	ld	r0, _var_i
	push	r0
	mov	r0, _strconst_3
	push	r0
	popr	5
	syscall	$1	; _SysCall_DebugPrint
	ld	r0, _var_i
	add	r0, 1
	mov	r1, _var_i
	st	r1, r0
	jmp	@for_4
@endfor_6:

	; records.pas(75): c := p[1];
	mov	r0, _var_c
	push	r0
	mov	r0, _var_p + 12
	push	r0
	popr	2
	mov	r2, 12
	syscall	$11	; _SysCall_MemoryCopy

	; records.pas(77): cp := @p[1];
	mov	r0, _var_p + 12
	mov	r1, _var_cp
	st	r1, r0

	; records.pas(79): Writeln('%d, %d', c.x, cp^.y);
	ld	r0, _var_cp
	call	TPoint_GetY
	push	r0
	mov	r0, _var_c
	ldo	r0, r0, 0
	push	r0
	mov	r0, _strconst_4
	push	r0
	popr	3
	syscall	$1	; _SysCall_DebugPrint
	leave
	ret


_var_cp:
	.res	4

_var_c:
	.res	12

_var_i:
	.res	4

_var_p:
	.res	36

_strconst_3:
	.str	"%d: %d, %d, %d", 13, 10, 0

_strconst_2:
	.str	"  %d", 13, 10, 0

_strconst_1:
	.str	"%d: %d, %d", 13, 10, 0

_strconst_4:
	.str	"%d, %d", 13, 10, 0
