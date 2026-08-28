	call	Main
	halt

CountDownA:
	enter	1, $4

	; UnitForward.pas(20): if n > 0 then
	ldo	r0, bp, -4
	cmp	r0, 0
	jle	@endif_2

	; UnitForward.pas(22): Writeln('A: %d', n);
	ldo	r0, bp, -4
	push	r0
	mov	r0, _strconst_1
	push	r0
	popr	2
	syscall	$1	; _SysCall_DebugPrint

	; UnitForward.pas(23): CountDownB(n - 1);
	ldo	r0, bp, -4
	sub	r0, 1
	call	CountDownB
@endif_2:
	leave
	ret

CountDownB:
	enter	1, $4

	; UnitForward.pas(29): if n > 0 then
	ldo	r0, bp, -4
	cmp	r0, 0
	jle	@endif_4

	; UnitForward.pas(31): Writeln('B: %d', n);
	ldo	r0, bp, -4
	push	r0
	mov	r0, _strconst_2
	push	r0
	popr	2
	syscall	$1	; _SysCall_DebugPrint

	; UnitForward.pas(32): CountDownA(n - 1);
	ldo	r0, bp, -4
	sub	r0, 1
	call	CountDownA
@endif_4:
	leave
	ret

Main:

	; testforward.pas(11): CountDownA(6);
	mov	r0, 6
	call	CountDownA
	ret


_strconst_2:
	.str	"B: %d", 13, 10, 0

_strconst_1:
	.str	"A: %d", 13, 10, 0
