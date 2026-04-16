; hlasm.s -- HLASM-Inspired Macro-Assembler for COR24
; Step 001: Skeleton with UART output.
; Prints "HLASM" to UART and halts.
;
; UART data register at 0xFF0100 = -65280 signed
; UART status register at 0xFF0101 = -65279 signed
; TX busy: bit 7 of status (sign-extended: negative = busy)

_main:
	push	fp
	mov	fp,sp

	la	r2,-65280

	lc	r0,72
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lc	r0,76
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lc	r0,65
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lc	r0,83
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lc	r0,77
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

	mov	sp,fp
	pop	fp
_halt:
	bra	_halt

; _emit_char: Write one byte to UART (with TX busy-wait).
; Arg (on stack): byte value
_emit_char:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	la	r2,-65280

_poll:
	lb	r1,1(r2)
	cls	r1,z
	brt	_poll

	sb	r0,0(r2)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_crlf: Print CR+LF to UART.
_emit_crlf:
	push	fp
	mov	fp,sp
	push	r1

	lc	r0,13
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lc	r0,10
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	pop	r1
	mov	sp,fp
	pop	fp
	jmp	(r1)
