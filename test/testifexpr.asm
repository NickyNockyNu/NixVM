.target "console", 1, 0
.name "TestIfExpr"
.version 1, 0
.base   $4E0
.heap   0
.stack  128

	call	__program_begin_
	halt


; testifexpr.pas(12): begin
__program_begin_:

	; testifexpr.pas(13): score := 85;
	mov	r0, 85
	mov	r1, _var_score
	st	r1, r0

	; testifexpr.pas(15): if (score > 10) and (score < 100) then
	ld	r0, _var_score
	cmp	r0, 10
	jle	@and_false_3
	ld	r0, _var_score
	cmp	r0, 100
	setl	r0
	cmp	r0, 0
	setne	r0
	jmp	@and_end_4
@and_false_3:
	mov	r0, 0
@and_end_4:
	cmp	r0, 0
	je	@else_1

	; testifexpr.pas(16): PrintLn('yeps')
	mov	r0, _strconst_1
	syscall	$1	; _SysCall_DebugPrint
	jmp	@endif_2
@else_1:

	; testifexpr.pas(18): PrintLn('Nopes');
	mov	r0, _strconst_2
	syscall	$1	; _SysCall_DebugPrint
@endif_2:

	; testifexpr.pas(20): status := if score >= 50 then 'PASS' else 'FAIL';
	ld	r0, _var_score
	cmp	r0, 50
	jl	@ifexp_else_5
	mov	r0, _strconst_3
	jmp	@ifexp_end_6
@ifexp_else_5:
	mov	r0, _strconst_4
@ifexp_end_6:
	mov	r1, _var_status
	st	r1, r0

	; testifexpr.pas(21): Println('Score: %d -> Status: %s', score, status);
	ld	r0, _var_status
	push	r0
	ld	r0, _var_score
	push	r0
	push	_strconst_5
	popr	3
	syscall	$1	; _SysCall_DebugPrint

	; testifexpr.pas(23): bonus := if score > 80 then 10.5 else 0;
	ld	r0, _var_score
	cmp	r0, 80
	jle	@ifexp_else_7
	mov	r0, 1093140480
	jmp	@ifexp_end_8
@ifexp_else_7:
	mov	r0, 0
	itof	r0, r0
@ifexp_end_8:
	mov	r1, _var_bonus
	st	r1, r0

	; testifexpr.pas(24): Println('Bonus: %f', bonus);
	ld	r0, _var_bonus
	push	r0
	push	_strconst_6
	popr	2
	syscall	$1	; _SysCall_DebugPrint

	; testifexpr.pas(26): for i := 1 to 5 do
	mov	r0, 1
	mov	r1, _var_i
	st	r1, r0
@for_9:
	ld	r0, _var_i
	cmp	r0, 5
	jg	@endfor_11

	; testifexpr.pas(27): Println('Num %d is %s', i, if (i mod 2) = 0 then 'Even' else 'Odd');
	ld	r0, _var_i

	cmp	r0, 0
	jnz	@ifexp_else_12
	mov	r0, _strconst_7
	jmp	@ifexp_end_13
@ifexp_else_12:
	mov	r0, _strconst_8
@ifexp_end_13:
	push	r0
	ld	r0, _var_i
	push	r0
	push	_strconst_9
	popr	3
	syscall	$1	; _SysCall_DebugPrint
	ld	r0, _var_i
	add	r0, 1
	mov	r1, _var_i
	st	r1, r0
	jmp	@for_9
@endfor_11:

	; testifexpr.pas(29): score := -5;
	mov	r0, -5
	mov	r1, _var_score
	st	r1, r0

	; testifexpr.pas(30): Println('Sign: %s', if score > 0 then 'Positive' else if score < 0 then 'Negative' else 'Zero');
	ld	r0, _var_score
	cmp	r0, 0
	jle	@ifexp_else_14
	mov	r0, _strconst_10
	jmp	@ifexp_end_15
@ifexp_else_14:
	ld	r0, _var_score
	cmp	r0, 0
	jge	@ifexp_else_16
	mov	r0, _strconst_11
	jmp	@ifexp_end_17
@ifexp_else_16:
	mov	r0, _strconst_12
@ifexp_end_17:
@ifexp_end_15:
	push	r0
	push	_strconst_13
	popr	2
	syscall	$1	; _SysCall_DebugPrint
	ret


_var_score:
	.res	4

_var_status:
	.res	4

_var_bonus:
	.res	4

_var_i:
	.res	4

_strconst_9:
	.str	"Num %d is %s", 13, 10, 0

_strconst_11:
	.str	"Negative", 0

_strconst_1:
	.str	"yeps", 13, 10, 0

_strconst_6:
	.str	"Bonus: %f", 13, 10, 0

_strconst_4:
	.str	"FAIL", 0

_strconst_10:
	.str	"Positive", 0

_strconst_5:
	.str	"Score: %d -> Status: %s", 13, 10, 0

_strconst_3:
	.str	"PASS", 0

_strconst_2:
	.str	"Nopes", 13, 10, 0

_strconst_12:
	.str	"Zero", 0

_strconst_8:
	.str	"Odd", 0

_strconst_7:
	.str	"Even", 0

_strconst_13:
	.str	"Sign: %s", 13, 10, 0
