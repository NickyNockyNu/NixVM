.target "console", 1, 0
.name "testheapfile"
.version 1, 0
.base   $528
.heap   32768
.stack  16384

	call	__program_begin_
	halt


; testheapfile.pas(18): function MakeOrLoad(AFileName: String): PData;
MakeOrLoad:
	enter	1, $8

	; testheapfile.pas(20): Print('loading...');
	mov	r0, _strconst_1
	syscall	$1	; _SysCall_DebugPrint

	; testheapfile.pas(21): Result := HeapLoad(AFileName);
	ldo	r0, bp, -4
	syscall	$25	; _SysCall_HeapLoad
	sto	bp, r0, -8

	; testheapfile.pas(23): if not Assigned(Result) then
	ldo	r0, bp, -8
	cmp	r0, 0
	jnz	@else_1

	; testheapfile.pas(25): Println('[failed]');
	mov	r0, _strconst_2
	syscall	$1	; _SysCall_DebugPrint

	; testheapfile.pas(27): Print('allocating...');
	mov	r0, _strconst_3
	syscall	$1	; _SysCall_DebugPrint

	; testheapfile.pas(28): Result := HeapAlloc(SizeOf(TData));
	mov	r0, 16
	syscall	$20	; _SysCall_HeapAlloc
	sto	bp, r0, -8

	; testheapfile.pas(30): if not Assigned(Result) then
	ldo	r0, bp, -8
	cmp	r0, 0
	jnz	@else_3

	; testheapfile.pas(32): Println('[failed]');
	mov	r0, _strconst_2
	syscall	$1	; _SysCall_DebugPrint

	; testheapfile.pas(33): Exit;
	leave
	ret
@else_3:

	; testheapfile.pas(36): Println('[ok]');
	mov	r0, _strconst_4
	syscall	$1	; _SysCall_DebugPrint

	; testheapfile.pas(38): Result^.a := 11;
	push	$B
	ldo	r1, bp, -8
	pop	r0
	st	r1, r0

	; testheapfile.pas(39): Result^.b := 22;
	push	$16
	ldo	r0, bp, -8
	add	r0, 4
	mov	r1, r0
	pop	r0
	st	r1, r0

	; testheapfile.pas(40): Result^.c := 33;
	push	$21
	ldo	r0, bp, -8
	add	r0, 8
	mov	r1, r0
	pop	r0
	st	r1, r0

	; testheapfile.pas(41): Result^.d := 44;
	push	$2C
	ldo	r0, bp, -8
	add	r0, 12
	mov	r1, r0
	pop	r0
	st	r1, r0

	; testheapfile.pas(43): Print('saving...');
	mov	r0, _strconst_5
	syscall	$1	; _SysCall_DebugPrint

	; testheapfile.pas(44): if HeapSave(AFileName, Result) = SizeOf(TData) then
	ldo	r0, bp, -8
	push	r0
	ldo	r0, bp, -4
	push	r0
	popr	2
	syscall	$26	; _SysCall_HeapSave
	cmp	r0, 16
	jnz	@else_5

	; testheapfile.pas(45): Println('[ok]')
	mov	r0, _strconst_4
	syscall	$1	; _SysCall_DebugPrint
	jmp	@endif_2
@else_5:

	; testheapfile.pas(48): Println('[failed]');
	mov	r0, _strconst_2
	syscall	$1	; _SysCall_DebugPrint

	; testheapfile.pas(49): HeapFree(Result);
	ldo	r0, bp, -8
	syscall	$22	; _SysCall_HeapFree

	; testheapfile.pas(50): Result := nil;
	mov	r0, 0
	sto	bp, r0, -8

	; testheapfile.pas(51): Exit;
	leave
	ret
@else_1:

	; testheapfile.pas(55): Println('[ok]');
	mov	r0, _strconst_4
	syscall	$1	; _SysCall_DebugPrint
@endif_2:
	ldo	r0, bp, -8

	; end (MakeOrLoad)
	leave
	ret


; testheapfile.pas(60): begin
__program_begin_:

	; testheapfile.pas(61): Data := MakeOrLoad('test');
	mov	r0, _strconst_6
	call	MakeOrLoad
	mov	r1, _var_data
	st	r1, r0

	; testheapfile.pas(63): if Assigned(Data) then
	ld	r0, _var_data
	cmp	r0, 0
	je	@endif_8

	; testheapfile.pas(64): Println('%d %d %d %d', Data^.a, Data^.b, Data^.c, Data^.d);
	ld	r0, _var_data
	ldo	r0, r0, 12
	push	r0
	ld	r0, _var_data
	ldo	r0, r0, 8
	push	r0
	ld	r0, _var_data
	ldo	r0, r0, 4
	push	r0
	ld	r0, _var_data
	ldo	r0, r0, 0
	push	r0
	push	_strconst_7
	popr	5
	syscall	$1	; _SysCall_DebugPrint
@endif_8:
	ret


_var_data:
	.res	4

_strconst_2:
	.str	"[failed]", 13, 10, 0

_strconst_4:
	.str	"[ok]", 13, 10, 0

_strconst_5:
	.str	"saving...", 0

_strconst_1:
	.str	"loading...", 0

_strconst_7:
	.str	"%d %d %d %d", 13, 10, 0

_strconst_3:
	.str	"allocating...", 0

_strconst_6:
	.str	"test", 0
