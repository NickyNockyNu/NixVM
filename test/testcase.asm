	call	Main
	halt

classifyint:
	enter	1, $4

	; testcase.pas(12): Write('%d: ', a);
	ldo	r0, bp, -4
	push	r0
	mov	r0, _strconst_1
	push	r0
	popr	2
	syscall	$1	; _SysCall_DebugPrint

	; testcase.pas(13): case a of
	ldo	r0, bp, -4
	push	r0
	ldo	r0, sp, 0
	cmp	r0, 3
	je	@case_branch_2
	ldo	r0, sp, 0
	cmp	r0, 5
	je	@case_branch_2
	ldo	r0, sp, 0
	cmp	r0, 7
	je	@case_branch_2
	jmp	@case_next_3
@case_branch_2:

	; testcase.pas(14): 3, 5, 7: Writeln('Small prime');
	mov	r0, _strconst_2
	syscall	$1	; _SysCall_DebugPrint
	jmp	@endcase_1
@case_next_3:
	ldo	r0, sp, 0
	cmp	r0, 13
	jl	@skip_range_6
	cmp	r0, 19
	jle	@case_branch_4
@skip_range_6:
	jmp	@case_next_5
@case_branch_4:

	; testcase.pas(15): 13..19:  Writeln('Teen');
	mov	r0, _strconst_3
	syscall	$1	; _SysCall_DebugPrint
	jmp	@endcase_1
@case_next_5:

	; testcase.pas(17): Writeln('Not classified');
	mov	r0, _strconst_4
	syscall	$1	; _SysCall_DebugPrint
@endcase_1:
	pop	r0
	leave
	ret

Main:

	; testcase.pas(25): for i := 0 to 20 do
	mov	r0, 0
	mov	r1, _var_i
	st	r1, r0
@for_7:
	ld	r0, _var_i
	cmp	r0, 20
	jg	@endfor_9

	; testcase.pas(26): classifyint(i);
	ld	r0, _var_i
	call	classifyint
	ld	r0, _var_i
	add	r0, 1
	mov	r1, _var_i
	st	r1, r0
	jmp	@for_7
@endfor_9:
	ret


_var_i:
	.res	4

_strconst_1:
	.str	"%d: ", 0

_strconst_3:
	.str	"Teen", 13, 10, 0

_strconst_4:
	.str	"Not classified", 13, 10, 0

_strconst_2:
	.str	"Small prime", 13, 10, 0
