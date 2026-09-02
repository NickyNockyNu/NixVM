.target "console", 1, 0
.name "HelloWorld"
.version 1, 0
.base   $528
.heap   0
.stack  128

	call	__program_begin_
	halt


; helloworld.pas(9): procedure Main;
Main:

	; helloworld.pas(11): Println('Hello, World!');
	mov	r0, _strconst_1
	syscall	$1	; _SysCall_DebugPrint

	; helloworld.pas(12): Halt(123);
	mov	r0, 123
	mov	r1, 1164
	st	r1, r0
	halt

	; end (Main)


; helloworld.pas(15): begin
__program_begin_:

	; helloworld.pas(16): Main;
	call	Main
	ret


_strconst_1:
	.str	"Hello, World!", 13, 10, 0
