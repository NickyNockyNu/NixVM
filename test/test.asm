.target "Test", 1, 0
.name   "testcase"
.version 1, 0
.base   $4E0
.stack  128

	call	sub_000005B0
	halt

sub_000004E8:
	enter	1, $4
	ldo	r0, bp, -4
	push	r0
	mov	r0, data_00000600
	push	r0
	popr	2
	syscall	$1	; _SysCall_DebugPrint
	ldo	r0, bp, -4
	push	r0
	ldo	r0, sp, 0
	cmp	r0, 3
	je	@loc_0000054A
	ldo	r0, sp, 0
	cmp	r0, 5
	je	@loc_0000054A
	ldo	r0, sp, 0
	cmp	r0, 7
	je	@loc_0000054A
	jmp	@loc_00000560

@loc_0000054A:
	mov	r0, data_0000061D
	push	r0
	pop	r0
	syscall	$1	; _SysCall_DebugPrint
	jmp	@loc_000005AA

@loc_00000560:
	ldo	r0, sp, 0
	cmp	r0, 13
	jl	@loc_0000057E
	cmp	r0, 19
	jle	@loc_00000584

@loc_0000057E:
	jmp	@loc_0000059A

@loc_00000584:
	mov	r0, data_00000605
	push	r0
	pop	r0
	syscall	$1	; _SysCall_DebugPrint
	jmp	@loc_000005AA

@loc_0000059A:
	mov	r0, data_0000060C
	push	r0
	pop	r0
	syscall	$1	; _SysCall_DebugPrint

@loc_000005AA:
	pop	r0
	leave
	ret

sub_000005B0:
	mov	r0, 0
	mov	r1, data_000005FC
	st	r1, r0

@loc_000005BE:
	ld	r0, data_000005FC
	cmp	r0, 20
	jg	@loc_000005FA
	ld	r0, data_000005FC
	push	r0
	pop	r0
	call	sub_000004E8
	ld	r0, data_000005FC
	add	r0, 1
	mov	r1, data_000005FC
	st	r1, r0
	jmp	@loc_000005BE

@loc_000005FA:
	ret

data_000005FC:
	.db	$00, $00, $00, $00

data_00000600:
	.str	"%d: ", 0

data_00000605:
	.str	"Teen", 13, 10, 0

data_0000060C:
	.str	"Not classified", 13, 10, 0

data_0000061D:
	.str	"Small prime", 13, 10, 0
