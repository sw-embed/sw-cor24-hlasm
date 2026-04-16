; hlasm.s -- HLASM-Inspired Macro-Assembler for COR24
; Step 002: Source buffer reader with UART output.
;
; UART data register at 0xFF0100 = -65280 signed
; UART status register at 0xFF0101 = -65279 signed
; TX busy: bit 7 of status (sign-extended: negative = busy)
;
; Source buffer descriptor layout (9 bytes):
;   +0: base address (24-bit)
;   +3: length (24-bit)
;   +6: current position (24-bit)

_main:
	push	fp
	mov	fp,sp

	la	r2,-65280

	la	r0,_src_desc
	push	r0
	la	r0,_echo_source
	jal	r1,(r0)
	add	sp,3

	mov	sp,fp
	pop	fp
_halt:
	bra	_halt

; _echo_source: Read all chars from source buffer and echo to UART.
; Arg (on stack): pointer to source descriptor
_echo_source:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	lw	r2,9(fp)

_echo_loop:
	push	r2
	la	r0,_read_char
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_echo_done

	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lw	r2,9(fp)
	bra	_echo_loop

_echo_done:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _read_char: Read next byte from source buffer.
; Arg (on stack): pointer to source descriptor
; Returns: r0 = byte value (0-255), or 0 on EOF
_read_char:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r2,9(fp)

	lw	r0,6(r2)
	lw	r1,3(r2)
	clu	r0,r1
	brf	_read_eof

	lw	r1,6(r2)
	lw	r0,0(r2)
	add	r0,r1
	lbu	r0,0(r0)

	lw	r1,6(r2)
	add	r1,1
	sw	r1,6(r2)

	bra	_read_ret

_read_eof:
	la	r0,0

_read_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _peek_char: Read current byte without advancing.
; Arg (on stack): pointer to source descriptor
; Returns: r0 = byte value (0-255), or 0 on EOF
_peek_char:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r2,9(fp)

	lw	r0,6(r2)
	lw	r1,3(r2)
	clu	r0,r1
	brf	_peek_eof

	lw	r1,6(r2)
	lw	r0,0(r2)
	add	r0,r1
	lbu	r0,0(r0)

	bra	_peek_ret

_peek_eof:
	la	r0,0

_peek_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _at_eol: Check if current position is at newline or EOF.
; Arg (on stack): pointer to source descriptor
; Returns: r0 = 1 if at EOL/EOF, 0 otherwise
; Sets C flag if at EOL/EOF
_at_eol:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r2,9(fp)

	lw	r0,6(r2)
	lw	r1,3(r2)
	clu	r0,r1
	brt	_at_eol_yes

	push	r2
	la	r0,_peek_char
	jal	r1,(r0)
	add	sp,3

	lc	r1,10
	ceq	r0,r1
	brt	_at_eol_yes

	la	r0,0
	bra	_at_eol_ret

_at_eol_yes:
	la	r0,1

_at_eol_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _advance_char: Move position forward by 1.
; Arg (on stack): pointer to source descriptor
_advance_char:
	push	fp
	push	r1
	mov	fp,sp

	lw	r1,9(fp)

	lw	r0,6(r1)
	add	r0,1
	sw	r0,6(r1)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _skip_whitespace: Advance past spaces (32) and tabs (9).
; Arg (on stack): pointer to source descriptor
_skip_whitespace:
	push	fp
	push	r0
	push	r1
	push	r2
	mov	fp,sp

	lw	r2,9(fp)

_sw_loop:
	push	r2
	la	r0,_peek_char
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_sw_done

	lc	r1,32
	ceq	r0,r1
	brt	_sw_skip

	lc	r1,9
	ceq	r0,r1
	brt	_sw_skip

	bra	_sw_done

_sw_skip:
	push	r2
	la	r0,_advance_char
	jal	r1,(r0)
	add	sp,3

	bra	_sw_loop

_sw_done:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	r0
	pop	fp
	jmp	(r1)

; _skip_to_eol: Advance to end of current line (past newline or to EOF).
; Arg (on stack): pointer to source descriptor
_skip_to_eol:
	push	fp
	push	r0
	push	r1
	push	r2
	mov	fp,sp

	lw	r2,9(fp)

_ste_loop:
	push	r2
	la	r0,_at_eol
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brf	_ste_done

	push	r2
	la	r0,_advance_char
	jal	r1,(r0)
	add	sp,3

	bra	_ste_loop

_ste_done:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	r0
	pop	fp
	jmp	(r1)

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

_src_desc:
	.word	524288
	.word	5
	.word	0
