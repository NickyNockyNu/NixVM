	call	Main
	halt

ShouldNotBeCalled:
	enter	$4

	; shortcircuit.pas(9): Writeln('ERROR: Right side was evaluated!');
	mov	r0, _strconst_1
	syscall	$1

	; shortcircuit.pas(10): Result := True;
	mov	r0, 1
	sto	bp, r0, -4
	leave
	ret

Main:

	; shortcircuit.pas(15): if (1 = 2) and ShouldNotBeCalled then

	; shortcircuit.pas(16): Writeln('Unreachable');

	; shortcircuit.pas(19): if (1 = 1) or ShouldNotBeCalled then

	; shortcircuit.pas(20): Writeln('Short-circuit OR OK');
	mov	r0, _strconst_3
	syscall	$1
	ret


_strconst_3:
	.str	"Short-circuit OR OK", 13, 10, 0

_strconst_1:
	.str	"ERROR: Right side was evaluated!", 13, 10, 0

