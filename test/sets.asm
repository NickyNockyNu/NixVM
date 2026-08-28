	call	Main
	halt

Test:
	enter	0, $8

	; sets.pas(19): Day := TDays.Mon;
	mov	r0, 0
	stob	bp, r0, -4

	; sets.pas(21): if Day in Weekend then
	ldob	r0, bp, -4
	push	r0
	mov	r0, 96
	mov	r1, r0
	pop	r0
	cmp	r0, 0
	je	@endif_2

	; sets.pas(22): Writeln('Weekend!');
	mov	r0, _strconst_1
	syscall	$1
@endif_2:

	; sets.pas(24): Work := [TDays.Tue..TDays.Wed, TDays.Fri, TDays.Sun];
	mov	r0, 86
	sto	bp, r0, -8

	; sets.pas(25): Work := Work - [TDays.Sun];
	push	r0
	mov	r0, 64
	mov	r1, r0
	pop	r0
	bclr	r0, r1
	sto	bp, r0, -8

	; sets.pas(27): if not (TDays.Sun in Work) then
	mov	r0, 6
	push	r0
	ldo	r0, bp, -8
	mov	r1, r0
	pop	r0
	not	r0, r0
	cmp	r0, 0
	je	@endif_4

	; sets.pas(28): Writeln('we dont work sundays!');
	mov	r0, _strconst_2
	syscall	$1
@endif_4:

	; sets.pas(30): case Day of
	ldob	r0, bp, -4
	push	r0
	ldo	r0, sp, 0
	cmp	r0, 0
	je	@case_branch_6
	jmp	@case_next_7
@case_branch_6:

	; sets.pas(32): Writeln('YAWN! Monday');
	mov	r0, _strconst_3
	syscall	$1
	jmp	@endcase_5
@case_next_7:
	ldo	r0, sp, 0
	cmp	r0, 1
	jl	@case_next_9
	cmp	r0, 4
	jle	@case_branch_8
	jmp	@case_next_9
@case_branch_8:

	; sets.pas(35): Writeln('Week day');
	mov	r0, _strconst_4
	syscall	$1
	jmp	@endcase_5
@case_next_9:
	ldo	r0, sp, 0
	cmp	r0, 5
	je	@case_branch_10
	ldo	r0, sp, 0
	cmp	r0, 6
	je	@case_branch_10
	jmp	@case_next_11
@case_branch_10:

	; sets.pas(38): Writeln('Weekend');
	mov	r0, _strconst_5
	syscall	$1
	jmp	@endcase_5
@case_next_11:

	; sets.pas(40): Writeln('Time and space is broken');
	mov	r0, _strconst_6
	syscall	$1
@endcase_5:
	pop	r0
	leave
	ret

Main:

	; sets.pas(45): Test;
	call	Test
	ret


_strconst_5:
	.str	"Weekend", 13, 10, 0

_strconst_1:
	.str	"Weekend!", 13, 10, 0

_strconst_3:
	.str	"YAWN! Monday", 13, 10, 0

_strconst_4:
	.str	"Week day", 13, 10, 0

_strconst_6:
	.str	"Time and space is broken", 13, 10, 0

_strconst_2:
	.str	"we dont work sundays!", 13, 10, 0
