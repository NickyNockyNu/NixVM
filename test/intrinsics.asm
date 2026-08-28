	call	Main
	halt

Main:

	; intrinsics.pas(18): i := 100;
	mov	r0, 100
	mov	r1, _var_i
	st	r1, r0

	; intrinsics.pas(19): Inc(i);        // 101
	mov	r1, 1
	ld	r0, _var_i
	add	r0, r1
	mov	r1, _var_i
	st	r1, r0

	; intrinsics.pas(20): Inc(i, 9);     // 110
	mov	r0, 9
	mov	r1, r0
	ld	r0, _var_i
	add	r0, r1
	mov	r1, _var_i
	st	r1, r0

	; intrinsics.pas(21): Dec(i, 10);    // 100
	mov	r0, 10
	mov	r1, r0
	ld	r0, _var_i
	sub	r0, r1
	mov	r1, _var_i
	st	r1, r0

	; intrinsics.pas(23): c := Chr(65);  // 'A'
	mov	r0, 65
	mov	r1, _var_c
	stb	r1, r0

	; intrinsics.pas(24): c := Succ(c);  // 'B'
	ldb	r0, _var_c
	add	r0, 1
	mov	r1, _var_c
	stb	r1, r0

	; intrinsics.pas(26): s := TState.Running;
	mov	r0, 1
	mov	r1, _var_s
	stb	r1, r0

	; intrinsics.pas(27): s := Succ(s);  // Paused (2)
	ldb	r0, _var_s
	add	r0, 1
	mov	r1, _var_s
	stb	r1, r0

	; intrinsics.pas(29): Writeln('i=%d, c=%c, Ord(c)=%d, s=%d', i, c, Ord(c), Ord(s));
	ldb	r0, _var_s
	push	r0
	ldb	r0, _var_c
	push	r0
	mov	r1, _var_c
	ldb	r0, r1
	push	r0
	ld	r0, _var_i
	push	r0
	mov	r0, _strconst_1
	push	r0
	popr	$5
	syscall	$1

	; intrinsics.pas(30): Writeln('Low(Arr)=%d, High(Arr)=%d, Length(Arr)=%d', Low(Arr), High(Arr), Length(Arr));
	mov	r0, 11
	push	r0
	mov	r0, 20
	push	r0
	mov	r0, 10
	push	r0
	mov	r0, _strconst_2
	push	r0
	popr	$4
	syscall	$1

	; intrinsics.pas(32): p := nil;
	mov	r0, 0
	mov	r1, _var_p
	st	r1, r0

	; intrinsics.pas(33): if not Assigned(p) then
	ld	r0, _var_p
	cmp	r0, 0
	setne	r0
	not	r0, r0
	cmp	r0, 0
	je	@endif_2

	; intrinsics.pas(34): Writeln('Assigned check OK');
	mov	r0, _strconst_3
	syscall	$1
@endif_2:
	ret


_var_i:
	.res	4

_var_c:
	.res	4

_var_s:
	.res	4

_var_p:
	.res	4

_strconst_2:
	.str	"Low(Arr)=%d, High(Arr)=%d, Length(Arr)=%d", 13, 10, 0

_strconst_3:
	.str	"Assigned check OK", 13, 10, 0

_strconst_1:
	.str	"i=%d, c=%c, Ord(c)=%d, s=%d", 13, 10, 0
