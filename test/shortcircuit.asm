	call	Main
	halt

ShouldNotBeCalled:
	enter	0, $4

	; shortcircuit.pas(9): Writeln('ERROR: Right side was evaluated!');
	mov	r0, _strconst_1
	syscall	$1	; _SysCall_DebugPrint

	; shortcircuit.pas(10): Result := True;
	mov	r0, 1
	sto	bp, r0, -4
	leave
	ret

Main:

	; shortcircuit.pas(15): if (1 = 2) and ShouldNotBeCalled then
	jmp	@endif_2

	; shortcircuit.pas(16): Writeln('Unreachable');
@endif_2:

	; shortcircuit.pas(19): if (1 = 1) or ShouldNotBeCalled then
	jmp	@or_true_7
@or_true_7:

	; shortcircuit.pas(20): Writeln('Short-circuit OR OK');
	mov	r0, _strconst_3
	syscall	$1	; _SysCall_DebugPrint
	ret


_strconst_3:
	.str	"Short-circuit OR OK", 13, 10, 0

_strconst_1:
	.str	"ERROR: Right side was evaluated!", 13, 10, 0

