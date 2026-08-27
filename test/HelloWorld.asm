; ==============================================================================
; Disassembled by nvmd v1.0
; ROM:    HelloWorld (v1.0)
; Target: Test (v1.0)
; ==============================================================================

.target	"Test", 1, 0
.name	"HelloWorld"
.version	1, 0
.base	$4E0
.stack	128

	call	sub_000004E8
	halt

sub_000004E8:
	mov	r0, data_000004FA
	push	r0
	pop	r0
	syscall	$1 ; _SysCall_DebugPrint
	ret

data_000004FA:
	.str	"Hello, World!", 13, 10, 0
