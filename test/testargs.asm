	call	Main
	halt

Test:
	enter	4, $10

	; testargs.pas(9): Writeln('%d %d %d %d %d %d %d', a, b, c, d, e, f, g);
	ldo	r0, bp, 16
	push	r0
	ldo	r0, bp, 12
	push	r0
	ldo	r0, bp, 8
	push	r0
	ldo	r0, bp, -16
	push	r0
	ldo	r0, bp, -12
	push	r0
	ldo	r0, bp, -8
	push	r0
	ldo	r0, bp, -4
	push	r0
	mov	r0, _strconst_1
	push	r0
	popr	8
	syscall	$1	; _SysCall_DebugPrint
	leave
	ret

Main:

	; testargs.pas(13): Test(1, 2, 3, 4, 5, 6, 7);
	mov	r0, 7
	push	r0
	mov	r0, 6
	push	r0
	mov	r0, 5
	push	r0
	mov	r0, 4
	push	r0
	mov	r0, 3
	push	r0
	mov	r0, 2
	push	r0
	mov	r0, 1
	push	r0
	popr	4
	call	Test
	add	sp, 12
	ret


_strconst_1:
	.str	"%d %d %d %d %d %d %d", 13, 10, 0
