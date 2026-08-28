	call	Main
	halt

Main:

	; helloworld.pas(11): Writeln('Hello, World!');
	mov	r0, _strconst_1
	syscall	$1
	ret


_strconst_1:
	.str	"Hello, World!", 13, 10, 0
