; hlasm.s -- HLASM-Inspired Macro-Assembler for COR24
; Step 003: Scanner / tokenizer.
;
; UART at 0xFF0100 (-65280). TX busy: bit 7 of status (sign-extended).
;
; Source buffer descriptor (9 bytes):
;   +0: base address, +3: length, +6: position
;
; Token types (word-sized):
;   0=EOF 1=NEWLINE 2=KEYWORD 3=MNEMONIC 4=REGISTER 5=NUMBER
;   6=IDENT 7=LABEL 8=COMMENT 9=COMMA 10=LPAREN 11=RPAREN
;   12=BACKSLASH 13=DOT_IDENT
;
; Stack convention: jal stores RA in r1, does NOT push to stack.
; After N pushes + mov fp,sp, first caller arg is at N*3(fp).
; Functions returning r0 must NOT pop r0 (use add sp,3 instead).

_main:
	push	fp
	mov	fp,sp

_sa_loop:
	la	r0,_src_desc
	push	r0
	la	r0,_next_token
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_sa_done

	bra	_sa_loop

_sa_done:
	mov	sp,fp
	pop	fp
_halt:
	bra	_halt

; _next_token: Read and print next token.
; Arg on stack: src_desc pointer
; Returns: r0 = token type (0 = EOF)
; Frame: push fp, r1, r2 = 9 bytes. Arg at 9(fp).
_next_token:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r2,9(fp)

	push	r2
	la	r0,_skip_whitespace
	jal	r1,(r0)
	add	sp,3

	lw	r2,9(fp)
	push	r2
	la	r0,_peek_char
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_nt_eof

	push	r0
	lw	r2,9(fp)
	push	r2
	la	r0,_nt_switch
	jal	r1,(r0)
	add	sp,6

	bra	_nt_ret

_nt_eof:
	la	r0,0

_nt_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _nt_switch: Dispatch on first char to appropriate scanner.
; Args on stack: src_desc (9 fp), first_char (12 fp)
; Frame: push fp, r1 = 6 bytes. Args at 6,9(fp).
; Returns: r0 = token type
_nt_switch:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,9(fp)

	ceq	r0,z
	brt	_nsw_eof

	lc	r1,58
	ceq	r0,r1
	brt	_nsw_colon

	lc	r1,44
	ceq	r0,r1
	brt	_nsw_comma

	lc	r1,40
	ceq	r0,r1
	brt	_nsw_lparen

	lc	r1,41
	ceq	r0,r1
	brt	_nsw_rparen

	lc	r1,92
	ceq	r0,r1
	brt	_nsw_bslash

	lc	r1,10
	ceq	r0,r1
	brt	_nsw_newline

	lc	r1,59
	ceq	r0,r1
	brt	_nsw_comment

	lc	r1,35
	ceq	r0,r1
	brt	_nsw_comment

	lc	r1,46
	ceq	r0,r1
	brt	_nsw_dot

	lw	r0,9(fp)
	push	r0
	la	r0,_is_digit
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brf	_nsw_number

	lw	r0,9(fp)
	push	r0
	la	r0,_is_alpha
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brf	_nsw_ident

	la	r0,0
	bra	_nsw_ret

_nsw_eof:
	la	r0,0
	bra	_nsw_ret

_nsw_colon:
	lw	r0,6(fp)
	push	r0
	la	r0,_scan_colon
	jal	r1,(r0)
	add	sp,3
	bra	_nsw_ret

_nsw_comma:
	lw	r0,6(fp)
	push	r0
	la	r0,_scan_comma
	jal	r1,(r0)
	add	sp,3
	bra	_nsw_ret

_nsw_lparen:
	lw	r0,6(fp)
	push	r0
	la	r0,_scan_lparen
	jal	r1,(r0)
	add	sp,3
	bra	_nsw_ret

_nsw_rparen:
	lw	r0,6(fp)
	push	r0
	la	r0,_scan_rparen
	jal	r1,(r0)
	add	sp,3
	bra	_nsw_ret

_nsw_bslash:
	lw	r0,6(fp)
	push	r0
	la	r0,_scan_bslash
	jal	r1,(r0)
	add	sp,3
	bra	_nsw_ret

_nsw_newline:
	lw	r0,6(fp)
	push	r0
	la	r0,_scan_newline
	jal	r1,(r0)
	add	sp,3
	bra	_nsw_ret

_nsw_comment:
	lw	r0,6(fp)
	push	r0
	la	r0,_scan_comment
	jal	r1,(r0)
	add	sp,3
	bra	_nsw_ret

_nsw_dot:
	lw	r0,6(fp)
	push	r0
	la	r0,_scan_dot
	jal	r1,(r0)
	add	sp,3
	bra	_nsw_ret

_nsw_number:
	lw	r0,6(fp)
	push	r0
	la	r0,_scan_number
	jal	r1,(r0)
	add	sp,3
	bra	_nsw_ret

_nsw_ident:
	lw	r0,6(fp)
	push	r0
	la	r0,_scan_ident
	jal	r1,(r0)
	add	sp,3
	bra	_nsw_ret

_nsw_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_tt: Print type:text\r\n via _emit_type_text.
; Args on stack: text_ptr (6 fp), type (9 fp)
; Frame: push fp, r1 = 6 bytes. Args at 6,9(fp).
; Returns: r0 = type
_emit_tt:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,9(fp)
	lw	r1,6(fp)
	push	r1
	push	r0
	la	r0,_emit_type_text
	jal	r1,(r0)
	add	sp,6

	lw	r0,9(fp)
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_type_text: Print "TYPE:text\r\n" to UART.
; Args on stack: text_ptr (9 fp), type (12 fp)
; Frame: push fp, r1, r2 = 9 bytes. Args at 9,12(fp).
_emit_type_text:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,12(fp)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	lc	r0,58
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

_ett_loop:
	lw	r2,9(fp)
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_ett_done

	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lw	r2,9(fp)
	add	r2,1
	sw	r2,9(fp)
	bra	_ett_loop

_ett_done:
	la	r0,_emit_crlf
	jal	r1,(r0)

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _scan_colon: Scan colon, print "7::", advance.
; Arg on stack: src_desc ptr
; Frame: push fp, r1 = 6 bytes. Arg at 6(fp).
; Returns: r0 = 7
_scan_colon:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	push	r0
	la	r0,_advance_char
	jal	r1,(r0)
	add	sp,3

	la	r1,_colon_text
	la	r0,7
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,7
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

_colon_text:
	.byte 58,0

; _scan_comma: Scan comma.
; Frame: push fp, r1 = 6 bytes. Arg at 6(fp).
; Returns: r0 = 9
_scan_comma:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	push	r0
	la	r0,_advance_char
	jal	r1,(r0)
	add	sp,3

	la	r1,_comma_text
	la	r0,9
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,9
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

_comma_text:
	.byte 44,0

; _scan_lparen: Scan left paren.
; Frame: push fp, r1 = 6 bytes. Arg at 6(fp).
; Returns: r0 = 10
_scan_lparen:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	push	r0
	la	r0,_advance_char
	jal	r1,(r0)
	add	sp,3

	la	r1,_lparen_text
	la	r0,10
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,10
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

_lparen_text:
	.byte 40,0

; _scan_rparen: Scan right paren.
; Frame: push fp, r1 = 6 bytes. Arg at 6(fp).
; Returns: r0 = 11
_scan_rparen:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	push	r0
	la	r0,_advance_char
	jal	r1,(r0)
	add	sp,3

	la	r1,_rparen_text
	la	r0,11
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,11
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

_rparen_text:
	.byte 41,0

; _scan_bslash: Scan backslash.
; Frame: push fp, r1 = 6 bytes. Arg at 6(fp).
; Returns: r0 = 12
_scan_bslash:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	push	r0
	la	r0,_advance_char
	jal	r1,(r0)
	add	sp,3

	la	r1,_bslash_text
	la	r0,12
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,12
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

_bslash_text:
	.byte 92,0

; _scan_newline: Scan newline.
; Frame: push fp, r1 = 6 bytes. Arg at 6(fp).
; Returns: r0 = 1
_scan_newline:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	push	r0
	la	r0,_advance_char
	jal	r1,(r0)
	add	sp,3

	la	r1,_nl_text
	la	r0,1
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,1
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

_nl_text:
	.byte 10,0

; _scan_comment: Scan ; or # comment to end of line.
; Frame: push fp, r1, r2, r2 = 12 bytes. Arg at 12(fp).
; 0(fp) = buf_ptr
; Returns: r0 = 8
_scan_comment:
	push	fp
	push	r1
	push	r2
	push	r2
	mov	fp,sp

	lw	r2,12(fp)
	la	r1,_id_buf
	sw	r1,0(fp)

_sc_cloop:
	push	r2
	la	r0,_peek_char
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_sc_cdone

	lc	r1,10
	ceq	r0,r1
	brt	_sc_cdone

	lw	r1,0(fp)
	sb	r0,0(r1)
	add	r1,1
	sw	r1,0(fp)

	push	r2
	la	r0,_advance_char
	jal	r1,(r0)
	add	sp,3

	bra	_sc_cloop

_sc_cdone:
	lw	r1,0(fp)
	la	r0,0
	sb	r0,0(r1)

	la	r1,_id_buf
	la	r0,8
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,8
	mov	sp,fp
	pop	r2
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _scan_dot: Scan .directive.
; Frame: push fp, r1 = 6 bytes. Arg at 6(fp).
; Returns: r0 = 13
_scan_dot:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	push	r0
	la	r0,_advance_char
	jal	r1,(r0)
	add	sp,3

	la	r1,_id_buf
	lc	r0,46
	sb	r0,0(r1)
	add	r1,1

_sd_loop:
	lw	r0,6(fp)
	push	r0
	la	r0,_peek_char
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_sd_done

	push	r0
	la	r0,_is_alnum
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_sd_done

	sb	r0,0(r1)
	add	r1,1

	lw	r0,6(fp)
	push	r0
	la	r0,_advance_char
	jal	r1,(r0)
	add	sp,3

	bra	_sd_loop

_sd_done:
	la	r0,0
	sb	r0,0(r1)

	la	r1,_id_buf
	la	r0,13
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,13
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _scan_number: Scan decimal number.
; Frame: push fp, r1, r2, r2 = 12 bytes. Arg at 12(fp).
; 0(fp) = buf_ptr
; Returns: r0 = 5
_scan_number:
	push	fp
	push	r1
	push	r2
	push	r2
	mov	fp,sp

	lw	r2,12(fp)
	la	r1,_id_buf
	sw	r1,0(fp)

_sn_loop:
	push	r2
	la	r0,_peek_char
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_sn_done

	push	r0
	la	r0,_is_digit
	jal	r1,(r0)

	ceq	r0,z
	brt	_sn_not_digit

	pop	r0
	lw	r1,0(fp)
	sb	r0,0(r1)
	add	r1,1
	sw	r1,0(fp)

	push	r2
	la	r0,_advance_char
	jal	r1,(r0)
	add	sp,3

	bra	_sn_loop

_sn_not_digit:
	add	sp,3

_sn_done:
	lw	r1,0(fp)
	la	r0,0
	sb	r0,0(r1)

	la	r1,_id_buf
	la	r0,5
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,5
	mov	sp,fp
	pop	r2
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _scan_ident: Read identifier, classify, print.
; Frame: push fp, r1, r2, r2 = 12 bytes. Arg at 12(fp).
; 0(fp) = buf_ptr (saved in extra r2 slot)
; Returns: r0 = token type
_scan_ident:
	push	fp
	push	r1
	push	r2
	push	r2
	mov	fp,sp

	lw	r2,12(fp)
	la	r1,_id_buf
	sw	r1,0(fp)

_si_loop:
	push	r2
	la	r0,_peek_char
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_si_done

	push	r0
	la	r0,_is_alnum
	jal	r1,(r0)

	ceq	r0,z
	brt	_si_not_alnum

	pop	r0
	lw	r1,0(fp)
	sb	r0,0(r1)
	add	r1,1
	sw	r1,0(fp)

	push	r2
	la	r0,_advance_char
	jal	r1,(r0)
	add	sp,3

	bra	_si_loop

_si_not_alnum:
	add	sp,3

_si_done:
	lw	r1,0(fp)
	la	r0,0
	sb	r0,0(r1)

	la	r1,_id_buf
	la	r0,_mn_table
	push	r1
	push	r0
	la	r0,_lookup
	jal	r1,(r0)
	add	sp,6

	ceq	r0,z
	brt	_si_not_mn

	la	r1,_id_buf
	la	r0,3
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,3

_si_ret:
	mov	sp,fp
	pop	r2
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

_si_not_mn:
	la	r1,_id_buf
	la	r0,_reg_table
	push	r1
	push	r0
	la	r0,_lookup
	jal	r1,(r0)
	add	sp,6

	ceq	r0,z
	brt	_si_not_reg

	la	r1,_id_buf
	la	r0,4
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,4
	la	r1,_si_ret
	jmp	(r1)

_si_not_reg:
	la	r1,_id_buf
	la	r0,_cc_table
	push	r1
	push	r0
	la	r0,_lookup
	jal	r1,(r0)
	add	sp,6

	ceq	r0,z
	brt	_si_not_kw

	la	r1,_id_buf
	la	r0,2
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,2
	la	r1,_si_ret
	jmp	(r1)

_si_not_kw:
	la	r1,_id_buf
	la	r0,_kw_table
	push	r1
	push	r0
	la	r0,_lookup
	jal	r1,(r0)
	add	sp,6

	ceq	r0,z
	brt	_si_ident

	la	r1,_id_buf
	la	r0,2
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,2

_si_ident:
	la	r1,_id_buf
	la	r0,6
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,6
	la	r1,_si_ret
	jmp	(r1)

; _lookup: Check if id_buf matches any string in table.
; Args on stack: table_ptr (9 fp), id_buf_ptr (12 fp)
; Frame: push fp, r1, r2 = 9 bytes. Args at 9,12(fp).
; Returns: r0 = 1 if found, 0 if not
_lookup:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r2,9(fp)

_lt_entry:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_lt_no

	lw	r1,12(fp)
	push	r1
	push	r2
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6

	ceq	r0,z
	brf	_lt_yes

_lt_skip:
	lbu	r0,0(r2)
	add	r2,1
	ceq	r0,z
	brt	_lt_entry
	bra	_lt_skip

_lt_yes:
	la	r0,1
	bra	_lt_ret

_lt_no:
	la	r0,0

_lt_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _streq: Compare two null-terminated strings.
; Args on stack: table_ptr (9 fp), id_buf_ptr (12 fp)
; Frame: push fp, r1, r2 = 9 bytes. Args at 9,12(fp).
; Returns: r0 = 1 if equal
_streq:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r1,12(fp)
	lw	r2,9(fp)

_seq_loop:
	lbu	r0,0(r1)
	push	r2
	lbu	r2,0(r2)
	ceq	r0,r2
	brf	_seq_ne

	pop	r2

	ceq	r0,z
	brt	_seq_yes

	add	r1,1
	add	r2,1
	bra	_seq_loop

_seq_ne:
	add	sp,3
	la	r0,0
	bra	_seq_ret

_seq_yes:
	la	r0,1

_seq_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _is_alpha: r0 = 1 if A-Z or a-z
; Arg on stack: char (6 fp)
; Frame: push fp, r1 = 6 bytes. Arg at 6(fp).
; Returns: r0 = 1 or 0
_is_alpha:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)

	la	r1,_const_A
	lw	r1,0(r1)
	clu	r0,r1
	brt	_ia_mid2

	la	r1,_const_Zp1
	lw	r1,0(r1)
	clu r0,r1
	brt	_ia_mid1

	bra	_ia_mid2

_ia_mid2:
	la	r1,_const_a
	lw	r1,0(r1)
	clu	r0,r1
	brt	_ia_no

	la	r1,_const_zp1
	lw	r1,0(r1)
	clu r0,r1
	brt	_ia_yes

_ia_no:
	la	r0,0
	bra	_ia_ret

_ia_mid1:
	la	r0,1
	bra	_ia_ret

_ia_yes:
	la	r0,1

_ia_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _is_digit: r0 = 1 if 0-9
; Arg on stack: char (6 fp)
; Frame: push fp, r1 = 6 bytes. Arg at 6(fp).
; Returns: r0 = 1 or 0
_is_digit:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)

	lc	r1,48
	clu	r0,r1
	brt	_id_no

	lc	r1,58
	clu r0,r1
	brt	_id_yes

_id_no:
	la	r0,0
	bra	_id_ret

_id_yes:
	la	r0,1

_id_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _is_alnum: r0 = 1 if alnum or underscore
; Arg on stack: char (6 fp)
; Frame: push fp, r1 = 6 bytes. Arg at 6(fp).
; Returns: r0 = 1 or 0
_is_alnum:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)

	lc	r1,95
	ceq	r0,r1
	brt	_ian_yes

	push	r0
	la	r0,_is_alpha
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brf	_ian_yes

	lw	r0,6(fp)
	push	r0
	la	r0,_is_digit
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brf	_ian_yes

	la	r0,0
	bra	_ian_ret

_ian_yes:
	la	r0,1

_ian_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _skip_whitespace: Advance past spaces (32) and tabs (9).
; Arg (on stack): pointer to source descriptor
_skip_whitespace:
	push	fp
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
	pop	fp
	jmp	(r1)

; _skip_to_eol: Advance to end of current line (past newline or to EOF).
; Arg (on stack): pointer to source descriptor
_skip_to_eol:
	push	fp
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

; _emit_dec24: Print a small number (0-999) as decimal to UART.
; Arg on stack: number
; Frame: push fp, r1, r2 = 9 bytes. Arg at 9(fp).
_emit_dec24:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,9(fp)

	ceq	r0,z
	brt	_ed24_z

	lc	r1,100
	clu	r0,r1
	brt	_ed24_t

	la	r2,0

_ed24_hl:
	clu	r0,r1
	brt	_ed24_hd

	sub	r0,r1
	add	r2,1
	bra	_ed24_hl

_ed24_hd:
	lc	r0,48
	add	r0,r2
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

_ed24_t:
	lc	r1,10
	clu	r0,r1
	brt	_ed24_o

	la	r2,0

_ed24_tl:
	clu	r0,r1
	brt	_ed24_td

	sub	r0,r1
	add	r2,1
	bra	_ed24_tl

_ed24_td:
	lc	r0,48
	add	r0,r2
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

_ed24_o:
	lc	r1,48
	add	r0,r1
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	bra	_ed24_ret

_ed24_z:
	lc	r0,48
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

_ed24_ret:
	mov	sp,fp
	pop	r2
	pop	r1
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

	lw	r1,6(fp)

	lw	r0,6(r1)
	add	r0,1
	sw	r0,6(r1)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; --- Constants ---
_const_A:
	.word 65
_const_Zp1:
	.word 91
_const_a:
	.word 97
_const_zp1:
	.word 123

; --- Keyword table ---
_kw_table:
	.byte 77,65,67,82,79,0
	.byte 77,69,78,68,0
	.byte 73,70,0
	.byte 69,76,83,69,73,70,0
	.byte 69,76,83,69,0
	.byte 69,78,68,73,70,0
	.byte 68,79,0
	.byte 68,79,69,88,73,84,0
	.byte 73,84,69,82,65,84,69,0
	.byte 69,78,68,68,79,0
	.byte 83,69,76,69,67,84,0
	.byte 87,72,69,78,0
	.byte 79,84,72,69,82,87,73,83,69,0
	.byte 69,78,68,83,69,76,0
	.byte 83,69,84,0
	.byte 73,70,68,69,70,0
	.byte 73,70,78,68,69,70,0
	.byte 73,70,69,81,0
	.byte 73,70,78,69,0
	.byte 69,76,83,69,65,83,77,0
	.byte 69,78,68,73,70,65,83,77,0
	.byte 0

; --- Mnemonic table ---
_mn_table:
	.byte 110,111,112,0
	.byte 97,100,100,0
	.byte 115,117,98,0
	.byte 109,117,108,0
	.byte 97,110,100,0
	.byte 111,114,0
	.byte 120,111,114,0
	.byte 115,104,108,0
	.byte 115,114,97,0
	.byte 115,114,108,0
	.byte 99,101,113,0
	.byte 99,108,115,0
	.byte 99,108,117,0
	.byte 98,114,97,0
	.byte 98,114,116,0
	.byte 98,114,102,0
	.byte 106,109,112,0
	.byte 106,97,108,0
	.byte 108,97,0
	.byte 108,98,0
	.byte 108,98,117,0
	.byte 108,99,0
	.byte 108,99,117,0
	.byte 108,119,0
	.byte 115,98,0
	.byte 115,119,0
	.byte 109,111,118,0
	.byte 112,117,115,104,0
	.byte 112,111,112,0
	.byte 115,120,116,0
	.byte 122,120,116,0
	.byte 0

; --- Register table ---
_reg_table:
	.byte 114,48,0
	.byte 114,49,0
	.byte 114,50,0
	.byte 102,112,0
	.byte 115,112,0
	.byte 122,0
	.byte 105,118,0
	.byte 105,114,0
	.byte 0

; --- Condition specifier table ---
_cc_table:
	.byte 99,99,95,101,113,0
	.byte 99,99,95,110,101,0
	.byte 99,99,95,108,116,0
	.byte 99,99,95,108,117,0
	.byte 99,99,95,122,115,101,116,0
	.byte 99,99,95,122,99,108,114,0
	.byte 0

; --- Buffers ---
_id_buf:
	.byte 0, 0, 0, 0, 0, 0, 0, 0
	.byte 0, 0, 0, 0, 0, 0, 0, 0

; --- Source descriptor ---
_src_desc:
	.word	524288
	.word	64
	.word	0
