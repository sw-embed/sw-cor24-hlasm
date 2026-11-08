; hlasm.s -- HLASM-Inspired Macro-Assembler for COR24
; Step 007: Conditional assembly (SET, IFDEF, IFEQ, IFNDEF, IFNE; IFSAME, IFDIFF since saga step 10).
;
; UART at 0xFF0100 (-65280). TX busy: bit 7 of status (sign-extended).
;
; Source buffer descriptor (9 bytes):
;   +0: base address, +3: length, +6: position
;
; Bootstrap memory map (details: "Runtime memory map" near the data section):
;   0x010000-0x03FFFF symbol/macro tables, macro body pool, work area
;              (line and name buffers, assembly-time stacks), XREF tables
;   0x07F000  config block for extra source buffers
;   0x080000+ preloaded ASCII source/include buffers (main default length
;              32767 bytes)
;   0x0C0000+ runtime arena (counters, current source slot, source-return
;              stack), 4700 bytes
;   0x0D0000+ relax snapshot; 0x0E0000+ relax tables
;   EBR stack: prefer cor24-emu --stack-kilobytes 3 unless a future SRAM
;              fallback stack is explicitly needed
;
; Source config block at 0x07F000 (built by reg-rs/make_cfg.sh; all zero
; means main source only):
;   +0   member count N (0-32; more stops with an ERROR)
;   +3   main source base override (0 = default 0x080000)
;   +6   main source len override  (0 = default 32767)
;   +9   main source name, 16 bytes NUL-terminated (ERROR locations;
;        empty = "main")
;   +25  N member records of 22 bytes: base, len, name (16 bytes,
;        NUL-terminated, at most 15 chars; INCLUDE/COPY look it up, an
;        empty name is reachable only by slot number or by chaining).
;        Record i is source slot i+1.
;
; Token types (word-sized):
;   0=EOF 1=NEWLINE 2=KEYWORD 3=MNEMONIC 4=REGISTER 5=NUMBER
;   6=IDENT 7=LABEL 8=COMMENT 9=COMMA 10=LPAREN 11=RPAREN
;   12=BACKSLASH 13=DOT_IDENT
;
; Stack convention: jal stores RA in r1, does NOT push to stack.
; After N pushes + mov fp,sp, first caller arg is at N*3(fp).
; Functions returning r0 must NOT pop r0 (use add sp,3 instead).

; Step 005: Macro table -- record and expand macro definitions.

_main:
	push	fp
	mov	fp,sp
	push	r2
	mov	fp,sp

; Layout guards: the image must end below the tables at 0x010000, and the
; first relax snapshot region must fit its 1 KB slot at 0x0D0000.
	la	r0,_image_end
	la	r1,65536
	clu	r0,r1
	brt	_main_img_ok
	la	r0,_err_layout
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_main_img_ok:
	la	r0,_line_is_keyword
	la	r1,_const_A
	sub	r0,r1
	la	r1,1025
	clu	r0,r1
	brt	_main_snap_ok
	la	r0,_err_layout
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_main_snap_ok:

	la	r0,_relax_begin_pass
	jal	r1,(r0)

	la	r0,_init_runtime_arena
	jal	r1,(r0)

	la	r0,_init_src_table
	jal	r1,(r0)

_ml_loop:
	push	r0
	la	r0,_read_line
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brf	_ml_go
	la	r1,788191
	lw	r0,0(r1)
	ceq	r0,z
	brt	_ml_go

	la	r0,_emit_hldiag_banner_if_enabled
	jal	r1,(r0)

	la	r0,_emit_hldiag_undef_report
	jal	r1,(r0)

	la	r0,_emit_xref_report
	jal	r1,(r0)

	mov	sp,fp
	pop	r2
	pop	fp

	la	r0,_relax_pass
	lw	r0,0(r0)
	ceq	r0,z
	brf	_halt
	la	r0,_relax_end_pass1
	jal	r1,(r0)
	la	r0,_main
	jmp	(r0)

_halt:
	bra	_halt

_ml_go:
	sw	r0,0(fp)

	la	r1,787707
	lw	r0,0(r1)
	ceq	r0,z
	brf	_ml_cond_active

	la	r1,_ml_not_recording
	jmp	(r1)

_ml_cond_active:
	la	r0,_cond_top
	jal	r1,(r0)

	ceq	r0,z
	brf	_ml_cond_active_skip

	la	r1,_ml_not_recording
	jmp	(r1)

_ml_cond_active_skip:
	la	r1,_kw_endifasm
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_mc_skip_else

	la	r0,_ml_is_endifasm
	jal	r1,(r0)
	la	r1,_mc_skip_end
	jmp	(r1)

_mc_skip_else:
	la	r1,_kw_elseasm
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_mc_skip_ifdef

	la	r0,_ml_is_elseasm
	jal	r1,(r0)
	la	r1,_mc_skip_end
	jmp	(r1)

_mc_skip_ifdef:
	la	r1,_kw_ifdef
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_mc_skip_ifndef

	la	r0,_ml_is_ifdef
	jal	r1,(r0)
	la	r1,_mc_skip_end
	jmp	(r1)

_mc_skip_ifndef:
	la	r1,_kw_ifndef
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_mc_skip_ifeq

	la	r0,_ml_is_ifndef
	jal	r1,(r0)
	la	r1,_mc_skip_end
	jmp	(r1)

_mc_skip_ifeq:
	la	r1,_kw_ifeq
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_mc_skip_ifne

	la	r0,_ml_is_ifeq
	jal	r1,(r0)
	la	r1,_mc_skip_end
	jmp	(r1)

_mc_skip_ifne:
	la	r1,_kw_ifne
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_mc_skip_ifsame

	la	r0,_ml_is_ifne
	jal	r1,(r0)
	la	r1,_mc_skip_end
	jmp	(r1)

_mc_skip_ifsame:
	la	r1,_kw_ifsame
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_mc_skip_ifdiff

	la	r1,_ml_is_ifsame
	jmp	(r1)

_mc_skip_ifdiff:
	la	r1,_kw_ifdiff
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_mc_skip_ifne_handler

	la	r1,_ml_is_ifdiff
	jmp	(r1)

_mc_skip_ifne_handler:

_mc_skip_end:
	la	r1,_ml_loop
	jmp	(r1)

_ml_not_recording:
	la	r1,790710
	lw	r0,0(r1)
	ceq	r0,z
	brt	_mlnr_directives
	la	r1,_ml_recording
	jmp	(r1)

	_mlnr_directives:
	la	r1,_kw_include
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_include_near

	la	r1,_ml_is_include
	jmp	(r1)

_ml_is_include_near:

	la	r1,_kw_incbuf
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_incbuf_near

	la	r1,_ml_is_incbuf
	jmp	(r1)

_ml_is_incbuf_near:

	la	r1,_kw_srcbuf
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_srcbuf_near

	la	r1,_ml_is_srcbuf
	jmp	(r1)

_ml_is_srcbuf_near:

	la	r1,_kw_set
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_set_near

	la	r1,_ml_is_set
	jmp	(r1)

_ml_is_set_near:

	la	r1,_kw_endifasm
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_endifasm_near

	la	r1,_ml_is_endifasm
	jmp	(r1)

_ml_is_endifasm_near:

	la	r1,_kw_elseasm
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_elseasm_near

	la	r1,_ml_is_elseasm
	jmp	(r1)

_ml_is_elseasm_near:

	la	r1,_kw_ifdef
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_ifdef_near

	la	r1,_ml_is_ifdef
	jmp	(r1)

_ml_is_ifdef_near:

	la	r1,_kw_ifndef
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_ifndef_near

	la	r1,_ml_is_ifndef
	jmp	(r1)

_ml_is_ifndef_near:

	la	r1,_kw_ifeq
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_ifeq_near

	la	r1,_ml_is_ifeq
	jmp	(r1)

_ml_is_ifeq_near:

	la	r1,_kw_ifne
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_ifne_near

	la	r1,_ml_is_ifne
	jmp	(r1)

_ml_is_ifne_near:

	la	r1,_kw_ifsame
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_ifsame_near

	la	r1,_ml_is_ifsame
	jmp	(r1)

_ml_is_ifsame_near:

	la	r1,_kw_ifdiff
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_ifdiff_near

	la	r1,_ml_is_ifdiff
	jmp	(r1)

_ml_is_ifdiff_near:

	la	r1,_kw_if
	push	r1
	la	r0,_line_is_keyword
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_struct_if_near

	la	r1,_ml_is_struct_if
	jmp	(r1)

_ml_is_struct_if_near:

	la	r1,_kw_elseif
	push	r1
	la	r0,_line_is_keyword
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_struct_elseif_near

	la	r1,_ml_is_struct_elseif
	jmp	(r1)

_ml_is_struct_elseif_near:

	la	r1,_kw_else
	push	r1
	la	r0,_line_is_keyword
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_struct_else_near

	la	r1,_ml_is_struct_else
	jmp	(r1)

_ml_is_struct_else_near:

	la	r1,_kw_endif
	push	r1
	la	r0,_line_is_keyword
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_struct_endif_near

	la	r1,_ml_is_struct_endif
	jmp	(r1)

_ml_is_struct_endif_near:

	la	r1,_kw_do
	push	r1
	la	r0,_line_is_keyword
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_struct_do_near

	la	r1,_ml_is_struct_do
	jmp	(r1)

_ml_is_struct_do_near:

	la	r1,_kw_doexit
	push	r1
	la	r0,_line_is_keyword
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_struct_doexit_near

	la	r1,_ml_is_struct_doexit
	jmp	(r1)

_ml_is_struct_doexit_near:

	la	r1,_kw_iterate
	push	r1
	la	r0,_line_is_keyword
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_struct_iterate_near

	la	r1,_ml_is_struct_iterate
	jmp	(r1)

_ml_is_struct_iterate_near:

	la	r1,_kw_enddo
	push	r1
	la	r0,_line_is_keyword
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_struct_enddo_near

	la	r1,_ml_is_struct_enddo
	jmp	(r1)

	_ml_is_struct_enddo_near:

	la	r1,_kw_select
	push	r1
	la	r0,_line_is_keyword
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_struct_select_near

	la	r1,_ml_is_struct_select
	jmp	(r1)

_ml_is_struct_select_near:

	la	r1,_kw_when
	push	r1
	la	r0,_line_is_keyword
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_struct_when_near

	la	r1,_ml_is_struct_when
	jmp	(r1)

_ml_is_struct_when_near:

	la	r1,_kw_otherwise
	push	r1
	la	r0,_line_is_keyword
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_struct_otherwise_near

	la	r1,_ml_is_struct_otherwise
	jmp	(r1)

_ml_is_struct_otherwise_near:

	la	r1,_kw_endsel
	push	r1
	la	r0,_line_is_keyword
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_is_struct_endsel_near2

	la	r1,_ml_is_struct_endsel
	jmp	(r1)

_ml_is_struct_endsel_near2:

	la	r1,_kw_macro
	push	r1
	la	r0,_line_is_keyword
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_macro_near
	la	r1,_ml_is_macro
	jmp	(r1)

_ml_macro_near:

	la	r1,_kw_mend
	push	r1
	la	r0,_line_is_keyword
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_mend_near
	la	r1,_ml_is_mend_skip
	jmp	(r1)

_ml_mend_near:

	lw	r0,0(fp)
	push	r0
	la	r0,_is_structured
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brt	_ml_skipkw_near
	la	r1,_ml_skip_kw
	jmp	(r1)

_ml_skipkw_near:

	la	r1,_ml_nf4
	jmp	(r1)

	_ml_nf4:
		la	r1,_dot_ascii_txt
		push	r1
		la	r0,_starts_with
		jal	r1,(r0)
		add	sp,3

		ceq	r0,z
		brt	_ml_is_ascii_near

		la	r0,_handle_dot_ascii
		jal	r1,(r0)
		la	r1,_ml_loop
		jmp	(r1)

	_ml_is_ascii_near:

		la	r1,_dot_asciz_txt
		push	r1
		la	r0,_starts_with
		jal	r1,(r0)
		add	sp,3

		ceq	r0,z
		brt	_ml_is_asciz_near

		la	r0,_handle_dot_asciz
		jal	r1,(r0)
		la	r1,_ml_loop
		jmp	(r1)

	_ml_is_asciz_near:

		la	r1,_dot_space_txt
		push	r1
		la	r0,_starts_with
		jal	r1,(r0)
		add	sp,3

		ceq	r0,z
		brt	_ml_is_fill_near

		la	r0,_handle_dot_space
		jal	r1,(r0)
		la	r1,_ml_loop
		jmp	(r1)

	_ml_is_fill_near:

		la	r1,_dot_fill_txt
		push	r1
		la	r0,_starts_with
		jal	r1,(r0)
		add	sp,3

		ceq	r0,z
		brt	_ml_nf4b

		la	r0,_handle_dot_fill
		jal	r1,(r0)
		la	r1,_ml_loop
		jmp	(r1)

	_ml_nf4b:

		la	r0,_line_is_equ_stmt
		jal	r1,(r0)

		ceq	r0,z
		brt	_ml_nf4c

		la	r0,_handle_equ
		jal	r1,(r0)
		la	r1,_ml_loop
		jmp	(r1)

	_ml_nf4c:

		la	r1,_kw_copy
		push	r1
		la	r0,_line_is_keyword
		jal	r1,(r0)
		add	sp,3

		ceq	r0,z
		brt	_ml_nf4d

		la	r1,_ml_is_copy
		jmp	(r1)

	_ml_nf4d:

		lw	r0,0(fp)
		push	r0
		la	r0,_lookup_macro
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brf	_ml_emit_body

	la	r1,_ml_nf5
	jmp	(r1)

_ml_nf5:
	la	r0,_hldiag_check_unknown_mnemonic
	jal	r1,(r0)

	lw	r0,0(fp)
	push	r0
	la	r0,_emit_line
	jal	r1,(r0)
	add	sp,3
	la	r1,_ml_loop
	jmp	(r1)

_ml_emit_body:
	push	r0
	la	r0,_expand_macro
	jal	r1,(r0)
	add	sp,3
	la	r1,_ml_loop
	jmp	(r1)

_ml_skip_kw:
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_macro:
	la	r0,_extract_macro_name
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_mend_skip:
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_set:
	la	r0,_set_symbol
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_copy:
	la	r0,_handle_copy
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_include:
	la	r0,_handle_include
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_incbuf:
	la	r0,_handle_incbuf
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_srcbuf:
	la	r0,_handle_srcbuf
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_endifasm:
	la	r1,787707
	lw	r0,0(r1)
	add	r0,-1
	push	r0
	la	r0,_mul3
	jal	r1,(r0)
	add	sp,3
	la	r1,199712
	add	r1,r0
	la	r0,0
	sw	r0,0(r1)

	la	r1,787707
	lw	r0,0(r1)
	add	r0,-1
	sw	r0,0(r1)

	la	r1,_ml_loop
	jmp	(r1)

_ml_is_elseasm:
	la	r1,787707
	lw	r0,0(r1)
	add	r0,-1
	push	r0
	la	r0,_mul3
	jal	r1,(r0)
	add	sp,3
	la	r1,199712
	add	r1,r0
	lw	r0,0(r1)

	ceq	r0,z
	brf	_mle_was_skip

	la	r0,1
	sw	r0,0(r1)
	bra	_mle_done

_mle_was_skip:
	lc	r2,2
	ceq	r0,r2
	brt	_mle_done
	la	r0,0
	sw	r0,0(r1)

_mle_done:
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_ifdef:
	la	r0,_handle_ifdef
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_ifndef:
	la	r0,_handle_ifndef
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_ifeq:
	la	r0,_handle_ifeq
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_ifne:
	la	r0,_handle_ifne
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_ifsame:
	lc	r0,0
	bra	_ml_ifsame_call
_ml_is_ifdiff:
	lc	r0,1
_ml_ifsame_call:
	push	r0
	la	r0,_handle_ifsame
	jal	r1,(r0)
	add	sp,3
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_struct_if:
	la	r0,_handle_struct_if
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_struct_elseif:
	la	r0,_handle_struct_elseif
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_struct_else:
	la	r0,_handle_struct_else
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_struct_endif:
	la	r0,_handle_struct_endif
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_struct_do:
	la	r0,_handle_struct_do
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_struct_doexit:
	la	r0,_handle_struct_doexit
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_is_struct_iterate:
	la	r0,_handle_struct_iterate
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

	_ml_is_struct_enddo:
	la	r0,_handle_struct_enddo
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

	_ml_is_struct_select:
	la	r0,_handle_struct_select
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

	_ml_is_struct_when:
	la	r0,_handle_struct_when
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

	_ml_is_struct_otherwise:
	la	r0,_handle_struct_otherwise
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

	_ml_is_struct_endsel:
	la	r0,_handle_struct_endsel
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

_ml_recording:
	la	r1,_kw_mend
	push	r1
	la	r0,_starts_with
	jal	r1,(r0)
	add	sp,3

	ceq	r0,z
	brf	_ml_finish

	lw	r0,0(fp)
	push	r0
	la	r0,_record_macro_line
	jal	r1,(r0)
	add	sp,3
	la	r1,_ml_loop
	jmp	(r1)

_ml_finish:
	la	r0,_finish_macro
	jal	r1,(r0)
	la	r1,_ml_loop
	jmp	(r1)

; _read_line: Read one line from source into _line_buf.
; Returns: r0 = line length (0 on EOF)
; Frame: push fp, r1, r2, r2 = 12 bytes.
; 0(fp) = current length counter
; Uses runtime arena line buffer and source descriptor table for input.
_read_line:
	push	fp
	push	r1
	push	r2
	push	r2
	mov	fp,sp

	la	r1,196608
	la	r0,0
	sw	r0,0(fp)
	la	r1,788191
	sw	r0,0(r1)

; lines of an active macro expansion come before source lines
_rl_exp:
	la	r1,790719
	lw	r0,0(r1)
	ceq	r0,z
	brt	_rl_src
	la	r0,_exp_next_line
	jal	r1,(r0)
	ceq	r0,z
	brt	_rl_exp
	add	r0,-1
	mov	sp,fp
	pop	r2
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

_rl_src:
	la	r1,196608

_rl_loop:
	push	r1
	la	r2,786606
	push	r2
	la	r0,_read_char
	jal	r1,(r0)
	add	sp,3
	pop	r1

	ceq	r0,z
	brt	_rl_eof

	lc	r2,10
	ceq	r0,r2
	brt	_rl_eol

	sb	r0,0(r1)
	add	r1,1
	lw	r0,0(fp)
	add	r0,1
	sw	r0,0(fp)
	la	r2,257
	clu	r0,r2
	brt	_rl_loop
; count the line being read, so the ERROR names it
	la	r0,_current_src_desc
	jal	r1,(r0)
	mov	r2,r0
	lw	r0,9(r2)
	add	r0,1
	sw	r0,9(r2)
	la	r0,_err_line_long
	push	r0
	la	r0,_fatal
	jal	r1,(r0)

_rl_eof:
	lw	r0,0(fp)
	ceq	r0,z
	brt	_rl_eof_switch

	la	r0,0
	sb	r0,0(r1)
	bra	_rl_ret_len

_rl_eof_switch:
	push	r1
	la	r0,_pop_src_return
	jal	r1,(r0)
	pop	r1

	ceq	r0,z
	brf	_rl_switched_src

	push	r1
	la	r0,_advance_src_desc
	jal	r1,(r0)
	pop	r1

	ceq	r0,z
	brf	_rl_switched_src

	lw	r0,0(fp)
	ceq	r0,z
	brt	_rl_empty

	la	r0,0
	sb	r0,0(r1)
	bra	_rl_ret_len

_rl_switched_src:
	la	r2,_hldiag_src_id
	lw	r0,0(r2)
	add	r0,1
	sw	r0,0(r2)
	la	r2,_hldiag_line_no
	la	r0,0
	sw	r0,0(r2)
	la	r2,_rl_loop
	jmp	(r2)

_rl_eol:
	la	r0,0
	sb	r0,0(r1)

_rl_ret_len:
	la	r2,_hldiag_line_no
	lw	r0,0(r2)
	add	r0,1
	sw	r0,0(r2)
	la	r0,_current_src_desc
	jal	r1,(r0)
	mov	r2,r0
	lw	r0,9(r2)
	add	r0,1
	sw	r0,9(r2)
	lw	r0,0(fp)
	mov	sp,fp
	pop	r2
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

_rl_empty:
	la	r1,788191
	la	r0,1
	sw	r0,0(r1)
	la	r0,0
	mov	sp,fp
	pop	r2
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_line: Write the runtime line buffer to UART followed by CR+LF
; (symbol operands rewritten by _emit_subst_text).
; Arg on stack: line length
; Frame: push fp, r1, r2 = 9 bytes. Arg at 9(fp).
_emit_line:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,9(fp)
	ceq	r0,z
	brt	_el_empty

	la	r0,196608
	push	r0
	la	r0,_emit_subst_text
	jal	r1,(r0)
	add	sp,3
	bra	_el_done

_el_empty:
	la	r0,_emit_crlf
	jal	r1,(r0)

_el_done:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _is_structured: Check if line starts with a keyword.
; Arg on stack: line length
; Returns: r0 = 1 if structured (starts with keyword), 0 if not
; Frame: push fp, r1, r2 = 9 bytes. Arg at 9(fp).
_is_structured:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,9(fp)
	ceq	r0,z
	brt	_is_no

	la	r2,196608

_is_skip_ws:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_is_no

	lc	r1,32
	ceq	r0,r1
	brt	_is_ws_skip

	lc	r1,9
	ceq	r0,r1
	brt	_is_ws_skip

	bra	_is_check

_is_ws_skip:
	add	r2,1
	bra	_is_skip_ws

_is_check:
	la	r1,_kw_prefix_table

_is_loop:
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_is_no

	push	r1
	push	r2
	la	r0,_kw_prefix_match
	jal	r1,(r0)
	pop	r2
	pop	r1

	ceq	r0,z
	brt	_is_next

	la	r0,1
	bra	_is_ret

_is_next:
_is_skip_entry:
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_is_skipped

	add	r1,1
	bra	_is_skip_entry

_is_skipped:
	add	r1,1
	bra	_is_loop

_is_no:
	la	r0,0

_is_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _kw_prefix_match: Check if line at r2 matches prefix at r1.
; Args on stack: line_ptr (9 fp), prefix_ptr (12 fp)
; Frame: push fp, r1, r2 = 9 bytes. Args at 9,12(fp).
; Returns: r0 = 1 if match, 0 if not
_kw_prefix_match:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r1,12(fp)
	lw	r2,9(fp)

_kpm_loop:
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_kpm_match

	push	r2
	lbu	r2,0(r2)
	ceq	r2,z
	brf	_kpm_has_char

	pop	r2
	la	r0,0
	bra	_kpm_ret

_kpm_has_char:
	ceq	r0,r2
	brf	_kpm_nomatch

	pop	r2
	add	r1,1
	add	r2,1
	bra	_kpm_loop

_kpm_nomatch:
	add	sp,3
	la	r0,0
	bra	_kpm_ret

_kpm_match:
	la	r0,1

_kpm_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

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
	la	r1,196868
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

	lw	r1,-3(fp)
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

	la	r1,196868
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

	la	r1,196868
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

	la	r1,196868
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
	la	r1,196868
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

	la	r1,196868
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
	la	r1,196868
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

	la	r1,196868
	la	r0,_mn_table
	push	r1
	push	r0
	la	r0,_lookup
	jal	r1,(r0)
	add	sp,6

	ceq	r0,z
	brt	_si_not_mn

	la	r1,196868
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
	la	r1,196868
	la	r0,_reg_table
	push	r1
	push	r0
	la	r0,_lookup
	jal	r1,(r0)
	add	sp,6

	ceq	r0,z
	brt	_si_not_reg

	la	r1,196868
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
	la	r1,196868
	la	r0,_cc_table
	push	r1
	push	r0
	la	r0,_lookup
	jal	r1,(r0)
	add	sp,6

	ceq	r0,z
	brt	_si_not_kw

	la	r1,196868
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
	la	r1,196868
	la	r0,_kw_table
	push	r1
	push	r0
	la	r0,_lookup
	jal	r1,(r0)
	add	sp,6

	ceq	r0,z
	brt	_si_ident

	la	r1,196868
	la	r0,2
	push	r1
	push	r0
	la	r0,_emit_tt
	jal	r1,(r0)
	add	sp,6

	la	r0,2

_si_ident:
	la	r1,196868
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

; _reg_digit: r0 = N if the string is exactly "rN" with N in 0-2, else -1
; Arg on stack: string ptr (6 fp)
_reg_digit:
	push	fp
	push	r1
	mov	fp,sp
	lw	r1,6(fp)
	lbu	r0,0(r1)
	add	r0,-114
	ceq	r0,z
	brf	_rd_no
	lbu	r0,2(r1)
	ceq	r0,z
	brf	_rd_no
	lbu	r0,1(r1)
	add	r0,-48
	cls	r0,z
	brt	_rd_no
	lc	r1,3
	cls	r0,r1
	brf	_rd_no
	bra	_rd_ret
_rd_no:
	lc	r0,-1
_rd_ret:
	mov	sp,fp
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

; _is_ident_start: r0 = 1 if alpha or underscore
; Arg on stack: char
_is_ident_start:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	lc	r1,95
	ceq	r0,r1
	brt	_iis_yes

	push	r0
	la	r0,_is_alpha
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_iis_no

_iis_yes:
	la	r0,1
	bra	_iis_ret

_iis_no:
	la	r0,0

_iis_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _is_ident_char: r0 = 1 if alnum or underscore
; Arg on stack: char
_is_ident_char:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	lc	r1,95
	ceq	r0,r1
	brt	_iic_yes

	push	r0
	la	r0,_is_alnum
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_iic_no

_iic_yes:
	la	r0,1
	bra	_iic_ret

_iic_no:
	la	r0,0

_iic_ret:
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
	push	r2
	mov	fp,sp

	lw	r0,9(fp)
	la	r2,_relax_pass
	lw	r2,0(r2)
	ceq	r2,z
	brf	_ec_uart

	push	r0
	la	r0,_relax_size_char
	jal	r1,(r0)
	add	sp,3
	bra	_ec_ret

_ec_uart:
	la	r2,-65280

_poll:
	lb	r1,1(r2)
	cls	r1,z
	brt	_poll

	sb	r0,0(r2)

_ec_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _fatal: Print "ERROR: <msg>" on the UART and halt.
; Used for every capacity limit, so nothing overflows silently. Setting
; _relax_pass forces the UART path even during the sizing pass.
; Arg on stack: message string ptr (9 fp)
_fatal:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r1,_relax_pass
	la	r0,1
	sw	r0,0(r1)

	la	r0,_fatal_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	la	r0,_emit_src_location
	jal	r1,(r0)
	lw	r0,9(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	la	r0,_emit_crlf
	jal	r1,(r0)

	la	r0,_halt
	jmp	(r0)

; _emit_src_location: Print "<member>:<line>: " for the source line being
; processed (lines from a macro expansion report the line of the call).
; The member is the config name of the current source, else "main" for
; slot 0 or "slot<N>". Prints nothing before the first source line is read.
_emit_src_location:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r1,786597
	lw	r0,0(r1)
	ceq	r0,z
	brf	_esl_src
_esl_none:
	la	r1,_esl_ret
	jmp	(r1)
_esl_src:
	la	r0,_current_src_desc
	jal	r1,(r0)
	lw	r0,9(r0)
	ceq	r0,z
	brt	_esl_none
_esl_go:
	la	r1,786600
	lw	r2,0(r1)
	push	r2
	la	r0,_src_name
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brf	_esl_name
	la	r0,_loc_main_txt
	ceq	r2,z
	brt	_esl_name
	la	r0,_loc_slot_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	push	r2
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3
	bra	_esl_line
_esl_name:
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
_esl_line:
	la	r0,_loc_colon_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	la	r0,_current_src_desc
	jal	r1,(r0)
	lw	r0,9(r0)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3
	la	r0,_loc_sep_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
_esl_ret:
	mov	sp,fp
	pop	r2
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
; _symbol_enabled: Return 1 if named SET/EQU symbol is active and nonzero.
; Arg on stack: symbol_name_ptr
; The caller's _parse_name_buf is saved in its own buffer (209408) and restored.
_symbol_enabled:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3

	la	r0,197128
	push	r0
	la	r0,209408
	push	r0
	la	r0,_copy_strz
	jal	r1,(r0)
	add	sp,6

	lw	r0,9(fp)
	push	r0
	la	r0,197128
	push	r0
	la	r0,_copy_strz
	jal	r1,(r0)
	add	sp,6

	la	r0,_lookup_symbol
	jal	r1,(r0)
	ceq	r0,z
	brt	_syme_off

	la	r1,786594
	lw	r0,0(r1)
	ceq	r0,z
	brt	_syme_off

	la	r0,1
	bra	_sye_ret

_syme_off:
	la	r0,0

_sye_ret:
	sw	r0,-3(fp)
	la	r0,209408
	push	r0
	la	r0,197128
	push	r0
	la	r0,_copy_strz
	jal	r1,(r0)
	add	sp,6

	lw	r0,-3(fp)
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _struct_ann_enabled: Return 1 if SET HLANN,<nonzero> is active.
_struct_ann_enabled:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_ann_symbol_name
	push	r0
	la	r0,_symbol_enabled
	jal	r1,(r0)
	add	sp,3
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _listing_enabled: Return 1 if SET HLLIST,<nonzero> is active.
_listing_enabled:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_list_symbol_name
	push	r0
	la	r0,_symbol_enabled
	jal	r1,(r0)
	add	sp,3

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _xref_enabled: Return 1 if SET HLXREF,<nonzero> is active.
_xref_enabled:
	push	fp
	push	r1
	mov	fp,sp

	la	r1,_xref_switch
	lw	r0,0(r1)
	ceq	r0,z
	brt	_xre_off
	la	r0,1
	bra	_xre_ret

_xre_off:
	la	r0,0

_xre_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_ann_prefix: Emit "; HLASM ".
_emit_ann_prefix:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_ann_prefix_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_ann_line0: Emit "; HLASM <keyword>" when annotations are enabled.
; Arg on stack: keyword_ptr
_emit_ann_line0:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_struct_ann_enabled
	jal	r1,(r0)
	ceq	r0,z
	brt	_eal0_ret

	la	r0,_emit_ann_prefix
	jal	r1,(r0)

	lw	r0,6(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

_eal0_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_ann_line1: Emit "; HLASM <keyword> <arg>" when enabled.
; Args on stack: keyword_ptr (9 fp), arg_ptr (6 fp)
_emit_ann_line1:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_struct_ann_enabled
	jal	r1,(r0)
	ceq	r0,z
	brt	_eal1_ret

	la	r0,_emit_ann_prefix
	jal	r1,(r0)

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lw	r0,6(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

_eal1_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_list_line1: Emit "; HLASM <keyword> <arg>" when listing is enabled.
; Args on stack: keyword_ptr (9 fp), arg_ptr (6 fp)
_emit_list_line1:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_listing_enabled
	jal	r1,(r0)
	ceq	r0,z
	brt	_ell1_ret

	la	r0,_emit_ann_prefix
	jal	r1,(r0)

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lw	r0,6(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

_ell1_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_xref_prefix: Emit "; HLASM XREF ".
_emit_xref_prefix:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_xref_prefix_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_xref_line1: Emit "; HLASM XREF <kind> <name>".
; Args on stack: kind_ptr (9 fp), name_ptr (6 fp)
_emit_xref_line1:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_emit_xref_prefix
	jal	r1,(r0)

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lw	r0,6(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_xref_line_count: Emit "; HLASM XREF <kind> <name> <count>".
; Args on stack: kind_ptr (12 fp), name_ptr (9 fp), count (6 fp)
_emit_xref_line_count:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_emit_xref_prefix
	jal	r1,(r0)

	lw	r0,12(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lw	r0,6(fp)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_ann_if_line: Emit "; HLASM <keyword> cc[, lhs, rhs]" when enabled.
; Arg on stack: keyword_ptr
_emit_ann_if_line:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_struct_ann_enabled
	jal	r1,(r0)
	ceq	r0,z
	brf	_eail_on
	la	r1,_eail_ret
	jmp	(r1)

_eail_on:

	la	r0,_emit_ann_prefix
	jal	r1,(r0)

	lw	r0,6(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	la	r0,197648
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_cc_zset_txt
	push	r0
	la	r0,197648
	push	r0
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	_eail_done

	la	r0,_cc_zclr_txt
	push	r0
	la	r0,197648
	push	r0
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	_eail_done

	lc	r0,44
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	la	r0,197908
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,44
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	la	r0,198168
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

_eail_done:
	la	r0,_emit_crlf
	jal	r1,(r0)

_eail_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_strz: Emit a null-terminated string.
; Arg on stack: ptr
_emit_strz:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r2,9(fp)

_esz_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_esz_ret

	push	r2
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3
	pop	r2

	add	r2,1
	bra	_esz_loop

_esz_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_inst1: Emit " mnemonic operand" and CRLF.
; Args on stack: mnemonic_ptr (9 fp), operand_ptr (6 fp)
_emit_inst1:
	push	fp
	push	r1
	mov	fp,sp

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lw	r0,6(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_inst2: Emit " mnemonic op1,op2" and CRLF.
; Args on stack: mnemonic_ptr (12 fp), op1_ptr (9 fp), op2_ptr (6 fp)
; ceq is encodable only with the lower register first (ceq r1,r2, not
; ceq r2,r1), so "ceq rB,rA" with B > A is emitted as "ceq rA,rB".
_emit_inst2:
	push	fp
	push	r1
	mov	fp,sp

; lc takes -128..127; a larger constant (e.g. an IF compare value) uses la.
	lw	r0,12(fp)
	la	r1,_lc_txt
	ceq	r0,r1
	brf	_ei2_ceq
	lw	r0,6(fp)
	push	r0
	la	r0,_is_number_str
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_ei2_ceq
	lw	r0,6(fp)
	push	r0
	la	r0,_atoi
	jal	r1,(r0)
	add	sp,3
; a constant written without '-' fits only if it is 0..127 (16777215 is -1
; in 24 bits, but cor24-asm rejects lc r0,16777215)
	lw	r1,6(fp)
	lbu	r1,0(r1)
	push	r2
	lc	r2,45
	ceq	r1,r2
	pop	r2
	brt	_ei2_neg
	la	r1,128
	clu	r0,r1
	brt	_ei2_ceq
	bra	_ei2_use_la
_ei2_neg:
	la	r1,128
	add	r0,r1
	la	r1,256
	clu	r0,r1
	brt	_ei2_ceq
_ei2_use_la:
	la	r0,_la_txt
	sw	r0,12(fp)

_ei2_ceq:
	lw	r0,12(fp)
	la	r1,_ceq_txt
	ceq	r0,r1
	brf	_ei2_emit
	lw	r0,9(fp)
	push	r0
	la	r0,_reg_digit
	jal	r1,(r0)
	add	sp,3
	push	r0
	lw	r0,6(fp)
	push	r0
	la	r0,_reg_digit
	jal	r1,(r0)
	add	sp,3
	pop	r1
	cls	r0,z
	brt	_ei2_emit
	cls	r0,r1
	brf	_ei2_emit
	lw	r0,9(fp)
	lw	r1,6(fp)
	sw	r1,9(fp)
	sw	r0,6(fp)

_ei2_emit:
	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lw	r0,12(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,44
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	; cor24-asm has no 0b literals: emit "0b..." operands in decimal.
	lw	r1,6(fp)
	lbu	r0,0(r1)
	add	r0,-48
	ceq	r0,z
	brf	_ei2_op2_text
	lbu	r0,1(r1)
	add	r0,-66
	ceq	r0,z
	brt	_ei2_op2_bin
	add	r0,-32
	ceq	r0,z
	brf	_ei2_op2_text

_ei2_op2_bin:
	push	r1
	la	r0,_atoi
	jal	r1,(r0)
	add	sp,3
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3
	bra	_ei2_crlf

_ei2_op2_text:
	lw	r0,6(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

_ei2_crlf:
	la	r0,_emit_crlf
	jal	r1,(r0)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_branch_label: Emit " mnemonic _hlif_<n><suffix>" and CRLF.
; Args on stack: mnemonic_ptr (12 fp), label_id (9 fp), suffix_ptr (6 fp)
_emit_branch_label:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,12(fp)
	la	r1,_jmp_txt
	ceq	r0,r1
	brf	_ebrl_plain
	la	r0,_if_label_prefix
	push	r0
	lw	r0,9(fp)
	push	r0
	lw	r0,6(fp)
	push	r0
	la	r0,_emit_relaxed_jump
	jal	r1,(r0)
	add	sp,9
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

_ebrl_plain:

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lw	r0,12(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	la	r0,_if_label_prefix
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	lw	r0,6(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_label_def: Emit "_hlif_<n><suffix>:" and CRLF.
; Args on stack: label_id (9 fp), suffix_ptr (6 fp)
_emit_label_def:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_if_label_prefix
	push	r0
	lw	r0,9(fp)
	push	r0
	lw	r0,6(fp)
	push	r0
	la	r0,_relax_label_def
	jal	r1,(r0)
	add	sp,9

	la	r0,_if_label_prefix
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	lw	r0,6(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,58
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_do_branch_label: Emit " mnemonic _hldo_<n><suffix>" and CRLF.
; Args on stack: mnemonic_ptr (12 fp), label_id (9 fp), suffix_ptr (6 fp)
_emit_do_branch_label:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,12(fp)
	la	r1,_jmp_txt
	ceq	r0,r1
	brf	_edbrl_plain
	la	r0,_do_label_prefix
	push	r0
	lw	r0,9(fp)
	push	r0
	lw	r0,6(fp)
	push	r0
	la	r0,_emit_relaxed_jump
	jal	r1,(r0)
	add	sp,9
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

_edbrl_plain:

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lw	r0,12(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	la	r0,_do_label_prefix
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	lw	r0,6(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_do_label_def: Emit "_hldo_<n><suffix>:" and CRLF.
; Args on stack: label_id (9 fp), suffix_ptr (6 fp)
_emit_do_label_def:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_do_label_prefix
	push	r0
	lw	r0,9(fp)
	push	r0
	lw	r0,6(fp)
	push	r0
	la	r0,_relax_label_def
	jal	r1,(r0)
	add	sp,9

	la	r0,_do_label_prefix
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	lw	r0,6(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,58
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_select_branch_label: Emit " mnemonic _hlsel_<n><suffix>" and CRLF.
; Args on stack: mnemonic_ptr (12 fp), label_id (9 fp), suffix_ptr (6 fp)
_emit_select_branch_label:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,12(fp)
	la	r1,_jmp_txt
	ceq	r0,r1
	brf	_esbrl_plain
	la	r0,_sel_label_prefix
	push	r0
	lw	r0,9(fp)
	push	r0
	lw	r0,6(fp)
	push	r0
	la	r0,_emit_relaxed_jump
	jal	r1,(r0)
	add	sp,9
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

_esbrl_plain:

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	lw	r0,12(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,32
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	la	r0,_sel_label_prefix
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	lw	r0,6(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_select_label_def: Emit "_hlsel_<n><suffix>:" and CRLF.
; Args on stack: label_id (9 fp), suffix_ptr (6 fp)
_emit_select_label_def:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_sel_label_prefix
	push	r0
	lw	r0,9(fp)
	push	r0
	lw	r0,6(fp)
	push	r0
	la	r0,_relax_label_def
	jal	r1,(r0)
	add	sp,9

	la	r0,_sel_label_prefix
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	lw	r0,6(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lc	r0,58
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_dec24: Print an unsigned 24-bit number as decimal (no padding).
; Arg on stack: number
; Frame: push fp, r1, r2 = 9 bytes. Arg at 9(fp).
; -3(fp) = remaining value, -6(fp) = digit started flag, -9(fp) = power ptr
_emit_dec24:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-9

	lw	r0,9(fp)
	sw	r0,-3(fp)
	la	r0,0
	sw	r0,-6(fp)
	la	r0,_dec_pow
	sw	r0,-9(fp)

_ed24_pow:
	lw	r1,-9(fp)
	lw	r1,0(r1)
	ceq	r1,z
	brt	_ed24_ret
	la	r2,0

_ed24_sub:
	lw	r0,-3(fp)
	clu	r0,r1
	brt	_ed24_digit
	sub	r0,r1
	sw	r0,-3(fp)
	add	r2,1
	bra	_ed24_sub

_ed24_digit:
	ceq	r2,z
	brf	_ed24_emit
	lw	r0,-6(fp)
	ceq	r0,z
	brf	_ed24_emit
	lc	r0,1
	ceq	r0,r1
	brf	_ed24_next

_ed24_emit:
	lc	r0,48
	add	r0,r2
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3
	la	r0,1
	sw	r0,-6(fp)

_ed24_next:
	lw	r0,-9(fp)
	add	r0,3
	sw	r0,-9(fp)
	bra	_ed24_pow

_ed24_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _alloc_struct_label_id: Return next structured-control-flow label id and bump it.
_alloc_struct_label_id:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r2,787810
	lw	r0,0(r2)
	mov	r1,r0
	add	r1,1
	sw	r1,0(r2)

	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _zero_bytes: Zero a byte range in SRAM.
; Args on stack: ptr (9 fp), len (12 fp)
_zero_bytes:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r2,9(fp)
	lw	r1,12(fp)

_zb_loop:
	ceq	r1,z
	brt	_zb_ret

	la	r0,0
	sb	r0,0(r2)
	add	r2,1
	add	r1,-1
	bra	_zb_loop

_zb_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _init_runtime_arena: Initialize mutable assembler state in middle SRAM.
_init_runtime_arena:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

		la	r0,4700
	push	r0
	la	r0,786432
	push	r0
	la	r0,_zero_bytes
	jal	r1,(r0)
	add	sp,6

; Work area at 0x030000 (line, token, name and operand buffers, expansion
; buffer, assembly-time stacks): 4576 bytes, cleared a word at a time.
	la	r1,196608
	la	r2,201184
	lc	r0,0
_ira_wa_loop:
	sw	r0,0(r1)
	add	r1,3
	clu	r1,r2
	brt	_ira_wa_loop

; XREF macro expansion counters at 0x038800 (256 x 3 bytes).
	la	r1,231424
	la	r2,232192
_ira_xc_loop:
	sw	r0,0(r1)
	add	r1,3
	clu	r1,r2
	brt	_ira_xc_loop

	la	r1,786597
	la	r0,1
	sw	r0,0(r1)

	la	r1,786642
	la	r0,131072
	sw	r0,0(r1)

	la	r1,790704
	la	r0,198688
	sw	r0,0(r1)

	la	r1,790707
	la	r0,1
	sw	r0,0(r1)

	la	r1,790716
	la	r0,131072
	sw	r0,0(r1)

	la	r1,787810
	la	r0,1
	sw	r0,0(r1)

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _init_src_table: Initialize the source descriptors from the config block at
; 0x07F000 (see the header): slot 0 is the main source, slots 1-32 the
; configured members.
; Descriptors at 239104, 12 bytes each: +0 base, +3 length, +6 position,
; +9 line number (of the line last read from that source).
_init_src_table:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-3

	la	r1,786600
	lc	r0,0
	sw	r0,0(r1)

	la	r1,239104
	la	r0,524288
	sw	r0,0(r1)
	la	r0,32767
	sw	r0,3(r1)
	lc	r0,0
	sw	r0,6(r1)
	sw	r0,9(r1)

	la	r2,520192
	lw	r0,3(r2)
	ceq	r0,z
	brt	_ist_main_len
	sw	r0,0(r1)
_ist_main_len:
	lw	r0,6(r2)
	ceq	r0,z
	brt	_ist_count
	sw	r0,3(r1)

_ist_count:
	lw	r0,0(r2)
	lc	r1,33
	clu	r0,r1
	brt	_ist_count_ok
	la	r0,_err_cfg_full
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_ist_count_ok:
	la	r1,786597
	add	r0,1
	sw	r0,0(r1)

; copy member i (0-based) to descriptor i+1
	lc	r0,0
	sw	r0,0(fp)
_ist_copy_loop:
	lw	r0,0(fp)
	la	r1,520192
	lw	r1,0(r1)
	clu	r0,r1
	brf	_ist_ret

	push	r0
	la	r0,_cfg_member
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0

	lw	r0,0(fp)
	add	r0,1
	push	r0
	la	r0,_mul12
	jal	r1,(r0)
	add	sp,3
	la	r1,239104
	add	r1,r0

	lw	r0,0(r2)
	sw	r0,0(r1)
	lw	r0,3(r2)
	sw	r0,3(r1)
	lc	r0,0
	sw	r0,6(r1)
	sw	r0,9(r1)

	lw	r0,0(fp)
	add	r0,1
	sw	r0,0(fp)
	bra	_ist_copy_loop

_ist_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _cfg_member: r0 = address of config member record index (0-based):
; 520217 + index * 22 (+0 base, +3 length, +6 name, 16 bytes).
; Arg on stack: index
_cfg_member:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,9(fp)
	add	r0,r0
	mov	r1,r0
	add	r0,r0
	mov	r2,r0
	add	r0,r0
	add	r0,r0
	add	r0,r1
	add	r0,r2
	la	r1,520217
	add	r0,r1

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _advance_src_desc: Switch to the next configured source buffer.
; Returns: r0 = 1 if switched, 0 if no additional source exists.
_advance_src_desc:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r1,786597
	lw	r1,0(r1)
	la	r2,786600
	lw	r0,0(r2)
	add	r0,1
	clu	r0,r1
	brf	_asd_no

	sw	r0,0(r2)
	la	r0,1
	bra	_asd_ret

_asd_no:
	la	r0,0

_asd_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _select_src_slot: Activate a configured source slot and rewind it (position
; and line number).
; Arg on stack: slot index (0=main, 1+=configured member)
; Returns: r0 = 1 if switched, 0 if invalid
_select_src_slot:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,9(fp)
	la	r1,786597
	lw	r1,0(r1)
	clu	r0,r1
	brf	_sss_no

	push	r0
	la	r0,_mul12
	jal	r1,(r0)
	add	sp,3
	la	r1,239104
	add	r1,r0
	lc	r0,0
	sw	r0,6(r1)
	sw	r0,9(r1)

	lw	r0,9(fp)
	la	r1,786600
	sw	r0,0(r1)
	la	r0,1
	bra	_sss_ret

_sss_no:
	la	r0,0

_sss_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _push_src_return: Save the current source slot for include return.
; Stack: depth at 787734, 16 slots of 3 bytes at 787737. Deeper nesting
; stops with an ERROR.
; Returns: r0 = 1
_push_src_return:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r1,787734
	lw	r0,0(r1)
	lc	r2,16
	clu	r0,r2
	brt	_psr_room
	la	r0,_err_inc_deep
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_psr_room:
	push	r0
	la	r0,_mul3
	jal	r1,(r0)
	add	sp,3
	la	r1,787737
	add	r1,r0
	mov	r2,r1

	la	r1,786600
	lw	r0,0(r1)
	sw	r0,0(r2)

	la	r1,787734
	lw	r0,0(r1)
	add	r0,1
	sw	r0,0(r1)
	la	r0,1

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _pop_src_return: Restore the caller source slot after include EOF.
; Returns: r0 = 1 if restored, 0 if stack empty
_pop_src_return:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r1,787734
	lw	r0,0(r1)
	ceq	r0,z
	brt	_prr_no

	add	r0,-1
	sw	r0,0(r1)

	push	r0
	la	r0,_mul3
	jal	r1,(r0)
	add	sp,3
	la	r1,787737
	add	r1,r0
	mov	r2,r1

	lw	r0,0(r2)
	la	r1,786600
	sw	r0,0(r1)

	la	r0,1
	bra	_prr_ret

_prr_no:
	la	r0,0

_prr_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _lookup_include_slot: Resolve _parse_name_buf against the member names in
; the config block.
; Returns: r0 = 1 if found, 0 if not. Stores slot in _include_lookup_slot.
_lookup_include_slot:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-3

	la	r1,787804
	lc	r0,0
	sw	r0,0(r1)
	sw	r0,-3(fp)

_lis_loop:
	lw	r0,-3(fp)
	la	r1,520192
	lw	r1,0(r1)
	clu	r0,r1
	brf	_lis_no

	push	r0
	la	r0,_cfg_member
	jal	r1,(r0)
	add	sp,3
	add	r0,6
	lbu	r1,0(r0)
	ceq	r1,z
	brt	_lis_next

	push	r0
	la	r2,197128
	push	r2
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brt	_lis_next

	lw	r0,-3(fp)
	add	r0,1
	la	r1,787804
	sw	r0,0(r1)
	la	r0,1
	bra	_lis_ret

_lis_next:
	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
	bra	_lis_loop

_lis_no:
	la	r0,0

_lis_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _src_name: r0 = name of source slot (strz): the config name, or 0 when the
; slot has none (slot 0 uses the main name at 520201).
; Arg on stack: slot
_src_name:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,9(fp)
	ceq	r0,z
	brf	_srn_member
	la	r0,520201
	bra	_srn_check
_srn_member:
	add	r0,-1
	push	r0
	la	r0,_cfg_member
	jal	r1,(r0)
	add	sp,3
	add	r0,6
_srn_check:
	lbu	r1,0(r0)
	ceq	r1,z
	brf	_srn_ret
	lc	r0,0
_srn_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _current_src_desc: Return pointer to active source descriptor.
; Returns: r0 = descriptor pointer
_current_src_desc:
	push	fp
	push	r1
	mov	fp,sp

	la	r1,786600
	lw	r0,0(r1)
	push	r0
	la	r0,_mul12
	jal	r1,(r0)
	add	sp,3
	la	r1,239104
	add	r0,r1

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _read_char: Read next byte from source buffer.
; Arg (on stack): pointer to source descriptor table
; Returns: r0 = byte value (0-255), or 0 on EOF
_read_char:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r0,_current_src_desc
	jal	r1,(r0)
	mov	r2,r0

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
; Arg (on stack): pointer to source descriptor table
; Returns: r0 = byte value (0-255), or 0 on EOF
_peek_char:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r0,_current_src_desc
	jal	r1,(r0)
	mov	r2,r0

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
	.byte 99,99,95,103,101,0
	.byte 99,99,95,103,101,117,0
	.byte 99,99,95,103,116,0
	.byte 99,99,95,103,116,117,0
	.byte 99,99,95,108,101,0
	.byte 99,99,95,108,101,117,0
	.byte 0

; --- Compare conditions for _cc_info: name, NUL, code ---
; code bits 0-1: 1 ceq, 2 cls, 3 clu; 4: swap operands; 8: true when the
; compare is false. le = !(b<a), gt = b<a, ge = !(a<b).
_cc_info_table:
	.byte	99,99,95,101,113,0,1
	.byte	99,99,95,110,101,0,9
	.byte	99,99,95,108,116,0,2
	.byte	99,99,95,108,117,0,3
	.byte	99,99,95,103,101,0,10
	.byte	99,99,95,103,101,117,0,11
	.byte	99,99,95,103,116,0,6
	.byte	99,99,95,103,116,117,0,7
	.byte	99,99,95,108,101,0,14
	.byte	99,99,95,108,101,117,0,15
	.byte	0


; --- Keyword prefix table (for _is_structured) ---

; --- Step 5: Macro functions ---

; _line_is_keyword: Check if first word in _line_buf matches keyword exactly.
; Arg on stack: keyword_ptr
; Returns: r0 = 1 if exact word match, 0 if not
_line_is_keyword:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r2,196608

_lik_skip:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_lik_no

	lc	r1,32
	ceq	r0,r1
	brt	_lik_skip_ws

	lc	r1,9
	ceq	r0,r1
	brt	_lik_skip_ws

	bra	_lik_cmp

_lik_skip_ws:
	add	r2,1
	bra	_lik_skip

_lik_cmp:
	lw	r1,9(fp)

_lik_loop:
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_lik_done

	push	r2
	lbu	r2,0(r2)
	ceq	r2,z
	brt	_lik_no_pop

	ceq	r0,r2
	brf	_lik_no_pop

	pop	r2
	add	r1,1
	add	r2,1
	bra	_lik_loop

_lik_no_pop:
	pop	r2
	bra	_lik_no

_lik_done:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_lik_yes

	lc	r1,32
	ceq	r0,r1
	brt	_lik_yes

	lc	r1,9
	ceq	r0,r1
	brt	_lik_yes

	lc	r1,59
	ceq	r0,r1
	brt	_lik_yes

	lc	r1,35
	ceq	r0,r1
	brt	_lik_yes

	bra	_lik_no

_lik_yes:
	la	r0,1
	bra	_lik_ret

_lik_no:
	la	r0,0

_lik_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _starts_with: Check if _line_buf starts with the given prefix.
; Arg on stack: prefix_ptr
; Returns: r0 = 1 if match, 0 if not
; Frame: push fp, r1, r2 = 9 bytes. Arg at 9(fp).
_starts_with:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r2,196608

_sws_skip:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_sws_check

	lc	r1,32
	ceq	r0,r1
	brt	_sws_ws

	lc	r1,9
	ceq	r0,r1
	brt	_sws_ws

	bra	_sws_check

_sws_ws:
	add	r2,1
	bra	_sws_skip

_sws_check:
	lw	r1,9(fp)

_sws_loop:
	push	r1
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_sws_match

	push	r0
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_sws_nomatch_pop

	pop	r1
	ceq	r0,r1
	brt	_sws_next

	bra	_sws_nomatch_pop2

_sws_nomatch_pop:
	pop	r1
	bra	_sws_nomatch_pop2

_sws_nomatch_pop2:
	pop	r1
	bra	_sws_nomatch

_sws_next:
	pop	r1
	add	r1,1
	add	r2,1
	bra	_sws_loop

_sws_match:
	la	r0,1
	bra	_sws_ret

_sws_nomatch:
	la	r0,0

_sws_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _line_is_equ_stmt: Return 1 if line starts with "name EQU ..."
_line_is_equ_stmt:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r2,196608

_lies_ws:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_lies_no_near
	lc	r1,32
	ceq	r0,r1
	brt	_lies_ws_adv
	lc	r1,9
	ceq	r0,r1
	brt	_lies_ws_adv
	bra	_lies_name

_lies_no_near:
	la	r1,_lies_no
	jmp	(r1)

_lies_ws_adv:
	add	r2,1
	bra	_lies_ws

_lies_name:
	lbu	r0,0(r2)
	push	r0
	la	r0,_is_ident_start
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_lies_no

_lies_name_loop:
	lbu	r0,0(r2)
	push	r0
	la	r0,_is_alnum
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_lies_after_name
	add	r2,1
	bra	_lies_name_loop

_lies_after_name:
	lbu	r0,0(r2)
	lc	r1,32
	ceq	r0,r1
	brt	_lies_kw_ws
	lc	r1,9
	ceq	r0,r1
	brt	_lies_kw_ws
	bra	_lies_no

_lies_kw_ws:
	lbu	r0,0(r2)
	lc	r1,32
	ceq	r0,r1
	brt	_lies_kw_ws_adv
	lc	r1,9
	ceq	r0,r1
	brt	_lies_kw_ws_adv
	bra	_lies_kw

_lies_kw_ws_adv:
	add	r2,1
	bra	_lies_kw_ws

_lies_kw:
	lbu	r0,0(r2)
	lc	r1,69
	ceq	r0,r1
	brt	_lies_kw_q
	bra	_lies_no

_lies_kw_q:
	lbu	r0,1(r2)
	lc	r1,81
	ceq	r0,r1
	brt	_lies_kw_u
	bra	_lies_no

_lies_kw_u:
	lbu	r0,2(r2)
	lc	r1,85
	ceq	r0,r1
	brt	_lies_kw_end
	bra	_lies_no

_lies_kw_end:
	add	r2,3
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_lies_yes
	lc	r1,32
	ceq	r0,r1
	brt	_lies_yes
	lc	r1,9
	ceq	r0,r1
	brt	_lies_yes
	bra	_lies_no

_lies_yes:
	la	r0,1
	bra	_lies_ret

_lies_no:
	la	r0,0

_lies_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _extract_macro_name: Parse macro name from _line_buf after "MACRO ".
; Sets _macro_state=1, _macro_rec_idx=next slot.
_extract_macro_name:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-6

; Skip "MACRO" (5 chars) in _line_buf
	la	r1,196608
	la	r0,5
	add	r1,r0

; Skip whitespace after MACRO
_emn_skip_ws:
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_emn_done_far

	lc	r2,32
	ceq	r0,r2
	brt	_emn_ws

	lc	r2,9
	ceq	r0,r2
	brt	_emn_ws

	bra	_emn_copy

_emn_ws:
	add	r1,1
	bra	_emn_skip_ws

_emn_done_far:
	la	r1,_emn_done
	jmp	(r1)

; Now r1 points to macro name in _line_buf
; Copy name to macro table entry
_emn_copy:
	push	r1
	la	r2,786645
	lw	r2,0(r2)
	la	r0,256
	clu	r2,r0
	brt	_emn_room
	la	r0,_err_mac_full
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_emn_room:

	push	r2
	la	r0,_mul39
	jal	r1,(r0)
	add	sp,3

	la	r2,98304
	add	r2,r0
	sw	r2,-6(fp)
	pop	r1
	la	r0,31
	sw	r0,-3(fp)

; r2 = &macro_table[index], r1 = name ptr in _line_buf
_emn_cloop:
	push	r2
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_emn_ne_pop

	lc	r2,32
	ceq	r0,r2
	brt	_emn_ne_pop

	lc	r2,9
	ceq	r0,r2
	brt	_emn_ne_pop

	lw	r2,-3(fp)
	ceq	r2,z
	brt	_emn_long_pop

	pop	r2
	sb	r0,0(r2)
	add	r1,1
	add	r2,1
	lw	r0,-3(fp)
	add	r0,-1
	sw	r0,-3(fp)
	bra	_emn_cloop

_emn_long_pop:
	pop	r2
	push	r1
	lbu	r0,0(r1)
	push	r0
	la	r0,_is_macro_name_char
	jal	r1,(r0)
	add	sp,3
	pop	r1
	ceq	r0,z
	brt	_emn_long_skip
	la	r0,_err_mac_long
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_emn_long_skip:
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_emn_name_end
	lc	r2,32
	ceq	r0,r2
	brt	_emn_name_end
	lc	r2,9
	ceq	r0,r2
	brt	_emn_name_end
	add	r1,1
	bra	_emn_long_skip

_emn_ne_pop:
	pop	r2
	bra	_emn_name_end

_emn_name_end:
	la	r0,0
	push	r1
	push	r2
	sb	r0,0(r2)
	pop	r2
	pop	r1

; Set macro state to recording
	la	r1,790710
	la	r0,1
	sw	r0,0(r1)

; Save current macro index
	la	r1,790713
	la	r2,786645
	lw	r0,0(r2)
	sw	r0,0(r1)

; Set body ptr to current _macro_body_start
	la	r1,790713
	lw	r0,0(r1)
	push	r0
	la	r0,_mul39
	jal	r1,(r0)
	add	sp,3
	la	r1,98304
	add	r1,r0

	la	r0,790716
	lw	r0,0(r0)
	sw	r0,33(r1)

	la	r0,_parse_macro_params
	jal	r1,(r0)

	la	r0,_write_macro_header
	jal	r1,(r0)

	la	r0,_kw_macro
	push	r0
	lw	r0,-6(fp)
	push	r0
	la	r0,_emit_list_line1
	jal	r1,(r0)
	add	sp,6

_emn_done:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _parse_macro_params: Parse parameter names from the current MACRO line.
; Stores count and 9-byte null-terminated names in runtime scratch.
_parse_macro_params:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-9

	la	r1,788194
	la	r0,0
	sw	r0,0(r1)
	sw	r0,-6(fp)

	la	r0,196608
	sw	r0,-3(fp)
	la	r0,5
	lw	r1,-3(fp)
	add	r1,r0
	sw	r1,-3(fp)

_pmp_skip_ws0:
	lw	r1,-3(fp)
	lbu	r0,0(r1)
	ceq	r0,z
	brf	_pmp_skip_ws0_nz
	la	r1,_pmp_ret
	jmp	(r1)
_pmp_skip_ws0_nz:
	lc	r1,32
	ceq	r0,r1
	brt	_pmp_skip_ws0_1
	lc	r1,9
	ceq	r0,r1
	brt	_pmp_skip_ws0_1
	bra	_pmp_skip_name

_pmp_skip_ws0_1:
	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
	bra	_pmp_skip_ws0

_pmp_skip_name:
	lw	r1,-3(fp)
	lbu	r0,0(r1)
	ceq	r0,z
	brf	_pmp_skip_name_nz
	la	r1,_pmp_ret
	jmp	(r1)
_pmp_skip_name_nz:
	lc	r1,32
	ceq	r0,r1
	brt	_pmp_after_name
	lc	r1,9
	ceq	r0,r1
	brt	_pmp_after_name
	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
	bra	_pmp_skip_name

_pmp_after_name:
	lw	r1,-3(fp)
	lbu	r0,0(r1)
	ceq	r0,z
	brf	_pmp_after_name_nz
	la	r1,_pmp_ret
	jmp	(r1)
_pmp_after_name_nz:
	lc	r1,32
	ceq	r0,r1
	brt	_pmp_after_name_ws
	lc	r1,9
	ceq	r0,r1
	brt	_pmp_after_name_ws
	lc	r1,44
	ceq	r0,r1
	brt	_pmp_after_name_comma
	bra	_pmp_param_start

_pmp_after_name_ws:
	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
	bra	_pmp_after_name

_pmp_after_name_comma:
	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
	bra	_pmp_after_name

_pmp_param_start:
	lw	r0,-6(fp)
	lc	r1,16
	clu	r0,r1
	brt	_pmp_param_start_ok
	la	r0,_err_parm_full
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_pmp_param_start_ok:

	lw	r1,-3(fp)
	lbu	r0,0(r1)
	lc	r2,38
	ceq	r0,r2
	brf	_pmp_param_slot
	add	r1,1
	sw	r1,-3(fp)

_pmp_param_slot:
	lw	r0,-6(fp)
	push	r0
	la	r0,_default_slot
	jal	r1,(r0)
	add	sp,3
	lc	r1,0
	sb	r1,0(r0)

	lw	r0,-6(fp)
	push	r0
	la	r0,_mul32
	jal	r1,(r0)
	add	sp,3
	la	r1,200672
	add	r1,r0
	la	r0,0
	sw	r0,-9(fp)

_pmp_param_copy:
	lw	r2,-3(fp)
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_pmp_param_done
	lc	r1,32
	ceq	r0,r1
	brt	_pmp_param_done_pop
	lc	r1,9
	ceq	r0,r1
	brt	_pmp_param_done_pop
	lc	r1,44
	ceq	r0,r1
	brt	_pmp_param_done_pop
	lc	r1,61
	ceq	r0,r1
	brt	_pmp_default
	lw	r1,-9(fp)
	lc	r2,31
	clu	r1,r2
	brt	_pmp_name_ok
	la	r0,_err_parm_long
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_pmp_name_ok:
	lw	r1,-3(fp)
	lbu	r0,0(r1)
	lw	r2,-6(fp)
	push	r2
	la	r2,_mul32
	jal	r1,(r2)
	add	sp,3
	la	r1,200672
	add	r1,r0
	lw	r0,-9(fp)
	add	r1,r0
	lw	r2,-3(fp)
	lbu	r0,0(r2)
	sb	r0,0(r1)
	lw	r0,-9(fp)
	add	r0,1
	sw	r0,-9(fp)

_pmp_param_skip:
	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
	bra	_pmp_param_copy

; &NAME=default: the name ends at '=', the default text is kept per index
_pmp_default:
	lw	r0,-3(fp)
	add	r0,1
	push	r0
	lw	r0,-6(fp)
	push	r0
	la	r0,_pmp_copy_default
	jal	r1,(r0)
	add	sp,6
	sw	r0,-3(fp)

_pmp_param_done_pop:
_pmp_param_done:
	lw	r0,-6(fp)
	push	r0
	la	r0,_mul32
	jal	r1,(r0)
	add	sp,3
	la	r1,200672
	add	r1,r0
	lw	r0,-9(fp)
	add	r1,r0
	la	r0,0
	sb	r0,0(r1)
	lw	r0,-6(fp)
	add	r0,1
	sw	r0,-6(fp)
	la	r1,788194
	sw	r0,0(r1)

_pmp_seek_next:
	lw	r1,-3(fp)
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_pmp_ret
	lc	r1,44
	ceq	r0,r1
	brt	_pmp_next_param
	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
	bra	_pmp_seek_next

_pmp_next_param:
	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
_pmp_next_param_ws:
	lw	r1,-3(fp)
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_pmp_ret
	lc	r1,32
	ceq	r0,r1
	brt	_pmp_next_param_ws_1
	lc	r1,9
	ceq	r0,r1
	brt	_pmp_next_param_ws_1
	la	r1,_pmp_param_start
	jmp	(r1)

_pmp_next_param_ws_1:
	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
	bra	_pmp_next_param_ws

_pmp_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _find_named_macro_param: Return 1-based parameter index for name at ptr, else 0.
; Arg on stack: pointer to identifier start
_find_named_macro_param:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-9

	lw	r0,9(fp)
	sw	r0,-3(fp)
	sw	r0,-9(fp)
	la	r0,1
	sw	r0,-6(fp)

_fmp_loop:
	la	r1,788194
	lw	r1,0(r1)
	lw	r0,-6(fp)
	clu	r1,r0
	brt	_fmp_nf

	lw	r0,-6(fp)
	add	r0,-1
	push	r0
	la	r0,_mul32
	jal	r1,(r0)
	add	sp,3
	la	r1,200672
	add	r1,r0
	lw	r0,-3(fp)
	sw	r0,-9(fp)

_fmp_cmp:
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_fmp_check_tail
	lw	r2,-9(fp)
	lbu	r2,0(r2)
	ceq	r0,r2
	brf	_fmp_next
	add	r1,1
	lw	r2,-9(fp)
	add	r2,1
	sw	r2,-9(fp)
	bra	_fmp_cmp

_fmp_check_tail:
	lw	r2,-9(fp)
	lbu	r0,0(r2)
	push	r0
	la	r0,_is_macro_name_char
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_fmp_match
	bra	_fmp_next

_fmp_match:
	lw	r0,-6(fp)
	bra	_fmp_ret

_fmp_next:
	lw	r0,-6(fp)
	add	r0,1
	sw	r0,-6(fp)
	bra	_fmp_loop

_fmp_nf:
	la	r0,0

_fmp_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _is_macro_name_char: Return 1 if char is [0-9A-Za-z_], else 0.
; Arg on stack: character value
_is_macro_name_char:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,9(fp)
	lc	r1,48
	clu	r0,r1
	brt	_imnc_upper
	lc	r1,57
	clu	r1,r0
	brt	_imnc_upper
	la	r0,1
	bra	_imnc_ret

_imnc_upper:
	lw	r0,9(fp)
	lc	r1,65
	clu	r0,r1
	brt	_imnc_lower
	lc	r1,90
	clu	r1,r0
	brt	_imnc_lower
	la	r0,1
	bra	_imnc_ret

_imnc_lower:
	lw	r0,9(fp)
	lc	r1,97
	clu	r0,r1
	brt	_imnc_us
	lc	r1,122
	clu	r1,r0
	brt	_imnc_us
	la	r0,1
	bra	_imnc_ret

_imnc_us:
	lw	r0,9(fp)
	lc	r1,95
	ceq	r0,r1
	brt	_imnc_yes
	la	r0,0
	bra	_imnc_ret

_imnc_yes:
	la	r0,1

_imnc_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

_mul3:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,9(fp)
	mov	r2,r0
	add	r0,r2
	add	r0,r2
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

_mul39:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	lw	r0,9(fp)
	mov	r2,r0
	add	r0,r0
	add	r0,r0
	add	r0,r0
	mov	r1,r0
	add	r0,r0
	add	r0,r0
	add	r0,r1
	sub	r0,r2
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _mul32 / _mul256 / _mul40: r0 = arg * 32 / 256 / 40
_mul32:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	lw	r0,9(fp)
	add	r0,r0
	add	r0,r0
	add	r0,r0
	add	r0,r0
	add	r0,r0
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

_mul256:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	lw	r0,9(fp)
	add	r0,r0
	add	r0,r0
	add	r0,r0
	add	r0,r0
	add	r0,r0
	add	r0,r0
	add	r0,r0
	add	r0,r0
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

_mul40:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	lw	r0,9(fp)
	add	r0,r0
	add	r0,r0
	add	r0,r0
	mov	r1,r0
	add	r0,r0
	add	r0,r0
	add	r0,r1
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _record_macro_line: Append current _line_buf to _macro_buf.
; Arg on stack: line length
_record_macro_line:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-6

	lw	r0,9(fp)
	ceq	r0,z
	brf	_rml_has_len
	la	r1,_rml_done
	jmp	(r1)
_rml_has_len:
; Body pool is 0x020000-0x02FFFF. A recorded line is never longer than the
; source line plus a newline (\name and &name shrink to &N), so check first.
	la	r1,790716
	lw	r0,0(r1)
	lw	r1,9(fp)
	add	r0,r1
	add	r0,2
	la	r1,196608
	clu	r1,r0
	brf	_rml_room
	la	r0,_err_pool_full
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_rml_room:

	la	r0,196608
	sw	r0,-3(fp)
	la	r1,790716
	lw	r0,0(r1)
	sw	r0,-6(fp)

	_rml_cloop:
		lw	r1,-3(fp)
		lbu	r0,0(r1)
		ceq	r0,z
		brf	_rml_not_end
		la	r1,_rml_end
		jmp	(r1)
_rml_not_end:

		lc	r1,92
		ceq	r0,r1
		brf	_rml_not_bslash
		la	r1,_rml_bslash
		jmp	(r1)
_rml_not_bslash:

		lc	r1,38
		ceq	r0,r1
		brf	_rml_not_amp
		la	r1,_rml_amp
		jmp	(r1)
_rml_not_amp:

		lw	r2,-6(fp)
		sb	r0,0(r2)
		add	r2,1
		sw	r2,-6(fp)
		lw	r1,-3(fp)
		add	r1,1
		sw	r1,-3(fp)
		bra	_rml_cloop

_rml_bslash:
	lw	r1,-3(fp)
	add	r1,1
	lbu	r0,0(r1)
	lc	r2,64
	ceq	r0,r2
	brt	_rml_copy_bslash_at
	ceq	r0,z
	brt	_rml_copy_bslash
	push	r0
	la	r0,_is_macro_name_char
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_rml_copy_bslash
	lw	r1,-3(fp)
	add	r1,1
	push	r1
	la	r0,_find_named_macro_param
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_rml_copy_bslash
	lw	r2,-6(fp)
	lc	r1,38
	sb	r1,0(r2)
	add	r2,1
	lc	r1,48
	add	r1,r0
	sb	r1,0(r2)
	add	r2,1
	sw	r2,-6(fp)
	lw	r1,-3(fp)
	add	r1,1
_rml_skip_bname:
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_rml_skip_bname_done
	push	r1
	push	r0
	la	r0,_is_macro_name_char
	jal	r1,(r0)
	add	sp,3
	pop	r1
	ceq	r0,z
	brt	_rml_skip_bname_done
	add	r1,1
	bra	_rml_skip_bname
_rml_skip_bname_done:
	sw	r1,-3(fp)
	la	r1,_rml_cloop
	jmp	(r1)

_rml_copy_bslash_at:
	lw	r2,-6(fp)
	lc	r0,92
	sb	r0,0(r2)
	add	r2,1
	lc	r0,64
	sb	r0,0(r2)
	add	r2,1
	sw	r2,-6(fp)
	lw	r1,-3(fp)
	add	r1,2
	sw	r1,-3(fp)
	la	r1,_rml_cloop
	jmp	(r1)

_rml_copy_bslash:
	lw	r2,-6(fp)
	lc	r0,92
	sb	r0,0(r2)
	add	r2,1
	sw	r2,-6(fp)
	lw	r1,-3(fp)
	add	r1,1
	sw	r1,-3(fp)
	la	r1,_rml_cloop
	jmp	(r1)

_rml_amp:
	lw	r1,-3(fp)
	add	r1,1
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_rml_copy_amp
	lc	r2,48
	clu	r0,r2
	brt	_rml_try_named_amp
	lc	r2,57
	clu	r2,r0
	brt	_rml_try_named_amp
	bra	_rml_copy_amp
_rml_try_named_amp:
	push	r0
	la	r0,_is_macro_name_char
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_rml_copy_amp
	lw	r1,-3(fp)
	add	r1,1
	push	r1
	la	r0,_find_named_macro_param
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_rml_copy_amp
	lw	r2,-6(fp)
	lc	r1,38
	sb	r1,0(r2)
	add	r2,1
	lc	r1,48
	add	r1,r0
	sb	r1,0(r2)
	add	r2,1
	sw	r2,-6(fp)
	lw	r1,-3(fp)
	add	r1,1
_rml_skip_aname:
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_rml_skip_aname_done
	push	r1
	push	r0
	la	r0,_is_macro_name_char
	jal	r1,(r0)
	add	sp,3
	pop	r1
	ceq	r0,z
	brt	_rml_skip_aname_done
	add	r1,1
	bra	_rml_skip_aname
_rml_skip_aname_done:
	sw	r1,-3(fp)
	la	r1,_rml_cloop
	jmp	(r1)

_rml_copy_amp:
	lw	r2,-6(fp)
	lc	r0,38
	sb	r0,0(r2)
	add	r2,1
	sw	r2,-6(fp)
	lw	r1,-3(fp)
	add	r1,1
	sw	r1,-3(fp)
	la	r1,_rml_cloop
	jmp	(r1)

	_rml_end:
		lw	r2,-6(fp)
		la	r0,10
		sb	r0,0(r2)
		add	r2,1

		la	r1,790716
		sw	r2,0(r1)

	_rml_done:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _finish_macro: Finalize current macro recording.
_finish_macro:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

; Get macro table entry for current recording index
	la	r1,790713
	lw	r0,0(r1)
	push	r0
	la	r0,_mul39
	jal	r1,(r0)
	add	sp,3
	la	r1,98304
	add	r1,r0

; Store body end position
	la	r0,790716
	lw	r0,0(r0)
	sw	r0,36(r1)

; Clear macro state
	la	r1,790710
	la	r0,0
	sw	r0,0(r1)

; Increment macro count
	la	r1,786645
	lw	r0,0(r1)
	add	r0,1
	sw	r0,0(r1)

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _lookup_macro: Check if _line_buf starts with a defined macro name.
; Returns: r0 = 0 if not found, 1+index if found
_lookup_macro:
	push	fp
	push	r1
	push	r2
	push	r2
	mov	fp,sp

; Save name start from _line_buf (skip whitespace)
	la	r2,196608

_lm_scan_name:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_lm_sn2

	lc	r1,32
	ceq	r0,r1
	brt	_lm_skip_ws

	lc	r1,9
	ceq	r0,r1
	brt	_lm_skip_ws

; r2 points to first char of name. Save it.
	sw	r2,0(fp)

	bra	_lm_tbl_start

_lm_sn2:
	la	r1,_lm_not_found
	jmp	(r1)

_lm_skip_ws:
	add	r2,1
	bra	_lm_scan_name

_lm_tbl_start:
	la	r0,0

_lm_tbl_loop:
	la	r1,786645
	lw	r1,0(r1)
	clu	r0,r1
	brf	_lm_nf3

; Get macro table entry for index r0
; Save index on stack for later use in _lm_found
	push	r0
	push	r0
	la	r0,_mul39
	jal	r1,(r0)
	add	sp,3

	la	r1,98304
	add	r1,r0

; Compare table name (r1) with line_buf name (saved at 0(fp))
; Stack: [... saved_index]
	lw	r2,0(fp)

_lm_name_check:
	lbu	r0,0(r1)
	push	r2
	lbu	r2,0(r2)
	ceq	r0,z
	brt	_lm_tail_check

	ceq	r0,r2
	brf	_lm_next_entry2

	pop	r2
	add	r1,1
	add	r2,1
	bra	_lm_name_check

_lm_tail_check:
	push	r2
	la	r0,_is_macro_name_char
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_lm_found_pop2_idx
	la	r1,_lm_next_entry2
	jmp	(r1)

_lm_found_pop2_idx:
	pop	r2
_lm_found_pop_idx:
	pop	r0
	add	r0,1
	bra	_lm_ret

_lm_next_entry2:
	pop	r2
	pop	r0
	add	r0,1
	la	r1,_lm_tbl_loop
	jmp	(r1)

_lm_nf3:
	la	r1,_lm_not_found
	jmp	(r1)

_lm_not_found:
	la	r0,0

_lm_ret:
	mov	sp,fp
	pop	r2
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; --- Macro expansion stack ---
; A call pushes a frame; _read_line then takes lines from the innermost frame
; (via _exp_next_line) before reading source, so expanded lines go through
; the whole line processor: macro calls nest and directives work in bodies.
; 790719 depth (0..8). Frames at 233472, 64 bytes each:
;   +0 body read ptr, +3 body end, +6 \@ / &SYSNDX number,
;   +9 positional argument count, +12 + (N-1)*3 value ptr of parameter N
;   (0 = none; N = 1..16).
; Argument strings at 233984 + depth*512 (a call line is at most 256 chars).
; The pool header written by _write_macro_header holds the parameter names
; and defaults: count byte, then per parameter name strz and default strz.

; _expand_macro: Push an expansion frame for a macro call in the line buffer.
; Arg on stack: macro index (1-based from _lookup_macro)
; Frame: push fp, r1, r2, r2 = 12 bytes. Arg at 12(fp).
; 0(fp) entry ptr, -3 frame ptr, -6 string write ptr, -9 header names ptr,
; -12 scan ptr, -15 positional count, -18 arg end, -21 param count
_expand_macro:
	push	fp
	push	r1
	push	r2
	push	r2
	mov	fp,sp
	add	sp,-21

	lw	r0,12(fp)
	push	r0
	la	r0,_xref_mark_macro_expand
	jal	r1,(r0)
	add	sp,3

	lw	r0,12(fp)
	add	r0,-1
	push	r0
	la	r0,_mul39
	jal	r1,(r0)
	add	sp,3
	la	r1,98304
	add	r1,r0
	sw	r1,0(fp)

	la	r0,_expand_txt
	push	r0
	push	r1
	la	r0,_emit_list_line1
	jal	r1,(r0)
	add	sp,6

	la	r1,790719
	lw	r0,0(r1)
	lc	r2,8
	clu	r0,r2
	brt	_exm_room
	la	r0,_err_mac_deep
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_exm_room:
	push	r0
	la	r0,_mul32
	jal	r1,(r0)
	add	sp,3
	add	r0,r0
	la	r1,233472
	add	r0,r1
	sw	r0,-3(fp)

	la	r1,790719
	lw	r0,0(r1)
	push	r0
	la	r0,_mul256
	jal	r1,(r0)
	add	sp,3
	add	r0,r0
	la	r1,233984
	add	r0,r1
	sw	r0,-6(fp)

; clear the positional count and the 16 value pointers
	lw	r1,-3(fp)
	add	r1,9
	lc	r2,17
	lc	r0,0
_exm_clear:
	sw	r0,0(r1)
	add	r1,3
	add	r2,-1
	ceq	r2,z
	brf	_exm_clear
	sw	r0,-15(fp)

; header: parameter count, then names/defaults; the body follows it
	lw	r1,0(fp)
	lw	r1,33(r1)
	lbu	r0,0(r1)
	sw	r0,-21(fp)
	add	r1,1
	sw	r1,-9(fp)
	mov	r2,r0
	add	r2,r0
_exm_skip_hdr:
	ceq	r2,z
	brt	_exm_body
	push	r1
	la	r0,_skip_strz
	jal	r1,(r0)
	add	sp,3
	mov	r1,r0
	add	r2,-1
	bra	_exm_skip_hdr
_exm_body:
	lw	r2,-3(fp)
	sw	r1,0(r2)
	lw	r1,0(fp)
	lw	r0,36(r1)
	sw	r0,3(r2)
	la	r1,790707
	lw	r0,0(r1)
	sw	r0,6(r2)
	add	r0,1
	sw	r0,0(r1)

; skip indentation and the macro name in the call line
	la	r1,196608
_exm_ind:
	lbu	r0,0(r1)
	lc	r2,32
	ceq	r0,r2
	brt	_exm_ind_adv
	lc	r2,9
	ceq	r0,r2
	brf	_exm_name
_exm_ind_adv:
	add	r1,1
	bra	_exm_ind
_exm_name:
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_exm_args_far
	lc	r2,32
	ceq	r0,r2
	brt	_exm_args_far
	lc	r2,9
	ceq	r0,r2
	brt	_exm_args_far
	add	r1,1
	bra	_exm_name
_exm_args_far:
	sw	r1,-12(fp)

; one argument per pass: skip blanks, stop at end or ';', find its end
_exm_arg:
	lw	r0,-12(fp)
	push	r0
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	sw	r0,-12(fp)
	lbu	r1,0(r0)
	ceq	r1,z
	brf	_exm_arg_nz
	la	r1,_exm_defaults
	jmp	(r1)
_exm_arg_nz:
	lc	r2,59
	ceq	r1,r2
	brf	_exm_arg_go
	la	r1,_exm_defaults
	jmp	(r1)
_exm_arg_go:
	push	r0
	la	r0,_arg_end
	jal	r1,(r0)
	add	sp,3
	sw	r0,-18(fp)

; keyword argument NAME=value when NAME is a parameter of this macro
	lw	r0,-21(fp)
	push	r0
	lw	r0,-9(fp)
	push	r0
	lw	r0,-12(fp)
	push	r0
	la	r0,_keyword_param
	jal	r1,(r0)
	add	sp,9
	ceq	r0,z
	brt	_exm_positional
	push	r0
	lw	r1,-12(fp)
_exm_kw_eq:
	lbu	r0,0(r1)
	add	r1,1
	lc	r2,61
	ceq	r0,r2
	brf	_exm_kw_eq
	sw	r1,-12(fp)
	pop	r0
	bra	_exm_store

_exm_positional:
	lw	r0,-15(fp)
	add	r0,1
	sw	r0,-15(fp)
	lc	r1,17
	clu	r0,r1
	brt	_exm_store
	la	r0,_err_arg_full
	push	r0
	la	r0,_fatal
	jal	r1,(r0)

; r0 = parameter number: point its slot at a copy of [scan ptr, arg end)
_exm_store:
	push	r0
	la	r0,_mul3
	jal	r1,(r0)
	add	sp,3
	lw	r1,-3(fp)
	add	r1,r0
	lw	r0,-6(fp)
	sw	r0,9(r1)
	lw	r0,-6(fp)
	push	r0
	lw	r0,-18(fp)
	push	r0
	lw	r0,-12(fp)
	push	r0
	la	r0,_copy_range
	jal	r1,(r0)
	add	sp,9
	sw	r0,-6(fp)

; after the argument: a comma starts the next one, anything else ends them
	lw	r0,-18(fp)
	push	r0
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	lbu	r1,0(r0)
	lc	r2,44
	ceq	r1,r2
	brf	_exm_defaults
	add	r0,1
	sw	r0,-12(fp)
	la	r1,_exm_arg
	jmp	(r1)

; parameters with no (or an empty) argument take their default
_exm_defaults:
	lw	r2,-3(fp)
	lw	r0,-15(fp)
	sw	r0,9(r2)
	add	r2,12
	lw	r1,-9(fp)
_exm_def_loop:
	lw	r0,-21(fp)
	ceq	r0,z
	brt	_exm_done
	add	r0,-1
	sw	r0,-21(fp)
	push	r1
	la	r0,_skip_strz
	jal	r1,(r0)
	add	sp,3
	mov	r1,r0
	lw	r0,0(r2)
	ceq	r0,z
	brt	_exm_def_use
	lbu	r0,0(r0)
	ceq	r0,z
	brf	_exm_def_next
_exm_def_use:
	sw	r1,0(r2)
_exm_def_next:
	push	r1
	la	r0,_skip_strz
	jal	r1,(r0)
	add	sp,3
	mov	r1,r0
	add	r2,3
	bra	_exm_def_loop

_exm_done:
	la	r1,790719
	lw	r0,0(r1)
	add	r0,1
	sw	r0,0(r1)

	mov	sp,fp
	pop	r2
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _exp_next_line: Write the next line of the innermost expansion into the
; input line buffer, replacing &N with argument N, \@ and &SYSNDX with the
; expansion number, and &SYSNARG with the positional argument count.
; Returns: r0 = line length + 1, or 0 if the expansion has ended (its frame
; is popped).
; Frame: push fp, r1, r2 = 9 bytes.
; -3(fp) frame ptr, -6 write ptr, -9 read ptr
_exp_next_line:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-9

	la	r1,790719
	lw	r0,0(r1)
	add	r0,-1
	push	r0
	la	r0,_mul32
	jal	r1,(r0)
	add	sp,3
	add	r0,r0
	la	r1,233472
	add	r0,r1
	sw	r0,-3(fp)
	mov	r2,r0
	lw	r1,0(r2)
	sw	r1,-9(fp)
	lw	r0,3(r2)
	clu	r1,r0
	brt	_enl_start

	la	r1,790719
	lw	r0,0(r1)
	add	r0,-1
	sw	r0,0(r1)
	la	r0,0
	la	r1,_enl_ret
	jmp	(r1)

_enl_start:
	la	r0,196608
	sw	r0,-6(fp)

_enl_loop:
	lw	r0,-6(fp)
	la	r1,196865
	clu	r0,r1
	brt	_enl_room
	la	r0,_err_exp_long
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_enl_room:
	lw	r2,-3(fp)
	lw	r0,3(r2)
	lw	r1,-9(fp)
	clu	r1,r0
	brt	_enl_more
	la	r1,_enl_eol
	jmp	(r1)
_enl_more:
	lbu	r0,0(r1)
	lc	r2,10
	ceq	r0,r2
	brf	_enl_not_nl
	add	r1,1
	sw	r1,-9(fp)
	la	r1,_enl_eol
	jmp	(r1)
_enl_not_nl:
	lc	r2,38
	ceq	r0,r2
	brt	_enl_amp
	lc	r2,92
	ceq	r0,r2
	brt	_enl_bslash
_enl_copy:
	lw	r2,-6(fp)
	sb	r0,0(r2)
	add	r2,1
	sw	r2,-6(fp)
	add	r1,1
	sw	r1,-9(fp)
	bra	_enl_loop

_enl_bslash:
	lbu	r2,1(r1)
	lc	r0,64
	ceq	r0,r2
	brt	_enl_ndx2
	lc	r0,92
	bra	_enl_copy

_enl_amp:
	lbu	r0,1(r1)
	lc	r2,48
	sub	r0,r2
	ceq	r0,z
	brt	_enl_sys
	lc	r2,17
	clu	r0,r2
	brf	_enl_sys
; &N: copy argument N (nothing when absent)
	add	r1,2
	sw	r1,-9(fp)
	push	r0
	la	r0,_mul3
	jal	r1,(r0)
	add	sp,3
	lw	r2,-3(fp)
	add	r2,r0
	lw	r1,9(r2)
	ceq	r1,z
	brt	_enl_loop_far
	lw	r2,-6(fp)
_enl_arg_copy:
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_enl_arg_done
	sb	r0,0(r2)
	add	r1,1
	add	r2,1
	bra	_enl_arg_copy
_enl_arg_done:
	sw	r2,-6(fp)
_enl_loop_far:
	la	r1,_enl_loop
	jmp	(r1)

_enl_ndx2:
	add	r1,2
	sw	r1,-9(fp)
	bra	_enl_ndx

_enl_sys:
	add	r1,1
	push	r1
	la	r0,_sysndx_txt
	push	r0
	push	r1
	la	r0,_match_word
	jal	r1,(r0)
	add	sp,6
	pop	r1
	ceq	r0,z
	brt	_enl_sys_narg
	add	r1,6
	sw	r1,-9(fp)
_enl_ndx:
	lw	r0,-6(fp)
	la	r1,790704
	sw	r0,0(r1)
	lw	r2,-3(fp)
	lw	r0,6(r2)
	push	r0
	la	r0,_emit_num4_to_buf
	jal	r1,(r0)
	add	sp,3
	la	r1,790704
	lw	r0,0(r1)
	sw	r0,-6(fp)
	la	r1,_enl_loop
	jmp	(r1)

_enl_sys_narg:
	push	r1
	la	r0,_sysnarg_txt
	push	r0
	push	r1
	la	r0,_match_word
	jal	r1,(r0)
	add	sp,6
	pop	r1
	ceq	r0,z
	brf	_enl_narg
; plain '&': keep it
	add	r1,-1
	lc	r0,38
	la	r2,_enl_copy
	jmp	(r2)

_enl_narg:
	add	r1,7
	sw	r1,-9(fp)
	lw	r2,-3(fp)
	lw	r0,9(r2)
	lw	r2,-6(fp)
	lc	r1,10
	clu	r0,r1
	brt	_enl_narg_one
	lc	r1,49
	sb	r1,0(r2)
	add	r2,1
	add	r0,-10
_enl_narg_one:
	add	r0,48
	sb	r0,0(r2)
	add	r2,1
	sw	r2,-6(fp)
	la	r1,_enl_loop
	jmp	(r1)

_enl_eol:
	lw	r2,-6(fp)
	lc	r0,0
	sb	r0,0(r2)
	lw	r1,-3(fp)
	lw	r0,-9(fp)
	sw	r0,0(r1)
	la	r1,196607
	mov	r0,r2
	sub	r0,r1

_enl_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _match_word: Return 1 if the text at ptr is word, not followed by a macro
; name character, else 0.
; Args on stack: ptr (9 fp), word (12 fp)
_match_word:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r1,9(fp)
	lw	r2,12(fp)
_mw_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_mw_tail
	push	r2
	lbu	r2,0(r1)
	ceq	r0,r2
	pop	r2
	brf	_mw_no
	add	r1,1
	add	r2,1
	bra	_mw_loop
_mw_tail:
	lbu	r0,0(r1)
	push	r0
	la	r0,_is_macro_name_char
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brf	_mw_no
	la	r0,1
	bra	_mw_ret
_mw_no:
	la	r0,0
_mw_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _skip_strz: Return the pointer just past the NUL of the string at ptr.
; Arg on stack: ptr
_skip_strz:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,9(fp)
_sks_loop:
	lbu	r1,0(r0)
	add	r0,1
	ceq	r1,z
	brf	_sks_loop

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _copy_range: Copy [src, end) to dst and NUL-terminate it.
; Args on stack: src (9 fp), end (12 fp), dst (15 fp)
; Returns: r0 = dst just past the NUL
_copy_range:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r1,9(fp)
	lw	r2,15(fp)
_cr_loop:
	lw	r0,12(fp)
	clu	r1,r0
	brf	_cr_done
	lbu	r0,0(r1)
	sb	r0,0(r2)
	add	r1,1
	add	r2,1
	bra	_cr_loop
_cr_done:
	lc	r0,0
	sb	r0,0(r2)
	add	r2,1
	mov	r0,r2

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _arg_end: Return the end of the macro argument (or default) at ptr: the
; first NUL, or comma, blank, tab or ';' outside quotes and parentheses.
; A backslash inside quotes escapes the next character.
; Arg on stack: ptr
; Frame: push fp, r1, r2 = 9 bytes. -3(fp) quote char, -6 paren depth
_arg_end:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-6

	lc	r0,0
	sw	r0,-3(fp)
	sw	r0,-6(fp)
	lw	r1,9(fp)
_ae_loop:
	lbu	r0,0(r1)
	ceq	r0,z
	brf	_ae_nz
	la	r2,_ae_done
	jmp	(r2)
_ae_nz:
	lw	r2,-3(fp)
	ceq	r2,z
	brt	_ae_open
; inside quotes
	ceq	r0,r2
	brf	_ae_in_bs
	lc	r2,0
	sw	r2,-3(fp)
	bra	_ae_next
_ae_in_bs:
	lc	r2,92
	ceq	r0,r2
	brf	_ae_next
	lbu	r0,1(r1)
	ceq	r0,z
	brt	_ae_next
	add	r1,1
	bra	_ae_next
_ae_open:
	lc	r2,39
	ceq	r0,r2
	brt	_ae_quote
	lc	r2,34
	ceq	r0,r2
	brt	_ae_quote
	lc	r2,40
	ceq	r0,r2
	brt	_ae_lpar
	lc	r2,41
	ceq	r0,r2
	brt	_ae_rpar
	lw	r2,-6(fp)
	ceq	r2,z
	brf	_ae_next
	lc	r2,44
	ceq	r0,r2
	brt	_ae_done
	lc	r2,32
	ceq	r0,r2
	brt	_ae_done
	lc	r2,9
	ceq	r0,r2
	brt	_ae_done
	lc	r2,59
	ceq	r0,r2
	brt	_ae_done
	bra	_ae_next
_ae_quote:
	sw	r0,-3(fp)
	bra	_ae_next
_ae_lpar:
	lw	r0,-6(fp)
	add	r0,1
	sw	r0,-6(fp)
	bra	_ae_next
_ae_rpar:
	lw	r0,-6(fp)
	ceq	r0,z
	brt	_ae_next
	add	r0,-1
	sw	r0,-6(fp)
_ae_next:
	add	r1,1
	la	r2,_ae_loop
	jmp	(r2)
_ae_done:
	mov	r0,r1

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _keyword_param: If the argument at ptr is NAME=... and NAME is one of the
; macro's parameters, return that parameter's number (1-based), else 0.
; Args on stack: ptr (9 fp), header names ptr (12 fp), param count (15 fp)
; Frame: push fp, r1, r2 = 9 bytes. -3(fp) name end, -6 number, -9 entry ptr
_keyword_param:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-9

	lw	r1,9(fp)
_kwp_name:
	lbu	r0,0(r1)
	push	r1
	push	r0
	la	r0,_is_macro_name_char
	jal	r1,(r0)
	add	sp,3
	pop	r1
	ceq	r0,z
	brt	_kwp_name_end
	add	r1,1
	bra	_kwp_name
_kwp_name_end:
	lw	r0,9(fp)
	ceq	r0,r1
	brt	_kwp_no
	lbu	r0,0(r1)
	lc	r2,61
	ceq	r0,r2
	brf	_kwp_no
	sw	r1,-3(fp)
	lc	r0,1
	sw	r0,-6(fp)
	lw	r0,12(fp)
	sw	r0,-9(fp)

_kwp_entry:
	lw	r0,-6(fp)
	lw	r1,15(fp)
	clu	r1,r0
	brt	_kwp_no
; compare [ptr, name end) with the entry name (NUL-terminated)
	lw	r1,9(fp)
	lw	r2,-9(fp)
_kwp_cmp:
	lw	r0,-3(fp)
	clu	r1,r0
	brf	_kwp_cmp_end
	lbu	r0,0(r1)
	push	r1
	lbu	r1,0(r2)
	ceq	r0,r1
	pop	r1
	brf	_kwp_next
	add	r1,1
	add	r2,1
	bra	_kwp_cmp
_kwp_cmp_end:
	lbu	r0,0(r2)
	ceq	r0,z
	brf	_kwp_next
	lw	r0,-6(fp)
	bra	_kwp_ret
_kwp_next:
	lw	r0,-9(fp)
	push	r0
	la	r0,_skip_strz
	jal	r1,(r0)
	add	sp,3
	push	r0
	la	r0,_skip_strz
	jal	r1,(r0)
	add	sp,3
	sw	r0,-9(fp)
	lw	r0,-6(fp)
	add	r0,1
	sw	r0,-6(fp)
	bra	_kwp_entry
_kwp_no:
	la	r0,0
_kwp_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _write_macro_header: Write the parameter header of the macro being defined
; at the pool write position: count byte, then for each parameter its name
; strz (from 200672) and default strz (from 238080). The body follows.
_write_macro_header:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-3

; header is at most 1 + 16 * (32 + 64) bytes
	la	r1,790716
	lw	r0,0(r1)
	la	r2,1600
	add	r0,r2
	la	r2,196608
	clu	r0,r2
	brt	_wmh_room
	la	r0,_err_pool_full
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_wmh_room:
	la	r1,788194
	lw	r0,0(r1)
	la	r1,790716
	lw	r2,0(r1)
	sb	r0,0(r2)
	add	r2,1
	lc	r0,0
	sw	r0,-3(fp)
_wmh_loop:
	lw	r0,-3(fp)
	la	r1,788194
	lw	r1,0(r1)
	clu	r0,r1
	brf	_wmh_done
	push	r0
	la	r0,_mul32
	jal	r1,(r0)
	add	sp,3
	la	r1,200672
	add	r0,r1
	push	r2
	push	r0
	la	r0,_copy_strz_end
	jal	r1,(r0)
	add	sp,6
	mov	r2,r0
	lw	r0,-3(fp)
	push	r0
	la	r0,_default_slot
	jal	r1,(r0)
	add	sp,3
	push	r2
	push	r0
	la	r0,_copy_strz_end
	jal	r1,(r0)
	add	sp,6
	mov	r2,r0
	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
	bra	_wmh_loop
_wmh_done:
	la	r1,790716
	sw	r2,0(r1)

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _copy_strz_end: Copy the string at src to dst.
; Args on stack: src (9 fp), dst (12 fp)
; Returns: r0 = dst just past the NUL
_copy_strz_end:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r1,9(fp)
	lw	r2,12(fp)
_cse_loop:
	lbu	r0,0(r1)
	sb	r0,0(r2)
	add	r1,1
	add	r2,1
	ceq	r0,z
	brf	_cse_loop
	mov	r0,r2

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _default_slot: r0 = 238080 + index * 64, the default text of parameter
; index (0-based) of the macro being defined.
; Arg on stack: index
_default_slot:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,9(fp)
	push	r0
	la	r0,_mul32
	jal	r1,(r0)
	add	sp,3
	add	r0,r0
	la	r1,238080
	add	r0,r1

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _pmp_copy_default: Copy the default text at src (after '=') into the slot
; of parameter index; at most 63 characters.
; Args on stack: index (9 fp), src (12 fp)
; Returns: r0 = end of the default text
_pmp_copy_default:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,12(fp)
	push	r0
	la	r0,_arg_end
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0
	lw	r1,12(fp)
	sub	r0,r1
	lc	r1,64
	clu	r0,r1
	brt	_pcd_ok
	la	r0,_err_def_long
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_pcd_ok:
	lw	r0,9(fp)
	push	r0
	la	r0,_default_slot
	jal	r1,(r0)
	add	sp,3
	push	r0
	push	r2
	lw	r0,12(fp)
	push	r0
	la	r0,_copy_range
	jal	r1,(r0)
	add	sp,9
	mov	r0,r2

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_char_to_buf: Write char to _expand_buf at current write position.
; Arg on stack: char value
; Frame: push fp, r1, r2 = 9 bytes. Arg at 9(fp).
_emit_char_to_buf:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r2,790704
	lw	r1,0(r2)

	lw	r0,9(fp)
	sb	r0,0(r1)

	add	r1,1
	sw	r1,0(r2)

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_num4_to_buf: Write a decimal number to _expand_buf, zero-padded to at
; least 4 digits (0001-9999, then 10000 and up unpadded, so labels stay unique).
; Arg on stack: number
; Frame: push fp, r1, r2, r2 = 12 bytes. Arg at 12(fp).
; 0(fp) = remaining value, -3(fp) = started flag, -6(fp) = power ptr
_emit_num4_to_buf:
	push	fp
	push	r1
	push	r2
	push	r2
	mov	fp,sp
	add	sp,-6

	lw	r0,12(fp)
	sw	r0,0(fp)
	la	r0,0
	sw	r0,-3(fp)
	la	r0,_dec_pow
	sw	r0,-6(fp)

_en4_pow:
	lw	r1,-6(fp)
	lw	r1,0(r1)
	ceq	r1,z
	brt	_en4_ret
	la	r2,0

_en4_sub:
	lw	r0,0(fp)
	clu	r0,r1
	brt	_en4_digit
	sub	r0,r1
	sw	r0,0(fp)
	add	r2,1
	bra	_en4_sub

_en4_digit:
	ceq	r2,z
	brf	_en4_emit
	lw	r0,-3(fp)
	ceq	r0,z
	brf	_en4_emit
	la	r0,1001
	clu	r1,r0
	brf	_en4_next

_en4_emit:
	lc	r0,48
	add	r0,r2
	push	r0
	la	r0,_emit_char_to_buf
	jal	r1,(r0)
	add	sp,3
	la	r0,1
	sw	r0,-3(fp)

_en4_next:
	lw	r0,-6(fp)
	add	r0,3
	sw	r0,-6(fp)
	bra	_en4_pow

_en4_ret:
	mov	sp,fp
	pop	r2
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _copy_ident_token: Copy identifier token at ptr to _parse_name_buf.
; Arg on stack: ptr
; Returns: r0 = ptr after token
_copy_ident_token:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3

	lw	r2,9(fp)
	la	r0,197128
	sw	r0,-3(fp)

	lbu	r0,0(r2)
	push	r0
	la	r0,_is_ident_start
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_cit_done

_cit_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_cit_done
	push	r0
	la	r0,_is_ident_char
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_cit_done
	lbu	r0,0(r2)
	lw	r1,-3(fp)
	sb	r0,0(r1)
	add	r1,1
	sw	r1,-3(fp)
	add	r2,1
	bra	_cit_loop

_cit_done:
	lw	r1,-3(fp)
	la	r0,0
	sb	r0,0(r1)
	mov	r0,r2
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _copy_expr_token: Copy one expression term token to _parse_name_buf.
; Arg on stack: ptr
; Returns: r0 = ptr after token
_copy_expr_token:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3

	lw	r2,9(fp)
	la	r0,197128
	sw	r0,-3(fp)

_cet_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_cet_done
	lc	r1,32
	ceq	r0,r1
	brt	_cet_done
	lc	r1,9
	ceq	r0,r1
	brt	_cet_done
	lc	r1,43
	ceq	r0,r1
	brt	_cet_done
	lc	r1,45
	ceq	r0,r1
	brt	_cet_done
	lc	r1,44
	ceq	r0,r1
	brt	_cet_done
	lc	r1,59
	ceq	r0,r1
	brt	_cet_done
	lc	r1,35
	ceq	r0,r1
	brt	_cet_done
	lw	r1,-3(fp)
	lbu	r0,0(r2)
	sb	r0,0(r1)
	add	r1,1
	sw	r1,-3(fp)
	la	r0,0
	sb	r0,0(r1)
	add	r2,1
	bra	_cet_loop

_cet_done:
	mov	r0,r2
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _store_parse_name_value: Store value under _parse_name_buf in symbol table.
; Arg on stack: value
_store_parse_name_value:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-6

; Symbol names are at most 31 characters (40-byte entries: name + NUL at +0,
; value at +32).
	la	r1,197128
	la	r2,0
_spnv_len:
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_spnv_len_done
	add	r1,1
	add	r2,1
	bra	_spnv_len
_spnv_len_done:
	lc	r0,32
	clu	r2,r0
	brt	_spnv_len_ok
	la	r0,_err_sym_long
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_spnv_len_ok:

	la	r0,_sym_find
	jal	r1,(r0)
	la	r1,787560
	lw	r1,0(r1)
	clu	r0,r1
	brf	_spnv_new
	push	r0
	la	r0,_mul40
	jal	r1,(r0)
	add	sp,3
	la	r1,65536
	add	r1,r0
	bra	_spnv_store

_spnv_new:
	la	r1,787560
	lw	r0,0(r1)
	la	r2,512
	clu	r0,r2
	brt	_spnv_room
	la	r0,_err_sym_full
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_spnv_room:
	la	r1,787560
	lw	r0,0(r1)
	push	r0
	la	r0,_mul40
	jal	r1,(r0)
	add	sp,3
	la	r1,65536
	add	r1,r0
	la	r2,787560
	lw	r0,0(r2)
	add	r0,1
	sw	r0,0(r2)

_spnv_store:
	sw	r1,-3(fp)
	la	r2,197128

_spnv_name:
	lbu	r0,0(r2)
	sb	r0,0(r1)
	ceq	r0,z
	brt	_spnv_after
	add	r1,1
	add	r2,1
	bra	_spnv_name

_spnv_after:
	lw	r1,-3(fp)
	lw	r0,9(fp)
	sw	r0,32(r1)

	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _eval_expr_ptr: Evaluate an assembly-time expression at ptr (see
; _eval_full for the grammar). Undefined symbols count as 0 and are
; reported under HLDIAG.
; Args on stack: ptr
; Returns: r0 = value
_eval_expr_ptr:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	lw	r0,9(fp)
	push	r0
	lc	r0,0
	push	r0
	la	r0,_eval_full
	jal	r1,(r0)
	add	sp,6
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _skip_ws_ptr: Advance pointer past spaces and tabs.
; Arg on stack: ptr
; Returns: r0 = advanced ptr
_skip_ws_ptr:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	lw	r2,9(fp)

_swp_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_swp_ret_ptr
	la	r1,32
	ceq	r0,r1
	brt	_swp_advance
	la	r1,9
	ceq	r0,r1
	brt	_swp_advance
	bra	_swp_ret_ptr

_swp_advance:
	add	r2,1
	bra	_swp_loop

_swp_ret_ptr:
	mov	r0,r2
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _emit_byte_list_value: Emit one decimal item into a lowered .byte list.
; Args on stack: flag_ptr (9 fp), value (12 fp)
_emit_byte_list_value:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	lw	r2,9(fp)
	lw	r0,0(r2)
	ceq	r0,z
	brt	_eblv_first

	lc	r0,44
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3
	bra	_eblv_emit

_eblv_first:
	la	r0,_dot_byte_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	la	r0,1
	sw	r0,0(r2)

_eblv_emit:
	lw	r0,12(fp)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _emit_fill_line: Lower count/value to one .byte list line.
; Args on stack: count (9 fp), value (12 fp)
_emit_fill_line:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3
	la	r0,0
	sw	r0,-3(fp)

	lw	r2,9(fp)
	ceq	r2,z
	brt	_efl_ret

	_efl_loop:
		lw	r0,12(fp)
		push	r0
		la	r0,0
		add	r0,fp
		add	r0,-3
		push	r0
		la	r0,_emit_byte_list_value
	jal	r1,(r0)
	add	sp,6
	add	r2,-1
	ceq	r2,z
	brt	_efl_done
	bra	_efl_loop

_efl_done:
	la	r0,_emit_crlf
	jal	r1,(r0)

_efl_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _handle_dot_space: Lower .space N to .byte 0,...
_handle_dot_space:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

; the directive may be indented (as in a macro body)
	la	r2,196608
	push	r2
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	add	r0,6
	push	r0
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	push	r0
	la	r0,_atoi
	jal	r1,(r0)
	add	sp,3
		mov	r2,r0
		la	r0,0
		push	r0
		push	r2
		la	r0,_emit_fill_line
		jal	r1,(r0)
	add	sp,6

	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _handle_dot_fill: Lower .fill N,V to .byte V,V,...
_handle_dot_fill:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-6

; the directive may be indented (as in a macro body)
	la	r2,196608
	push	r2
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	add	r0,5
	push	r0
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0

	push	r2
	la	r0,_atoi
	jal	r1,(r0)
	add	sp,3
	sw	r0,-3(fp)

_hdf_find_comma:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_hdf_ret
	la	r1,44
	ceq	r0,r1
	brt	_hdf_after_comma
	add	r2,1
	bra	_hdf_find_comma

_hdf_after_comma:
	add	r2,1
	push	r2
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	push	r0
	la	r0,_atoi
	jal	r1,(r0)
	add	sp,3
	sw	r0,-6(fp)

	lw	r0,-6(fp)
	push	r0
	lw	r0,-3(fp)
	push	r0
	la	r0,_emit_fill_line
	jal	r1,(r0)
	add	sp,6

_hdf_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _emit_ascii_line: Lower a quoted string to a .byte list.
; Args on stack: add_zero (9 fp), ptr (12 fp)
_emit_ascii_line:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3
	la	r0,0
	sw	r0,-3(fp)
	lw	r2,12(fp)

_eal_find_quote:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_eal_done
	la	r1,34
	ceq	r0,r1
	brt	_eal_string
	add	r2,1
	bra	_eal_find_quote

_eal_string:
	add	r2,1

_eal_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_eal_done
	la	r1,34
	ceq	r0,r1
	brt	_eal_done_chars
	la	r1,92
	ceq	r0,r1
	brt	_eal_escape
	bra	_eal_emit

_eal_escape:
	add	r2,1
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_eal_done_chars
	lc	r1,120
	ceq	r0,r1
	brt	_eal_hex
	push	r0
	la	r0,_string_escape
	jal	r1,(r0)
	add	sp,3
	bra	_eal_emit

; \xNN: exactly two hex digits; r2 ends on the second digit
_eal_hex:
	add	r2,1
	push	r2
	la	r0,_eal_hex_digit
	jal	r1,(r0)
	pop	r2
	add	r0,r0
	add	r0,r0
	add	r0,r0
	add	r0,r0
	push	r0
	add	r2,1
	push	r2
	la	r0,_eal_hex_digit
	jal	r1,(r0)
	pop	r2
	pop	r1
	add	r0,r1

	_eal_emit:
		push	r0
		la	r0,0
		add	r0,fp
		add	r0,-3
		push	r0
	la	r0,_emit_byte_list_value
	jal	r1,(r0)
	add	sp,6
	add	r2,1
	bra	_eal_loop

_eal_done_chars:
	lw	r0,9(fp)
	ceq	r0,z
	brt	_eal_done
	la	r0,0
	push	r0
	la	r0,0
	add	r0,fp
	add	r0,-3
	push	r0
	la	r0,_emit_byte_list_value
	jal	r1,(r0)
	add	sp,6

_eal_done:
	lw	r0,-3(fp)
	ceq	r0,z
	brt	_eal_ret
	la	r0,_emit_crlf
	jal	r1,(r0)

_eal_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _handle_dot_ascii: Lower .ascii "..." to .byte ...
_handle_dot_ascii:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,196608
	push	r0
	la	r0,0
	push	r0
	la	r0,_emit_ascii_line
	jal	r1,(r0)
	add	sp,6

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _handle_dot_asciz: Lower .asciz "..." to .byte ...,0
_handle_dot_asciz:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,196608
	push	r0
	la	r0,1
	push	r0
	la	r0,_emit_ascii_line
	jal	r1,(r0)
	add	sp,6

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; --- Step 7: Conditional assembly ---
; Following the standard calling convention from fib.s/sieve.s:
;   push fp; push r2; push r1; mov fp,sp
;   ... body (args at 9(fp), 12(fp), ...) ...
;   mov sp,fp; pop r1; pop r2; pop fp; jmp (r1)
; r0 = scratch/return, r1 = return address, r2 = callee-saved register var

; _is_hex_digit: r0 = 1 if 0-9, A-F, or a-f
; Arg on stack: char
_is_hex_digit:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	push	r0
	la	r0,_is_digit
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brf	_ihd_yes

	lw	r0,6(fp)
	la	r1,65
	clu	r0,r1
	brt	_ihd_lower
	la	r1,71
	clu	r0,r1
	brt	_ihd_yes

_ihd_lower:
	lw	r0,6(fp)
	la	r1,97
	clu	r0,r1
	brt	_ihd_no
	la	r1,103
	clu	r0,r1
	brt	_ihd_yes

_ihd_no:
	la	r0,0
	bra	_ihd_ret

_ihd_yes:
	la	r0,1

_ihd_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _hex_digit_val: Convert 0-9, A-F, a-f to integer value.
; Arg on stack: char
; Returns: r0 = 0..15, or 0 for unsupported input
_hex_digit_val:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	push	r0
	la	r0,_is_digit
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brf	_hdv_digit

	lw	r0,6(fp)
	la	r1,97
	clu	r0,r1
	brt	_hdv_upper
	la	r1,103
	clu	r0,r1
	brf	_hdv_upper
	la	r1,87
	lw	r0,6(fp)
	sub	r0,r1
	bra	_hdv_ret

_hdv_upper:
	lw	r0,6(fp)
	la	r1,65
	clu	r0,r1
	brt	_hdv_bad
	la	r1,71
	clu	r0,r1
	brf	_hdv_bad
	la	r1,55
	lw	r0,6(fp)
	sub	r0,r1
	bra	_hdv_ret

_hdv_digit:
	lw	r0,6(fp)
	la	r1,48
	sub	r0,r1
	bra	_hdv_ret

_hdv_bad:
	la	r0,0

_hdv_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _is_bin_digit: r0 = 1 if 0 or 1
; Arg on stack: char
_is_bin_digit:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	la	r1,48
	ceq	r0,r1
	brt	_ibd_yes
	la	r1,49
	ceq	r0,r1
	brt	_ibd_yes
	la	r0,0
	bra	_ibd_ret

_ibd_yes:
	la	r0,1

_ibd_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _atoi: Parse decimal, 0x-prefixed hex, 0b-prefixed binary, or h-suffixed hex.
; Arg on stack: string pointer (9 fp)
; Returns: r0 = integer value
_atoi:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-12
	lw	r2,9(fp)
	la	r0,0
	sw	r0,-3(fp)
	la	r0,10
	sw	r0,-6(fp)
	la	r0,0
	sw	r0,-9(fp)

	lbu	r0,0(r2)
	la	r1,45
	ceq	r0,r1
	brt	atoi_neg
	bra	atoi_prefix

atoi_neg:
	la	r0,1
	sw	r0,-9(fp)
	add	r2,1

atoi_prefix:
	lbu	r0,0(r2)
	la	r1,48
	ceq	r0,r1
	brt	atoi_pref_0
	bra	atoi_suffix_check

atoi_pref_0:
	lbu	r0,1(r2)
	la	r1,120
	ceq	r0,r1
	brt	atoi_hex_prefix
	la	r1,88
	ceq	r0,r1
	brt	atoi_hex_prefix
	la	r1,98
	ceq	r0,r1
	brt	atoi_bin_prefix
	la	r1,66
	ceq	r0,r1
	brt	atoi_bin_prefix
	bra	atoi_suffix_check

atoi_hex_prefix:
	la	r0,16
	sw	r0,-6(fp)
	add	r2,2
	bra	atoi_loop

atoi_bin_prefix:
	la	r0,2
	sw	r0,-6(fp)
	add	r2,2
	bra	atoi_loop

atoi_suffix_check:
	push	r2
	la	r0,_strlen24
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	atoi_loop
	add	r0,-1
	add	r0,r2
	lbu	r0,0(r0)
	la	r1,104
	ceq	r0,r1
	brt	atoi_hex_suffix
	la	r1,72
	ceq	r0,r1
	brt	atoi_hex_suffix
	bra	atoi_loop

atoi_hex_suffix:
	la	r0,16
	sw	r0,-6(fp)

	atoi_loop:
		lbu	r0,0(r2)
		ceq	r0,z
		brf	atoi_loop_not_done
		la	r1,atoi_done
		jmp	(r1)

atoi_loop_not_done:

	lw	r1,-6(fp)
	la	r0,16
	ceq	r0,r1
	brt	atoi_hex_digit
	la	r0,2
	ceq	r0,r1
	brt	atoi_bin_digit

		lbu	r0,0(r2)
		la	r1,48
		clu	r0,r1
		brf	atoi_dec_ge_48
		la	r1,atoi_done
		jmp	(r1)

atoi_dec_ge_48:
		la	r1,58
		clu	r0,r1
		brt	atoi_dec_lt_58
		la	r1,atoi_done
		jmp	(r1)

atoi_dec_lt_58:
	la	r1,48
	sub	r0,r1
	sw	r0,-12(fp)
	lw	r0,-3(fp)
	push	r0
	la	r0,_mul10
	jal	r1,(r0)
	add	sp,3
	lw	r1,-12(fp)
	add	r0,r1
	sw	r0,-3(fp)
	add	r2,1
	la	r1,atoi_loop
	jmp	(r1)

atoi_hex_digit:
		lbu	r0,0(r2)
		la	r1,104
		ceq	r0,r1
		brf	atoi_hex_chk_upper
		la	r1,atoi_done
		jmp	(r1)

atoi_hex_chk_upper:
		la	r1,72
		ceq	r0,r1
		brf	atoi_hex_chk_digit
		la	r1,atoi_done
		jmp	(r1)

atoi_hex_chk_digit:
	push	r0
	la	r0,_is_hex_digit
		jal	r1,(r0)
		add	sp,3
		ceq	r0,z
		brf	atoi_hex_accum
		la	r1,atoi_done
		jmp	(r1)

atoi_hex_accum:
	lbu	r0,0(r2)
	push	r0
	la	r0,_hex_digit_val
	jal	r1,(r0)
	add	sp,3
	sw	r0,-12(fp)
	lw	r0,-3(fp)
	add	r0,r0
	add	r0,r0
	add	r0,r0
	add	r0,r0
	lw	r1,-12(fp)
	add	r0,r1
		sw	r0,-3(fp)
		add	r2,1
		la	r1,atoi_loop
		jmp	(r1)

atoi_bin_digit:
	lbu	r0,0(r2)
	push	r0
	la	r0,_is_bin_digit
		jal	r1,(r0)
		add	sp,3
		ceq	r0,z
		brf	atoi_bin_accum
		la	r1,atoi_done
		jmp	(r1)

atoi_bin_accum:
	lbu	r0,0(r2)
	la	r1,48
	sub	r0,r1
	sw	r0,-12(fp)
	lw	r0,-3(fp)
	add	r0,r0
	lw	r1,-12(fp)
	add	r0,r1
		sw	r0,-3(fp)
		add	r2,1
		la	r1,atoi_loop
		jmp	(r1)
atoi_done:
	lw	r0,-3(fp)
	lw	r1,-9(fp)
	ceq	r1,z
	brt	atoi_ret
	la	r1,0
	sub	r1,r0
	mov	r0,r1
atoi_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _extract_kw_arg: Skip keyword (alpha chars) and whitespace in _line_buf,
; then copy identifier to _parse_name_buf.
_extract_kw_arg:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3
	la	r2,196608
eka_skip:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	eka_done
	push	r0
	la	r0,_is_alpha
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	eka_ws
	add	r2,1
	bra	eka_skip
eka_ws:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	eka_done
	la	r1,32
	ceq	r0,r1
	brt	eka_ws2
	la	r1,9
	ceq	r0,r1
	brt	eka_ws2
	bra	eka_copy
eka_ws2:
	add	r2,1
	bra	eka_ws
eka_copy:
	la	r0,197128
	sw	r0,-3(fp)
eka_cn:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	eka_cn_done
	la	r1,44
	ceq	r0,r1
	brt	eka_cn_done
	la	r1,32
	ceq	r0,r1
	brt	eka_cn_done
	lw	r1,-3(fp)
	sb	r0,0(r1)
	add	r1,1
	sw	r1,-3(fp)
	add	r2,1
	bra	eka_cn
eka_cn_done:
	lw	r1,-3(fp)
	la	r0,0
	sb	r0,0(r1)
eka_done:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _parse_cond_value: Find comma in _line_buf, parse integer after it.
; Returns: r0 = integer value
_parse_cond_value:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	la	r2,196608
pcv_find:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	pcv_zero
	la	r1,44
	ceq	r0,r1
	brt	pcv_after
	add	r2,1
	bra	pcv_find
pcv_zero:
	la	r0,0
	bra	pcv_ret
pcv_after:
	add	r2,1
pcv_ws:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	pcv_zero
	la	r1,32
	ceq	r0,r1
	brt	pcv_ws2
	la	r1,9
	ceq	r0,r1
	brt	pcv_ws2
	bra	pcv_call
pcv_ws2:
	add	r2,1
	bra	pcv_ws
pcv_call:
	push	r2
	la	r0,_eval_expr_ptr
	jal	r1,(r0)
	add	sp,3
pcv_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _sym_find: Search symbol table for _parse_name_buf.
; Returns: r0 = index if found, symbol_count if not found
_sym_find:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3
	la	r0,0
	sw	r0,-3(fp)
sf_loop:
	la	r1,787560
	lw	r1,0(r1)
	lw	r0,-3(fp)
	clu	r0,r1
	brf	sf_not_found
	lw	r0,-3(fp)
	push	r0
	la	r0,_mul40
	jal	r1,(r0)
	add	sp,3
	la	r1,65536
	add	r1,r0
	push	r1
	la	r1,197128
	push	r1
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	sf_found
	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
	bra	sf_loop
sf_not_found:
	la	r1,787560
	lw	r0,0(r1)
	bra	sf_ret
sf_found:
	lw	r0,-3(fp)
sf_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _handle_equ: Parse "name EQU expr" from _line_buf, store/update in table.
_handle_equ:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-24

	la	r2,196608
	push	r2
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0

	push	r2
	la	r0,_copy_ident_token
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0

	la	r0,_kw_equ
	push	r0
	la	r0,197128
	push	r0
	la	r0,_emit_list_line1
	jal	r1,(r0)
	add	sp,6

	sw	r2,-6(fp)
	la	r1,197128
	la	r2,209668
_heq_save_name:
	lbu	r0,0(r1)
	sb	r0,0(r2)
	ceq	r0,z
	brt	_heq_saved
	add	r1,1
	add	r2,1
	bra	_heq_save_name

_heq_saved:
	lw	r2,-6(fp)
	push	r2
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0

	add	r2,3
	push	r2
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	push	r0
	la	r0,_eval_expr_ptr
	jal	r1,(r0)
	add	sp,3
	sw	r0,-3(fp)

	la	r1,209668
	la	r2,197128
_heq_restore_name:
	lbu	r0,0(r1)
	sb	r0,0(r2)
	ceq	r0,z
	brt	_heq_name_restored
	add	r1,1
	add	r2,1
	bra	_heq_restore_name

_heq_name_restored:
	la	r0,_xref_mark_symbol_current
	jal	r1,(r0)

	lw	r0,-3(fp)
	push	r0
	la	r0,_xref_update_switch_current
	jal	r1,(r0)
	add	sp,3

	lw	r0,-3(fp)
	push	r0
	la	r0,_store_parse_name_value
	jal	r1,(r0)
	add	sp,3

	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _set_symbol: Parse 'SET name,value' from _line_buf, store/update in table.
_set_symbol:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-24
	la	r2,196608
	add	r2,3
	push	r2
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0

	push	r2
	la	r0,_copy_ident_token
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0

	sw	r2,-6(fp)
	la	r1,197128
	la	r2,209928
_ss_save_name:
	lbu	r0,0(r1)
	sb	r0,0(r2)
	ceq	r0,z
	brt	_ss_saved
	add	r1,1
	add	r2,1
	bra	_ss_save_name

_ss_saved:
	lw	r2,-6(fp)
_ss_find_comma:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_ss_no_val
	lc	r1,44
	ceq	r0,r1
	brt	_ss_after_comma
	add	r2,1
	bra	_ss_find_comma

_ss_after_comma:
	add	r2,1
	push	r2
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	push	r0
	la	r0,_eval_expr_ptr
	jal	r1,(r0)
	add	sp,3
	sw	r0,-3(fp)
	bra	_ss_store

_ss_no_val:
	la	r0,0
	sw	r0,-3(fp)

_ss_store:
	la	r1,209928
	la	r2,197128
_ss_restore_name:
	lbu	r0,0(r1)
	sb	r0,0(r2)
	ceq	r0,z
	brt	_ss_name_restored
	add	r1,1
	add	r2,1
	bra	_ss_restore_name

_ss_name_restored:
	la	r0,_xref_mark_symbol_current
	jal	r1,(r0)

	lw	r0,-3(fp)
	push	r0
	la	r0,_xref_update_switch_current
	jal	r1,(r0)
	add	sp,3

	lw	r0,-3(fp)
	push	r0
	la	r0,_hldiag_update_switch_current
	jal	r1,(r0)
	add	sp,3

	lw	r0,-3(fp)
	push	r0
	la	r0,_store_parse_name_value
	jal	r1,(r0)
	add	sp,3
ss_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _xref_mark_symbol_current: Add current _parse_name_buf to xref symbol table if absent.
_xref_mark_symbol_current:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3
	la	r0,0
	sw	r0,-3(fp)

_xmsc_loop:
	la	r1,_xref_symbol_count
	lw	r1,0(r1)
	lw	r0,-3(fp)
	clu	r0,r1
	brf	_xmsc_add

	lw	r0,-3(fp)
	push	r0
	la	r0,_mul32
	jal	r1,(r0)
	add	sp,3
	la	r1,212992
	add	r1,r0
	push	r1
	la	r1,197128
	push	r1
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	_xmsc_ret

	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
	bra	_xmsc_loop

_xmsc_add:
	la	r1,_xref_symbol_count
	lw	r0,0(r1)
	la	r2,512
	clu	r0,r2
	brf	_xmsc_ret

	push	r0
	la	r0,_mul32
	jal	r1,(r0)
	add	sp,3
	la	r1,212992
	add	r1,r0
	la	r2,197128
	lc	r0,32
	sw	r0,-3(fp)

_xmsc_copy:
	lbu	r0,0(r2)
	sb	r0,0(r1)
	add	r1,1
	add	r2,1
	lw	r0,-3(fp)
	add	r0,-1
	sw	r0,-3(fp)
	ceq	r0,z
	brt	_xmsc_inc
	bra	_xmsc_copy

_xmsc_inc:
	la	r1,_xref_symbol_count
	lw	r0,0(r1)
	add	r0,1
	sw	r0,0(r1)

_xmsc_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _xref_update_switch_current: Update HLXREF switch when current symbol name matches.
; Arg on stack: value
_xref_update_switch_current:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_xref_symbol_name
	push	r0
	la	r0,197128
	push	r0
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brt	_xusc_ret

	la	r1,_xref_switch
	lw	r0,6(fp)
	sw	r0,0(r1)

_xusc_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _lookup_symbol: Check if _parse_name_buf is in symbol table.
; Returns: r0 = 1 if found, 0 if not. Sets _lookup_sym_val.
_lookup_symbol:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3
	la	r0,_sym_find
	jal	r1,(r0)
	sw	r0,-3(fp)
	la	r1,787560
	lw	r1,0(r1)
	lw	r0,-3(fp)
	clu	r0,r1
	brf	ls_no
	lw	r0,-3(fp)
	push	r0
	la	r0,_mul40
	jal	r1,(r0)
	add	sp,3
	la	r1,65536
	add	r1,r0
	lw	r0,32(r1)
	la	r1,786594
	sw	r0,0(r1)
	la	r0,1
	bra	ls_ret
ls_no:
	la	r0,0
ls_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _cond_push: Push state onto cond stack, increment depth.
; Arg on stack: state (0=include, 1=skip)
; Inside a skipped region the state is 2 (skipped by an enclosing
; conditional), which ELSEASM leaves alone.
_cond_push:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	la	r0,_cond_top
	jal	r1,(r0)
	ceq	r0,z
	brt	_cp_state
	lc	r0,2
	sw	r0,9(fp)
_cp_state:
	lw	r0,9(fp)
	la	r1,787707
	lw	r2,0(r1)
	lc	r1,32
	clu	r2,r1
	brt	_cp_room
	la	r0,_err_cond_deep
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_cp_room:
	push	r2
	la	r0,_mul3
	jal	r1,(r0)
	add	sp,3
	la	r1,199712
	add	r1,r0
	lw	r0,9(fp)
	sw	r0,0(r1)
	la	r1,787707
	lw	r0,0(r1)
	add	r0,1
	sw	r0,0(r1)
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _cond_top: Get top cond stack state.
; Returns: r0 = state (0 or 1), or 0 if depth==0
_cond_top:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	la	r1,787707
	lw	r0,0(r1)
	ceq	r0,z
	brt	ct_zero
	add	r0,-1
	push	r0
	la	r0,_mul3
	jal	r1,(r0)
	add	sp,3
	la	r1,199712
	add	r1,r0
	lw	r0,0(r1)
	bra	ct_ret
ct_zero:
	la	r0,0
ct_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _cond_set_top: Set top cond stack state.
; Arg on stack: new state
_cond_set_top:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	la	r1,787707
	lw	r0,0(r1)
	add	r0,-1
	push	r0
	la	r0,_mul3
	jal	r1,(r0)
	add	sp,3
	la	r1,199712
	add	r1,r0
	lw	r0,9(fp)
	sw	r0,0(r1)
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _cond_pop: Pop cond stack (clear top, decrement depth).
_cond_pop:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	la	r1,787707
	lw	r0,0(r1)
	add	r0,-1
	push	r0
	la	r0,_mul3
	jal	r1,(r0)
	add	sp,3
	la	r1,199712
	add	r1,r0
	la	r0,0
	sw	r0,0(r1)
	la	r1,787707
	lw	r0,0(r1)
	add	r0,-1
	sw	r0,0(r1)
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _handle_ifdef: IFDEF -- include if symbol defined and nonzero, skip if not.
_handle_ifdef:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3
	la	r0,_extract_kw_arg
	jal	r1,(r0)
	la	r0,_lookup_symbol
	jal	r1,(r0)
	ceq	r0,z
	brt	hif_not_found
	la	r1,786594
	lw	r0,0(r1)
	ceq	r0,z
	brt	hif_zero_val
	la	r0,0
	bra	hif_do_push
hif_zero_val:
	la	r0,1
	bra	hif_do_push
hif_not_found:
	la	r0,1
hif_do_push:
	push	r0
	la	r0,_cond_push
	jal	r1,(r0)
	add	sp,3
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _handle_ifndef: IFNDEF -- include if symbol not defined.
_handle_ifndef:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3
	la	r0,_extract_kw_arg
	jal	r1,(r0)
	la	r0,_lookup_symbol
	jal	r1,(r0)
	sw	r0,-3(fp)
	lw	r0,-3(fp)
	ceq	r0,z
	brt	hinf_notdef
	la	r0,1
	bra	hinf_do_push
hinf_notdef:
	la	r0,0
hinf_do_push:
	push	r0
	la	r0,_cond_push
	jal	r1,(r0)
	add	sp,3
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _cond_lhs_value: Value of the first operand of IFEQ/IFNE in the line
; buffer: an expression (a symbol, or a number such as a substituted &SYSNARG).
; A name that is not a SET/EQU symbol is an ERROR unless the line is in a
; skipped region (to compare text, such as a register name, use IFSAME).
; Returns: r0 = value
_cond_lhs_value:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r0,196608
	push	r0
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0
_clv_kw:
	lbu	r0,0(r2)
	push	r0
	la	r0,_is_alpha
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_clv_kw_end
	add	r2,1
	bra	_clv_kw
_clv_kw_end:
	push	r2
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	push	r0
	la	r0,1
	push	r0
	la	r0,_eval_full
	jal	r1,(r0)
	add	sp,6
	mov	r2,r0

	la	r1,786651
	lw	r0,0(r1)
	ceq	r0,z
	brt	_clv_ret
	la	r0,_cond_top
	jal	r1,(r0)
	ceq	r0,z
	brf	_clv_ret
	la	r0,_err_cond_undef
	push	r0
	la	r0,_fatal
	jal	r1,(r0)

_clv_ret:
	mov	r0,r2
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _handle_ifsame: IFSAME a,b / IFDIFF a,b -- include if the operand texts
; are the same (IFSAME) or differ (IFDIFF), compared byte for byte after
; macro argument substitution. An operand ends at a comma, blank, tab or ';'
; outside quotes and parentheses, as a macro argument does; either may be
; empty.
; Arg on stack: 0 for IFSAME, 1 for IFDIFF (9 fp)
; Frame: -3 first operand pointer, -6 its end then length, -9 count
_handle_ifsame:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-9

	la	r0,196608
	push	r0
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0
_his_kw:
	lbu	r0,0(r2)
	push	r0
	la	r0,_is_alpha
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_his_kw_end
	add	r2,1
	bra	_his_kw
_his_kw_end:
	push	r2
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	sw	r0,-3(fp)
	push	r0
	la	r0,_arg_end
	jal	r1,(r0)
	add	sp,3
	sw	r0,-6(fp)

; the second operand follows the comma
	push	r0
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0
	lbu	r0,0(r2)
	lc	r1,44
	ceq	r0,r1
	brf	_his_second
	add	r2,1
_his_second:
	push	r2
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0
	push	r0
	la	r0,_arg_end
	jal	r1,(r0)
	add	sp,3
	sub	r0,r2
	sw	r0,-9(fp)

	lw	r0,-6(fp)
	lw	r1,-3(fp)
	sub	r0,r1
	lw	r1,-9(fp)
	ceq	r0,r1
	brf	_his_differ

_his_cmp:
	ceq	r0,z
	brt	_his_same
	sw	r0,-9(fp)
	lw	r1,-3(fp)
	lbu	r0,0(r1)
	add	r1,1
	sw	r1,-3(fp)
	lbu	r1,0(r2)
	add	r2,1
	ceq	r0,r1
	brf	_his_differ
	lw	r0,-9(fp)
	add	r0,-1
	bra	_his_cmp

_his_same:
	lc	r0,0
	bra	_his_result
_his_differ:
	lc	r0,1

; r0 = 1 if the texts differ: include when that matches the directive
_his_result:
	lw	r1,9(fp)
	ceq	r0,r1
	brt	_his_include
	lc	r0,1
	bra	_his_push
_his_include:
	lc	r0,0
_his_push:
	push	r0
	la	r0,_cond_push
	jal	r1,(r0)
	add	sp,3
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _handle_ifeq: IFEQ expr,value -- include if the two values are equal.
_handle_ifeq:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3
	la	r0,_cond_lhs_value
	jal	r1,(r0)
	sw	r0,-3(fp)
	la	r0,_parse_cond_value
	jal	r1,(r0)
	lw	r1,-3(fp)
	ceq	r0,r1
	brf	hieq_skip
	la	r0,0
	bra	hieq_push
hieq_skip:
	la	r0,1
hieq_push:
	push	r0
	la	r0,_cond_push
	jal	r1,(r0)
	add	sp,3
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _handle_ifne: IFNE expr,value -- opposite of IFEQ.
_handle_ifne:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3
	la	r0,_cond_lhs_value
	jal	r1,(r0)
	sw	r0,-3(fp)
	la	r0,_parse_cond_value
	jal	r1,(r0)
	lw	r1,-3(fp)
	ceq	r0,r1
	brt	hine_skip
	la	r0,0
	bra	hine_push
hine_skip:
	la	r0,1
hine_push:
	push	r0
	la	r0,_cond_push
	jal	r1,(r0)
	add	sp,3
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _handle_srcbuf: SRCBUF slot -- switch to configured source slot immediately.
_handle_srcbuf:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3
	la	r0,_extract_kw_arg
	jal	r1,(r0)
	la	r0,197128
	push	r0
	la	r0,_atoi
	jal	r1,(r0)
	add	sp,3
	sw	r0,-3(fp)
	lw	r0,-3(fp)
	push	r0
	la	r0,_select_src_slot
	jal	r1,(r0)
	add	sp,3
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _handle_include: INCLUDE name -- resolve include name to slot and return on EOF.
_handle_include:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r0,_extract_kw_arg
	jal	r1,(r0)
	la	r0,_kw_include
	push	r0
	la	r0,197128
	push	r0
	la	r0,_emit_list_line1
	jal	r1,(r0)
	add	sp,6
	la	r0,_lookup_include_slot
	jal	r1,(r0)
	ceq	r0,z
	brt	_hi_missing

	la	r1,787804
	lw	r0,0(r1)
	push	r0
	la	r0,_xref_mark_copy_slot
	jal	r1,(r0)
	add	sp,3

	la	r0,_push_src_return
	jal	r1,(r0)
	ceq	r0,z
	brt	_hi_ret

	la	r1,787804
	lw	r0,0(r1)
	push	r0
	la	r0,_select_src_slot
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brf	_hi_ret

	la	r0,_pop_src_return
	jal	r1,(r0)
	bra	_hi_ret

_hi_missing:
	la	r0,_missing_txt
	push	r0
	la	r0,197128
	push	r0
	la	r0,_emit_list_line1
	jal	r1,(r0)
	add	sp,6

_hi_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _handle_copy: COPY name -- HLASM-style alias for named source include.
_handle_copy:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r0,_extract_kw_arg
	jal	r1,(r0)
	la	r0,_kw_copy
	push	r0
	la	r0,197128
	push	r0
	la	r0,_emit_list_line1
	jal	r1,(r0)
	add	sp,6
	la	r0,_lookup_include_slot
	jal	r1,(r0)
	ceq	r0,z
	brt	_hc_missing

	la	r1,787804
	lw	r0,0(r1)
	push	r0
	la	r0,_xref_mark_copy_slot
	jal	r1,(r0)
	add	sp,3

	la	r0,_push_src_return
	jal	r1,(r0)
	ceq	r0,z
	brt	_hc_ret

	la	r1,787804
	lw	r0,0(r1)
	push	r0
	la	r0,_select_src_slot
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brf	_hc_ret

	la	r0,_pop_src_return
	jal	r1,(r0)
	bra	_hc_ret

_hc_missing:
	la	r0,_missing_txt
	push	r0
	la	r0,197128
	push	r0
	la	r0,_emit_list_line1
	jal	r1,(r0)
	add	sp,6

_hc_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _xref_mark_copy_slot: Mark used COPY/INCLUDE slot (1-based).
; Arg on stack: slot
_xref_mark_copy_slot:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	add	r0,-1
	la	r1,_xref_copy_used
	add	r1,r0
	la	r0,1
	sb	r0,0(r1)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _xref_mark_macro_expand: Increment expansion count for macro index (1-based).
; Arg on stack: macro index
_xref_mark_macro_expand:
	push	fp
	push	r1
	mov	fp,sp

	lw	r0,6(fp)
	add	r0,-1
	push	r0
	la	r0,_mul3
	jal	r1,(r0)
	add	sp,3
	la	r1,231424
	add	r1,r0
	lw	r0,0(r1)
	add	r0,1
	sw	r0,0(r1)

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_xref_report: Emit end-of-run xref section when HLXREF is enabled.
_emit_xref_report:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-6

	la	r0,_xref_enabled
	jal	r1,(r0)
	ceq	r0,z
	brf	_exr_go
	la	r1,_exr_ret
	jmp	(r1)

_exr_go:
	la	r0,_xref_begin_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	la	r0,_emit_crlf
	jal	r1,(r0)

	la	r2,520192
	lw	r0,0(r2)
	sw	r0,-3(fp)
	la	r0,0
	sw	r0,-6(fp)

; named members (config records) that a COPY or INCLUDE used
_exr_copy_loop:
	lw	r0,-6(fp)
	lw	r1,-3(fp)
	clu	r0,r1
	brf	_exr_macro_defs

	lw	r0,-6(fp)
	la	r1,_xref_copy_used
	add	r1,r0
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_exr_copy_next

	lw	r0,-6(fp)
	push	r0
	la	r0,_cfg_member
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0
	add	r2,6

	la	r0,_xref_copy_txt
	push	r0
	push	r2
	la	r0,_emit_xref_line1
	jal	r1,(r0)
	add	sp,6

_exr_copy_next:
	lw	r0,-6(fp)
	add	r0,1
	sw	r0,-6(fp)
	bra	_exr_copy_loop

_exr_macro_defs:
	la	r1,786645
	lw	r0,0(r1)
	sw	r0,-3(fp)
	la	r0,0
	sw	r0,-6(fp)

_exr_macro_loop:
	lw	r0,-6(fp)
	lw	r1,-3(fp)
	clu	r0,r1
	brf	_exr_expand_defs

	lw	r0,-6(fp)
	push	r0
	la	r0,_mul39
	jal	r1,(r0)
	add	sp,3
	la	r2,98304
	add	r2,r0
	la	r0,_xref_macro_txt
	push	r0
	push	r2
	la	r0,_emit_xref_line1
	jal	r1,(r0)
	add	sp,6

	lw	r0,-6(fp)
	add	r0,1
	sw	r0,-6(fp)
	bra	_exr_macro_loop

_exr_expand_defs:
	la	r1,786645
	lw	r0,0(r1)
	sw	r0,-3(fp)
	la	r0,0
	sw	r0,-6(fp)

_exr_expand_loop:
	lw	r0,-6(fp)
	lw	r1,-3(fp)
	clu	r0,r1
	brf	_exr_symbols

	lw	r0,-6(fp)
	push	r0
	la	r0,_mul3
	jal	r1,(r0)
	add	sp,3
	la	r1,231424
	add	r1,r0
	lw	r2,0(r1)
	ceq	r2,z
	brt	_exr_expand_next

	lw	r0,-6(fp)
	push	r0
	la	r0,_mul39
	jal	r1,(r0)
	add	sp,3
	la	r1,98304
	add	r1,r0
	la	r0,_xref_expand_txt
	push	r0
	push	r1
	push	r2
	la	r0,_emit_xref_line_count
	jal	r1,(r0)
	add	sp,9

_exr_expand_next:
	lw	r0,-6(fp)
	add	r0,1
	sw	r0,-6(fp)
	bra	_exr_expand_loop

_exr_symbols:
	la	r1,_xref_symbol_count
	lw	r0,0(r1)
	sw	r0,-3(fp)
	la	r0,0
	sw	r0,-6(fp)

_exr_symbol_loop:
	lw	r0,-6(fp)
	lw	r1,-3(fp)
	clu	r0,r1
	brf	_exr_end

	lw	r0,-6(fp)
	push	r0
	la	r0,_mul32
	jal	r1,(r0)
	add	sp,3
	la	r2,212992
	add	r2,r0
	la	r0,_xref_symbol_txt
	push	r0
	push	r2
	la	r0,_emit_xref_line1
	jal	r1,(r0)
	add	sp,6

	lw	r0,-6(fp)
	add	r0,1
	sw	r0,-6(fp)
	bra	_exr_symbol_loop

_exr_end:
	la	r0,_xref_end_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	la	r0,_emit_crlf
	jal	r1,(r0)

_exr_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _handle_incbuf: INCBUF slot -- push current source state, switch, return on EOF.
_handle_incbuf:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3
	la	r0,_extract_kw_arg
	jal	r1,(r0)
	la	r0,197128
	push	r0
	la	r0,_atoi
	jal	r1,(r0)
	add	sp,3
	sw	r0,-3(fp)
	la	r0,_push_src_return
	jal	r1,(r0)
	ceq	r0,z
	brt	_hib_ret
	lw	r0,-3(fp)
	push	r0
	la	r0,_select_src_slot
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brf	_hib_ret
	la	r0,_pop_src_return
	jal	r1,(r0)
_hib_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _copy_strz: Copy null-terminated string.
; Args on stack: src_ptr (12 fp), dst_ptr (9 fp)
_copy_strz:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	lw	r1,12(fp)
	lw	r2,9(fp)

_csz_loop:
	lbu	r0,0(r1)
	sb	r0,0(r2)
	ceq	r0,z
	brt	_csz_ret
	add	r1,1
	add	r2,1
	bra	_csz_loop

_csz_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _parse_struct_kw_arg: Parse one token after the leading keyword into dst.
; Arg on stack: dst_ptr
_parse_struct_kw_arg:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	lw	r1,9(fp)
	la	r0,0
	sb	r0,0(r1)
	la	r2,196608

_pska_skip:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_pska_ret
	lc	r1,32
	ceq	r0,r1
	brt	_pska_skip_ws
	lc	r1,9
	ceq	r0,r1
	brt	_pska_skip_ws
	bra	_pska_kw

_pska_skip_ws:
	add	r2,1
	bra	_pska_skip

_pska_kw:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_pska_ret
	push	r0
	la	r0,_is_alpha
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_pska_after_kw
	add	r2,1
	bra	_pska_kw

_pska_after_kw:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_pska_ret
	lc	r1,32
	ceq	r0,r1
	brt	_pska_after_kw_skip
	lc	r1,9
	ceq	r0,r1
	brt	_pska_after_kw_skip
	bra	_pska_copy

_pska_after_kw_skip:
	add	r2,1
	bra	_pska_after_kw

_pska_copy:
	lw	r1,9(fp)

_pska_copy_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_pska_done
	lc	r1,32
	ceq	r0,r1
	brt	_pska_done
	lc	r1,9
	ceq	r0,r1
	brt	_pska_done
	lc	r1,44
	ceq	r0,r1
	brt	_pska_done
	lw	r1,9(fp)
	sb	r0,0(r1)
	add	r1,1
	sw	r1,9(fp)
	add	r2,1
	bra	_pska_copy_loop

_pska_done:
	lw	r1,9(fp)
	la	r0,0
	sb	r0,0(r1)

_pska_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _struct_select_top_ptr: Return ptr to top structured-SELECT frame, or 0 if empty.
; Frame layout: next label +0, end label +3, arm open +6, otherwise seen +9.
_struct_select_top_ptr:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r1,787984
	lw	r0,0(r1)
	ceq	r0,z
	brt	_sstp_empty

	add	r0,-1
	push	r0
	la	r0,_mul12
	jal	r1,(r0)
	add	sp,3

	la	r1,200288
	add	r0,r1
	bra	_sstp_ret

_sstp_empty:
	la	r0,0

_sstp_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _struct_select_top_sel_ptr: Return ptr to top structured-SELECT selector buffer, or 0 if empty.
_struct_select_top_sel_ptr:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r1,787984
	lw	r0,0(r1)
	ceq	r0,z
	brt	_sstsp_empty

	add	r0,-1
	push	r0
	la	r0,_mul256
	jal	r1,(r0)
	add	sp,3

	la	r1,201216
	add	r0,r1
	bra	_sstsp_ret

_sstsp_empty:
	la	r0,0

_sstsp_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _struct_do_top_ptr: Return ptr to top structured-DO frame, or 0 if empty.
; Frame layout: top label +0, end label +3.
_struct_do_top_ptr:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r1,787933
	lw	r0,0(r1)
	ceq	r0,z
	brt	_sdtp_empty

	add	r0,-1
	push	r0
	la	r0,_mul6
	jal	r1,(r0)
	add	sp,3

	la	r1,200096
	add	r0,r1
	bra	_sdtp_ret

_sdtp_empty:
	la	r0,0

_sdtp_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _parse_struct_if: Parse IF condition fields into scratch buffers.
_parse_struct_if:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r1,197648
	la	r0,0
	sb	r0,0(r1)
	la	r1,197908
	sb	r0,0(r1)
	la	r1,198168
	sb	r0,0(r1)

	la	r2,196608

_psi_skip:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_psi_early_ret
	lc	r1,32
	ceq	r0,r1
	brt	_psi_skip_ws
	lc	r1,9
	ceq	r0,r1
	brt	_psi_skip_ws
	bra	_psi_kw

_psi_skip_ws:
	add	r2,1
	bra	_psi_skip

_psi_early_ret:
	la	r1,_psi_ret
	jmp	(r1)

_psi_kw:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_psi_early_ret
	push	r0
	la	r0,_is_alpha
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_psi_after_kw
	add	r2,1
	bra	_psi_kw

_psi_after_kw:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_psi_after_kw_ret
	lc	r1,32
	ceq	r0,r1
	brt	_psi_after_kw_skip
	lc	r1,9
	ceq	r0,r1
	brt	_psi_after_kw_skip
	bra	_psi_cc

_psi_after_kw_skip:
	add	r2,1
	bra	_psi_after_kw

_psi_after_kw_ret:
	la	r1,_psi_ret
	jmp	(r1)

_psi_cc:
	la	r1,197648

_psi_cc_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_psi_cc_done
	push	r1
	lc	r1,44
	ceq	r0,r1
	brt	_psi_cc_done_pop
	lc	r1,32
	ceq	r0,r1
	brt	_psi_cc_done_pop
	lc	r1,9
	ceq	r0,r1
	brt	_psi_cc_done_pop
	pop	r1
	sb	r0,0(r1)
	add	r1,1
	add	r2,1
	bra	_psi_cc_loop

_psi_cc_done_pop:
	pop	r1

_psi_cc_done:
	la	r0,0
	sb	r0,0(r1)

_psi_sep1:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_psi_sep1_ret
	lc	r1,44
	ceq	r0,r1
	brt	_psi_sep1_skip
	lc	r1,32
	ceq	r0,r1
	brt	_psi_sep1_skip
	lc	r1,9
	ceq	r0,r1
	brt	_psi_sep1_skip
	bra	_psi_check_flag

_psi_sep1_skip:
	add	r2,1
	bra	_psi_sep1

_psi_sep1_ret:
	la	r1,_psi_ret
	jmp	(r1)

_psi_check_flag:
	la	r0,_cc_zset_txt
	push	r0
	la	r0,197648
	push	r0
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	_psi_ret

	la	r0,_cc_zclr_txt
	push	r0
	la	r0,197648
	push	r0
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	_psi_ret

	la	r1,197908

_psi_lhs_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_psi_lhs_done
	push	r1
	lc	r1,44
	ceq	r0,r1
	brt	_psi_lhs_done_pop
	lc	r1,32
	ceq	r0,r1
	brt	_psi_lhs_done_pop
	lc	r1,9
	ceq	r0,r1
	brt	_psi_lhs_done_pop
	pop	r1
	sb	r0,0(r1)
	add	r1,1
	add	r2,1
	bra	_psi_lhs_loop

_psi_lhs_done_pop:
	pop	r1

_psi_lhs_done:
	la	r0,0
	sb	r0,0(r1)

_psi_sep2:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_psi_ret
	lc	r1,44
	ceq	r0,r1
	brt	_psi_sep2_skip
	lc	r1,32
	ceq	r0,r1
	brt	_psi_sep2_skip
	lc	r1,9
	ceq	r0,r1
	brt	_psi_sep2_skip
	bra	_psi_rhs

_psi_sep2_skip:
	add	r2,1
	bra	_psi_sep2

_psi_rhs:
	la	r1,198168

_psi_rhs_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_psi_rhs_done
	push	r1
	lc	r1,44
	ceq	r0,r1
	brt	_psi_rhs_done_pop
	lc	r1,32
	ceq	r0,r1
	brt	_psi_rhs_done_pop
	lc	r1,9
	ceq	r0,r1
	brt	_psi_rhs_done_pop
	pop	r1
	sb	r0,0(r1)
	add	r1,1
	add	r2,1
	bra	_psi_rhs_loop

_psi_rhs_done_pop:
	pop	r1

_psi_rhs_done:
	la	r0,0
	sb	r0,0(r1)

_psi_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _strlen24: Return length of null-terminated string.
; Arg on stack: ptr
; Returns: r0 = length
_strlen24:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	lw	r2,9(fp)
	la	r0,0

_sl24_loop:
	lbu	r1,0(r2)
	ceq	r1,z
	brt	_sl24_ret
	add	r0,1
	add	r2,1
	bra	_sl24_loop

_sl24_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _is_number_str: Return 1 if string is decimal, 0x hex, 0b binary, or h-suffix hex.
; Arg on stack: ptr
_is_number_str:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	lw	r2,9(fp)
	lbu	r0,0(r2)
	ceq	r0,z
	brf	_ins_not_empty
	la	r1,_ins_no
	jmp	(r1)

_ins_not_empty:

	la	r1,45
	ceq	r0,r1
	brt	_ins_skip_minus
	bra	_ins_prefix

	_ins_skip_minus:
	add	r2,1
	lbu	r0,0(r2)
	ceq	r0,z
	brf	_ins_after_minus
	la	r1,_ins_no
	jmp	(r1)

_ins_after_minus:

_ins_prefix:
	lbu	r0,0(r2)
	la	r1,48
	ceq	r0,r1
	brt	_ins_pref0
	bra	_ins_suffix

_ins_pref0:
	lbu	r0,1(r2)
	la	r1,120
	ceq	r0,r1
	brt	_ins_hex_pref
	la	r1,88
	ceq	r0,r1
	brt	_ins_hex_pref
	la	r1,98
	ceq	r0,r1
	brt	_ins_bin_pref
	la	r1,66
	ceq	r0,r1
	brt	_ins_bin_pref
	bra	_ins_suffix

	_ins_hex_pref:
	add	r2,2
	lbu	r0,0(r2)
	ceq	r0,z
	brf	_ins_hex_pref_loop
	la	r1,_ins_no
	jmp	(r1)

	_ins_hex_pref_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brf	_ins_hex_pref_chk
	la	r1,_ins_yes
	jmp	(r1)

_ins_hex_pref_chk:
	push	r0
	la	r0,_is_hex_digit
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brf	_ins_hex_pref_next
	la	r1,_ins_no
	jmp	(r1)

_ins_hex_pref_next:
	add	r2,1
	bra	_ins_hex_pref_loop

	_ins_bin_pref:
	add	r2,2
	lbu	r0,0(r2)
	ceq	r0,z
	brf	_ins_bin_pref_loop
	la	r1,_ins_no
	jmp	(r1)

_ins_bin_pref_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_ins_yes
	push	r0
	la	r0,_is_bin_digit
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_ins_no
	add	r2,1
	bra	_ins_bin_pref_loop

_ins_suffix:
	push	r2
	la	r0,_strlen24
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_ins_no
	add	r0,-1
	add	r0,r2
	lbu	r0,0(r0)
	la	r1,104
	ceq	r0,r1
	brt	_ins_hex_suffix
	la	r1,72
	ceq	r0,r1
	brt	_ins_hex_suffix
	bra	_ins_loop

	_ins_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_ins_yes
	push	r0
	la	r0,_is_digit
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_ins_no
	add	r2,1
	bra	_ins_loop

_ins_hex_suffix:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_ins_no

_ins_hex_suffix_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_ins_no
	la	r1,104
	ceq	r0,r1
	brt	_ins_hex_suffix_last
	la	r1,72
	ceq	r0,r1
	brt	_ins_hex_suffix_last
	push	r0
	la	r0,_is_hex_digit
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_ins_no
	add	r2,1
	bra	_ins_hex_suffix_loop

_ins_hex_suffix_last:
	add	r2,1
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_ins_yes
	bra	_ins_no

_ins_yes:
	la	r0,1
	bra	_ins_ret

_ins_no:
	la	r0,0

_ins_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _select_if_temp: Choose a scratch register string for literal compares.
; Arg on stack: lhs_ptr
; Returns: r0 = ptr to "r1" or "r2"
_select_if_temp:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r0,_r2_txt
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brt	_sit_r2

	la	r0,_r1_txt
	bra	_sit_ret

_sit_r2:
	la	r0,_r2_txt

_sit_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _struct_if_top_ptr: Return ptr to top structured-IF frame, or 0 if empty.
; Frame layout: false label +0, end label +3, else seen +6.
_struct_if_top_ptr:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r1,787807
	lw	r0,0(r1)
	ceq	r0,z
	brt	_sitp_empty

	add	r0,-1
	push	r0
	la	r0,_mul9
	jal	r1,(r0)
	add	sp,3

	la	r1,199808
	add	r0,r1
	bra	_sitp_ret

_sitp_empty:
	la	r0,0

_sitp_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _cc_info: Look up the condition name at 197648 in _cc_info_table.
; Returns its code (bits 0-1: 1 ceq, 2 cls, 3 clu; 4: swap the operands;
; 8: the compare is true when the condition is false), or 0 if unknown.
_cc_info:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	la	r2,_cc_info_table

_cci_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_cci_ret
	push	r2
	la	r0,197648
	push	r0
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
_cci_skip:
	lbu	r1,0(r2)
	add	r2,1
	ceq	r1,z
	brf	_cci_skip
	ceq	r0,z
	brf	_cci_hit
	add	r2,1
	bra	_cci_loop

_cci_hit:
	lbu	r0,0(r2)

_cci_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _cc_setup: Return the _cc_info code of the current compare condition;
; ERROR if the name is unknown. A swapped compare cannot take z as its
; first operand, so a z right-hand side is rewritten as the constant 0.
_cc_setup:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	la	r0,_cc_info
	jal	r1,(r0)
	mov	r2,r0
	ceq	r0,z
	brf	_ccs_known
	la	r0,_err_bad_cc
	push	r0
	la	r0,_fatal
	jal	r1,(r0)

_ccs_known:
	lc	r1,4
	and	r0,r1
	ceq	r0,z
	brt	_ccs_ret
	la	r1,198168
	lbu	r0,0(r1)
	lc	r1,122
	ceq	r0,r1
	brf	_ccs_ret
	la	r1,198168
	lbu	r0,1(r1)
	ceq	r0,z
	brf	_ccs_ret
	lc	r0,48
	sb	r0,0(r1)

_ccs_ret:
	mov	r0,r2
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _emit_cc_compare: Emit the compare for a structured condition: ceq/cls/clu
; of the left operand (197908) and the right one (the temp register holding
; a constant, or 198168), in the other order when the code says swap.
; Args on stack: code (12 fp), temp register string or 0 (9 fp)
_emit_cc_compare:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	lw	r0,12(fp)
	lc	r1,3
	and	r0,r1
	lc	r1,1
	ceq	r0,r1
	brf	_ecc_not_ceq
	la	r0,_ceq_txt
	bra	_ecc_op
_ecc_not_ceq:
	lc	r1,2
	ceq	r0,r1
	brf	_ecc_clu
	la	r0,_cls_txt
	bra	_ecc_op
_ecc_clu:
	la	r0,_clu_txt

_ecc_op:
	push	r0
	lw	r2,9(fp)
	ceq	r2,z
	brf	_ecc_rhs
	la	r2,198168

_ecc_rhs:
	lw	r0,12(fp)
	lc	r1,4
	and	r0,r1
	ceq	r0,z
	brf	_ecc_swap
	la	r0,197908
	push	r0
	push	r2
	bra	_ecc_emit

_ecc_swap:
	push	r2
	la	r0,197908
	push	r0

_ecc_emit:
	la	r0,_emit_inst2
	jal	r1,(r0)
	add	sp,9

	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _emit_struct_if_test: Emit compare/test sequence that branches to false label.
; Arg on stack: false_label_id
_emit_struct_if_test:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

; rhs that is a symbol expression becomes its decimal value
	la	r0,198168
	push	r0
	la	r0,_subst_buf
	jal	r1,(r0)
	add	sp,3
; -3 temp register (0 = none), -6 skip label id, -9 condition code (_cc_info)
	add	sp,-9

	la	r0,_alloc_struct_label_id
	jal	r1,(r0)
	sw	r0,-6(fp)

	la	r0,_cc_zset_txt
	push	r0
	la	r0,197648
	push	r0
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brt	_esit_zclr

	la	r0,_brt_txt
	push	r0
	lw	r0,-6(fp)
	push	r0
	la	r0,_if_skip_suffix
	push	r0
	la	r0,_emit_branch_label
	jal	r1,(r0)
	add	sp,9
	la	r0,_jmp_txt
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_if_false_suffix
	push	r0
	la	r0,_emit_branch_label
	jal	r1,(r0)
	add	sp,9
	lw	r0,-6(fp)
	push	r0
	la	r0,_if_skip_suffix
	push	r0
	la	r0,_emit_label_def
	jal	r1,(r0)
	add	sp,6
	la	r1,_esit_ret
	jmp	(r1)

_esit_zclr:
	la	r0,_cc_zclr_txt
	push	r0
	la	r0,197648
	push	r0
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brt	_esit_cmp_setup

	la	r0,_brf_txt
	push	r0
	lw	r0,-6(fp)
	push	r0
	la	r0,_if_skip_suffix
	push	r0
	la	r0,_emit_branch_label
	jal	r1,(r0)
	add	sp,9
	la	r0,_jmp_txt
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_if_false_suffix
	push	r0
	la	r0,_emit_branch_label
	jal	r1,(r0)
	add	sp,9
	lw	r0,-6(fp)
	push	r0
	la	r0,_if_skip_suffix
	push	r0
	la	r0,_emit_label_def
	jal	r1,(r0)
	add	sp,6
	la	r1,_esit_ret
	jmp	(r1)

_esit_cmp_setup:
	la	r0,_cc_setup
	jal	r1,(r0)
	sw	r0,-9(fp)
	la	r0,198168
	push	r0
	la	r0,_is_number_str
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_esit_cmp_direct

	la	r0,197908
	push	r0
	la	r0,_select_if_temp
	jal	r1,(r0)
	add	sp,3
	sw	r0,-3(fp)

	la	r0,_push_txt
	push	r0
	lw	r0,-3(fp)
	push	r0
	la	r0,_emit_inst1
	jal	r1,(r0)
	add	sp,6

	la	r0,_lc_txt
	push	r0
	lw	r0,-3(fp)
	push	r0
	la	r0,198168
	push	r0
	la	r0,_emit_inst2
	jal	r1,(r0)
	add	sp,9
	bra	_esit_cmp_emit

_esit_cmp_direct:
	la	r0,0
	sw	r0,-3(fp)

_esit_cmp_emit:
	lw	r0,-9(fp)
	push	r0
	lw	r0,-3(fp)
	push	r0
	la	r0,_emit_cc_compare
	jal	r1,(r0)
	add	sp,6

	lw	r0,-3(fp)
	ceq	r0,z
	brt	_esit_branch

	la	r0,_pop_txt
	push	r0
	lw	r0,-3(fp)
	push	r0
	la	r0,_emit_inst1
	jal	r1,(r0)
	add	sp,6

_esit_branch:
; skip the jump to the false label when the condition holds
	lw	r0,-9(fp)
	lc	r1,8
	and	r0,r1
	ceq	r0,z
	brt	_esit_branch_false

	la	r0,_brf_txt
	bra	_esit_branch_emit

_esit_branch_false:
	la	r0,_brt_txt

	_esit_branch_emit:
	push	r0
	lw	r0,-6(fp)
	push	r0
	la	r0,_if_skip_suffix
	push	r0
	la	r0,_emit_branch_label
	jal	r1,(r0)
	add	sp,9
	la	r0,_jmp_txt
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_if_false_suffix
	push	r0
	la	r0,_emit_branch_label
	jal	r1,(r0)
	add	sp,9
	lw	r0,-6(fp)
	push	r0
	la	r0,_if_skip_suffix
	push	r0
	la	r0,_emit_label_def
	jal	r1,(r0)
	add	sp,6

_esit_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _handle_struct_if: Lower structured IF and push one frame on the IF stack.
_handle_struct_if:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3

	la	r1,787807
	lw	r0,0(r1)
	lc	r2,32
	clu	r0,r2
	brt	_hsi_start
	la	r0,_err_if_deep
	push	r0
	la	r0,_fatal
	jal	r1,(r0)

_hsi_start:
	push	r0
	la	r0,_mul9
	jal	r1,(r0)
	add	sp,3
	la	r1,199808
	add	r0,r1
	sw	r0,-3(fp)

	la	r1,787810
	lw	r0,0(r1)
	lw	r2,-3(fp)
	sw	r0,0(r2)
	add	r0,1
	sw	r0,3(r2)
	la	r2,0
	lw	r1,-3(fp)
	sw	r2,6(r1)
	add	r0,1
	la	r1,787810
	sw	r0,0(r1)

	la	r1,787807
	lw	r0,0(r1)
	add	r0,1
	sw	r0,0(r1)

	la	r0,_parse_struct_if
	jal	r1,(r0)

	la	r0,_kw_if
	push	r0
	la	r0,_emit_ann_if_line
	jal	r1,(r0)
	add	sp,3

	lw	r0,-3(fp)
	lw	r0,0(r0)
	push	r0
	la	r0,_emit_struct_if_test
	jal	r1,(r0)
	add	sp,3

	la	r0,_then_txt
	push	r0
	la	r0,_emit_ann_line0
	jal	r1,(r0)
	add	sp,3

_hsi_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

_handle_struct_else:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r0,_struct_if_top_ptr
	jal	r1,(r0)
	ceq	r0,z
	brt	_hse_ret

	mov	r2,r0
	lw	r0,6(r2)
	ceq	r0,z
	brt	_hse_emit
	bra	_hse_ret

_hse_emit:
	la	r0,_jmp_txt
	push	r0
	lw	r0,3(r2)
	push	r0
	la	r0,_if_end_suffix
	push	r0
	la	r0,_emit_branch_label
	jal	r1,(r0)
	add	sp,9

	lw	r0,0(r2)
	push	r0
	la	r0,_if_false_suffix
	push	r0
	la	r0,_emit_label_def
	jal	r1,(r0)
	add	sp,6

	la	r0,_kw_else
	push	r0
	la	r0,_emit_ann_line0
	jal	r1,(r0)
	add	sp,3

	la	r0,1
	sw	r0,6(r2)

_hse_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

_handle_struct_elseif:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3

	la	r0,_struct_if_top_ptr
	jal	r1,(r0)
	ceq	r0,z
	brt	_hsel_ret

	mov	r2,r0
	lw	r0,6(r2)
	ceq	r0,z
	brt	_hsel_emit
	bra	_hsel_ret

_hsel_emit:
	la	r0,_jmp_txt
	push	r0
	lw	r0,3(r2)
	push	r0
	la	r0,_if_end_suffix
	push	r0
	la	r0,_emit_branch_label
	jal	r1,(r0)
	add	sp,9

	lw	r0,0(r2)
	push	r0
	la	r0,_if_false_suffix
	push	r0
	la	r0,_emit_label_def
	jal	r1,(r0)
	add	sp,6

	la	r1,787810
	lw	r0,0(r1)
	sw	r0,0(r2)
	add	r0,1
	sw	r0,0(r1)

	la	r0,_parse_struct_if
	jal	r1,(r0)

	la	r0,_kw_elseif
	push	r0
	la	r0,_emit_ann_if_line
	jal	r1,(r0)
	add	sp,3

	lw	r0,0(r2)
	push	r0
	la	r0,_emit_struct_if_test
	jal	r1,(r0)
	add	sp,3

	la	r0,_then_txt
	push	r0
	la	r0,_emit_ann_line0
	jal	r1,(r0)
	add	sp,3

_hsel_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

_handle_struct_endif:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r0,_struct_if_top_ptr
	jal	r1,(r0)
	ceq	r0,z
	brt	_hsend_ret

	mov	r2,r0
	lw	r0,6(r2)
	ceq	r0,z
	brt	_hsend_false

	lw	r0,3(r2)
	push	r0
	la	r0,_if_end_suffix
	push	r0
	la	r0,_emit_label_def
	jal	r1,(r0)
	add	sp,6
	bra	_hsend_clear

_hsend_false:
	lw	r0,0(r2)
	push	r0
	la	r0,_if_false_suffix
	push	r0
	la	r0,_emit_label_def
	jal	r1,(r0)
	add	sp,6
	lw	r0,3(r2)
	push	r0
	la	r0,_if_end_suffix
	push	r0
	la	r0,_emit_label_def
	jal	r1,(r0)
	add	sp,6

_hsend_clear:
	la	r1,787807
	lw	r0,0(r1)
	add	r0,-1
	sw	r0,0(r1)

	la	r0,_kw_endif
	push	r0
	la	r0,_emit_ann_line0
	jal	r1,(r0)
	add	sp,3

_hsend_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

_handle_struct_do:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3

	la	r1,787933
	lw	r0,0(r1)
	lc	r2,32
	clu	r0,r2
	brt	_hsd_start
	la	r0,_err_do_deep
	push	r0
	la	r0,_fatal
	jal	r1,(r0)

_hsd_start:
	push	r0
	la	r0,_mul6
	jal	r1,(r0)
	add	sp,3
	la	r1,200096
	add	r0,r1
	sw	r0,-3(fp)

	la	r1,787810
	lw	r0,0(r1)
	lw	r2,-3(fp)
	sw	r0,0(r2)
	add	r0,1
	sw	r0,3(r2)
	add	r0,1
	sw	r0,0(r1)

	la	r1,787933
	lw	r0,0(r1)
	add	r0,1
	sw	r0,0(r1)

	lw	r0,-3(fp)
	lw	r0,0(r0)
	push	r0
	la	r0,_do_top_suffix
	push	r0
	la	r0,_emit_do_label_def
	jal	r1,(r0)
	add	sp,6

	la	r0,_kw_do
	push	r0
	la	r0,_emit_ann_line0
	jal	r1,(r0)
	add	sp,3

_hsd_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

_handle_struct_doexit:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r0,_struct_do_top_ptr
	jal	r1,(r0)
	ceq	r0,z
	brt	_hsdx_ret

	mov	r2,r0
	la	r0,_parse_struct_if
	jal	r1,(r0)

	la	r0,_kw_doexit
	push	r0
	la	r0,_emit_ann_if_line
	jal	r1,(r0)
	add	sp,3

	lw	r0,3(r2)
	push	r0
	la	r0,_do_end_suffix
	push	r0
	la	r0,_emit_struct_branch_if_true
	jal	r1,(r0)
	add	sp,6

_hsdx_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

_handle_struct_iterate:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r0,_struct_do_top_ptr
	jal	r1,(r0)
	ceq	r0,z
	brt	_hsdi_ret

	mov	r2,r0
	la	r0,_jmp_txt
	push	r0
	lw	r0,0(r2)
	push	r0
	la	r0,_do_top_suffix
	push	r0
	la	r0,_emit_do_branch_label
	jal	r1,(r0)
	add	sp,9

	la	r0,_kw_iterate
	push	r0
	la	r0,_emit_ann_line0
	jal	r1,(r0)
	add	sp,3

_hsdi_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

_handle_struct_enddo:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r0,_struct_do_top_ptr
	jal	r1,(r0)
	ceq	r0,z
	brt	_hsdd_ret

	mov	r2,r0
	la	r0,_jmp_txt
	push	r0
	lw	r0,0(r2)
	push	r0
	la	r0,_do_top_suffix
	push	r0
	la	r0,_emit_do_branch_label
	jal	r1,(r0)
	add	sp,9

	lw	r0,3(r2)
	push	r0
	la	r0,_do_end_suffix
	push	r0
	la	r0,_emit_do_label_def
	jal	r1,(r0)
	add	sp,6

	la	r1,787933
	lw	r0,0(r1)
	add	r0,-1
	sw	r0,0(r1)

	la	r0,_kw_enddo
	push	r0
	la	r0,_emit_ann_line0
	jal	r1,(r0)
	add	sp,3

_hsdd_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _emit_struct_branch_if_true: Emit test sequence that branches to a label when
; the condition is true (DOEXIT). The skip branch jumps over the jump when the
; condition is false.
; Args on stack: label_id (12 fp), suffix_ptr (9 fp)
_emit_struct_branch_if_true:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

; rhs that is a symbol expression becomes its decimal value
	la	r0,198168
	push	r0
	la	r0,_subst_buf
	jal	r1,(r0)
	add	sp,3
; -3 temp register (0 = none), -6 skip label id, -9 condition code (_cc_info)
	add	sp,-9

; no condition (DOEXIT alone, C's break): jump to the target unconditionally
	la	r1,197648
	lbu	r0,0(r1)
	ceq	r0,z
	brf	_esbf_has_cc
	la	r0,_jmp_txt
	push	r0
	lw	r0,12(fp)
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_emit_do_branch_label
	jal	r1,(r0)
	add	sp,9
	la	r1,_esbf_ret
	jmp	(r1)

_esbf_has_cc:
	la	r0,_alloc_struct_label_id
	jal	r1,(r0)
	sw	r0,-6(fp)

	la	r0,_cc_zset_txt
	push	r0
	la	r0,197648
	push	r0
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brt	_esbf_zclr

	la	r0,_brf_txt
	push	r0
	lw	r0,-6(fp)
	push	r0
	la	r0,_do_skip_suffix
	push	r0
	la	r0,_emit_do_branch_label
	jal	r1,(r0)
	add	sp,9
	la	r0,_jmp_txt
	push	r0
	lw	r0,12(fp)
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_emit_do_branch_label
	jal	r1,(r0)
	add	sp,9
	lw	r0,-6(fp)
	push	r0
	la	r0,_do_skip_suffix
	push	r0
	la	r0,_emit_do_label_def
	jal	r1,(r0)
	add	sp,6
	la	r1,_esbf_ret
	jmp	(r1)

_esbf_zclr:
	la	r0,_cc_zclr_txt
	push	r0
	la	r0,197648
	push	r0
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brt	_esbf_cmp_setup

	la	r0,_brt_txt
	push	r0
	lw	r0,-6(fp)
	push	r0
	la	r0,_do_skip_suffix
	push	r0
	la	r0,_emit_do_branch_label
	jal	r1,(r0)
	add	sp,9
	la	r0,_jmp_txt
	push	r0
	lw	r0,12(fp)
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_emit_do_branch_label
	jal	r1,(r0)
	add	sp,9
	lw	r0,-6(fp)
	push	r0
	la	r0,_do_skip_suffix
	push	r0
	la	r0,_emit_do_label_def
	jal	r1,(r0)
	add	sp,6
	la	r1,_esbf_ret
	jmp	(r1)

_esbf_cmp_setup:
	la	r0,_cc_setup
	jal	r1,(r0)
	sw	r0,-9(fp)
	la	r0,198168
	push	r0
	la	r0,_is_number_str
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_esbf_cmp_direct

	la	r0,197908
	push	r0
	la	r0,_select_if_temp
	jal	r1,(r0)
	add	sp,3
	sw	r0,-3(fp)

	la	r0,_push_txt
	push	r0
	lw	r0,-3(fp)
	push	r0
	la	r0,_emit_inst1
	jal	r1,(r0)
	add	sp,6

	la	r0,_lc_txt
	push	r0
	lw	r0,-3(fp)
	push	r0
	la	r0,198168
	push	r0
	la	r0,_emit_inst2
	jal	r1,(r0)
	add	sp,9
	bra	_esbf_cmp_emit

_esbf_cmp_direct:
	la	r0,0
	sw	r0,-3(fp)

_esbf_cmp_emit:
	lw	r0,-9(fp)
	push	r0
	lw	r0,-3(fp)
	push	r0
	la	r0,_emit_cc_compare
	jal	r1,(r0)
	add	sp,6

	lw	r0,-3(fp)
	ceq	r0,z
	brt	_esbf_branch

	la	r0,_pop_txt
	push	r0
	lw	r0,-3(fp)
	push	r0
	la	r0,_emit_inst1
	jal	r1,(r0)
	add	sp,6

_esbf_branch:
; skip the jump to the target when the condition does not hold
	lw	r0,-9(fp)
	lc	r1,8
	and	r0,r1
	ceq	r0,z
	brt	_esbf_branch_false

	la	r0,_brt_txt
	bra	_esbf_branch_emit

_esbf_branch_false:
	la	r0,_brf_txt

	_esbf_branch_emit:
	push	r0
	lw	r0,-6(fp)
	push	r0
	la	r0,_do_skip_suffix
	push	r0
	la	r0,_emit_do_branch_label
	jal	r1,(r0)
	add	sp,9
	la	r0,_jmp_txt
	push	r0
	lw	r0,12(fp)
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_emit_do_branch_label
	jal	r1,(r0)
	add	sp,9
	lw	r0,-6(fp)
	push	r0
	la	r0,_do_skip_suffix
	push	r0
	la	r0,_emit_do_label_def
	jal	r1,(r0)
	add	sp,6

_esbf_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _emit_struct_select_eq_test: Emit equality test that branches to next SELECT arm on mismatch.
; Arg on stack: next_label_id
_emit_struct_select_eq_test:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

; rhs that is a symbol expression becomes its decimal value
	la	r0,198168
	push	r0
	la	r0,_subst_buf
	jal	r1,(r0)
	add	sp,3
	add	sp,-6

	la	r0,_alloc_struct_label_id
	jal	r1,(r0)
	sw	r0,-6(fp)

	la	r0,198168
	push	r0
	la	r0,_is_number_str
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_esst_cmp_direct

	la	r0,197908
	push	r0
	la	r0,_select_if_temp
	jal	r1,(r0)
	add	sp,3
	sw	r0,-3(fp)

	la	r0,_push_txt
	push	r0
	lw	r0,-3(fp)
	push	r0
	la	r0,_emit_inst1
	jal	r1,(r0)
	add	sp,6

	la	r0,_lc_txt
	push	r0
	lw	r0,-3(fp)
	push	r0
	la	r0,198168
	push	r0
	la	r0,_emit_inst2
	jal	r1,(r0)
	add	sp,9
	bra	_esst_cmp_emit

_esst_cmp_direct:
	la	r0,0
	sw	r0,-3(fp)

_esst_cmp_emit:
	la	r0,_ceq_txt
	push	r0
	la	r0,197908
	push	r0
	lw	r0,-3(fp)
	ceq	r0,z
	brt	_esst_rhs_direct
	push	r0
	bra	_esst_cmp_call

_esst_rhs_direct:
	la	r0,198168
	push	r0

_esst_cmp_call:
	la	r0,_emit_inst2
	jal	r1,(r0)
	add	sp,9

	lw	r0,-3(fp)
	ceq	r0,z
	brt	_esst_branch

	la	r0,_pop_txt
	push	r0
	lw	r0,-3(fp)
	push	r0
	la	r0,_emit_inst1
	jal	r1,(r0)
	add	sp,6

_esst_branch:
	la	r0,_brt_txt
	push	r0
	lw	r0,-6(fp)
	push	r0
	la	r0,_sel_skip_suffix
	push	r0
	la	r0,_emit_select_branch_label
	jal	r1,(r0)
	add	sp,9
	la	r0,_jmp_txt
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_sel_next_suffix
	push	r0
	la	r0,_emit_select_branch_label
	jal	r1,(r0)
	add	sp,9
	lw	r0,-6(fp)
	push	r0
	la	r0,_sel_skip_suffix
	push	r0
	la	r0,_emit_select_label_def
	jal	r1,(r0)
	add	sp,6

	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

_handle_struct_select:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-6

	la	r1,787984
	lw	r0,0(r1)
	lc	r2,32
	clu	r0,r2
	brt	_hss_start
	la	r0,_err_sel_deep
	push	r0
	la	r0,_fatal
	jal	r1,(r0)

_hss_start:
	push	r0
	la	r0,_mul12
	jal	r1,(r0)
	add	sp,3
	la	r1,200288
	add	r0,r1
	sw	r0,-3(fp)

	la	r1,787984
	lw	r0,0(r1)
	push	r0
	la	r0,_mul256
	jal	r1,(r0)
	add	sp,3
	la	r1,201216
	add	r0,r1
	sw	r0,-6(fp)

	lw	r0,-6(fp)
	push	r0
	la	r0,_parse_struct_kw_arg
	jal	r1,(r0)
	add	sp,3

	la	r0,_kw_select
	push	r0
	lw	r0,-6(fp)
	push	r0
	la	r0,_emit_ann_line1
	jal	r1,(r0)
	add	sp,6

	la	r0,_alloc_struct_label_id
	jal	r1,(r0)
	lw	r2,-3(fp)
	la	r1,0
	sw	r1,0(r2)
	sw	r0,3(r2)
	sw	r1,6(r2)
	sw	r1,9(r2)

	la	r1,787984
	lw	r0,0(r1)
	add	r0,1
	sw	r0,0(r1)

_hss_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

_handle_struct_when:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-6

	la	r0,_struct_select_top_ptr
	jal	r1,(r0)
	ceq	r0,z
	brf	_hsw_have_frame
	la	r1,_hsw_ret
	jmp	(r1)

_hsw_have_frame:
	sw	r0,-3(fp)

	la	r0,_struct_select_top_sel_ptr
	jal	r1,(r0)
	ceq	r0,z
	brf	_hsw_have_sel
	la	r1,_hsw_ret
	jmp	(r1)

_hsw_have_sel:
	sw	r0,-6(fp)

	lw	r2,-3(fp)
	lw	r0,9(r2)
	ceq	r0,z
	brt	_hsw_maybe_close
	bra	_hsw_ret

_hsw_maybe_close:
	lw	r0,6(r2)
	ceq	r0,z
	brt	_hsw_parse

	la	r0,_jmp_txt
	push	r0
	lw	r0,3(r2)
	push	r0
	la	r0,_sel_end_suffix
	push	r0
	la	r0,_emit_select_branch_label
	jal	r1,(r0)
	add	sp,9

	lw	r0,0(r2)
	push	r0
	la	r0,_sel_next_suffix
	push	r0
	la	r0,_emit_select_label_def
	jal	r1,(r0)
	add	sp,6

_hsw_parse:
	la	r0,198428
	push	r0
	la	r0,_parse_struct_kw_arg
	jal	r1,(r0)
	add	sp,3

	lw	r0,-6(fp)
	push	r0
	la	r0,197908
	push	r0
	la	r0,_copy_strz
	jal	r1,(r0)
	add	sp,6

	la	r0,198428
	push	r0
	la	r0,198168
	push	r0
	la	r0,_copy_strz
	jal	r1,(r0)
	add	sp,6

	la	r0,_kw_when
	push	r0
	la	r0,198168
	push	r0
	la	r0,_emit_ann_line1
	jal	r1,(r0)
	add	sp,6

	la	r0,_alloc_struct_label_id
	jal	r1,(r0)
	lw	r2,-3(fp)
	sw	r0,0(r2)
	push	r0
	la	r0,_emit_struct_select_eq_test
	jal	r1,(r0)
	add	sp,3

	la	r0,1
	sw	r0,6(r2)

_hsw_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

_handle_struct_otherwise:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r0,_struct_select_top_ptr
	jal	r1,(r0)
	ceq	r0,z
	brt	_hso_ret

	mov	r2,r0
	lw	r0,9(r2)
	ceq	r0,z
	brt	_hso_maybe_close
	bra	_hso_ret

_hso_maybe_close:
	lw	r0,6(r2)
	ceq	r0,z
	brt	_hso_mark

	la	r0,_jmp_txt
	push	r0
	lw	r0,3(r2)
	push	r0
	la	r0,_sel_end_suffix
	push	r0
	la	r0,_emit_select_branch_label
	jal	r1,(r0)
	add	sp,9

	lw	r0,0(r2)
	push	r0
	la	r0,_sel_next_suffix
	push	r0
	la	r0,_emit_select_label_def
	jal	r1,(r0)
	add	sp,6

_hso_mark:
	la	r0,1
	sw	r0,6(r2)
	sw	r0,9(r2)

	la	r0,_kw_otherwise
	push	r0
	la	r0,_emit_ann_line0
	jal	r1,(r0)
	add	sp,3

_hso_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

_handle_struct_endsel:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r0,_struct_select_top_ptr
	jal	r1,(r0)
	ceq	r0,z
	brt	_hsse_ret

	mov	r2,r0
	lw	r0,6(r2)
	ceq	r0,z
	brt	_hsse_end

	lw	r0,9(r2)
	ceq	r0,z
	brf	_hsse_end

	lw	r0,0(r2)
	push	r0
	la	r0,_sel_next_suffix
	push	r0
	la	r0,_emit_select_label_def
	jal	r1,(r0)
	add	sp,6

_hsse_end:
	lw	r0,3(r2)
	push	r0
	la	r0,_sel_end_suffix
	push	r0
	la	r0,_emit_select_label_def
	jal	r1,(r0)
	add	sp,6

	la	r0,_kw_endsel
	push	r0
	la	r0,_emit_ann_line0
	jal	r1,(r0)
	add	sp,3

	la	r1,787984
	lw	r0,0(r1)
	add	r0,-1
	sw	r0,0(r1)

_hsse_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _mul9: Multiply arg by 9 (symbol table entry offset).
; Arg on stack: value
; Returns: r0 = value * 9
_mul9:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	lw	r0,9(fp)
	mov	r2,r0
	add	r0,r0
	add	r0,r0
	add	r0,r0
	add	r0,r2
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _mul6: Multiply arg by 6.
; Arg on stack: value
; Returns: r0 = value * 6
_mul6:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	lw	r0,9(fp)
	mov	r2,r0
	add	r0,r0
	add	r0,r0
	add	r0,r2
	add	r0,r2
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _mul10: Multiply arg by 10.
; Arg on stack: value
; Returns: r0 = value * 10
_mul10:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	lw	r0,9(fp)
	mov	r2,r0
	add	r0,r0
	add	r0,r0
	add	r0,r2
	add	r0,r0
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _mul12: Multiply arg by 12.
; Arg on stack: value
; Returns: r0 = value * 12
_mul12:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	lw	r0,9(fp)
	mov	r2,r0
	add	r0,r0
	add	r0,r2
	add	r0,r0
	add	r0,r0
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _hldiag_enabled: Return 1 if SET HLDIAG,<nonzero> is active.
; Reads cached _hldiag_switch (maintained by _hldiag_update_switch_current)
; to avoid the 6-character limit of the generic _parse_name_buf lookup path.
_hldiag_enabled:
	push	fp
	push	r1
	mov	fp,sp

	la	r1,_hldiag_switch
	lw	r0,0(r1)
	ceq	r0,z
	brt	_hde_off
	la	r0,1
	bra	_hde_ret

_hde_off:
	la	r0,0

_hde_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _hldiag_update_switch_current: Update HLDIAG switch when current _parse_name_buf
; matches HLDIAG. Called from _set_symbol so SET HLDIAG,<val> toggles the cache.
; Arg on stack: value
_hldiag_update_switch_current:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_hldiag_symbol_name
	push	r0
	la	r0,197128
	push	r0
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brt	_hdus_ret

	la	r1,_hldiag_switch
	lw	r0,6(fp)
	sw	r0,0(r1)

_hdus_ret:
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _hldiag_warn: Emit "; !! hlasm: <msg> at src<id>:<line>" when HLDIAG is on.
; Arg on stack: msg_ptr (null-terminated ASCII)
; No-op when HLDIAG is off.
_hldiag_warn:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r0,_hldiag_enabled
	jal	r1,(r0)
	ceq	r0,z
	brt	_hdw_ret

	la	r0,_hldiag_prefix_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_hldiag_at_src_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r1,_hldiag_src_id
	lw	r0,0(r1)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	la	r0,_hldiag_colon_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r1,_hldiag_line_no
	lw	r0,0(r1)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

_hdw_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _emit_hldiag_banner_if_enabled: Smoke usage proving the HLDIAG channel works.
; Fires once at end-of-run, only when HLDIAG is active.
_emit_hldiag_banner_if_enabled:
	push	fp
	push	r1
	mov	fp,sp

	la	r0,_hldiag_banner_msg
	push	r0
	la	r0,_hldiag_warn
	jal	r1,(r0)
	add	sp,3

	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; _hldiag_warn_unknown_mnemonic: Emit an HLDIAG warning for an unknown mnemonic.
; Arg on stack: token_ptr (null-terminated name currently in _parse_name_buf).
; No-op when HLDIAG is off.
_hldiag_warn_unknown_mnemonic:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r0,_hldiag_enabled
	jal	r1,(r0)
	ceq	r0,z
	brt	_hwum_ret

	la	r0,_hldiag_prefix_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_hldiag_unknown_mn_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_hldiag_quote_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_hldiag_at_src_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r1,_hldiag_src_id
	lw	r0,0(r1)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	la	r0,_hldiag_colon_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r1,_hldiag_line_no
	lw	r0,0(r1)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

_hwum_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _hldiag_check_unknown_mnemonic: At pass-through, warn when the line's
; first mnemonic-position token is not a known COR24 mnemonic. Skips
; blanks, comments, '.'-prefixed raw directives, and pure labels. Uses
; _parse_name_buf (197128) as scratch; safe because the line has already
; been dispatched past any hlasm-owned directive path.
_hldiag_check_unknown_mnemonic:
	push	fp
	push	r2
	push	r1
	mov	fp,sp

	la	r0,_hldiag_enabled
	jal	r1,(r0)
	ceq	r0,z
	brt	_hcum_ret

	la	r2,196608

_hcum_skipws:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_hcum_ret
	lc	r1,32
	ceq	r0,r1
	brt	_hcum_ws_adv
	lc	r1,9
	ceq	r0,r1
	brf	_hcum_got_start

_hcum_ws_adv:
	add	r2,1
	bra	_hcum_skipws

_hcum_got_start:
	lbu	r0,0(r2)
	lc	r1,59
	ceq	r0,r1
	brt	_hcum_ret
	lc	r1,35
	ceq	r0,r1
	brt	_hcum_ret
	lc	r1,46
	ceq	r0,r1
	brt	_hcum_ret

	push	r2
	la	r0,_copy_ident_token
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0

	la	r1,197128
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_hcum_ret

_hcum_after_ws:
	lbu	r0,0(r2)
	lc	r1,32
	ceq	r0,r1
	brt	_hcum_after_ws_adv
	lc	r1,9
	ceq	r0,r1
	brt	_hcum_after_ws_adv
	bra	_hcum_after_check

_hcum_after_ws_adv:
	add	r2,1
	bra	_hcum_after_ws

_hcum_after_check:
	lc	r1,58
	ceq	r0,r1
	brt	_hcum_ret

	la	r1,197128
	la	r0,_mn_table
	push	r1
	push	r0
	la	r0,_lookup
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	_hcum_ret

	la	r0,197128
	push	r0
	la	r0,_hldiag_warn_unknown_mnemonic
	jal	r1,(r0)
	add	sp,3

_hcum_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _hldiag_mark_undef_current: Record _parse_name_buf (197128) in the undef-
; symbol table if HLDIAG is on and the name is not already there. Invoked
; from _eval_expr_ptr's _eep_zero_term (symbol-lookup miss) so SET/EQU
; expressions that silently resolve undefined terms to 0 get captured.
_hldiag_mark_undef_current:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3

	la	r0,_hldiag_enabled
	jal	r1,(r0)
	ceq	r0,z
	brt	_hmu_ret

	la	r0,0
	sw	r0,-3(fp)

_hmu_loop:
	la	r1,_xref_undef_count
	lw	r1,0(r1)
	lw	r0,-3(fp)
	clu	r0,r1
	brf	_hmu_add

	lw	r0,-3(fp)
	push	r0
	la	r0,_mul32
	jal	r1,(r0)
	add	sp,3
	la	r1,229376
	add	r1,r0
	push	r1
	la	r1,197128
	push	r1
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	_hmu_ret

	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
	bra	_hmu_loop

_hmu_add:
	la	r1,_xref_undef_count
	lw	r0,0(r1)
	lc	r2,64
	clu	r0,r2
	brf	_hmu_ret

	push	r0
	la	r0,_mul32
	jal	r1,(r0)
	add	sp,3
	la	r1,229376
	add	r1,r0
	la	r2,197128
	lc	r0,32
	sw	r0,-3(fp)

_hmu_copy:
	lbu	r0,0(r2)
	sb	r0,0(r1)
	add	r1,1
	add	r2,1
	lw	r0,-3(fp)
	add	r0,-1
	sw	r0,-3(fp)
	ceq	r0,z
	brt	_hmu_inc
	bra	_hmu_copy

_hmu_inc:
	la	r1,_xref_undef_count
	lw	r0,0(r1)
	add	r0,1
	sw	r0,0(r1)

_hmu_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; _emit_hldiag_undef_report: When HLDIAG is on, emit a warning per collected
; undefined-symbol name as an end-of-run pass. No output if the table is
; empty or HLDIAG is off.
_emit_hldiag_undef_report:
	push	fp
	push	r2
	push	r1
	mov	fp,sp
	add	sp,-3

	la	r0,_hldiag_enabled
	jal	r1,(r0)
	ceq	r0,z
	brf	_ehur_continue
	la	r1,_ehur_ret
	jmp	(r1)

_ehur_continue:
	la	r0,0
	sw	r0,-3(fp)

_ehur_loop:
	la	r1,_xref_undef_count
	lw	r1,0(r1)
	lw	r0,-3(fp)
	clu	r0,r1
	brf	_ehur_ret

	la	r0,_hldiag_prefix_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_hldiag_undef_sym_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lw	r0,-3(fp)
	push	r0
	la	r0,_mul32
	jal	r1,(r0)
	add	sp,3
	la	r1,229376
	add	r1,r0
	push	r1
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_hldiag_quote_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r0,_hldiag_at_src_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r1,_hldiag_src_id
	lw	r0,0(r1)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	la	r0,_hldiag_colon_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	la	r1,_hldiag_line_no
	lw	r0,0(r1)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	la	r0,_emit_crlf
	jal	r1,(r0)

	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
	la	r1,_ehur_loop
	jmp	(r1)

_ehur_ret:
	mov	sp,fp
	pop	r1
	pop	r2
	pop	fp
	jmp	(r1)

; --- Structured jump relaxation (docs/structured-jump-relaxation.md) ---
; hlasm runs twice. Pass 1 (_relax_pass = 0) sends output to a line sizer
; instead of the UART and records label and jump positions; pass 2 restores
; the mutable data and emits, using bra for jumps whose pass-1 distance fits
; and push r2 / la r2,L_far / jmp (r2) otherwise.
; Relax state at 0x0E0000 (917504):
;   +0 pos  +3 jump count  +6 line length  +16 line buffer (256 bytes)
;   921600 label_pos[4096]  933888 jump_pos[4096]  946176 jump_tgt[4096]
;   958464 label_def[4096]  962560 label_far[4096]  966656 jump_far[4096]
; Data snapshot at 0x0D0000 (851968).

; _relax_begin_pass: Prepare relax state at the start of each pass.
_relax_begin_pass:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r2,_relax_pass
	lw	r0,0(r2)
	ceq	r0,z
	brf	_rbp_common

	lc	r0,0
	push	r0
	la	r0,_relax_snapshot
	jal	r1,(r0)
	add	sp,3

	; clear label_def, label_far and jump_far (12288 bytes) a word at a time
	la	r2,958464
	la	r1,970752
	lc	r0,0

_rbp_zero:
	sw	r0,0(r2)
	add	r2,3
	clu	r2,r1
	brt	_rbp_zero

_rbp_common:
	la	r2,917504
	lc	r0,0
	sw	r0,0(r2)
	sw	r0,3(r2)
	sw	r0,6(r2)

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _relax_end_pass1: Decide near/far jumps, restore data, select pass 2.
_relax_end_pass1:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r0,_relax_resolve
	jal	r1,(r0)

	lc	r0,1
	push	r0
	la	r0,_relax_snapshot
	jal	r1,(r0)
	add	sp,3

	la	r2,_relax_pass
	lc	r0,1
	sw	r0,0(r2)

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _relax_snapshot: Save (dir 0) or restore (dir 1) the image's mutable data.
; Arg on stack: dir (9 fp)
_relax_snapshot:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r0,_const_A
	push	r0
	la	r0,_line_is_keyword
	push	r0
	la	r0,851968
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_relax_copy
	jal	r1,(r0)
	add	sp,12

	la	r0,_id_buf
	push	r0
	la	r0,_image_end
	push	r0
	la	r0,852992
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_relax_copy
	jal	r1,(r0)
	add	sp,12

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _relax_copy: Copy words between an image range and the snapshot area.
; Args: dir (9 fp), snap ptr (12 fp), image end (15 fp), image begin (18 fp)
; dir 0: image -> snapshot; dir 1: snapshot -> image.
_relax_copy:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r1,18(fp)
	lw	r2,12(fp)

_rcp_loop:
	lw	r0,15(fp)
	clu	r1,r0
	brf	_rcp_ret
	lw	r0,9(fp)
	ceq	r0,z
	brf	_rcp_back
	lw	r0,0(r1)
	sw	r0,0(r2)
	bra	_rcp_next

_rcp_back:
	lw	r0,0(r2)
	sw	r0,0(r1)

_rcp_next:
	add	r1,3
	add	r2,3
	bra	_rcp_loop

_rcp_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _rx_addr3: Return base + 3 * index.
; Args on stack: base (9 fp), index (12 fp)
_rx_addr3:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,12(fp)
	mov	r2,r0
	add	r0,r2
	add	r0,r2
	lw	r2,9(fp)
	add	r0,r2

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _relax_size_char: Pass-1 replacement for UART output. Buffers the line and
; adds its size bound to the position counter at each LF (CR is ignored).
; Arg on stack: byte value (9 fp)
_relax_size_char:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,9(fp)
	lc	r2,13
	ceq	r0,r2
	brt	_rsc_ret
	lc	r2,10
	ceq	r0,r2
	brt	_rsc_eol

	la	r2,917510
	lw	r1,0(r2)
	add	r1,1
	sw	r1,0(r2)
	add	r1,-1
	la	r0,255
	clu	r1,r0
	brf	_rsc_ret
	la	r0,917520
	add	r0,r1
	lw	r1,9(fp)
	sb	r1,0(r0)
	bra	_rsc_ret

_rsc_eol:
	la	r0,_relax_size_line
	jal	r1,(r0)
	la	r2,917504
	lw	r1,0(r2)
	add	r1,r0
	sw	r1,0(r2)
	lc	r0,0
	sw	r0,6(r2)

_rsc_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _relax_size_line: Upper bound on the bytes the buffered line assembles to.
; Skips a leading "name:" label; comment/empty = 0; .byte = items;
; .word = 3 * items; .text/.data/.glob* = 0; other directives, quoted data or
; an overlong line = 256 (forces any spanning jump far); instruction = 4.
; Returns: r0 = size
_relax_size_line:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-3

	la	r2,917510
	lw	r1,0(r2)
	la	r0,255
	clu	r1,r0
	brt	_rsl_fits
	la	r0,256
	la	r1,_rsl_ret
	jmp	(r1)

_rsl_fits:
	la	r0,917520
	add	r0,r1
	lc	r1,0
	sb	r1,0(r0)

	la	r0,917520
	push	r0
	la	r0,_rx_skip_ws
	jal	r1,(r0)
	add	sp,3
	sw	r0,-3(fp)
	mov	r2,r0

_rsl_tok:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_rsl_body
	lc	r1,32
	ceq	r0,r1
	brt	_rsl_body
	lc	r1,9
	ceq	r0,r1
	brt	_rsl_body
	lc	r1,59
	ceq	r0,r1
	brt	_rsl_body
	lc	r1,58
	ceq	r0,r1
	brt	_rsl_label
	add	r2,1
	bra	_rsl_tok

_rsl_label:
	add	r2,1
	push	r2
	la	r0,_rx_skip_ws
	jal	r1,(r0)
	add	sp,3
	sw	r0,-3(fp)

_rsl_body:
	lw	r2,-3(fp)
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_rsl_zero
	lc	r1,59
	ceq	r0,r1
	brt	_rsl_zero
	lc	r1,46
	ceq	r0,r1
	brt	_rsl_dot
	lc	r0,4
	la	r1,_rsl_ret
	jmp	(r1)

_rsl_zero:
	lc	r0,0
	la	r1,_rsl_ret
	jmp	(r1)

_rsl_dot:
	add	r2,1
	sw	r2,-3(fp)

	push	r2
	la	r0,_rx_byte_txt
	push	r0
	la	r0,_rx_prefix
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brt	_rsl_not_byte
	lw	r0,-3(fp)
	push	r0
	la	r0,_rx_count_items
	jal	r1,(r0)
	add	sp,3
	la	r1,_rsl_ret
	jmp	(r1)

_rsl_not_byte:
	lw	r0,-3(fp)
	push	r0
	la	r0,_rx_word_txt
	push	r0
	la	r0,_rx_prefix
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brt	_rsl_not_word
	lw	r0,-3(fp)
	push	r0
	la	r0,_rx_count_items
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0
	add	r0,r2
	add	r0,r2
	la	r1,_rsl_ret
	jmp	(r1)

_rsl_not_word:
	lw	r0,-3(fp)
	push	r0
	la	r0,_rx_text_txt
	push	r0
	la	r0,_rx_prefix
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	_rsl_zero_far

	lw	r0,-3(fp)
	push	r0
	la	r0,_rx_data_txt
	push	r0
	la	r0,_rx_prefix
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	_rsl_zero_far

	lw	r0,-3(fp)
	push	r0
	la	r0,_rx_glob_txt
	push	r0
	la	r0,_rx_prefix
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	_rsl_zero_far

	la	r0,256
	bra	_rsl_ret

_rsl_zero_far:
	lc	r0,0

_rsl_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _rx_skip_ws: Return pointer past spaces and tabs.
; Arg on stack: ptr (9 fp)
_rx_skip_ws:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r2,9(fp)

_rsw_loop:
	lbu	r0,0(r2)
	lc	r1,32
	ceq	r0,r1
	brt	_rsw_adv
	lc	r1,9
	ceq	r0,r1
	brf	_rsw_ret

_rsw_adv:
	add	r2,1
	bra	_rsw_loop

_rsw_ret:
	mov	r0,r2
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _rx_prefix: Return 1 if text starts with the NUL-terminated word.
; Args on stack: word (9 fp), text (12 fp)
_rx_prefix:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-3

	lw	r0,12(fp)
	sw	r0,-3(fp)
	lw	r2,9(fp)

_rxp_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_rxp_yes
	lw	r1,-3(fp)
	lbu	r1,0(r1)
	ceq	r0,r1
	brf	_rxp_no
	lw	r1,-3(fp)
	add	r1,1
	sw	r1,-3(fp)
	add	r2,1
	bra	_rxp_loop

_rxp_yes:
	lc	r0,1
	bra	_rxp_ret

_rxp_no:
	lc	r0,0

_rxp_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _rx_count_items: Return commas + 1 up to end of line or ';' comment, or
; 256 if the line holds a quote (string or character data).
; Arg on stack: ptr (9 fp)
_rx_count_items:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-3

	lc	r0,1
	sw	r0,-3(fp)
	lw	r2,9(fp)

_rci_loop:
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_rci_done
	lc	r1,59
	ceq	r0,r1
	brt	_rci_done
	lc	r1,34
	ceq	r0,r1
	brt	_rci_poison
	lc	r1,39
	ceq	r0,r1
	brt	_rci_poison
	lc	r1,44
	ceq	r0,r1
	brf	_rci_next
	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)

_rci_next:
	add	r2,1
	bra	_rci_loop

_rci_poison:
	la	r0,256
	bra	_rci_ret

_rci_done:
	lw	r0,-3(fp)

_rci_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _rx_emit_label: Emit "<prefix><id><suffix>" (no newline).
; Args on stack: suffix (9 fp), id (12 fp), prefix (15 fp)
_rx_emit_label:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,15(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	lw	r0,12(fp)
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3

	lw	r0,9(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_relaxed_jump: Emit a structured jump to <prefix><id><suffix>.
; Near: " bra L". Far: " push r2" / " la r2,L_far" / " jmp (r2)".
; Pass 1 always emits the far form and records the jump.
; Args on stack: suffix (9 fp), id (12 fp), prefix (15 fp)
; Locals: far flag (-3 fp), jump index (-6 fp)
_emit_relaxed_jump:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-6

	la	r2,917507
	lw	r1,0(r2)
	sw	r1,-6(fp)
	add	r1,1
	sw	r1,0(r2)
	add	r1,-1

	lc	r0,1
	sw	r0,-3(fp)

	la	r2,_relax_pass
	lw	r2,0(r2)
	ceq	r2,z
	brf	_erj_pass2

	la	r0,4096
	clu	r1,r0
	brf	_erj_p1_overflow
	lw	r0,12(fp)
	la	r2,4096
	clu	r0,r2
	brf	_erj_emit_near

	lw	r0,-6(fp)
	push	r0
	la	r0,933888
	push	r0
	la	r0,_rx_addr3
	jal	r1,(r0)
	add	sp,6
	la	r2,917504
	lw	r2,0(r2)
	sw	r2,0(r0)

	lw	r0,-6(fp)
	push	r0
	la	r0,946176
	push	r0
	la	r0,_rx_addr3
	jal	r1,(r0)
	add	sp,6
	lw	r2,12(fp)
	sw	r2,0(r0)
	bra	_erj_emit_near

_erj_p1_overflow:
	lw	r0,12(fp)
	la	r2,4096
	clu	r0,r2
	brf	_erj_emit_near
	la	r2,962560
	add	r2,r0
	lc	r0,1
	sb	r0,0(r2)
	bra	_erj_emit_near

_erj_pass2:
	la	r0,4096
	clu	r1,r0
	brf	_erj_emit_near
	lw	r0,12(fp)
	la	r2,4096
	clu	r0,r2
	brf	_erj_emit_near
	la	r2,966656
	add	r2,r1
	lbu	r0,0(r2)
	sw	r0,-3(fp)

_erj_emit_near:
	lw	r0,-3(fp)
	ceq	r0,z
	brf	_erj_far

	la	r0,_rx_bra_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	lw	r0,15(fp)
	push	r0
	lw	r0,12(fp)
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_rx_emit_label
	jal	r1,(r0)
	add	sp,9
	la	r0,_emit_crlf
	jal	r1,(r0)
	la	r1,_erj_ret
	jmp	(r1)

_erj_far:
	la	r0,_rx_push_r2_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	la	r0,_emit_crlf
	jal	r1,(r0)

	la	r0,_rx_la_r2_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	lw	r0,15(fp)
	push	r0
	lw	r0,12(fp)
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_rx_emit_label
	jal	r1,(r0)
	add	sp,9
	la	r0,_rx_far_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	la	r0,_emit_crlf
	jal	r1,(r0)

	la	r0,_rx_jmp_r2_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	la	r0,_emit_crlf
	jal	r1,(r0)

_erj_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _relax_label_def: Called before a structured label definition is emitted.
; Emits the far-entry trampoline " bra L" / "L_far:" / " pop r2" when the
; label is a far target (pass 1: any non-skip label, as a size bound), then
; records the label position in pass 1.
; Args on stack: suffix (9 fp), id (12 fp), prefix (15 fp)
_relax_label_def:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	lw	r0,9(fp)
	la	r2,_if_skip_suffix
	ceq	r0,r2
	brt	_rld_record
	la	r2,_do_skip_suffix
	ceq	r0,r2
	brt	_rld_record
	la	r2,_sel_skip_suffix
	ceq	r0,r2
	brt	_rld_record

	la	r2,_relax_pass
	lw	r2,0(r2)
	ceq	r2,z
	brt	_rld_tramp
	lw	r0,12(fp)
	la	r2,4096
	clu	r0,r2
	brf	_rld_tramp
	la	r2,962560
	add	r2,r0
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_rld_record

_rld_tramp:
	la	r0,_rx_bra_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	lw	r0,15(fp)
	push	r0
	lw	r0,12(fp)
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_rx_emit_label
	jal	r1,(r0)
	add	sp,9
	la	r0,_emit_crlf
	jal	r1,(r0)

	lw	r0,15(fp)
	push	r0
	lw	r0,12(fp)
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_rx_emit_label
	jal	r1,(r0)
	add	sp,9
	la	r0,_rx_far_def_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	la	r0,_emit_crlf
	jal	r1,(r0)

	la	r0,_rx_pop_r2_txt
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	la	r0,_emit_crlf
	jal	r1,(r0)

_rld_record:
	la	r2,_relax_pass
	lw	r2,0(r2)
	ceq	r2,z
	brf	_rld_ret
	lw	r0,12(fp)
	la	r2,4096
	clu	r0,r2
	brf	_rld_ret

	lw	r0,12(fp)
	push	r0
	la	r0,921600
	push	r0
	la	r0,_rx_addr3
	jal	r1,(r0)
	add	sp,6
	la	r2,917504
	lw	r2,0(r2)
	sw	r2,0(r0)

	lw	r0,12(fp)
	la	r2,958464
	add	r2,r0
	lc	r0,1
	sb	r0,0(r2)

_rld_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _relax_resolve: After pass 1, mark each recorded jump far when its target
; is undefined, unrecorded, or outside the bra offset range [-128, 127]
; measured from the jump address + 4; mark far targets for trampolines.
; Locals: jump index (-3 fp), target id (-6 fp), target pos (-9 fp)
_relax_resolve:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-9

	lc	r0,0
	sw	r0,-3(fp)

_rr_loop:
	lw	r1,-3(fp)
	la	r2,917507
	lw	r0,0(r2)
	clu	r1,r0
	brt	_rr_in_count
	la	r0,_rr_ret
	jmp	(r0)

_rr_in_count:
	la	r0,4096
	clu	r1,r0
	brt	_rr_in_table
	la	r0,_rr_ret
	jmp	(r0)

_rr_in_table:
	push	r1
	la	r0,946176
	push	r0
	la	r0,_rx_addr3
	jal	r1,(r0)
	add	sp,6
	lw	r0,0(r0)
	sw	r0,-6(fp)

	la	r2,4096
	clu	r0,r2
	brf	_rr_far_jump

	la	r2,958464
	add	r2,r0
	lbu	r2,0(r2)
	ceq	r2,z
	brt	_rr_far_target

	push	r0
	la	r0,921600
	push	r0
	la	r0,_rx_addr3
	jal	r1,(r0)
	add	sp,6
	lw	r0,0(r0)
	sw	r0,-9(fp)

	lw	r0,-3(fp)
	push	r0
	la	r0,933888
	push	r0
	la	r0,_rx_addr3
	jal	r1,(r0)
	add	sp,6
	lw	r1,0(r0)

	lw	r0,-9(fp)
	sub	r0,r1
	add	r0,124
	la	r2,256
	clu	r0,r2
	brt	_rr_next

_rr_far_target:
	lw	r0,-6(fp)
	la	r2,962560
	add	r2,r0
	lc	r0,1
	sb	r0,0(r2)

_rr_far_jump:
	lw	r0,-3(fp)
	la	r2,966656
	add	r2,r0
	lc	r0,1
	sb	r0,0(r2)

_rr_next:
	lw	r0,-3(fp)
	add	r0,1
	sw	r0,-3(fp)
	la	r0,_rr_loop
	jmp	(r0)

_rr_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

_rx_bra_txt:
	.byte	32,98,114,97,32,0

_rx_push_r2_txt:
	.byte	32,112,117,115,104,32,114,50,0

_rx_pop_r2_txt:
	.byte	32,112,111,112,32,114,50,0

_rx_la_r2_txt:
	.byte	32,108,97,32,114,50,44,0

_rx_jmp_r2_txt:
	.byte	32,106,109,112,32,40,114,50,41,0

_rx_far_txt:
	.byte	95,102,97,114,0

_rx_far_def_txt:
	.byte	95,102,97,114,58,0

_rx_byte_txt:
	.byte	98,121,116,101,0

_rx_word_txt:
	.byte	119,111,114,100,0

_rx_text_txt:
	.byte	116,101,120,116,0

_rx_data_txt:
	.byte	100,97,116,97,0

_rx_glob_txt:
	.byte	103,108,111,98,0

; --- Assembly-time expressions and operand substitution ---
; Expression grammar (lowest to highest precedence):
;   |   ^   &   << >>   + -   * / %   unary - ~ +   ( ) number 'c' symbol
; Numbers: decimal, 0x hex, 0b binary, h-suffixed hex. 'c' is a character
; literal (escapes \n \t \r \0 \\ \'). A symbol is a SET/EQU name.
; State (runtime arena, cleared at pass start):
;   786648 _ev_pos      current parse pointer
;   786651 _ev_undef    identifiers that are not symbols (registers, labels)
;   786654 _ev_nontriv  1 if a symbol, operator, ( ), 'c' or 0b was used
;   786657 _ev_err      1 on a syntax error
;   786660 _ev_quiet    1 = do not report undefined symbols to HLDIAG
;   786663 _div_rem     remainder from _sdiv

; _eval_full: Evaluate the expression at ptr. Leaves _ev_pos after it.
; Args on stack: quiet (9 fp), ptr (12 fp)
; Returns: r0 = value
_eval_full:
	push	fp
	push	r1
	push	r2
	mov	fp,sp

	la	r2,786648
	lw	r0,12(fp)
	sw	r0,0(r2)
	lc	r0,0
	sw	r0,3(r2)
	sw	r0,6(r2)
	sw	r0,9(r2)
	lw	r0,9(fp)
	sw	r0,12(r2)

	la	r0,_ev_or
	jal	r1,(r0)
	push	r0
	la	r0,_ev_skip
	jal	r1,(r0)
	pop	r0

	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _ev_skip: Skip spaces/tabs at _ev_pos. Returns: r0 = char there.
_ev_skip:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	la	r2,786648
	lw	r1,0(r2)
_evs_loop:
	lbu	r0,0(r1)
	lc	r2,32
	ceq	r0,r2
	brt	_evs_adv
	lc	r2,9
	ceq	r0,r2
	brt	_evs_adv
	la	r2,786648
	sw	r1,0(r2)
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)
_evs_adv:
	add	r1,1
	bra	_evs_loop

; _ev_take: Advance _ev_pos by n and mark the expression non-trivial.
; Arg on stack: n (9 fp)
_ev_take:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	la	r2,786648
	lw	r1,0(r2)
	lw	r0,9(fp)
	add	r1,r0
	sw	r1,0(r2)
	lc	r0,1
	sw	r0,6(r2)
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _ev_next2: r0 = character at _ev_pos+1 (call right after _ev_skip).
_ev_next2:
	push	fp
	push	r1
	mov	fp,sp
	la	r1,786648
	lw	r1,0(r1)
	lbu	r0,1(r1)
	mov	sp,fp
	pop	r1
	pop	fp
	jmp	(r1)

; Binary levels. Each keeps the left value at -3(fp).
_ev_or:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-3
	la	r0,_ev_xor
	jal	r1,(r0)
	sw	r0,-3(fp)
_evo_loop:
	la	r0,_ev_skip
	jal	r1,(r0)
	lc	r1,124
	ceq	r0,r1
	brf	_evo_ret
	lc	r0,1
	push	r0
	la	r0,_ev_take
	jal	r1,(r0)
	add	sp,3
	la	r0,_ev_xor
	jal	r1,(r0)
	lw	r1,-3(fp)
	or	r0,r1
	sw	r0,-3(fp)
	bra	_evo_loop
_evo_ret:
	lw	r0,-3(fp)
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

_ev_xor:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-3
	la	r0,_ev_and
	jal	r1,(r0)
	sw	r0,-3(fp)
_evx_loop:
	la	r0,_ev_skip
	jal	r1,(r0)
	lc	r1,94
	ceq	r0,r1
	brf	_evx_ret
	lc	r0,1
	push	r0
	la	r0,_ev_take
	jal	r1,(r0)
	add	sp,3
	la	r0,_ev_and
	jal	r1,(r0)
	lw	r1,-3(fp)
	xor	r0,r1
	sw	r0,-3(fp)
	bra	_evx_loop
_evx_ret:
	lw	r0,-3(fp)
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

_ev_and:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-3
	la	r0,_ev_shift
	jal	r1,(r0)
	sw	r0,-3(fp)
_eva_loop:
	la	r0,_ev_skip
	jal	r1,(r0)
	lc	r1,38
	ceq	r0,r1
	brf	_eva_ret
	lc	r0,1
	push	r0
	la	r0,_ev_take
	jal	r1,(r0)
	add	sp,3
	la	r0,_ev_shift
	jal	r1,(r0)
	lw	r1,-3(fp)
	and	r0,r1
	sw	r0,-3(fp)
	bra	_eva_loop
_eva_ret:
	lw	r0,-3(fp)
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; << and >> (>> is arithmetic, like the 24-bit signed values it shifts)
_ev_shift:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-6
	la	r0,_ev_add
	jal	r1,(r0)
	sw	r0,-3(fp)
_evh_loop:
	la	r0,_ev_skip
	jal	r1,(r0)
	sw	r0,-6(fp)
	lc	r1,60
	ceq	r0,r1
	brt	_evh_cand
	lc	r1,62
	ceq	r0,r1
	brf	_evh_ret
_evh_cand:
	la	r0,_ev_next2
	jal	r1,(r0)
	lw	r1,-6(fp)
	ceq	r0,r1
	brf	_evh_ret
	lc	r0,2
	push	r0
	la	r0,_ev_take
	jal	r1,(r0)
	add	sp,3
	la	r0,_ev_add
	jal	r1,(r0)
	mov	r1,r0
	lw	r0,-6(fp)
	lc	r2,60
	ceq	r0,r2
	lw	r0,-3(fp)
	brf	_evh_right
	shl	r0,r1
	bra	_evh_store
_evh_right:
	sra	r0,r1
_evh_store:
	sw	r0,-3(fp)
	bra	_evh_loop
_evh_ret:
	lw	r0,-3(fp)
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

_ev_add:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-6
	la	r0,_ev_mul
	jal	r1,(r0)
	sw	r0,-3(fp)
_evd_loop:
	la	r0,_ev_skip
	jal	r1,(r0)
	sw	r0,-6(fp)
	lc	r1,43
	ceq	r0,r1
	brt	_evd_op
	lc	r1,45
	ceq	r0,r1
	brf	_evd_ret
_evd_op:
	lc	r0,1
	push	r0
	la	r0,_ev_take
	jal	r1,(r0)
	add	sp,3
	la	r0,_ev_mul
	jal	r1,(r0)
	mov	r1,r0
	lw	r0,-6(fp)
	lc	r2,43
	ceq	r0,r2
	lw	r0,-3(fp)
	brf	_evd_sub
	add	r0,r1
	bra	_evd_store
_evd_sub:
	sub	r0,r1
_evd_store:
	sw	r0,-3(fp)
	bra	_evd_loop
_evd_ret:
	lw	r0,-3(fp)
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

_ev_mul:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-6
	la	r0,_ev_unary
	jal	r1,(r0)
	sw	r0,-3(fp)
_evm_loop:
	la	r0,_ev_skip
	jal	r1,(r0)
	sw	r0,-6(fp)
	lc	r1,42
	ceq	r0,r1
	brt	_evm_op
	lc	r1,47
	ceq	r0,r1
	brt	_evm_op
	lc	r1,37
	ceq	r0,r1
	brf	_evm_ret
_evm_op:
	lc	r0,1
	push	r0
	la	r0,_ev_take
	jal	r1,(r0)
	add	sp,3
	la	r0,_ev_unary
	jal	r1,(r0)
	mov	r1,r0
	lw	r0,-6(fp)
	lc	r2,42
	ceq	r0,r2
	brf	_evm_div
	lw	r0,-3(fp)
	mul	r0,r1
	bra	_evm_store
_evm_div:
	push	r1
	lw	r0,-3(fp)
	push	r0
	la	r0,_sdiv
	jal	r1,(r0)
	add	sp,6
	lw	r1,-6(fp)
	lc	r2,37
	ceq	r1,r2
	brf	_evm_store
	la	r1,786663
	lw	r0,0(r1)
_evm_store:
	sw	r0,-3(fp)
	bra	_evm_loop
_evm_ret:
	lw	r0,-3(fp)
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

_ev_unary:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-3
	la	r0,_ev_skip
	jal	r1,(r0)
	sw	r0,-3(fp)
	lc	r1,45
	ceq	r0,r1
	brt	_evu_op
	lc	r1,126
	ceq	r0,r1
	brt	_evu_op
	lc	r1,43
	ceq	r0,r1
	brt	_evu_op
	la	r0,_ev_primary
	jal	r1,(r0)
	bra	_evu_ret
_evu_op:
	lc	r0,1
	push	r0
	la	r0,_ev_take
	jal	r1,(r0)
	add	sp,3
	la	r0,_ev_unary
	jal	r1,(r0)
	lw	r1,-3(fp)
	lc	r2,45
	ceq	r1,r2
	brt	_evu_neg
	lc	r2,126
	ceq	r1,r2
	brf	_evu_ret
	la	r1,-1
	xor	r0,r1
	bra	_evu_ret
_evu_neg:
	mov	r1,r0
	lc	r0,0
	sub	r0,r1
_evu_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _ev_primary: ( expr ) | number | 'c' | symbol. Sets _ev_err on anything else.
_ev_primary:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-3
	la	r0,_ev_skip
	jal	r1,(r0)
	lc	r1,40
	ceq	r0,r1
	brf	_evp_not_paren

	lc	r0,1
	push	r0
	la	r0,_ev_take
	jal	r1,(r0)
	add	sp,3
	la	r0,_ev_or
	jal	r1,(r0)
	sw	r0,-3(fp)
	la	r0,_ev_skip
	jal	r1,(r0)
	lc	r1,41
	ceq	r0,r1
	brt	_evp_paren_ok
	la	r1,_evp_err_keep
	jmp	(r1)
_evp_paren_ok:
	lc	r0,1
	push	r0
	la	r0,_ev_take
	jal	r1,(r0)
	add	sp,3
	la	r1,_evp_ret_val
	jmp	(r1)

_evp_not_paren:
	lc	r1,39
	ceq	r0,r1
	brf	_evp_not_char
	la	r1,_evp_char
	jmp	(r1)

_evp_not_char:
	lc	r1,48
	clu	r0,r1
	brt	_evp_ident
	lc	r1,58
	clu	r0,r1
	brf	_evp_ident
	la	r1,_evp_number
	jmp	(r1)

_evp_ident:
	push	r0
	la	r0,_is_macro_name_char
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_evp_err

	la	r0,_ev_copy_word
	jal	r1,(r0)

	la	r0,197128
	push	r0
	la	r0,_reg_table
	push	r0
	la	r0,_lookup
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	_evp_undef

	la	r0,_lookup_symbol
	jal	r1,(r0)
	ceq	r0,z
	brt	_evp_unknown
	la	r1,786594
	lw	r0,0(r1)
	sw	r0,-3(fp)
	la	r1,786654
	lc	r0,1
	sw	r0,0(r1)
	la	r1,_evp_ret_val
	jmp	(r1)

_evp_unknown:
	la	r1,786660
	lw	r0,0(r1)
	ceq	r0,z
	brf	_evp_undef
	la	r0,_hldiag_mark_undef_current
	jal	r1,(r0)
_evp_undef:
	la	r1,786651
	lw	r0,0(r1)
	add	r0,1
	sw	r0,0(r1)
	lc	r0,0
	sw	r0,-3(fp)
	bra	_evp_ret_val

_evp_err:
	lc	r0,0
	sw	r0,-3(fp)
_evp_err_keep:
	la	r1,786657
	lc	r0,1
	sw	r0,0(r1)
	bra	_evp_ret_val

_evp_number:
	la	r0,_ev_copy_word
	jal	r1,(r0)
	la	r0,197128
	push	r0
	la	r0,_is_number_str
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_evp_err
	la	r0,197128
	push	r0
	la	r0,_atoi
	jal	r1,(r0)
	add	sp,3
	sw	r0,-3(fp)
	; 0b literals are not understood by cor24-asm: force a rewrite
	la	r1,197128
	lbu	r0,1(r1)
	lc	r1,98
	ceq	r0,r1
	brt	_evp_num_bin
	lc	r1,66
	ceq	r0,r1
	brf	_evp_ret_val
_evp_num_bin:
	la	r1,786654
	lc	r0,1
	sw	r0,0(r1)
	bra	_evp_ret_val

; 'c' or '\e': value of the character
_evp_char:
	la	r2,786648
	lw	r1,0(r2)
	lbu	r0,1(r1)
	lc	r2,92
	ceq	r0,r2
	brf	_evp_char_plain
	lbu	r0,2(r1)
	push	r1
	push	r0
	la	r0,_string_escape
	jal	r1,(r0)
	add	sp,3
	pop	r1
	sw	r0,-3(fp)
	lc	r2,3
	bra	_evp_char_close
_evp_char_plain:
	sw	r0,-3(fp)
	lc	r2,2
_evp_char_close:
	add	r1,r2
	lbu	r0,0(r1)
	lc	r1,39
	ceq	r0,r1
	brf	_evp_err_keep
	add	r2,1
	push	r2
	la	r0,_ev_take
	jal	r1,(r0)
	add	sp,3

_evp_ret_val:
	lw	r0,-3(fp)
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _ev_copy_word: Copy [0-9A-Za-z_]* at _ev_pos into _parse_name_buf and
; advance _ev_pos past it (at most 255 characters).
_ev_copy_word:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-6
	la	r2,786648
	lw	r0,0(r2)
	sw	r0,-3(fp)
	la	r0,197128
	sw	r0,-6(fp)
_ecw_loop:
	lw	r1,-3(fp)
	lbu	r0,0(r1)
	push	r0
	la	r0,_is_macro_name_char
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_ecw_done
	lw	r1,-6(fp)
	la	r2,197383
	clu	r1,r2
	brf	_ecw_done
	lw	r2,-3(fp)
	lbu	r0,0(r2)
	sb	r0,0(r1)
	add	r1,1
	sw	r1,-6(fp)
	add	r2,1
	sw	r2,-3(fp)
	bra	_ecw_loop
_ecw_done:
	lw	r1,-6(fp)
	lc	r0,0
	sb	r0,0(r1)
	la	r2,786648
	lw	r0,-3(fp)
	sw	r0,0(r2)
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _sdiv: Signed 24-bit division (truncates toward zero, like C).
; Args on stack: divisor (12 fp), dividend (9 fp)
; Returns: r0 = quotient; remainder (sign of the dividend) at 786663.
; -3 |dividend|  -6 |divisor|  -9 quotient  -12 remainder  -15 bit  -18 signs
_sdiv:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-18

	lw	r0,12(fp)
	ceq	r0,z
	brf	_sd_nonzero
	la	r0,_err_div_zero
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_sd_nonzero:
	lc	r2,0
	lw	r0,9(fp)
	cls	r0,z
	brf	_sd_a_pos
	mov	r1,r0
	lc	r0,0
	sub	r0,r1
	lc	r2,3
_sd_a_pos:
	sw	r0,-3(fp)
	lw	r0,12(fp)
	cls	r0,z
	brf	_sd_b_pos
	mov	r1,r0
	lc	r0,0
	sub	r0,r1
	add	r2,1
_sd_b_pos:
	sw	r0,-6(fp)
	sw	r2,-18(fp)
	lc	r0,0
	sw	r0,-9(fp)
	sw	r0,-12(fp)
	lc	r0,23
	sw	r0,-15(fp)

_sd_loop:
	lw	r0,-12(fp)
	add	r0,r0
	sw	r0,-12(fp)
	lw	r0,-3(fp)
	lw	r1,-15(fp)
	srl	r0,r1
	lc	r1,1
	and	r0,r1
	lw	r1,-12(fp)
	add	r0,r1
	sw	r0,-12(fp)
	lw	r0,-9(fp)
	add	r0,r0
	sw	r0,-9(fp)
	lw	r0,-12(fp)
	lw	r1,-6(fp)
	clu	r0,r1
	brt	_sd_next
	sub	r0,r1
	sw	r0,-12(fp)
	lw	r0,-9(fp)
	add	r0,1
	sw	r0,-9(fp)
_sd_next:
	lw	r0,-15(fp)
	ceq	r0,z
	brt	_sd_signs
	add	r0,-1
	sw	r0,-15(fp)
	bra	_sd_loop

; signs: +3 if the dividend was negative, +1 if the divisor was
_sd_signs:
	lw	r2,-18(fp)
	lw	r0,-12(fp)
	lc	r1,2
	clu	r1,r2
	brf	_sd_rem_store
	mov	r1,r0
	lc	r0,0
	sub	r0,r1
_sd_rem_store:
	la	r1,786663
	sw	r0,0(r1)
	lw	r0,-9(fp)
	lc	r1,1
	ceq	r1,r2
	brt	_sd_neg_q
	lc	r1,3
	ceq	r1,r2
	brt	_sd_neg_q
	bra	_sd_ret
_sd_neg_q:
	mov	r1,r0
	lc	r0,0
	sub	r0,r1
_sd_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _string_escape: Map the character after a backslash to its byte value:
; n t r 0 \ " ' are accepted; anything else stops with an ERROR (\x is
; handled by the caller because it consumes two more characters).
; Arg on stack: escaped char (9 fp)
; Returns: r0 = byte value
_string_escape:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	lw	r0,9(fp)
	lc	r1,110
	ceq	r0,r1
	brt	_se_n
	lc	r1,116
	ceq	r0,r1
	brt	_se_t
	lc	r1,114
	ceq	r0,r1
	brt	_se_r
	lc	r1,48
	ceq	r0,r1
	brt	_se_z
	lc	r1,92
	ceq	r0,r1
	brt	_se_ret
	lc	r1,34
	ceq	r0,r1
	brt	_se_ret
	lc	r1,39
	ceq	r0,r1
	brt	_se_ret
	la	r0,_err_bad_escape
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_se_n:
	lc	r0,10
	bra	_se_ret
_se_t:
	lc	r0,9
	bra	_se_ret
_se_r:
	lc	r0,13
	bra	_se_ret
_se_z:
	lc	r0,0
_se_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _eal_hex_digit: Value of the hex digit at ptr; ERROR if it is not one.
; Arg on stack: ptr (9 fp)
_eal_hex_digit:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	lw	r2,9(fp)
	lbu	r0,0(r2)
	push	r0
	la	r0,_is_hex_digit
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brf	_ehd_ok
	la	r0,_err_bad_escape
	push	r0
	la	r0,_fatal
	jal	r1,(r0)
_ehd_ok:
	lw	r2,9(fp)
	lbu	r0,0(r2)
	push	r0
	la	r0,_hex_digit_val
	jal	r1,(r0)
	add	sp,3
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_sdec: Print a 24-bit value as signed decimal.
; Arg on stack: value (9 fp)
_emit_sdec:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	lw	r0,9(fp)
	cls	r0,z
	brf	_esd_pos
	lc	r0,45
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3
	lw	r1,9(fp)
	lc	r0,0
	sub	r0,r1
	bra	_esd_emit
_esd_pos:
	lw	r0,9(fp)
_esd_emit:
	push	r0
	la	r0,_emit_dec24
	jal	r1,(r0)
	add	sp,3
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _fmt_sdec: Write a 24-bit value as signed decimal + NUL into buf.
; Args on stack: value (12 fp), buf (9 fp)
_fmt_sdec:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-9
	lw	r2,9(fp)
	lw	r0,12(fp)
	cls	r0,z
	brf	_fsd_pos
	lc	r1,45
	sb	r1,0(r2)
	add	r2,1
	mov	r1,r0
	lc	r0,0
	sub	r0,r1
_fsd_pos:
	sw	r0,-3(fp)
	lc	r0,0
	sw	r0,-6(fp)
	la	r0,_dec_pow
	sw	r0,-9(fp)
_fsd_pow:
	lw	r1,-9(fp)
	lw	r1,0(r1)
	ceq	r1,z
	brt	_fsd_done
	lc	r0,0
	push	r0
_fsd_sub:
	lw	r0,-3(fp)
	clu	r0,r1
	brt	_fsd_digit
	sub	r0,r1
	sw	r0,-3(fp)
	pop	r0
	add	r0,1
	push	r0
	bra	_fsd_sub
_fsd_digit:
	pop	r0
	ceq	r0,z
	brf	_fsd_emit
	push	r0
	lw	r0,-6(fp)
	ceq	r0,z
	pop	r0
	brf	_fsd_emit
	push	r0
	lc	r0,1
	ceq	r0,r1
	pop	r0
	brf	_fsd_next
_fsd_emit:
	add	r0,48
	sb	r0,0(r2)
	add	r2,1
	lc	r0,1
	sw	r0,-6(fp)
_fsd_next:
	lw	r0,-9(fp)
	add	r0,3
	sw	r0,-9(fp)
	bra	_fsd_pow
_fsd_done:
	lc	r0,0
	sb	r0,0(r2)
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _operand_value: Try to evaluate a NUL-terminated operand quietly.
; Arg on stack: ptr (9 fp)
; Returns: r0 = 1 if it is a complete expression of literals and symbols
; that is worth rewriting (uses a symbol, operator, ( ), 'c' or 0b);
; then the value is at 786666.
_operand_value:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	lw	r0,9(fp)
	push	r0
	lc	r0,1
	push	r0
	la	r0,_eval_full
	jal	r1,(r0)
	add	sp,6
	la	r1,786666
	sw	r0,0(r1)
	la	r2,786648
	lw	r1,0(r2)
	lbu	r0,0(r1)
	ceq	r0,z
	brf	_ov_no
	lw	r0,3(r2)
	ceq	r0,z
	brf	_ov_no
	lw	r0,9(r2)
	ceq	r0,z
	brf	_ov_no
	lw	r0,6(r2)
	bra	_ov_ret
_ov_no:
	lc	r0,0
_ov_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _subst_buf: If the operand text in buf is a symbol expression, replace it
; with its signed decimal value (used for IF/DOEXIT and WHEN operands).
; Arg on stack: buf (9 fp)
_subst_buf:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	lw	r0,9(fp)
	push	r0
	la	r0,_operand_value
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_sb_ret
	la	r1,786666
	lw	r0,0(r1)
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_fmt_sdec
	jal	r1,(r0)
	add	sp,6
_sb_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_range: Emit the characters in [start, end).
; Args on stack: end (12 fp), start (9 fp)
_emit_range:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	lw	r2,9(fp)
_er_loop:
	lw	r1,12(fp)
	clu	r2,r1
	brf	_er_ret
	lbu	r0,0(r2)
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3
	add	r2,1
	bra	_er_loop
_er_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_operand: Emit one operand [start, end), rewriting it (or the
; displacement before a trailing "(reg)") to decimal when it is a symbol
; expression; otherwise emit it unchanged. Leading and trailing blanks are
; kept. Uses the scratch buffer at 197388.
; Args on stack: end (12 fp), start (9 fp)
; -3 text start  -6 text end  -9 value end (before "(reg)")
_emit_operand:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-9

	lw	r2,9(fp)
_eo_lead:
	lw	r1,12(fp)
	clu	r2,r1
	brt	_eo_raw_nr1
	la	r1,_eo_raw
	jmp	(r1)
_eo_raw_nr1:
	lbu	r0,0(r2)
	lc	r1,32
	ceq	r0,r1
	brt	_eo_lead_adv
	lc	r1,9
	ceq	r0,r1
	brf	_eo_lead_done
_eo_lead_adv:
	add	r2,1
	bra	_eo_lead
_eo_lead_done:
	sw	r2,-3(fp)
	lw	r2,12(fp)
_eo_trail:
	add	r2,-1
	lbu	r0,0(r2)
	lc	r1,32
	ceq	r0,r1
	brt	_eo_trail
	lc	r1,9
	ceq	r0,r1
	brt	_eo_trail
	add	r2,1
	sw	r2,-6(fp)
	sw	r2,-9(fp)

; trailing "(reg)": evaluate only the displacement in front of it
	add	r2,-1
	lbu	r0,0(r2)
	lc	r1,41
	ceq	r0,r1
	brf	_eo_copy
_eo_find_open:
	lw	r1,-3(fp)
	clu	r1,r2
	brf	_eo_copy
	add	r2,-1
	lbu	r0,0(r2)
	lc	r1,40
	ceq	r0,r1
	brf	_eo_find_open
	; r2 = '(' ; copy the inside and check that it is a register name
	mov	r1,r2
	add	r1,1
	la	r0,197388
	push	r2
	push	r0
_eo_reg_copy:
	lbu	r0,0(r1)
	lc	r2,41
	ceq	r0,r2
	brt	_eo_reg_end
	pop	r2
	sb	r0,0(r2)
	add	r2,1
	push	r2
	add	r1,1
	bra	_eo_reg_copy
_eo_reg_end:
	pop	r2
	lc	r0,0
	sb	r0,0(r2)
	pop	r2
	la	r0,197388
	push	r0
	la	r0,_reg_table
	push	r0
	la	r0,_lookup
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brt	_eo_copy
	sw	r2,-9(fp)

; copy the value text to the scratch buffer and try to evaluate it
_eo_copy:
	lw	r1,-3(fp)
	lw	r2,-9(fp)
	clu	r1,r2
	brf	_eo_raw
	la	r2,197388
_eo_copy_loop:
	lw	r0,-9(fp)
	clu	r1,r0
	brf	_eo_copy_done
	lbu	r0,0(r1)
	sb	r0,0(r2)
	add	r1,1
	add	r2,1
	bra	_eo_copy_loop
_eo_copy_done:
	lc	r0,0
	sb	r0,0(r2)
	la	r0,197388
	push	r0
	la	r0,_operand_value
	jal	r1,(r0)
	add	sp,3
	ceq	r0,z
	brt	_eo_raw

	lw	r0,-3(fp)
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_emit_range
	jal	r1,(r0)
	add	sp,6
	la	r1,786666
	lw	r0,0(r1)
	push	r0
	la	r0,_emit_sdec
	jal	r1,(r0)
	add	sp,3
	lw	r0,12(fp)
	push	r0
	lw	r0,-9(fp)
	push	r0
	la	r0,_emit_range
	jal	r1,(r0)
	add	sp,6
	bra	_eo_ret

_eo_raw:
	lw	r0,12(fp)
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_emit_range
	jal	r1,(r0)
	add	sp,6
_eo_ret:
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)

; _emit_subst_text: Emit a NUL-terminated source line plus CRLF. On
; instruction, .byte and .word lines, operands that are symbol expressions
; are emitted as decimal values (cor24-asm has no EQU); everything else is
; emitted unchanged.
; Arg on stack: line ptr (9 fp)
; -3 operand start  -6 scan ptr  -9 quote char (0 = none)  -12 paren depth
_emit_subst_text:
	push	fp
	push	r1
	push	r2
	mov	fp,sp
	add	sp,-12

	lw	r0,9(fp)
	push	r0
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	mov	r2,r0
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_est_raw_far
	lc	r1,59
	ceq	r0,r1
	brt	_est_raw_far

; skip an optional "label:" (the word must end in ':')
	mov	r1,r2
_est_lbl:
	lbu	r0,0(r1)
	push	r1
	push	r0
	la	r0,_is_macro_name_char
	jal	r1,(r0)
	add	sp,3
	pop	r1
	ceq	r0,z
	brt	_est_lbl_end
	add	r1,1
	bra	_est_lbl
_est_lbl_end:
	lbu	r0,0(r1)
	lc	r2,58
	ceq	r0,r2
	brf	_est_word_start
	add	r1,1
	push	r1
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	mov	r1,r0
	bra	_est_have_word
_est_word_start:
	lw	r0,9(fp)
	push	r0
	la	r0,_skip_ws_ptr
	jal	r1,(r0)
	add	sp,3
	mov	r1,r0
	bra	_est_have_word

_est_raw_far:
	la	r1,_est_raw
	jmp	(r1)

; r1 = start of the mnemonic or directive; copy it to the scratch buffer
_est_have_word:
	la	r2,197388
_est_wcopy:
	lbu	r0,0(r1)
	ceq	r0,z
	brt	_est_wdone
	push	r2
	lc	r2,32
	ceq	r0,r2
	pop	r2
	brt	_est_wdone
	push	r2
	lc	r2,9
	ceq	r0,r2
	pop	r2
	brt	_est_wdone
	push	r2
	lc	r2,59
	ceq	r0,r2
	pop	r2
	brt	_est_wdone
	sb	r0,0(r2)
	add	r1,1
	add	r2,1
	bra	_est_wcopy
_est_wdone:
	lc	r0,0
	sb	r0,0(r2)
	sw	r1,-3(fp)

	la	r0,197388
	push	r0
	la	r0,_mn_table
	push	r0
	la	r0,_lookup
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	_est_operands
	la	r0,_w_byte_txt
	push	r0
	la	r0,197388
	push	r0
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	_est_operands
	la	r0,_w_word_txt
	push	r0
	la	r0,197388
	push	r0
	la	r0,_streq
	jal	r1,(r0)
	add	sp,6
	ceq	r0,z
	brf	_est_raw_nr1
	la	r1,_est_raw
	jmp	(r1)
_est_raw_nr1:

; emit everything up to the operands unchanged, then each operand
_est_operands:
	lw	r0,-3(fp)
	push	r0
	lw	r0,9(fp)
	push	r0
	la	r0,_emit_range
	jal	r1,(r0)
	add	sp,6

_est_op_start:
	lw	r0,-3(fp)
	sw	r0,-6(fp)
	lc	r0,0
	sw	r0,-9(fp)
	sw	r0,-12(fp)
_est_scan:
	lw	r2,-6(fp)
	lbu	r0,0(r2)
	ceq	r0,z
	brt	_est_op_end
	lw	r1,-9(fp)
	ceq	r1,z
	brt	_est_noq
	ceq	r0,r1
	brf	_est_scan_adv
	lc	r1,0
	sw	r1,-9(fp)
	bra	_est_scan_adv
_est_noq:
	lc	r1,39
	ceq	r0,r1
	brt	_est_quote
	lc	r1,34
	ceq	r0,r1
	brt	_est_quote
	lc	r1,59
	ceq	r0,r1
	brt	_est_op_end
	lc	r1,40
	ceq	r0,r1
	brt	_est_open
	lc	r1,41
	ceq	r0,r1
	brt	_est_close
	lc	r1,44
	ceq	r0,r1
	brf	_est_scan_adv
	lw	r1,-12(fp)
	ceq	r1,z
	brt	_est_op_end
	bra	_est_scan_adv
_est_quote:
	sw	r0,-9(fp)
	bra	_est_scan_adv
_est_open:
	lw	r1,-12(fp)
	add	r1,1
	sw	r1,-12(fp)
	bra	_est_scan_adv
_est_close:
	lw	r1,-12(fp)
	add	r1,-1
	sw	r1,-12(fp)
_est_scan_adv:
	add	r2,1
	sw	r2,-6(fp)
	bra	_est_scan

; operand is [-3, -6); -6 points at ',', ';' or NUL
_est_op_end:
	lw	r0,-6(fp)
	push	r0
	lw	r0,-3(fp)
	push	r0
	la	r0,_emit_operand
	jal	r1,(r0)
	add	sp,6
	lw	r2,-6(fp)
	lbu	r0,0(r2)
	lc	r1,44
	ceq	r0,r1
	brf	_est_rest
	push	r0
	la	r0,_emit_char
	jal	r1,(r0)
	add	sp,3
	lw	r2,-6(fp)
	add	r2,1
	sw	r2,-3(fp)
	la	r1,_est_op_start
	jmp	(r1)

; the rest (a comment, or nothing) is emitted unchanged
_est_rest:
	lw	r0,-6(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
	bra	_est_crlf

_est_raw:
	lw	r0,9(fp)
	push	r0
	la	r0,_emit_strz
	jal	r1,(r0)
	add	sp,3
_est_crlf:
	la	r0,_emit_crlf
	jal	r1,(r0)
	mov	sp,fp
	pop	r2
	pop	r1
	pop	fp
	jmp	(r1)


; --- Capacity limits: _fatal messages ---
_fatal_txt:
	.byte	69,82,82,79,82,58,32,0

_err_line_long:
	.byte	105,110,112,117,116,32,108,105,110,101,32,108,111,110,103,101,114,32,116,104,97,110,32,50,53,54,32,99,104,97,114,97,99,116,101,114,115,0

_err_sym_full:
	.byte	115,121,109,98,111,108,32,116,97,98,108,101,32,111,118,101,114,102,108,111,119,32,40,53,49,50,32,115,121,109,98,111,108,115,41,0

_err_sym_long:
	.byte	115,121,109,98,111,108,32,110,97,109,101,32,108,111,110,103,101,114,32,116,104,97,110,32,51,49,32,99,104,97,114,97,99,116,101,114,115,0

_err_mac_full:
	.byte	109,97,99,114,111,32,116,97,98,108,101,32,111,118,101,114,102,108,111,119,32,40,50,53,54,32,109,97,99,114,111,115,41,0

_err_mac_long:
	.byte	109,97,99,114,111,32,110,97,109,101,32,108,111,110,103,101,114,32,116,104,97,110,32,51,49,32,99,104,97,114,97,99,116,101,114,115,0

_err_parm_full:
	.byte	109,111,114,101,32,116,104,97,110,32,49,54,32,109,97,99,114,111,32,112,97,114,97,109,101,116,101,114,115,0

_err_parm_long:
	.byte	109,97,99,114,111,32,112,97,114,97,109,101,116,101,114,32,110,97,109,101,32,108,111,110,103,101,114,32,116,104,97,110,32,51,49,32,99,104,97,114,97,99,116,101,114,115,0

_err_pool_full:
	.byte	109,97,99,114,111,32,98,111,100,121,32,112,111,111,108,32,111,118,101,114,102,108,111,119,32,40,54,53,53,51,54,32,98,121,116,101,115,41,0

_err_exp_long:
	.byte	101,120,112,97,110,100,101,100,32,109,97,99,114,111,32,108,105,110,101,32,108,111,110,103,101,114,32,116,104,97,110,32,50,53,54,32,99,104,97,114,97,99,116,101,114,115,0

_err_cond_deep:
	.byte	99,111,110,100,105,116,105,111,110,97,108,32,97,115,115,101,109,98,108,121,32,110,101,115,116,101,100,32,100,101,101,112,101,114,32,116,104,97,110,32,51,50,0

_err_if_deep:
	.byte	73,70,32,110,101,115,116,101,100,32,100,101,101,112,101,114,32,116,104,97,110,32,51,50,0

_err_do_deep:
	.byte	68,79,32,110,101,115,116,101,100,32,100,101,101,112,101,114,32,116,104,97,110,32,51,50,0

_err_sel_deep:
	.byte	83,69,76,69,67,84,32,110,101,115,116,101,100,32,100,101,101,112,101,114,32,116,104,97,110,32,51,50,0

_err_layout:
	.byte	104,108,97,115,109,32,105,109,97,103,101,32,111,118,101,114,108,97,112,115,32,105,116,115,32,116,97,98,108,101,115,32,40,108,97,121,111,117,116,32,99,104,101,99,107,41,0


_err_div_zero:
	.byte	100,105,118,105,115,105,111,110,32,98,121,32,122,101,114,111,32,105,110,32,101,120,112,114,101,115,115,105,111,110,0

_err_bad_escape:
	.byte	117,110,107,110,111,119,110,32,101,115,99,97,112,101,32,105,110,32,115,116,114,105,110,103,32,111,114,32,99,104,97,114,97,99,116,101,114,32,108,105,116,101,114,97,108,0

_err_mac_deep:
	.byte	109,97,99,114,111,32,99,97,108,108,115,32,110,101,115,116,101,100,32,100,101,101,112,101,114,32,116,104,97,110,32,56,0

_err_arg_full:
	.byte	109,111,114,101,32,116,104,97,110,32,49,54,32,109,97,99,114,111,32,97,114,103,117,109,101,110,116,115,0

_err_def_long:
	.byte	109,97,99,114,111,32,112,97,114,97,109,101,116,101,114,32,100,101,102,97,117,108,116,32,108,111,110,103,101,114,32,116,104,97,110,32,54,51,32,99,104,97,114,97,99,116,101,114,115,0

_err_inc_deep:
	.byte	73,78,67,76,85,68,69,32,110,101,115,116,101,100,32,100,101,101,112,101,114,32,116,104,97,110,32,49,54,0
_err_cond_undef:
	.byte	73,70,69,81,47,73,70,78,69,32,111,112,101,114,97,110,100,32,105,115,32,110,111,116,32,97,32,83,69,84,32,111,114,32,69,81,85,32,115,121,109,98,111,108,0
_err_bad_cc:
	.byte	117,110,107,110,111,119,110,32,115,116,114,117,99,116,117,114,101,100,32,99,111,110,100,105,116,105,111,110,0

_err_cfg_full:
	.byte	115,111,117,114,99,101,32,99,111,110,102,105,103,32,104,97,115,32,109,111,114,101,32,116,104,97,110,32,51,50,32,109,101,109,98,101,114,115,0

_loc_main_txt:
	.byte	109,97,105,110,0

_loc_slot_txt:
	.byte	115,108,111,116,0

_loc_colon_txt:
	.byte	58,0

_loc_sep_txt:
	.byte	58,32,0

_sysndx_txt:
	.byte	83,89,83,78,68,88,0

_sysnarg_txt:
	.byte	83,89,83,78,65,82,71,0

_w_byte_txt:
	.byte	46,98,121,116,101,0

_w_word_txt:
	.byte	46,119,111,114,100,0

; Powers of ten for _emit_dec24 and _emit_num4_to_buf (0-terminated).
_dec_pow:
	.word	10000000,1000000,100000,10000,1000,100,10,1,0

; --- Buffers ---
_id_buf:
	.byte 0, 0, 0, 0, 0, 0, 0, 0
	.byte 0, 0, 0, 0, 0, 0, 0, 0

; Relax pass: 0 = sizing pass (output suppressed), 1 = emitting pass.
; Saved with the data at pass-1 start and restored to 0 before being set to 1.
_relax_pass:
	.word	0


_kw_macro:
	.byte	77,65,67,82,79,0

_kw_mend:
	.byte	77,69,78,68,0

_kw_prefix_table:
	.byte	77,65,67,82,79,0
	.byte	77,69,78,68,0
	.byte	73,70,0
	.byte	69,76,83,69,73,70,0
	.byte	69,76,83,69,0
	.byte	69,78,68,73,70,0
	.byte	68,79,0
	.byte	68,79,69,88,73,84,0
	.byte	73,84,69,82,65,84,69,0
	.byte	69,78,68,68,79,0
	.byte	83,69,76,69,67,84,0
	.byte	87,72,69,78,0
	.byte	79,84,72,69,82,87,73,83,69,0
	.byte	69,78,68,83,69,76,0
	.byte	0

; --- Step 7: Conditional assembly data ---
_kw_set:
	.byte	83,69,84,0

_kw_equ:
	.byte	69,81,85,0

_kw_include:
	.byte	73,78,67,76,85,68,69,0

_kw_copy:
	.byte	67,79,80,89,0

_kw_incbuf:
	.byte	73,78,67,66,85,70,0

_kw_srcbuf:
	.byte	83,82,67,66,85,70,0

_dot_ascii_txt:
	.byte	46,97,115,99,105,105,0

_dot_asciz_txt:
	.byte	46,97,115,99,105,122,0

_dot_space_txt:
	.byte	46,115,112,97,99,101,0

_dot_fill_txt:
	.byte	46,102,105,108,108,0

_dot_byte_txt:
	.byte	46,98,121,116,101,32,0

_kw_ifdef:
	.byte	73,70,68,69,70,0

_kw_ifndef:
	.byte	73,70,78,68,69,70,0

_kw_ifeq:
	.byte	73,70,69,81,0

_kw_ifne:
	.byte	73,70,78,69,0

_kw_ifsame:
	.byte	73,70,83,65,77,69,0

_kw_ifdiff:
	.byte	73,70,68,73,70,70,0

_kw_if:
	.byte	73,70,0

_kw_elseif:
	.byte	69,76,83,69,73,70,0

_kw_else:
	.byte	69,76,83,69,0

_kw_endif:
	.byte	69,78,68,73,70,0

_kw_do:
	.byte	68,79,0

_kw_doexit:
	.byte	68,79,69,88,73,84,0

_kw_iterate:
	.byte	73,84,69,82,65,84,69,0

_kw_enddo:
	.byte	69,78,68,68,79,0

_kw_select:
	.byte	83,69,76,69,67,84,0

_kw_when:
	.byte	87,72,69,78,0

_kw_otherwise:
	.byte	79,84,72,69,82,87,73,83,69,0

_kw_endsel:
	.byte	69,78,68,83,69,76,0

_then_txt:
	.byte	84,72,69,78,0

_kw_elseasm:
	.byte	69,76,83,69,65,83,77,0

_kw_endifasm:
	.byte	69,78,68,73,70,65,83,77,0


; --- Runtime memory map (see docs/limits-and-lifting-plan.md) ---
; Every table below has a capacity check that stops with "ERROR: ..." via
; _fatal; nothing overflows silently.
;
; 0x010000 (65536)   symbol table: 512 x 40 bytes (name + NUL at +0, value +32)
; 0x018000 (98304)   macro table: 256 x 39 bytes (name + NUL at +0,
;                    body start +33, body end +36)
; 0x020000 (131072)  macro body pool, to 0x02FFFF (64 KB)
; 0x030000 (196608)  work area, cleared at each pass start (4576 bytes):
;   196608 input line (256 chars + NUL; 260 bytes)
;   196868 scanner token buffer (260)
;   197128 _parse_name_buf (260)
;   197388 spare (260)
;   197648 IF/DO cc buffer (260)
;   197908 lhs buffer (260)
;   198168 rhs buffer (260)
;   198428 SELECT WHEN scratch buffer (260)
;   198688 macro expansion buffer (1024; lines limited to 256)
;   199712 conditional-assembly stack: 32 x 3 bytes
;   199808 IF frame stack: 32 x 9 bytes
;          +0 false label id, +3 end label id, +6 else seen
;   200096 DO frame stack: 32 x 6 bytes (+0 top label id, +3 end label id)
;   200288 SELECT frame stack: 32 x 12 bytes
;          +0 next label id, +3 end label id, +6 arm open, +9 otherwise seen
;   200672 macro parameter names: 16 x 32 bytes
; 201216             SELECT selector strings: 32 x 256 bytes
; 209408 / 209668 / 209928  name save buffers for _symbol_enabled,
;                    _handle_equ and _set_symbol (260 each)
; 0x034000 (212992)  XREF symbol names: 512 x 32 bytes
; 0x038000 (229376)  HLDIAG undefined-symbol names: 64 x 32 bytes
; 0x039000 (233472)  macro expansion frames: 8 x 64 bytes, depth at 790719
;                    (see "Macro expansion stack")
; 0x039200 (233984)  argument strings per frame: 8 x 512 bytes
; 0x03A200 (238080)  parameter defaults while parsing a MACRO line: 16 x 64
; 0x03A600 (239104)  source descriptors: 33 x 12 bytes (base, length,
;                    position, line number); slot 0 is the main source
; 0x0C0000 arena:    786597 source count, 786600 current slot, 787734
;                    include return depth, 787737 return slots (16 x 3)
; 0x038800 (231424)  XREF macro expansion counters: 256 x 3 bytes (cleared
;                    at each pass start)
; 0x0C0000 (786432)  arena of counters and source state (4700 bytes, cleared
;                    at each pass start); e.g. 787560 symbol count, 786645
;                    macro count, 787707 cond depth, 787807/787933/787984
;                    IF/DO/SELECT depth, 787810 next structured label id
; 0x0D0000 / 0x0E0000  relax snapshot and tables (see _relax_begin_pass)

_push_txt:
	.byte	112,117,115,104,0

_pop_txt:
	.byte	112,111,112,0

_la_txt:
	.byte	108,97,0

_lc_txt:
	.byte	108,99,0

_ceq_txt:
	.byte	99,101,113,0

_cls_txt:
	.byte	99,108,115,0

_clu_txt:
	.byte	99,108,117,0

_bra_txt:
	.byte	98,114,97,0

_jmp_txt:
	.byte	106,109,112,0

_brf_txt:
	.byte	98,114,102,0

_brt_txt:
	.byte	98,114,116,0

_r1_txt:
	.byte	114,49,0

_r2_txt:
	.byte	114,50,0

_ann_symbol_name:
	.byte	72,76,65,78,78,0

_list_symbol_name:
	.byte	72,76,73,83,84,0

_ann_prefix_txt:
	.byte	59,32,72,76,65,83,77,32,0

_expand_txt:
	.byte	69,88,80,65,78,68,0

_missing_txt:
	.byte	77,73,83,83,73,78,71,0

_cc_eq_txt:
	.byte	99,99,95,101,113,0

_cc_ne_txt:
	.byte	99,99,95,110,101,0

_cc_lt_txt:
	.byte	99,99,95,108,116,0

_cc_lu_txt:
	.byte	99,99,95,108,117,0

_cc_zset_txt:
	.byte	99,99,95,122,115,101,116,0

_cc_zclr_txt:
	.byte	99,99,95,122,99,108,114,0

_if_label_prefix:
	.byte	95,104,108,105,102,95,0

_if_false_suffix:
	.byte	95,102,97,108,115,101,0

_if_end_suffix:
	.byte	95,101,110,100,0

_if_skip_suffix:
	.byte	95,115,107,105,112,0

_do_label_prefix:
	.byte	95,104,108,100,111,95,0

_do_top_suffix:
	.byte	95,116,111,112,0

_do_end_suffix:
	.byte	95,101,110,100,0

_do_skip_suffix:
	.byte	95,115,107,105,112,0

_sel_label_prefix:
	.byte	95,104,108,115,101,108,95,0

_sel_next_suffix:
	.byte	95,110,101,120,116,0

_sel_end_suffix:
	.byte	95,101,110,100,0

_sel_skip_suffix:
	.byte	95,115,107,105,112,0

_xref_copy_used:
	.byte	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	.byte	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0


_xref_symbol_count:
	.word	0


_xref_symbol_name:
	.byte	72,76,88,82,69,70,0

_xref_switch:
	.word	0

_xref_prefix_txt:
	.byte	59,32,72,76,65,83,77,32,88,82,69,70,32,0

_xref_begin_txt:
	.byte	59,32,72,76,65,83,77,32,88,82,69,70,32,66,69,71,73,78,0

_xref_end_txt:
	.byte	59,32,72,76,65,83,77,32,88,82,69,70,32,69,78,68,0

_xref_copy_txt:
	.byte	67,79,80,89,0

_xref_macro_txt:
	.byte	77,65,67,82,79,0

_xref_expand_txt:
	.byte	69,88,80,65,78,68,0

_xref_symbol_txt:
	.byte	83,89,77,66,79,76,0

_hldiag_symbol_name:
	.byte	72,76,68,73,65,71,0

_hldiag_switch:
	.word	0

_hldiag_line_no:
	.word	0

_hldiag_src_id:
	.word	0

_hldiag_prefix_txt:
	.byte	59,32,33,33,32,104,108,97,115,109,58,32,0

_hldiag_at_src_txt:
	.byte	32,97,116,32,115,114,99,0

_hldiag_colon_txt:
	.byte	58,0

_hldiag_banner_msg:
	.byte	72,76,68,73,65,71,32,97,99,116,105,118,101,0

_hldiag_unknown_mn_txt:
	.byte	117,110,107,110,111,119,110,32,109,110,101,109,111,110,105,99,32,39,0

_hldiag_quote_txt:
	.byte	39,0

_hldiag_undef_sym_txt:
	.byte	117,110,100,101,102,105,110,101,100,32,115,121,109,98,111,108,32,39,0

_xref_undef_count:
	.word	0


; Must stay last: end of the mutable data saved between relax passes.
_image_end:
