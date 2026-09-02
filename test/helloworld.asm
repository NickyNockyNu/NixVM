.target "console", 1, 0
.name "HelloWorld"
.version 1, 0
.base   $4E0
.heap   0
.stack  128

	call	__program_begin_
	halt

Main:

	; helloworld.pas(11): Println('Hello, World!');
	mov	r0, _strconst_1
	syscall	$1	; _SysCall_DebugPrint
	ret

__program_begin_:

	; helloworld.pas(15): Main;
	call	Main
	ret


_strconst_1:
	.str	"Hello, World!", 13, 10, 0
