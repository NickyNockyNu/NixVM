	call	Main
	halt

Main:

	; exprfold.pas(10): i := 1 + 2 + 3;
	mov	r0, 6
	mov	r1, _var_i
	st	r1, r0

	; exprfold.pas(11): Writeln('%d', i);
	ld	r0, _var_i
	push	r0
	mov	r0, _strconst_1
	push	r0
	popr	2
	syscall	$1	; _SysCall_DebugPrint
	ret


_var_i:
	.res	4

_strconst_1:
	.str	"%d", 13, 10, 0
