	call	Main
	halt

Main:

	; floats.pas(12): fa := 9.876;
	mov	r0, 1092486169
	mov	r1, _var_fa
	st	r1, r0

	; floats.pas(13): ia := 1234;
	mov	r0, 1234
	mov	r1, _var_ia
	st	r1, r0

	; floats.pas(15): Writeln('%f %d', fa, ia);
	ld	r0, _var_ia
	push	r0
	ld	r0, _var_fa
	push	r0
	mov	r0, _strconst_1
	push	r0
	popr	3
	syscall	$1	; _SysCall_DebugPrint

	; floats.pas(17): fb := Single(ia);
	ld	r0, _var_ia
	itof	r0, r0
	mov	r1, _var_fb
	st	r1, r0

	; floats.pas(18): ib := Integer(fa);
	ld	r0, _var_fa
	ftoi	r0, r0
	mov	r1, _var_ib
	st	r1, r0

	; floats.pas(20): Writeln('%f %d', fb, ib);
	ld	r0, _var_ib
	push	r0
	ld	r0, _var_fb
	push	r0
	mov	r0, _strconst_1
	push	r0
	popr	3
	syscall	$1	; _SysCall_DebugPrint

	; floats.pas(22): ia := trunc(fa);
	ld	r0, _var_fa
	ftoi	r0, r0
	mov	r1, _var_ia
	st	r1, r0

	; floats.pas(23): ib := round(fa);
	ld	r0, _var_fa
	frnd	r0, r0
	mov	r1, _var_ib
	st	r1, r0

	; floats.pas(25): Writeln('%d %d', ia, ib);
	ld	r0, _var_ib
	push	r0
	ld	r0, _var_ia
	push	r0
	mov	r0, _strconst_2
	push	r0
	popr	3
	syscall	$1	; _SysCall_DebugPrint
	ret


_var_fa:
	.res	4

_var_fb:
	.res	4

_var_ia:
	.res	4

_var_ib:
	.res	4

_strconst_1:
	.str	"%f %d", 13, 10, 0

_strconst_2:
	.str	"%d %d", 13, 10, 0
