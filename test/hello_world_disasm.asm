; ==============================================================================
; Disassembled by nvmd v1.0
; ROM:    hello_world (v1.0)
; Target: Test (v1.0)
; ==============================================================================

.target	"Test", 1, 0
.name	"hello_world"
.version	1, 0
.base	$4E0
.stack	128

	call	sub_000004E8
	halt

sub_000004E8:
	mov	r0, data_00000502
	mov	r1, data_0000050C
	mov	r2, data_00000512
	syscall	$1
	ret

data_00000502:
	.str	"%s, %s!", 13, 10, 0

data_0000050C:
	.str	"Hello", 0

data_00000512:
	.str	"World", 0
