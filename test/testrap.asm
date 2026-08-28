	call	Main
	halt

ScalePoint:
	enter	2, $C

	; testrap.pas(28): with pt do
	ldo	r0, bp, -4
	sto	bp, r0, -12

	; testrap.pas(30): x := x * factor;
	ldo	r1, bp, -12
	ldo	r0, r1, 0
	push	r0
	ldo	r0, bp, -8
	mov	r1, r0
	pop	r0
	mul	r0, r1
	ldo	r1, bp, -12
	sto	r1, r0, 0

	; testrap.pas(31): y := y * factor;
	ldo	r1, bp, -12
	ldo	r0, r1, 4
	push	r0
	ldo	r0, bp, -8
	mov	r1, r0
	pop	r0
	mul	r0, r1
	ldo	r1, bp, -12
	sto	r1, r0, 4
	leave
	ret

Main:
	enter	0, $4

	; testrap.pas(36): for i := 0 to 2 do
	mov	r0, 0
	mov	r1, _var_i
	st	r1, r0
@for_1:
	ld	r0, _var_i
	cmp	r0, 2
	jg	@endfor_3

	; testrap.pas(38): points[i].x := (i + 1) * 10;
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

	; testrap.pas(39): points[i].y := (i + 1) * 20;
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

	; testrap.pas(42): ScalePoint(points[1], 2);
	mov	r0, 2
	push	r0
	mov	r0, _var_points + 8
	push	r0
	popr	2
	call	ScalePoint

	; testrap.pas(43): Writeln('ScalePoint var test: %d, %d', points[1].x, points[1].y);
	mov	r0, _var_points + 8
	ldo	r0, r0, 4
	push	r0
	mov	r0, _var_points + 8
	ldo	r0, r0, 0
	push	r0
	mov	r0, _strconst_1
	push	r0
	popr	3
	syscall	$1	; _SysCall_DebugPrint

	; testrap.pas(45): ptPtr := @points[0];
	mov	r0, _var_points
	mov	r1, _var_ptptr
	st	r1, r0

	; testrap.pas(46): Writeln('Ptr[0]: %d, %d', ptPtr^.x, ptPtr^.y);
	ld	r0, _var_ptptr
	ldo	r0, r0, 4
	push	r0
	ld	r0, _var_ptptr
	ldo	r0, r0, 0
	push	r0
	mov	r0, _strconst_2
	push	r0
	popr	3
	syscall	$1	; _SysCall_DebugPrint

	; testrap.pas(48): Inc(ptPtr);
	mov	r1, 8
	ld	r0, _var_ptptr
	add	r0, r1
	mov	r1, _var_ptptr
	st	r1, r0

	; testrap.pas(49): Writeln('Ptr[1] after Inc: %d, %d', ptPtr^.x, ptPtr^.y);
	ld	r0, _var_ptptr
	ldo	r0, r0, 4
	push	r0
	ld	r0, _var_ptptr
	ldo	r0, r0, 0
	push	r0
	mov	r0, _strconst_3
	push	r0
	popr	3
	syscall	$1	; _SysCall_DebugPrint

	; testrap.pas(51): with hero do
	mov	r0, _var_hero
	sto	bp, r0, -4

	; testrap.pas(53): id := 999;
	mov	r0, 999
	ldo	r1, bp, -4
	sto	r1, r0, 0

	; testrap.pas(54): pos.x := 100;
	mov	r0, 100
	ldo	r1, bp, -4
	sto	r1, r0, 4

	; testrap.pas(55): pos.y := 200;
	mov	r0, 200
	ldo	r1, bp, -4
	sto	r1, r0, 8

	; testrap.pas(56): stats[0] := 50;
	mov	r0, 50
	ldo	r1, bp, -4
	sto	r1, r0, 12

	; testrap.pas(57): stats[1] := 25;
	mov	r0, 25
	ldo	r1, bp, -4
	sto	r1, r0, 16

	; testrap.pas(58): stats[2] := 10;
	mov	r0, 10
	ldo	r1, bp, -4
	sto	r1, r0, 20

	; testrap.pas(61): Writeln('Hero ID=%d, Pos=(%d, %d), HP=%d, ATK=%d',
	mov	r0, 2
	shl	r0, 2
	mov	r1, r0
	mov	r0, _var_hero
	add	r0, 12
	add	r0, r1
	ld	r0, r0
	push	r0
	mov	r0, 0
	shl	r0, 2
	mov	r1, r0
	mov	r0, _var_hero
	add	r0, 12
	add	r0, r1
	ld	r0, r0
	push	r0
	mov	r0, _var_hero
	add	r0, 4
	ldo	r0, r0, 4
	push	r0
	mov	r0, _var_hero
	add	r0, 4
	ldo	r0, r0, 0
	push	r0
	mov	r0, _var_hero
	ldo	r0, r0, 0
	push	r0
	mov	r0, _strconst_4
	push	r0
	popr	6
	syscall	$1	; _SysCall_DebugPrint

	; testrap.pas(64): for i := 0 to 2 do
	mov	r0, 0
	mov	r1, _var_i
	st	r1, r0
@for_4:
	ld	r0, _var_i
	cmp	r0, 2
	jg	@endfor_6

	; testrap.pas(65): for j := 0 to 2 do
	mov	r0, 0
	mov	r1, _var_j
	st	r1, r0
@for_7:
	ld	r0, _var_j
	cmp	r0, 2
	jg	@endfor_9

	; testrap.pas(66): grid[i, j] := (i * 10) + j;
	ld	r0, _var_i
	mul	r0, 10
	push	r0
	ld	r0, _var_j
	mov	r1, r0
	pop	r0
	add	r0, r1
	push	r0
	mov	r0, _var_grid
	push	r0
	ld	r0, _var_i
	mul	r0, 12
	pop	r1
	add	r0, r1
	push	r0
	ld	r0, _var_j
	mul	r0, 4
	pop	r1
	add	r0, r1
	mov	r1, r0
	pop	r0
	st	r1, r0
	ld	r0, _var_j
	add	r0, 1
	mov	r1, _var_j
	st	r1, r0
	jmp	@for_7
@endfor_9:
	ld	r0, _var_i
	add	r0, 1
	mov	r1, _var_i
	st	r1, r0
	jmp	@for_4
@endfor_6:

	; testrap.pas(68): Writeln('Grid[1, 2] = %d', grid[1, 2]);
	mov	r0, _var_grid
	push	r0
	mov	r0, 1
	mul	r0, 12
	pop	r1
	add	r0, r1
	push	r0
	mov	r0, 2
	mul	r0, 4
	pop	r1
	add	r0, r1
	ld	r0, r0
	push	r0
	mov	r0, _strconst_5
	push	r0
	popr	2
	syscall	$1	; _SysCall_DebugPrint

	; testrap.pas(69): Writeln('Grid[2, 0] = %d', grid[2, 0]);
	mov	r0, _var_grid
	push	r0
	mov	r0, 2
	mul	r0, 12
	pop	r1
	add	r0, r1
	push	r0
	mov	r0, 0
	mul	r0, 4
	pop	r1
	add	r0, r1
	ld	r0, r0
	push	r0
	mov	r0, _strconst_6
	push	r0
	popr	2
	syscall	$1	; _SysCall_DebugPrint
	leave
	ret


_var_points:
	.res	24

_var_ptptr:
	.res	4

_var_hero:
	.res	24

_var_grid:
	.res	36

_var_i:
	.res	4

_var_j:
	.res	4

_strconst_5:
	.str	"Grid[1, 2] = %d", 13, 10, 0

_strconst_6:
	.str	"Grid[2, 0] = %d", 13, 10, 0

_strconst_2:
	.str	"Ptr[0]: %d, %d", 13, 10, 0

_strconst_1:
	.str	"ScalePoint var test: %d, %d", 13, 10, 0

_strconst_3:
	.str	"Ptr[1] after Inc: %d, %d", 13, 10, 0

_strconst_4:
	.str	"Hero ID=%d, Pos=(%d, %d), HP=%d, ATK=%d", 13, 10, 0
