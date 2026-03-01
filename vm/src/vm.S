.equ UART0_BASE, 0x10000000
.equ UART_RBR, 0
.equ UART_THR, 0
.equ UART_LSR, 5
.equ UART_LSR_DR, 0x01
.equ UART_LSR_THRE, 0x20

.equ VM_STACK_BYTES, 4096
.equ VM_METHOD_STACK_MAX, 64
.equ VM_IMAGE_BUFFER_BYTES, 131072
.equ VM_SYMBOL_STORAGE_BYTES, 8192
.equ VM_BLOCK_STORAGE_BYTES, 32768
.equ IMAGE_MIN_BYTES, 8640

.equ BC_OP_HALT, 0
.equ BC_OP_LOAD_CONST, 1
.equ BC_OP_DUP, 2
.equ BC_OP_POP, 3
.equ BC_OP_SEND, 4
.equ BC_OP_RETURN, 5
.equ BC_OP_LOAD_REF, 6
.equ BC_OP_STORE_REF, 7

.equ BC_CONST_INT, 0
.equ BC_CONST_SYMBOL, 1
.equ BC_CONST_STRING, 2
.equ BC_CONST_FLOAT, 3
.equ BC_CONST_SCALED_DECIMAL, 4
.equ BC_CONST_BLOCK, 5
.equ BC_CONST_OBJECT_ARRAY, 6
.equ BC_CONST_BYTE_ARRAY, 7

.equ PRIM_NOOP, 0
.equ PRIM_UART_PUTC, 1
.equ PRIM_DEBUG_BREAK, 2
.equ PRIM_PRINT_INT, 10
.equ PRIM_ADD_INT, 11
.equ PRIM_SUB_INT, 12
.equ PRIM_MUL_INT, 13
.equ PRIM_DIV_INT, 14
.equ PRIM_CLONE_OBJECT, 20
.equ PRIM_SLOT_NAME, 24
.equ PRIM_SLOT_VALUE, 25
.equ PRIM_SLOT_VALUE_PUT, 26
.equ PRIM_ADD_SLOT, 27
.equ PRIM_SLOT_NAMED, 28
.equ PRIM_ADD_METHOD, 29
.equ PRIM_PRIMITIVE_FAILED, 31
.equ PRIM_BYTES_SIZE, 40
.equ PRIM_BYTES_AT, 41
.equ PRIM_BYTES_AT_PUT, 42
.equ PRIM_OBJECT_ARRAY_SIZE, 43
.equ PRIM_OBJECT_ARRAY_AT, 44
.equ PRIM_OBJECT_ARRAY_AT_PUT, 45
.equ PRIM_BLOCK_VALUE, 46
.equ PRIM_BLOCK_VALUE_ARG, 47
.equ PRIM_PRINT_CANNOT_RETURN, 48
.equ PRIM_ON_CANNOT_RETURN, 49
.equ PRIM_HANDLE_CANNOT_RETURN, 50
.equ PRIM_DOES_NOT_UNDERSTAND_ARGC, 51
.equ PRIM_SAVE_IMAGE, 128
.equ PRIM_LOAD_IMAGE, 129
.equ PRIM_EXPORT_IMAGE, 130
.equ PRIM_IMPORT_IMAGE, 131
.equ PRIM_SAVE_IMAGE_TO_HOST, 132
.equ PRIM_LOAD_IMAGE_FROM_HOST, 133

.equ BLOCK_OP_END, 0
.equ BLOCK_OP_PUSH_SELF, 1
.equ BLOCK_OP_PUSH_ARG, 2
.equ BLOCK_OP_PUSH_CONST, 3
.equ BLOCK_OP_SEND, 4
.equ BLOCK_OP_DUP, 5
.equ BLOCK_OP_POP, 6
.equ BLOCK_OP_PUSH_REF, 7
.equ BLOCK_OP_STORE_REF, 8
.equ BLOCK_OP_PUSH_LOCAL, 9
.equ BLOCK_OP_STORE_LOCAL, 10
.equ BLOCK_OP_RETURN, 11

.equ BLOCK_CONST_INT, 0
.equ BLOCK_CONST_SYMBOL, 1
.equ BLOCK_CONST_STRING, 2
.equ BLOCK_CONST_BLOCK, 3

.equ OBJ_PROTO, 0
.equ OBJ_SLOT_COUNT, 8
.equ OBJ_SLOTS, 16
.equ OBJ_FIXED_SLOTS, 16
.equ OBJ_BYTES, 144

.section .text

.globl vm_boot
.globl vm_interpreter_loop
.globl uart_putc
.globl uart_puts
.globl uart_putint
.globl primitive_dispatch

.extern recorz_program_blob

vm_boot:
  la a0, boot_message
  call uart_puts

  li a0, 0
  call primitive_dispatch

  la a0, primitive_ready_message
  call uart_puts

  la a0, recorz_program_blob
  call vm_interpreter_loop

  la a0, vm_done_message
  call uart_puts
  ret

# a0 = pointer to RCBC program blob
vm_interpreter_loop:
  addi sp, sp, -128
  sd ra, 120(sp)
  sd s0, 112(sp)
  sd s1, 104(sp)
  sd s2, 96(sp)
  sd s3, 88(sp)
  sd s4, 80(sp)
  sd s5, 72(sp)
  sd s6, 64(sp)
  sd s7, 56(sp)
  sd s8, 48(sp)
  sd s9, 40(sp)
  sd s10, 32(sp)
  sd s11, 24(sp)

  mv s0, a0

  la a0, loop_message
  call uart_puts

  # Validate magic: 'R' 'C' 'B' 'C'
  lbu t0, 0(s0)
  li t1, 'R'
  bne t0, t1, vm_bad_header
  lbu t0, 1(s0)
  li t1, 'C'
  bne t0, t1, vm_bad_header
  lbu t0, 2(s0)
  li t1, 'B'
  bne t0, t1, vm_bad_header
  lbu t0, 3(s0)
  li t1, 'C'
  bne t0, t1, vm_bad_header

  # Version must be 2.
  lbu t0, 4(s0)
  li t1, 2
  bne t0, t1, vm_bad_header

  # Header counts.
  lbu s7, 5(s0)     # constant count
  lbu s8, 6(s0)     # selector count
  lbu s6, 7(s0)     # instruction count

  # Reset runtime allocation/interning state for this run.
  la t0, vm_heap_ptr
  la t1, vm_heap
  sd t1, 0(t0)
  la t0, vm_symbol_count
  sd zero, 0(t0)
  la t0, vm_cannot_return_value
  sd zero, 0(t0)

  # Decode constants into runtime values table.
  addi s9, s0, 8
  la s1, vm_constants_values
  li s11, 0

constant_decode_loop:
  bgeu s11, s7, constant_decode_done

  lbu t0, 0(s9)     # constant kind
  addi s9, s9, 1

  li t1, BC_CONST_INT
  beq t0, t1, constant_decode_int
  li t1, BC_CONST_SYMBOL
  beq t0, t1, constant_decode_symbol
  li t1, BC_CONST_STRING
  beq t0, t1, constant_decode_string
  li t1, BC_CONST_FLOAT
  beq t0, t1, constant_decode_float
  li t1, BC_CONST_SCALED_DECIMAL
  beq t0, t1, constant_decode_scaled_decimal
  li t1, BC_CONST_BLOCK
  beq t0, t1, constant_decode_block
  li t1, BC_CONST_OBJECT_ARRAY
  beq t0, t1, constant_decode_object_array
  li t1, BC_CONST_BYTE_ARRAY
  beq t0, t1, constant_decode_byte_array
  j vm_bad_header

constant_decode_int:
  ld t1, 0(s9)
  addi s9, s9, 8
  slli t1, t1, 1
  ori t1, t1, 1
  j constant_decode_store

constant_decode_symbol:
  lbu t2, 0(s9)     # symbol byte length
  addi s9, s9, 1
  mv s10, t2
  mv a0, s9
  mv a1, s10
  call vm_intern_symbol
  bnez a0, vm_bad_header
  mv t1, a1
  add s9, s9, s10
  j constant_decode_store

constant_decode_string:
  lbu t2, 0(s9)     # string byte length
  addi s9, s9, 1
  mv s10, t2
  mv a0, s9
  mv a1, s10
  call vm_make_string_object
  bnez a0, vm_bad_header
  mv t1, a1
  add s9, s9, s10
  j constant_decode_store

constant_decode_float:
  mv a0, s9
  li a1, 8
  call vm_make_float_object
  bnez a0, vm_bad_header
  mv t1, a1
  addi s9, s9, 8
  j constant_decode_store

constant_decode_scaled_decimal:
  lbu t2, 0(s9)     # scaled decimal byte length
  addi s9, s9, 1
  mv s10, t2
  mv a0, s9
  mv a1, s10
  call vm_make_scaled_decimal_object
  bnez a0, vm_bad_header
  mv t1, a1
  add s9, s9, s10
  j constant_decode_store

constant_decode_block:
  lbu t2, 0(s9)
  lbu t3, 1(s9)
  slli t3, t3, 8
  or t2, t2, t3     # block payload length (u16)
  addi s9, s9, 2
  mv s10, t2
  mv a0, s9
  mv a1, s10
  li a2, 0
  call vm_make_block_object
  bnez a0, vm_bad_header
  mv t1, a1
  add s9, s9, s10
  j constant_decode_store

constant_decode_object_array:
  lbu t2, 0(s9)
  lbu t3, 1(s9)
  slli t3, t3, 8
  or t2, t2, t3     # object-array payload length (u16)
  addi s9, s9, 2
  mv s10, t2
  mv a0, s9
  mv a1, s10
  call vm_make_object_array_object
  bnez a0, vm_bad_header
  mv t1, a1
  add s9, s9, s10
  j constant_decode_store

constant_decode_byte_array:
  lbu t2, 0(s9)
  lbu t3, 1(s9)
  slli t3, t3, 8
  or t2, t2, t3     # byte-array payload length (u16)
  addi s9, s9, 2
  mv s10, t2
  mv a0, s9
  mv a1, s10
  call vm_make_byte_array_object
  bnez a0, vm_bad_header
  mv t1, a1
  add s9, s9, s10

constant_decode_store:
  slli t3, s11, 3
  add t3, s1, t3
  sd t1, 0(t3)
  addi s11, s11, 1
  j constant_decode_loop

constant_decode_done:
  mv s2, s9         # selectors base

  # Find instruction stream base by walking selector entries.
  mv t5, s2         # selector walker pointer
  li t6, 0          # selector index

selector_scan_loop:
  bgeu t6, s8, selector_scan_done

  lbu t0, 0(t5)     # selector length
  addi t5, t5, 1
  add t5, t5, t0
  addi t6, t6, 1
  j selector_scan_loop

selector_scan_done:
  mv s3, t5         # instructions base

  # Reset global binding validity for this run.
  la t0, vm_globals_valid
  li t1, 0
clear_globals_loop:
  li t2, 256
  bgeu t1, t2, clear_globals_done
  sb zero, 0(t0)
  addi t0, t0, 1
  addi t1, t1, 1
  j clear_globals_loop
clear_globals_done:
  call vm_init_bootstrap_globals

  la s4, vm_stack   # stack top pointer (next free slot)
  li s5, 0          # instruction pointer index

interpreter_loop:
  bgeu s5, s6, interpreter_done

  slli t0, s5, 2
  add t1, s3, t0

  lbu t2, 0(t1)     # opcode
  lbu t3, 1(t1)     # op1
  lbu t4, 2(t1)     # op2

  li t0, BC_OP_HALT
  beq t2, t0, interpreter_done

  li t0, BC_OP_LOAD_CONST
  beq t2, t0, op_load_const

  li t0, BC_OP_DUP
  beq t2, t0, op_dup

  li t0, BC_OP_POP
  beq t2, t0, op_pop

  li t0, BC_OP_SEND
  beq t2, t0, op_send

  li t0, BC_OP_RETURN
  beq t2, t0, interpreter_done

  li t0, BC_OP_LOAD_REF
  beq t2, t0, op_load_ref

  li t0, BC_OP_STORE_REF
  beq t2, t0, op_store_ref

  j vm_bad_opcode

op_load_const:
  slli t0, t3, 3
  add t0, s1, t0
  ld t1, 0(t0)
  sd t1, 0(s4)
  addi s4, s4, 8
  j op_advance

op_dup:
  la t0, vm_stack
  beq s4, t0, vm_stack_underflow
  ld t1, -8(s4)
  sd t1, 0(s4)
  addi s4, s4, 8
  j op_advance

op_pop:
  la t0, vm_stack
  beq s4, t0, vm_stack_underflow
  addi s4, s4, -8
  j op_advance

op_send:
  mv s10, t3              # selector index (preserved across calls)
  beqz t4, op_send_unary
  li t0, 1
  beq t4, t0, op_send_binary
  li t0, 2
  beq t4, t0, op_send_keyword2
  j op_send_nary

op_send_unary:
  la t0, vm_stack
  beq s4, t0, vm_stack_underflow

  # Lookup primitive in receiver prototype chain.
  ld a0, -8(s4)           # receiver value
  mv a1, s10              # selector index
  call vm_lookup_method_primitive
  bltz a0, op_send_unary_dynamic

  mv t0, a0               # primitive id
  ld a1, -8(s4)           # receiver value
  li a2, 0
  li a3, 0
  mv a0, t0
  call primitive_dispatch

  li t1, -6
  beq a0, t1, op_send_unary_cannot_return
  bnez a0, op_send_unary_fallback

  # Replace receiver with result.
  sd a1, -8(s4)
  j op_advance

op_send_unary_dynamic:
  ld s7, -8(s4)           # receiver value (preserved across helper call)
  mv a0, s7               # receiver
  mv a1, s10              # selector index
  li a2, 0                # args ptr
  li a3, 0                # argc
  call vm_invoke_dynamic_method_block
  li t1, -6
  beq a0, t1, op_send_unary_cannot_return
  bnez a0, op_send_unary_fallback
  sd a1, -8(s4)
  j op_advance

op_send_unary_cannot_return:
  call vm_make_cannot_return_value
  bnez a0, vm_primitive_failed
  sd a1, -8(s4)
  j op_advance

op_send_unary_fallback:
  ld a0, -8(s4)           # receiver value
  mv a1, s10              # selector index
  li a2, 0                # argc
  call vm_invoke_does_not_understand
  bnez a0, vm_primitive_failed
  sd a1, -8(s4)
  j op_advance

op_send_binary:
  la t0, vm_stack
  addi t1, t0, 16
  bltu s4, t1, vm_stack_underflow

  # Lookup primitive in receiver prototype chain.
  ld a0, -16(s4)          # receiver value
  mv a1, s10              # selector index
  call vm_lookup_method_primitive
  bltz a0, op_send_binary_dynamic

  mv t0, a0               # primitive id
  ld a1, -16(s4)          # receiver value
  ld a2, -8(s4)           # argument value
  li a3, 0
  mv a0, t0
  call primitive_dispatch

  li t1, -6
  beq a0, t1, op_send_binary_cannot_return
  bnez a0, op_send_binary_fallback

  # Pop receiver+arg and push primitive result.
  addi s4, s4, -16
  sd a1, 0(s4)
  addi s4, s4, 8
  j op_advance

op_send_binary_dynamic:
  ld s7, -16(s4)          # receiver value (preserved across helper call)
  addi t0, s4, -8         # args ptr
  mv a0, s7               # receiver
  mv a1, s10              # selector index
  mv a2, t0               # args ptr
  li a3, 1                # argc
  call vm_invoke_dynamic_method_block
  li t1, -6
  beq a0, t1, op_send_binary_cannot_return
  bnez a0, op_send_binary_fallback

  addi s4, s4, -16
  sd a1, 0(s4)
  addi s4, s4, 8
  j op_advance

op_send_binary_cannot_return:
  call vm_make_cannot_return_value
  bnez a0, vm_primitive_failed
  addi s4, s4, -16
  sd a1, 0(s4)
  addi s4, s4, 8
  j op_advance

op_send_binary_fallback:
  ld a0, -16(s4)          # receiver value
  mv a1, s10              # selector index
  li a2, 1                # argc
  call vm_invoke_does_not_understand
  bnez a0, vm_primitive_failed
  addi s4, s4, -16
  sd a1, 0(s4)
  addi s4, s4, 8
  j op_advance

op_send_keyword2:
  la t0, vm_stack
  addi t1, t0, 24
  bltu s4, t1, vm_stack_underflow

  # Lookup primitive in receiver prototype chain.
  ld a0, -24(s4)          # receiver value
  mv a1, s10              # selector index
  call vm_lookup_method_primitive
  bltz a0, op_send_keyword2_dynamic

  mv t0, a0               # primitive id
  ld a1, -24(s4)          # receiver value
  ld a2, -16(s4)          # arg0 value
  ld a3, -8(s4)           # arg1 value
  mv a0, t0
  call primitive_dispatch

  li t1, -6
  beq a0, t1, op_send_keyword2_cannot_return
  bnez a0, op_send_keyword2_fallback

  # Pop receiver+2 args and push primitive result.
  addi s4, s4, -24
  sd a1, 0(s4)
  addi s4, s4, 8
  j op_advance

op_send_keyword2_dynamic:
  ld s7, -24(s4)          # receiver value (preserved across helper call)
  addi t0, s4, -16        # args ptr
  mv a0, s7               # receiver
  mv a1, s10              # selector index
  mv a2, t0               # args ptr
  li a3, 2                # argc
  call vm_invoke_dynamic_method_block
  li t1, -6
  beq a0, t1, op_send_keyword2_cannot_return
  bnez a0, op_send_keyword2_fallback

  addi s4, s4, -24
  sd a1, 0(s4)
  addi s4, s4, 8
  j op_advance

op_send_keyword2_cannot_return:
  call vm_make_cannot_return_value
  bnez a0, vm_primitive_failed
  addi s4, s4, -24
  sd a1, 0(s4)
  addi s4, s4, 8
  j op_advance

op_send_keyword2_fallback:
  ld a0, -24(s4)          # receiver value
  mv a1, s10              # selector index
  li a2, 2                # argc
  call vm_invoke_does_not_understand
  bnez a0, vm_primitive_failed
  addi s4, s4, -24
  sd a1, 0(s4)
  addi s4, s4, 8
  j op_advance

op_send_nary:
  # Requires at least receiver + argc arguments on stack.
  addi t0, t4, 1          # value count: receiver + args
  slli t0, t0, 3          # bytes required
  la t1, vm_stack
  add t1, t1, t0
  bltu s4, t1, vm_stack_underflow

  sub t2, s4, t0          # receiver slot ptr
  ld s7, 0(t2)            # receiver value
  addi t3, t2, 8          # args ptr

  addi sp, sp, -16
  sd t0, 8(sp)            # save byte width for stack rewrite
  mv a0, s7               # receiver
  mv a1, s10              # selector index
  mv a2, t3               # args ptr
  mv a3, t4               # argc
  call vm_invoke_dynamic_method_block
  ld t0, 8(sp)
  addi sp, sp, 16
  li t1, -6
  beq a0, t1, op_send_nary_cannot_return
  bnez a0, op_send_nary_fallback

  sub s4, s4, t0
  sd a1, 0(s4)
  addi s4, s4, 8
  j op_advance

op_send_nary_cannot_return:
  addi sp, sp, -16
  sd t0, 8(sp)            # preserve byte width across helper call
  call vm_make_cannot_return_value
  ld t0, 8(sp)
  addi sp, sp, 16
  bnez a0, vm_primitive_failed
  sub s4, s4, t0
  sd a1, 0(s4)
  addi s4, s4, 8
  j op_advance

op_send_nary_fallback:
  mv a0, s7               # receiver value
  mv a1, s10              # selector index
  srli a2, t0, 3
  addi a2, a2, -1         # argc
  addi sp, sp, -16
  sd t0, 8(sp)            # preserve byte width across fallback send helper
  call vm_invoke_does_not_understand
  ld t0, 8(sp)
  addi sp, sp, 16
  bnez a0, vm_primitive_failed
  sub s4, s4, t0
  sd a1, 0(s4)
  addi s4, s4, 8
  j op_advance

# a0=receiver value, a1=selector index -> a0=primitive id or -1
vm_lookup_method_primitive:
  addi sp, sp, -24
  sd ra, 16(sp)
  sd a0, 8(sp)
  sd a1, 0(sp)

  mv a0, a1
  call vm_get_selector_by_index
  bltz a2, vm_lookup_method_not_found

  mv t0, a0               # selector ptr
  mv t1, a1               # selector length
  ld t2, 8(sp)            # receiver value
  beqz t2, vm_lookup_method_not_found
  andi t3, t2, 1
  beqz t3, vm_lookup_method_object
  la a0, proto_integer
  j vm_lookup_method_chain

vm_lookup_method_object:
  ld a0, OBJ_PROTO(t2)
  beqz a0, vm_lookup_method_not_found

vm_lookup_method_chain:
  mv a1, t0
  mv a2, t1
  call vm_lookup_proto_chain
  j vm_lookup_method_done

vm_lookup_method_not_found:
  li a0, -1

vm_lookup_method_done:
  ld ra, 16(sp)
  addi sp, sp, 24
  ret

# a0=receiver value, a1=selector index, a2=args ptr, a3=argc -> a0=status, a1=result
vm_invoke_dynamic_method_block:
  addi sp, sp, -96
  sd ra, 88(sp)
  sd a0, 80(sp)           # receiver
  sd a1, 72(sp)           # selector index
  sd a2, 64(sp)           # args ptr
  sd a3, 56(sp)           # argc
  sd zero, 48(sp)         # method token
  sd zero, 40(sp)         # stack-push marker

  call vm_method_token_alloc
  beqz a0, vm_invoke_dynamic_method_fail
  sd a0, 48(sp)
  call vm_method_token_stack_push
  bnez a0, vm_invoke_dynamic_method_fail
  li t0, 1
  sd t0, 40(sp)

  ld a0, 80(sp)           # receiver
  ld a1, 72(sp)           # selector index
  call vm_lookup_dynamic_method_block
  beqz a0, vm_invoke_dynamic_method_not_found

  mv t0, a0               # method block object
  ld a1, 80(sp)           # lexical self = receiver
  ld a2, 64(sp)           # args ptr
  ld a3, 56(sp)           # argc
  mv a0, t0               # block object
  call vm_eval_block
  li t1, 1
  bne a0, t1, vm_invoke_dynamic_method_done
  # Resolve non-local return at the home method boundary only.
  la t0, vm_pending_return_token
  ld t2, 0(t0)
  ld t3, 48(sp)
  bne t2, t3, vm_invoke_dynamic_method_done
  sd zero, 0(t0)
  li a0, 0
  j vm_invoke_dynamic_method_done

vm_invoke_dynamic_method_not_found:
  li a0, -1
  li a1, 0
  j vm_invoke_dynamic_method_done

vm_invoke_dynamic_method_fail:
  li a0, -1
  li a1, 0

vm_invoke_dynamic_method_done:
  ld t0, 40(sp)
  beqz t0, vm_invoke_dynamic_method_done_nopop
  sd a0, 24(sp)
  sd a1, 16(sp)
  call vm_method_token_stack_pop
  ld a0, 24(sp)
  ld a1, 16(sp)
vm_invoke_dynamic_method_done_nopop:
  ld ra, 88(sp)
  addi sp, sp, 96
  ret

# a0=receiver value, a1=selector bytes ptr, a2=selector len, a3=args ptr, a4=argc
# -> a0=status, a1=result
vm_invoke_dynamic_method_block_literal:
  addi sp, sp, -112
  sd ra, 104(sp)
  sd a0, 96(sp)           # receiver
  sd a1, 88(sp)           # selector bytes ptr
  sd a2, 80(sp)           # selector len
  sd a3, 72(sp)           # args ptr
  sd a4, 64(sp)           # argc
  sd zero, 56(sp)         # method token
  sd zero, 48(sp)         # stack-push marker

  call vm_method_token_alloc
  beqz a0, vm_invoke_dynamic_method_literal_fail
  sd a0, 56(sp)
  call vm_method_token_stack_push
  bnez a0, vm_invoke_dynamic_method_literal_fail
  li t0, 1
  sd t0, 48(sp)

  ld a0, 96(sp)           # receiver
  ld a1, 88(sp)           # selector bytes ptr
  ld a2, 80(sp)           # selector len
  call vm_lookup_dynamic_method_block_literal
  beqz a0, vm_invoke_dynamic_method_literal_not_found

  mv t0, a0               # method block object
  ld a1, 96(sp)           # lexical self = receiver
  ld a2, 72(sp)           # args ptr
  ld a3, 64(sp)           # argc
  mv a0, t0               # block object
  call vm_eval_block
  li t1, 1
  bne a0, t1, vm_invoke_dynamic_method_literal_done
  # Resolve non-local return at the home method boundary only.
  la t0, vm_pending_return_token
  ld t2, 0(t0)
  ld t3, 56(sp)
  bne t2, t3, vm_invoke_dynamic_method_literal_done
  sd zero, 0(t0)
  li a0, 0
  j vm_invoke_dynamic_method_literal_done

vm_invoke_dynamic_method_literal_not_found:
  li a0, -1
  li a1, 0
  j vm_invoke_dynamic_method_literal_done

vm_invoke_dynamic_method_literal_fail:
  li a0, -1
  li a1, 0

vm_invoke_dynamic_method_literal_done:
  ld t0, 48(sp)
  beqz t0, vm_invoke_dynamic_method_literal_done_nopop
  sd a0, 40(sp)
  sd a1, 32(sp)
  call vm_method_token_stack_pop
  ld a0, 40(sp)
  ld a1, 32(sp)
vm_invoke_dynamic_method_literal_done_nopop:
  ld ra, 104(sp)
  addi sp, sp, 112
  ret

# -> a0=next non-zero method token
vm_method_token_alloc:
  la t0, vm_method_token_next
  ld t1, 0(t0)
  bnez t1, vm_method_token_alloc_ready
  li t1, 1
vm_method_token_alloc_ready:
  mv a0, t1
  addi t2, t1, 1
  bnez t2, vm_method_token_alloc_store
  li t2, 1
vm_method_token_alloc_store:
  sd t2, 0(t0)
  ret

# a0=method token -> a0=status(0/-1)
vm_method_token_stack_push:
  la t0, vm_method_token_depth
  ld t1, 0(t0)
  li t2, VM_METHOD_STACK_MAX
  bgeu t1, t2, vm_method_token_stack_push_fail
  la t3, vm_method_token_stack
  slli t4, t1, 3
  add t3, t3, t4
  sd a0, 0(t3)
  addi t1, t1, 1
  sd t1, 0(t0)
  li a0, 0
  ret
vm_method_token_stack_push_fail:
  li a0, -1
  ret

# -> a0=status(0/-1), a1=method token
vm_method_token_stack_pop:
  la t0, vm_method_token_depth
  ld t1, 0(t0)
  beqz t1, vm_method_token_stack_pop_fail
  li t2, VM_METHOD_STACK_MAX
  bgtu t1, t2, vm_method_token_stack_pop_fail_reset
  addi t1, t1, -1
  sd t1, 0(t0)
  la t2, vm_method_token_stack
  slli t3, t1, 3
  add t2, t2, t3
  ld t4, 0(t2)
  li a0, 0
  mv a1, t4
  ret
vm_method_token_stack_pop_fail_reset:
  sd zero, 0(t0)
vm_method_token_stack_pop_fail:
  li a0, -1
  li a1, 0
  ret

# -> a0=current top method token (or 0 if none active)
vm_method_token_stack_top:
  la t0, vm_method_token_depth
  ld t1, 0(t0)
  beqz t1, vm_method_token_stack_top_none
  li t2, VM_METHOD_STACK_MAX
  bgtu t1, t2, vm_method_token_stack_top_none
  addi t1, t1, -1
  la t2, vm_method_token_stack
  slli t3, t1, 3
  add t2, t2, t3
  ld a0, 0(t2)
  ret
vm_method_token_stack_top_none:
  li a0, 0
  ret

# a0=method token -> a0=status(0 found / -1 not found)
vm_method_token_stack_contains:
  beqz a0, vm_method_token_stack_contains_not_found
  mv t6, a0
  la t0, vm_method_token_depth
  ld t1, 0(t0)
  li t3, VM_METHOD_STACK_MAX
  bgtu t1, t3, vm_method_token_stack_contains_not_found
  la t2, vm_method_token_stack
vm_method_token_stack_contains_loop:
  beqz t1, vm_method_token_stack_contains_not_found
  addi t1, t1, -1
  slli t3, t1, 3
  add t4, t2, t3
  ld t5, 0(t4)
  beq t5, t6, vm_method_token_stack_contains_found
  j vm_method_token_stack_contains_loop
vm_method_token_stack_contains_found:
  li a0, 0
  ret
vm_method_token_stack_contains_not_found:
  li a0, -1
  ret

# a0=receiver value, a1=selector index -> a0=block object ptr or 0
vm_lookup_dynamic_method_block:
  addi sp, sp, -32
  sd ra, 24(sp)
  sd a0, 16(sp)
  sd a1, 8(sp)

  beqz a0, vm_lookup_dynamic_method_not_found
  andi t0, a0, 1
  bnez t0, vm_lookup_dynamic_method_not_found

  # Convert selector index to selector bytes.
  mv a0, a1
  call vm_get_selector_by_index
  bltz a2, vm_lookup_dynamic_method_not_found
  mv t1, a0               # selector bytes ptr
  mv t2, a1               # selector length

  ld t4, 16(sp)           # receiver object ptr
  ld t5, OBJ_SLOT_COUNT(t4)
  li t6, 0

vm_lookup_dynamic_method_loop:
  bgeu t6, t5, vm_lookup_dynamic_method_not_found

  slli a2, t6, 3
  add a2, t4, a2
  addi a2, a2, OBJ_SLOTS
  ld a3, 0(a2)            # slot object ptr
  beqz a3, vm_lookup_dynamic_method_next
  andi a5, a3, 1
  bnez a5, vm_lookup_dynamic_method_next
  ld a5, OBJ_PROTO(a3)
  la a6, proto_slot
  bne a5, a6, vm_lookup_dynamic_method_next

  # Compare slot-name symbol bytes to selector bytes.
  ld a4, OBJ_SLOTS(a3)    # slot name object
  beqz a4, vm_lookup_dynamic_method_next
  andi a5, a4, 1
  bnez a5, vm_lookup_dynamic_method_next

  ld a5, OBJ_SLOTS+8(a4)  # tagged symbol-name length
  andi a6, a5, 1
  beqz a6, vm_lookup_dynamic_method_next
  srai a5, a5, 1
  bne a5, t2, vm_lookup_dynamic_method_next

  ld a6, OBJ_SLOTS(a4)    # slot-name bytes ptr
  mv a7, t1               # selector bytes ptr
  li t0, 0

vm_lookup_dynamic_method_cmp_loop:
  bgeu t0, t2, vm_lookup_dynamic_method_name_match
  lbu t3, 0(a6)
  lbu a0, 0(a7)
  bne t3, a0, vm_lookup_dynamic_method_next
  addi a6, a6, 1
  addi a7, a7, 1
  addi t0, t0, 1
  j vm_lookup_dynamic_method_cmp_loop

vm_lookup_dynamic_method_name_match:
  ld a5, OBJ_SLOTS+8(a3)  # slot value
  beqz a5, vm_lookup_dynamic_method_not_found
  andi a6, a5, 1
  bnez a6, vm_lookup_dynamic_method_not_found
  ld a7, OBJ_PROTO(a5)
  la t0, proto_block
  bne a7, t0, vm_lookup_dynamic_method_not_found

  mv a0, a5
  j vm_lookup_dynamic_method_done

vm_lookup_dynamic_method_next:
  addi t6, t6, 1
  j vm_lookup_dynamic_method_loop

vm_lookup_dynamic_method_not_found:
  li a0, 0

vm_lookup_dynamic_method_done:
  ld ra, 24(sp)
  addi sp, sp, 32
  ret

# a0=receiver value, a1=selector bytes ptr, a2=selector length -> a0=block object ptr or 0
vm_lookup_dynamic_method_block_literal:
  addi sp, sp, -24
  sd ra, 16(sp)
  sd a1, 8(sp)            # selector bytes ptr
  sd a2, 0(sp)            # selector length

  beqz a0, vm_lookup_dynamic_method_literal_not_found
  andi t0, a0, 1
  bnez t0, vm_lookup_dynamic_method_literal_not_found

  mv t4, a0               # receiver object ptr
  ld t1, 8(sp)            # selector bytes ptr
  ld t2, 0(sp)            # selector length
  ld t5, OBJ_SLOT_COUNT(t4)
  li t6, 0

vm_lookup_dynamic_method_literal_loop:
  bgeu t6, t5, vm_lookup_dynamic_method_literal_not_found

  slli a2, t6, 3
  add a2, t4, a2
  addi a2, a2, OBJ_SLOTS
  ld a3, 0(a2)            # slot object ptr
  beqz a3, vm_lookup_dynamic_method_literal_next
  andi a5, a3, 1
  bnez a5, vm_lookup_dynamic_method_literal_next
  ld a5, OBJ_PROTO(a3)
  la a6, proto_slot
  bne a5, a6, vm_lookup_dynamic_method_literal_next

  # Compare slot-name symbol bytes to selector bytes.
  ld a4, OBJ_SLOTS(a3)    # slot name object
  beqz a4, vm_lookup_dynamic_method_literal_next
  andi a5, a4, 1
  bnez a5, vm_lookup_dynamic_method_literal_next

  ld a5, OBJ_SLOTS+8(a4)  # tagged symbol-name length
  andi a6, a5, 1
  beqz a6, vm_lookup_dynamic_method_literal_next
  srai a5, a5, 1
  bne a5, t2, vm_lookup_dynamic_method_literal_next

  ld a6, OBJ_SLOTS(a4)    # slot-name bytes ptr
  mv a7, t1               # selector bytes ptr
  li t0, 0

vm_lookup_dynamic_method_literal_cmp_loop:
  bgeu t0, t2, vm_lookup_dynamic_method_literal_name_match
  lbu t3, 0(a6)
  lbu a0, 0(a7)
  bne t3, a0, vm_lookup_dynamic_method_literal_next
  addi a6, a6, 1
  addi a7, a7, 1
  addi t0, t0, 1
  j vm_lookup_dynamic_method_literal_cmp_loop

vm_lookup_dynamic_method_literal_name_match:
  ld a5, OBJ_SLOTS+8(a3)  # slot value
  beqz a5, vm_lookup_dynamic_method_literal_not_found
  andi a6, a5, 1
  bnez a6, vm_lookup_dynamic_method_literal_not_found
  ld a7, OBJ_PROTO(a5)
  la t0, proto_block
  bne a7, t0, vm_lookup_dynamic_method_literal_not_found

  mv a0, a5
  j vm_lookup_dynamic_method_literal_done

vm_lookup_dynamic_method_literal_next:
  addi t6, t6, 1
  j vm_lookup_dynamic_method_literal_loop

vm_lookup_dynamic_method_literal_not_found:
  li a0, 0

vm_lookup_dynamic_method_literal_done:
  ld ra, 16(sp)
  addi sp, sp, 24
  ret

# a0=dst ptr, a1=src ptr, a2=len
vm_copy_bytes:
  beqz a2, vm_copy_bytes_done
vm_copy_bytes_loop:
  lbu t0, 0(a1)
  sb t0, 0(a0)
  addi a0, a0, 1
  addi a1, a1, 1
  addi a2, a2, -1
  bnez a2, vm_copy_bytes_loop
vm_copy_bytes_done:
  ret

# a0=ASCII hex digit -> a0=nibble(0..15) or -1
vm_hex_char_to_nibble:
  li t0, '0'
  bltu a0, t0, vm_hex_char_to_nibble_lower
  li t1, '9'
  bgtu a0, t1, vm_hex_char_to_nibble_lower
  addi a0, a0, -'0'
  ret
vm_hex_char_to_nibble_lower:
  li t0, 'a'
  bltu a0, t0, vm_hex_char_to_nibble_upper
  li t1, 'f'
  bgtu a0, t1, vm_hex_char_to_nibble_upper
  addi a0, a0, -('a' - 10)
  ret
vm_hex_char_to_nibble_upper:
  li t0, 'A'
  bltu a0, t0, vm_hex_char_to_nibble_fail
  li t1, 'F'
  bgtu a0, t1, vm_hex_char_to_nibble_fail
  addi a0, a0, -('A' - 10)
  ret
vm_hex_char_to_nibble_fail:
  li a0, -1
  ret

# a0=selector index -> a0=selector bytes ptr, a1=len, a2=status(0/-1)
vm_get_selector_by_index:
  lbu t0, 6(s0)           # selector count
  bgeu a0, t0, vm_get_selector_fail

  mv t1, s2               # selector table walker
  li t2, 0                # current index

vm_get_selector_loop:
  lbu t3, 0(t1)           # current selector length
  addi t1, t1, 1
  beq t2, a0, vm_get_selector_found
  add t1, t1, t3
  addi t2, t2, 1
  j vm_get_selector_loop

vm_get_selector_found:
  mv a0, t1
  mv a1, t3
  li a2, 0
  ret

vm_get_selector_fail:
  li a0, 0
  li a1, 0
  li a2, -1
  ret

# a0=proto*, a1=selector ptr, a2=selector len -> a0=primitive id or -1
vm_lookup_proto_chain:
  mv t6, a0

vm_lookup_proto_loop:
  beqz t6, vm_lookup_proto_not_found

  ld t0, 8(t6)            # slot count
  ld t1, 16(t6)           # slots ptr
  li t2, 0                # slot index

vm_lookup_slot_loop:
  bgeu t2, t0, vm_lookup_next_proto

  li t3, 24
  mul t4, t2, t3
  add t4, t1, t4          # slot entry ptr

  ld t5, 8(t4)            # slot name length
  bne t5, a2, vm_lookup_slot_next

  ld a3, 0(t4)            # slot name ptr
  mv a4, a1               # selector ptr
  li a5, 0

vm_lookup_cmp_loop:
  bgeu a5, a2, vm_lookup_slot_match
  lbu a6, 0(a3)
  lbu a7, 0(a4)
  bne a6, a7, vm_lookup_slot_next
  addi a3, a3, 1
  addi a4, a4, 1
  addi a5, a5, 1
  j vm_lookup_cmp_loop

vm_lookup_slot_match:
  ld a0, 16(t4)           # primitive id
  ret

vm_lookup_slot_next:
  addi t2, t2, 1
  j vm_lookup_slot_loop

vm_lookup_next_proto:
  ld t6, 0(t6)            # parent proto
  j vm_lookup_proto_loop

vm_lookup_proto_not_found:
  li a0, -1
  ret

# Initializes pre-bound globals (e.g. Object).
vm_init_bootstrap_globals:
  addi sp, sp, -16
  sd ra, 8(sp)

  la a0, global_name_object
  li a1, 6
  call vm_find_selector_index_literal
  bltz a0, vm_init_bootstrap_done

  la t0, vm_globals_values
  slli t1, a0, 3
  add t0, t0, t1
  la t2, root_object_instance
  sd t2, 0(t0)

  la t0, vm_globals_valid
  add t0, t0, a0
  li t1, 1
  sb t1, 0(t0)

vm_init_bootstrap_done:
  ld ra, 8(sp)
  addi sp, sp, 16
  ret

# a0=literal ptr, a1=literal len -> a0=selector index or -1
vm_find_selector_index_literal:
  mv t6, s2
  li t0, 0
  lbu t1, 6(s0)

vm_find_selector_loop:
  bgeu t0, t1, vm_find_selector_not_found

  lbu t2, 0(t6)
  addi t6, t6, 1
  bne t2, a1, vm_find_selector_skip

  mv t3, a0
  mv t4, t6
  li t5, 0

vm_find_selector_cmp:
  bgeu t5, a1, vm_find_selector_found
  lbu a2, 0(t3)
  lbu a3, 0(t4)
  bne a2, a3, vm_find_selector_skip
  addi t3, t3, 1
  addi t4, t4, 1
  addi t5, t5, 1
  j vm_find_selector_cmp

vm_find_selector_skip:
  add t6, t6, t2
  addi t0, t0, 1
  j vm_find_selector_loop

vm_find_selector_found:
  mv a0, t0
  ret

vm_find_selector_not_found:
  li a0, -1
  ret

# a0=string bytes ptr, a1=len -> a0=status, a1=string object ptr
vm_make_string_object:
  addi sp, sp, -24
  sd ra, 16(sp)
  sd a0, 8(sp)
  sd a1, 0(sp)

  call vm_alloc_object
  bltz a0, vm_make_string_object_fail
  mv t0, a1

  la t1, proto_string
  sd t1, OBJ_PROTO(t0)
  li t1, 2
  sd t1, OBJ_SLOT_COUNT(t0)

  ld t1, 8(sp)
  sd t1, OBJ_SLOTS(t0)

  ld t1, 0(sp)
  slli t1, t1, 1
  ori t1, t1, 1
  sd t1, OBJ_SLOTS+8(t0)

  mv a1, t0
  li a0, 0
  j vm_make_string_object_done

vm_make_string_object_fail:
  li a0, -1
  li a1, 0

vm_make_string_object_done:
  ld ra, 16(sp)
  addi sp, sp, 24
  ret

# -> a0=status, a1=CannotReturn runtime value object
vm_make_cannot_return_value:
  la t0, vm_cannot_return_value
  ld t1, 0(t0)
  bnez t1, vm_make_cannot_return_value_cached

  addi sp, sp, -24
  sd ra, 16(sp)
  call vm_alloc_object
  bltz a0, vm_make_cannot_return_value_fail
  mv t1, a1
  la t2, proto_cannot_return
  sd t2, OBJ_PROTO(t1)
  li t2, 0
  sd t2, OBJ_SLOT_COUNT(t1)
  mv a1, t1
  li a0, 0

vm_make_cannot_return_value_store:
  la t0, vm_cannot_return_value
  sd a1, 0(t0)
  j vm_make_cannot_return_value_done

vm_make_cannot_return_value_fail:
  li a0, -1
  li a1, 0

vm_make_cannot_return_value_done:
  ld ra, 16(sp)
  addi sp, sp, 24
  ret

vm_make_cannot_return_value_cached:
  li a0, 0
  mv a1, t1
  ret

# a0=float payload ptr (8 bytes), a1=len(8) -> a0=status, a1=float object ptr
vm_make_float_object:
  addi sp, sp, -24
  sd ra, 16(sp)
  sd a0, 8(sp)
  sd a1, 0(sp)

  call vm_alloc_object
  bltz a0, vm_make_float_object_fail
  mv t0, a1

  la t1, proto_float
  sd t1, OBJ_PROTO(t0)
  li t1, 2
  sd t1, OBJ_SLOT_COUNT(t0)

  ld t1, 8(sp)
  sd t1, OBJ_SLOTS(t0)

  ld t1, 0(sp)
  slli t1, t1, 1
  ori t1, t1, 1
  sd t1, OBJ_SLOTS+8(t0)

  mv a1, t0
  li a0, 0
  j vm_make_float_object_done

vm_make_float_object_fail:
  li a0, -1
  li a1, 0

vm_make_float_object_done:
  ld ra, 16(sp)
  addi sp, sp, 24
  ret

# a0=scaled-decimal bytes ptr, a1=len -> a0=status, a1=scaled-decimal object ptr
vm_make_scaled_decimal_object:
  addi sp, sp, -24
  sd ra, 16(sp)
  sd a0, 8(sp)
  sd a1, 0(sp)

  call vm_alloc_object
  bltz a0, vm_make_scaled_decimal_object_fail
  mv t0, a1

  la t1, proto_scaled_decimal
  sd t1, OBJ_PROTO(t0)
  li t1, 2
  sd t1, OBJ_SLOT_COUNT(t0)

  ld t1, 8(sp)
  sd t1, OBJ_SLOTS(t0)

  ld t1, 0(sp)
  slli t1, t1, 1
  ori t1, t1, 1
  sd t1, OBJ_SLOTS+8(t0)

  mv a1, t0
  li a0, 0
  j vm_make_scaled_decimal_object_done

vm_make_scaled_decimal_object_fail:
  li a0, -1
  li a1, 0

vm_make_scaled_decimal_object_done:
  ld ra, 16(sp)
  addi sp, sp, 24
  ret

# a0=block payload bytes ptr, a1=len, a2=captured env ptr (or 0) -> a0=status, a1=block object ptr
vm_make_block_object:
  addi sp, sp, -32
  sd ra, 24(sp)
  sd a0, 16(sp)
  sd a1, 8(sp)
  sd a2, 0(sp)

  la t0, vm_block_storage_used
  ld t1, 0(t0)            # used block bytes
  ld t2, 8(sp)            # payload length
  add t3, t1, t2
  li t4, VM_BLOCK_STORAGE_BYTES
  bgtu t3, t4, vm_make_block_object_fail
  sd t3, 0(t0)

  la a0, vm_block_storage
  add a0, a0, t1
  ld a1, 16(sp)
  mv a2, t2
  sd a0, 16(sp)           # stable payload bytes ptr
  call vm_copy_bytes

  call vm_alloc_object
  bltz a0, vm_make_block_object_fail
  mv t0, a1

  la t1, proto_block
  sd t1, OBJ_PROTO(t0)
  li t1, 3
  sd t1, OBJ_SLOT_COUNT(t0)

  ld t1, 16(sp)
  sd t1, OBJ_SLOTS(t0)

  ld t1, 8(sp)
  slli t1, t1, 1
  ori t1, t1, 1
  sd t1, OBJ_SLOTS+8(t0)
  ld t1, 0(sp)
  sd t1, OBJ_SLOTS+16(t0)

  mv a1, t0
  li a0, 0
  j vm_make_block_object_done

vm_make_block_object_fail:
  li a0, -1
  li a1, 0

vm_make_block_object_done:
  ld ra, 24(sp)
  addi sp, sp, 32
  ret

# a0=object-array payload bytes ptr, a1=len -> a0=status, a1=object-array object ptr
vm_make_object_array_object:
  addi sp, sp, -24
  sd ra, 16(sp)
  sd a0, 8(sp)
  sd a1, 0(sp)

  ld t1, 0(sp)            # payload length
  beqz t1, vm_make_object_array_object_fail
  ld t2, 8(sp)            # payload ptr
  lbu t3, 0(t2)           # element count
  li t4, OBJ_FIXED_SLOTS
  bgtu t3, t4, vm_make_object_array_object_fail
  addi t5, t3, 1
  bne t5, t1, vm_make_object_array_object_fail

  call vm_alloc_object
  bltz a0, vm_make_object_array_object_fail
  mv t0, a1
  ld t2, 8(sp)
  lbu t3, 0(t2)

  la t1, proto_object_array
  sd t1, OBJ_PROTO(t0)
  sd t3, OBJ_SLOT_COUNT(t0)

  li t4, 0
vm_make_object_array_fill_loop:
  bgeu t4, t3, vm_make_object_array_object_success
  add a4, t2, t4
  addi a4, a4, 1
  lbu a2, 0(a4)           # constant index
  bgeu a2, s11, vm_make_object_array_object_fail
  slli a5, a2, 3
  add a5, s1, a5
  ld a3, 0(a5)
  slli a6, t4, 3
  add a6, t0, a6
  addi a6, a6, OBJ_SLOTS
  sd a3, 0(a6)
  addi t4, t4, 1
  j vm_make_object_array_fill_loop

vm_make_object_array_object_success:
  mv a1, t0
  li a0, 0
  j vm_make_object_array_object_done

vm_make_object_array_object_fail:
  li a0, -1
  li a1, 0

vm_make_object_array_object_done:
  ld ra, 16(sp)
  addi sp, sp, 24
  ret

# a0=byte-array payload bytes ptr, a1=len -> a0=status, a1=byte-array object ptr
vm_make_byte_array_object:
  addi sp, sp, -24
  sd ra, 16(sp)
  sd a0, 8(sp)
  sd a1, 0(sp)

  call vm_alloc_object
  bltz a0, vm_make_byte_array_object_fail
  mv t0, a1

  la t1, proto_byte_array
  sd t1, OBJ_PROTO(t0)
  li t1, 2
  sd t1, OBJ_SLOT_COUNT(t0)

  ld t1, 8(sp)
  sd t1, OBJ_SLOTS(t0)

  ld t1, 0(sp)
  slli t1, t1, 1
  ori t1, t1, 1
  sd t1, OBJ_SLOTS+8(t0)

  mv a1, t0
  li a0, 0
  j vm_make_byte_array_object_done

vm_make_byte_array_object_fail:
  li a0, -1
  li a1, 0

vm_make_byte_array_object_done:
  ld ra, 16(sp)
  addi sp, sp, 24
  ret

# a0=symbol bytes ptr, a1=len -> a0=status, a1=symbol object ptr
vm_intern_symbol:
  addi sp, sp, -40
  sd ra, 32(sp)
  sd a0, 24(sp)
  sd a1, 16(sp)

  la t0, vm_symbol_count
  ld t1, 0(t0)            # symbol count
  sd t1, 8(sp)            # append index if needed
  li t2, 0                # current index

vm_intern_symbol_loop:
  bgeu t2, t1, vm_intern_symbol_not_found

  slli t3, t2, 3
  la t4, vm_symbol_lengths
  add t4, t4, t3
  ld t5, 0(t4)            # known symbol length
  ld t6, 16(sp)           # input symbol length
  bne t5, t6, vm_intern_symbol_next

  la t4, vm_symbol_data_ptrs
  add t4, t4, t3
  ld a2, 0(t4)            # known symbol bytes ptr
  ld a3, 24(sp)           # input symbol bytes ptr
  li t4, 0

vm_intern_symbol_cmp:
  bgeu t4, t6, vm_intern_symbol_found
  lbu a4, 0(a2)
  lbu a5, 0(a3)
  bne a4, a5, vm_intern_symbol_next
  addi a2, a2, 1
  addi a3, a3, 1
  addi t4, t4, 1
  j vm_intern_symbol_cmp

vm_intern_symbol_found:
  la t4, vm_symbol_values
  add t4, t4, t3
  ld a1, 0(t4)
  li a0, 0
  j vm_intern_symbol_done

vm_intern_symbol_next:
  addi t2, t2, 1
  j vm_intern_symbol_loop

vm_intern_symbol_not_found:
  li t2, 256
  bgeu t1, t2, vm_intern_symbol_fail

  la t2, vm_symbol_storage_used
  ld t3, 0(t2)            # bytes used in symbol storage
  ld t4, 16(sp)           # incoming symbol length
  add t5, t3, t4
  li t6, VM_SYMBOL_STORAGE_BYTES
  bgtu t5, t6, vm_intern_symbol_fail
  sd t5, 0(t2)

  la a0, vm_symbol_storage
  add a0, a0, t3
  ld a1, 24(sp)
  mv a2, t4
  sd a0, 0(sp)            # stable symbol bytes ptr
  call vm_copy_bytes

  call vm_alloc_object
  bltz a0, vm_intern_symbol_fail
  mv t2, a1

  la t3, proto_symbol
  sd t3, OBJ_PROTO(t2)
  li t3, 2
  sd t3, OBJ_SLOT_COUNT(t2)
  ld t3, 0(sp)
  sd t3, OBJ_SLOTS(t2)
  ld t3, 16(sp)
  slli t3, t3, 1
  ori t3, t3, 1
  sd t3, OBJ_SLOTS+8(t2)

  ld t1, 8(sp)
  slli t3, t1, 3

  la t4, vm_symbol_data_ptrs
  add t4, t4, t3
  ld t5, 0(sp)
  sd t5, 0(t4)

  la t4, vm_symbol_lengths
  add t4, t4, t3
  ld t5, 16(sp)
  sd t5, 0(t4)

  la t4, vm_symbol_values
  add t4, t4, t3
  sd t2, 0(t4)

  addi t1, t1, 1
  la t0, vm_symbol_count
  sd t1, 0(t0)

  mv a1, t2
  li a0, 0
  j vm_intern_symbol_done

vm_intern_symbol_fail:
  li a0, -1
  li a1, 0

vm_intern_symbol_done:
  ld ra, 32(sp)
  addi sp, sp, 40
  ret

# a0=receiver value, a1=selector index, a2=argc -> a0=status, a1=result
vm_invoke_does_not_understand:
  addi sp, sp, -48
  sd ra, 40(sp)
  sd a0, 32(sp)           # receiver
  sd a1, 24(sp)           # selector index
  sd a2, 16(sp)           # argc

  ld a0, 24(sp)
  call vm_get_selector_by_index
  bltz a2, vm_invoke_does_not_understand_not_found
  mv t0, a0               # selector bytes ptr
  mv t1, a1               # selector len

  ld a0, 32(sp)           # receiver value
  mv a1, t0               # selector bytes ptr
  mv a2, t1               # selector len
  ld a3, 16(sp)           # raw argc
  call vm_invoke_does_not_understand_literal
  j vm_invoke_does_not_understand_done

vm_invoke_does_not_understand_not_found:
  ld a1, 32(sp)           # receiver value
  call vm_invoke_primitive_failed

vm_invoke_does_not_understand_done:
  ld ra, 40(sp)
  addi sp, sp, 48
  ret

# a0=receiver value, a1=selector bytes ptr, a2=selector len, a3=argc -> a0=status, a1=result
vm_invoke_does_not_understand_literal:
  addi sp, sp, -48
  sd ra, 40(sp)
  sd a0, 32(sp)           # receiver
  sd a1, 24(sp)           # selector bytes ptr
  sd a2, 16(sp)           # selector len
  sd a3, 8(sp)            # argc

  ld a0, 24(sp)
  ld a1, 16(sp)
  call vm_intern_symbol
  bnez a0, vm_invoke_does_not_understand_literal_not_found
  sd a1, 0(sp)            # selector symbol object

  ld t0, 32(sp)           # receiver value
  beqz t0, vm_invoke_does_not_understand_literal_not_found
  andi t1, t0, 1
  beqz t1, vm_invoke_does_not_understand_literal_object
  la a0, proto_integer
  j vm_invoke_does_not_understand_literal_lookup

vm_invoke_does_not_understand_literal_object:
  ld a0, OBJ_PROTO(t0)
  beqz a0, vm_invoke_does_not_understand_literal_not_found

vm_invoke_does_not_understand_literal_lookup:
  la a1, selector_name_does_not_understand_argc
  li a2, 23
  call vm_lookup_proto_chain
  bltz a0, vm_invoke_does_not_understand_literal_not_found

  mv t0, a0               # primitive id
  ld a1, 32(sp)           # receiver value
  ld a2, 0(sp)            # selector symbol
  ld t1, 8(sp)            # raw argc
  slli a3, t1, 1
  ori a3, a3, 1           # tagged argc
  mv a0, t0
  call primitive_dispatch
  j vm_invoke_does_not_understand_literal_done

vm_invoke_does_not_understand_literal_not_found:
  ld a1, 32(sp)           # receiver value
  call vm_invoke_primitive_failed

vm_invoke_does_not_understand_literal_done:
  ld ra, 40(sp)
  addi sp, sp, 48
  ret

# a1=receiver value -> a0=status, a1=result
vm_invoke_primitive_failed:
  addi sp, sp, -16
  sd ra, 8(sp)
  sd a1, 0(sp)

  beqz a1, vm_invoke_primitive_failed_not_found
  andi t0, a1, 1
  beqz t0, vm_invoke_primitive_failed_object
  la a0, proto_integer
  j vm_invoke_primitive_failed_lookup

vm_invoke_primitive_failed_object:
  ld a0, OBJ_PROTO(a1)
  beqz a0, vm_invoke_primitive_failed_not_found

vm_invoke_primitive_failed_lookup:
  la a1, selector_name_primitive_failed
  li a2, 15
  call vm_lookup_proto_chain
  bltz a0, vm_invoke_primitive_failed_not_found

  mv t0, a0
  ld a1, 0(sp)
  li a2, 0
  li a3, 0
  mv a0, t0
  call primitive_dispatch
  j vm_invoke_primitive_failed_done

vm_invoke_primitive_failed_not_found:
  li a0, -1
  li a1, 0

vm_invoke_primitive_failed_done:
  ld ra, 8(sp)
  addi sp, sp, 16
  ret

op_load_ref:
  lbu t0, 6(s0)     # symbol pool count
  bgeu t3, t0, vm_bad_ref

  la t0, vm_globals_valid
  add t0, t0, t3
  lbu t1, 0(t0)
  beqz t1, vm_unbound_ref

  la t0, vm_globals_values
  slli t1, t3, 3
  add t0, t0, t1
  ld t2, 0(t0)
  sd t2, 0(s4)
  addi s4, s4, 8
  j op_advance

op_store_ref:
  lbu t0, 6(s0)     # symbol pool count
  bgeu t3, t0, vm_bad_ref

  la t0, vm_stack
  beq s4, t0, vm_stack_underflow
  addi s4, s4, -8
  ld t1, 0(s4)

  la t0, vm_globals_values
  slli t2, t3, 3
  add t0, t0, t2
  sd t1, 0(t0)

  la t0, vm_globals_valid
  add t0, t0, t3
  li t1, 1
  sb t1, 0(t0)
  j op_advance

op_advance:
  addi s5, s5, 1
  j interpreter_loop

interpreter_done:
  ld s11, 24(sp)
  ld s10, 32(sp)
  ld s9, 40(sp)
  ld s8, 48(sp)
  ld s7, 56(sp)
  ld s6, 64(sp)
  ld s5, 72(sp)
  ld s4, 80(sp)
  ld s3, 88(sp)
  ld s2, 96(sp)
  ld s1, 104(sp)
  ld s0, 112(sp)
  ld ra, 120(sp)
  addi sp, sp, 128
  ret

vm_bad_header:
  la a0, vm_bad_header_message
  call uart_puts
  j interpreter_done

vm_bad_opcode:
  la a0, vm_bad_opcode_message
  call uart_puts
  j interpreter_done

vm_unsupported_send:
  la a0, vm_unsupported_send_message
  call uart_puts
  j interpreter_done

vm_primitive_failed:
  addi sp, sp, -16
  sd ra, 8(sp)
  sd a0, 0(sp)
  la a0, vm_primitive_failed_message
  call uart_puts
  ld a0, 0(sp)
  call uart_putint
  li a0, 10
  call uart_putc
  ld ra, 8(sp)
  addi sp, sp, 16
  j interpreter_done

vm_bad_ref:
  la a0, vm_bad_ref_message
  call uart_puts
  j interpreter_done

vm_unbound_ref:
  la a0, vm_unbound_ref_message
  call uart_puts
  j interpreter_done

vm_div_zero:
  la a0, vm_div_zero_message
  call uart_puts
  j interpreter_done

vm_stack_underflow:
  la a0, vm_stack_underflow_message
  call uart_puts
  j interpreter_done

vm_cannot_return:
  la a0, vm_cannot_return_message
  call uart_puts
  j interpreter_done

# Primitive call ABI:
#   input:  a0=primitive id, a1=receiver/value, a2=arg0 (optional), a3=arg1 (optional)
#   output: a0=status (0 success, <0 failure), a1=result (on success)
primitive_dispatch:
  li t0, 255
  bgtu a0, t0, primitive_unimplemented
  slli t1, a0, 3
  la t2, primitive_table
  add t2, t2, t1
  ld t3, 0(t2)
  jr t3

primitive_noop:
  li a0, 0
  li a1, 0
  ret

# Expects a1 = byte value to emit.
primitive_uart_putc:
  addi sp, sp, -16
  sd ra, 8(sp)
  andi a0, a1, 0xff
  call uart_putc
  ld ra, 8(sp)
  addi sp, sp, 16
  li a0, 0
  li a1, 0
  ret

primitive_debug_break:
  ebreak
  li a0, 0
  li a1, 0
  ret

# Expects a1 = tagged integer receiver.
primitive_print_int:
  andi t0, a1, 1
  beqz t0, primitive_bad_type

  addi sp, sp, -16
  sd ra, 8(sp)
  sd a1, 0(sp)

  srai a0, a1, 1
  call uart_putint
  li a0, 10
  call uart_putc

  ld a1, 0(sp)
  ld ra, 8(sp)
  addi sp, sp, 16
  li a0, 0
  ret

# Expects a1=tagged lhs, a2=tagged rhs.
primitive_add_int:
  andi t0, a1, 1
  beqz t0, primitive_bad_type
  andi t0, a2, 1
  beqz t0, primitive_bad_type
  srai t1, a1, 1
  srai t2, a2, 1
  add t3, t1, t2
  slli a1, t3, 1
  ori a1, a1, 1
  li a0, 0
  ret

# Expects a1=tagged lhs, a2=tagged rhs.
primitive_sub_int:
  andi t0, a1, 1
  beqz t0, primitive_bad_type
  andi t0, a2, 1
  beqz t0, primitive_bad_type
  srai t1, a1, 1
  srai t2, a2, 1
  sub t3, t1, t2
  slli a1, t3, 1
  ori a1, a1, 1
  li a0, 0
  ret

# Expects a1=tagged lhs, a2=tagged rhs.
primitive_mul_int:
  andi t0, a1, 1
  beqz t0, primitive_bad_type
  andi t0, a2, 1
  beqz t0, primitive_bad_type
  srai t1, a1, 1
  srai t2, a2, 1
  mul t3, t1, t2
  slli a1, t3, 1
  ori a1, a1, 1
  li a0, 0
  ret

# Expects a1=tagged lhs, a2=tagged rhs.
primitive_div_int:
  andi t0, a1, 1
  beqz t0, primitive_bad_type
  andi t0, a2, 1
  beqz t0, primitive_bad_type
  srai t1, a1, 1
  srai t2, a2, 1
  beqz t2, primitive_div_int_zero
  div t3, t1, t2
  slli a1, t3, 1
  ori a1, a1, 1
  li a0, 0
  ret

# Expects a1=receiver object ptr.
primitive_clone_object:
  beqz a1, primitive_bad_type
  andi t0, a1, 1
  bnez t0, primitive_bad_type

  addi sp, sp, -16
  sd ra, 8(sp)
  sd a1, 0(sp)
  call vm_alloc_object
  ld t1, 0(sp)
  ld ra, 8(sp)
  addi sp, sp, 16
  bltz a0, primitive_alloc_failed
  mv t2, a1

  ld t3, OBJ_PROTO(t1)
  sd t3, OBJ_PROTO(t2)
  ld t3, OBJ_SLOT_COUNT(t1)
  sd t3, OBJ_SLOT_COUNT(t2)

  li t4, 0
primitive_clone_slots_loop:
  li t5, OBJ_FIXED_SLOTS
  bgeu t4, t5, primitive_clone_done
  slli t6, t4, 3
  add a4, t1, t6
  addi a4, a4, OBJ_SLOTS
  ld a5, 0(a4)
  add a6, t2, t6
  addi a6, a6, OBJ_SLOTS
  sd a5, 0(a6)
  addi t4, t4, 1
  j primitive_clone_slots_loop

primitive_clone_done:
  mv a1, t2
  li a0, 0
  ret

# Expects a1=receiver slot object ptr.
primitive_slot_name:
  beqz a1, primitive_bad_type
  andi t0, a1, 1
  bnez t0, primitive_bad_type
  ld a1, OBJ_SLOTS(a1)
  li a0, 0
  ret

# Expects a1=receiver slot object ptr.
primitive_slot_value:
  beqz a1, primitive_bad_type
  andi t0, a1, 1
  bnez t0, primitive_bad_type
  ld a1, OBJ_SLOTS+8(a1)
  li a0, 0
  ret

# Expects a1=receiver slot object ptr, a2=value.
primitive_slot_value_put:
  beqz a1, primitive_bad_type
  andi t0, a1, 1
  bnez t0, primitive_bad_type
  addi t3, a1, OBJ_SLOTS+8
  sd a2, 0(t3)
  mv a1, a2
  li a0, 0
  ret

# Expects a1=receiver object ptr, a2=slot name object, a3=slot value.
primitive_add_slot:
  beqz a1, primitive_bad_type
  andi t0, a1, 1
  bnez t0, primitive_bad_type
  beqz a2, primitive_bad_type

  ld t0, OBJ_SLOT_COUNT(a1)
  li t1, 0
primitive_add_slot_find_loop:
  bgeu t1, t0, primitive_add_slot_append

  slli t2, t1, 3
  add t2, a1, t2
  addi t2, t2, OBJ_SLOTS
  ld t3, 0(t2)
  beqz t3, primitive_add_slot_next

  ld t4, OBJ_SLOTS(t3)
  beq t4, a2, primitive_add_slot_match
  beqz t4, primitive_add_slot_next

  andi t5, t4, 1
  bnez t5, primitive_add_slot_next
  andi t5, a2, 1
  bnez t5, primitive_add_slot_next

  ld t5, OBJ_PROTO(t4)
  la t6, proto_symbol
  bne t5, t6, primitive_add_slot_next
  ld t5, OBJ_PROTO(a2)
  bne t5, t6, primitive_add_slot_next

  ld t5, OBJ_SLOTS+8(t4)
  ld t6, OBJ_SLOTS+8(a2)
  bne t5, t6, primitive_add_slot_next
  andi a4, t5, 1
  beqz a4, primitive_add_slot_next
  srai t5, t5, 1

  ld a5, OBJ_SLOTS(t4)
  ld a6, OBJ_SLOTS(a2)
  li a7, 0
primitive_add_slot_name_cmp_loop:
  bgeu a7, t5, primitive_add_slot_match
  lbu a4, 0(a5)
  lbu t6, 0(a6)
  bne a4, t6, primitive_add_slot_next
  addi a5, a5, 1
  addi a6, a6, 1
  addi a7, a7, 1
  j primitive_add_slot_name_cmp_loop

primitive_add_slot_match:
  sd a3, OBJ_SLOTS+8(t3)
  li a0, 0
  ret

primitive_add_slot_next:
  addi t1, t1, 1
  j primitive_add_slot_find_loop

primitive_add_slot_append:
  li t2, OBJ_FIXED_SLOTS
  bgeu t0, t2, primitive_bad_index

  addi sp, sp, -32
  sd ra, 24(sp)
  sd a1, 16(sp)
  sd a2, 8(sp)
  sd a3, 0(sp)

  call vm_alloc_object
  bltz a0, primitive_add_slot_alloc_failed
  mv t3, a1

  ld t4, 16(sp)
  ld t5, 8(sp)
  ld t6, 0(sp)

  la t0, proto_slot
  sd t0, OBJ_PROTO(t3)
  li t0, 2
  sd t0, OBJ_SLOT_COUNT(t3)
  sd t5, OBJ_SLOTS(t3)
  sd t6, OBJ_SLOTS+8(t3)

  ld t0, OBJ_SLOT_COUNT(t4)
  slli t1, t0, 3
  add t1, t4, t1
  addi t1, t1, OBJ_SLOTS
  sd t3, 0(t1)
  addi t0, t0, 1
  sd t0, OBJ_SLOT_COUNT(t4)

  mv a1, t4
  li a0, 0
  ld ra, 24(sp)
  addi sp, sp, 32
  ret

primitive_add_slot_alloc_failed:
  ld ra, 24(sp)
  addi sp, sp, 32
  j primitive_alloc_failed

# Expects a1=receiver object ptr, a2=method selector symbol, a3=block object.
primitive_add_method:
  j primitive_add_slot

# Expects a1=receiver object ptr, a2=slot name object.
primitive_slot_named:
  beqz a1, primitive_bad_type
  andi t0, a1, 1
  bnez t0, primitive_bad_type
  beqz a2, primitive_bad_type

  ld t0, OBJ_SLOT_COUNT(a1)
  li t1, 0
primitive_slot_named_loop:
  bgeu t1, t0, primitive_bad_index

  slli t2, t1, 3
  add t2, a1, t2
  addi t2, t2, OBJ_SLOTS
  ld t3, 0(t2)
  beqz t3, primitive_slot_named_next

  ld t4, OBJ_SLOTS(t3)
  beq t4, a2, primitive_slot_named_match
  beqz t4, primitive_slot_named_next

  andi t5, t4, 1
  bnez t5, primitive_slot_named_next
  andi t5, a2, 1
  bnez t5, primitive_slot_named_next

  ld t5, OBJ_PROTO(t4)
  la t6, proto_symbol
  bne t5, t6, primitive_slot_named_next
  ld t5, OBJ_PROTO(a2)
  bne t5, t6, primitive_slot_named_next

  ld t5, OBJ_SLOTS+8(t4)
  ld t6, OBJ_SLOTS+8(a2)
  bne t5, t6, primitive_slot_named_next
  andi a4, t5, 1
  beqz a4, primitive_slot_named_next
  srai t5, t5, 1

  ld a5, OBJ_SLOTS(t4)
  ld a6, OBJ_SLOTS(a2)
  li a7, 0
primitive_slot_named_cmp_loop:
  bgeu a7, t5, primitive_slot_named_match
  lbu a4, 0(a5)
  lbu t6, 0(a6)
  bne a4, t6, primitive_slot_named_next
  addi a5, a5, 1
  addi a6, a6, 1
  addi a7, a7, 1
  j primitive_slot_named_cmp_loop

primitive_slot_named_match:
  ld a1, OBJ_SLOTS+8(t3)
  li a0, 0
  ret

primitive_slot_named_next:
  addi t1, t1, 1
  j primitive_slot_named_loop

# Expects a1=receiver bytes-like object ptr (string/byte-array).
primitive_bytes_size:
  beqz a1, primitive_bad_type
  andi t0, a1, 1
  bnez t0, primitive_bad_type
  ld a1, OBJ_SLOTS+8(a1)  # tagged length
  li a0, 0
  ret

# Expects a1=receiver bytes-like object ptr, a2=tagged index.
primitive_bytes_at:
  beqz a1, primitive_bad_type
  andi t0, a1, 1
  bnez t0, primitive_bad_type
  andi t0, a2, 1
  beqz t0, primitive_bad_type

  srai t1, a2, 1
  bltz t1, primitive_bad_index

  ld t2, OBJ_SLOTS+8(a1)  # tagged length
  andi t3, t2, 1
  beqz t3, primitive_bad_type
  srai t2, t2, 1
  bgeu t1, t2, primitive_bad_index

  ld t4, OBJ_SLOTS(a1)    # bytes ptr
  add t4, t4, t1
  lbu t5, 0(t4)
  slli a1, t5, 1
  ori a1, a1, 1
  li a0, 0
  ret

# Expects a1=receiver bytes-like object ptr, a2=tagged index, a3=tagged value byte.
primitive_bytes_at_put:
  beqz a1, primitive_bad_type
  andi t0, a1, 1
  bnez t0, primitive_bad_type
  andi t0, a2, 1
  beqz t0, primitive_bad_type
  andi t0, a3, 1
  beqz t0, primitive_bad_type

  srai t1, a2, 1
  bltz t1, primitive_bad_index
  srai t2, a3, 1
  bltz t2, primitive_bad_type
  li t3, 255
  bgtu t2, t3, primitive_bad_type

  ld t4, OBJ_SLOTS+8(a1)  # tagged length
  andi t5, t4, 1
  beqz t5, primitive_bad_type
  srai t4, t4, 1
  bgeu t1, t4, primitive_bad_index

  ld t6, OBJ_SLOTS(a1)    # bytes ptr
  add t6, t6, t1
  sb t2, 0(t6)
  mv a1, a3
  li a0, 0
  ret

# Expects a1=receiver object-array object ptr.
primitive_object_array_size:
  beqz a1, primitive_bad_type
  andi t0, a1, 1
  bnez t0, primitive_bad_type
  ld t1, OBJ_SLOT_COUNT(a1)
  slli a1, t1, 1
  ori a1, a1, 1
  li a0, 0
  ret

# Expects a1=receiver object-array object ptr, a2=tagged index.
primitive_object_array_at:
  beqz a1, primitive_bad_type
  andi t0, a1, 1
  bnez t0, primitive_bad_type
  andi t0, a2, 1
  beqz t0, primitive_bad_type

  srai t1, a2, 1
  bltz t1, primitive_bad_index
  ld t2, OBJ_SLOT_COUNT(a1)
  bgeu t1, t2, primitive_bad_index

  slli t3, t1, 3
  add t3, a1, t3
  addi t3, t3, OBJ_SLOTS
  ld a1, 0(t3)
  li a0, 0
  ret

# Expects a1=receiver object-array object ptr, a2=tagged index, a3=value.
primitive_object_array_at_put:
  beqz a1, primitive_bad_type
  andi t0, a1, 1
  bnez t0, primitive_bad_type
  andi t0, a2, 1
  beqz t0, primitive_bad_type

  srai t1, a2, 1
  bltz t1, primitive_bad_index
  ld t2, OBJ_SLOT_COUNT(a1)
  bgeu t1, t2, primitive_bad_index

  slli t3, t1, 3
  add t3, a1, t3
  addi t3, t3, OBJ_SLOTS
  sd a3, 0(t3)
  mv a1, a3
  li a0, 0
  ret

# Expects a1=receiver block object ptr.
primitive_block_value:
  beqz a1, primitive_bad_type
  andi t0, a1, 1
  bnez t0, primitive_bad_type
  ld t1, OBJ_PROTO(a1)
  la t2, proto_block
  bne t1, t2, primitive_bad_type
  mv a0, a1               # block object
  mv a1, a2               # lexical self
  li a2, 0                # args ptr
  li a3, 0                # passed arg count
  addi sp, sp, -16
  sd ra, 8(sp)
  call vm_eval_block
  ld ra, 8(sp)
  addi sp, sp, 16
  ret

# Expects a1=receiver block object ptr, a2=arg, a3=method receiver (or 0 for direct block sends).
primitive_block_value_arg:
  beqz a1, primitive_bad_type
  andi t0, a1, 1
  bnez t0, primitive_bad_type
  ld t1, OBJ_PROTO(a1)
  la t2, proto_block
  bne t1, t2, primitive_bad_type

  mv t3, a3               # preserve lexical self if present
  mv a0, a1               # block object
  mv a1, t3               # lexical self (0 when absent)
  la t4, vm_block_args_tmp
  sd a2, 0(t4)
  mv a2, t4               # args ptr
  li a3, 1                # passed arg count
  addi sp, sp, -16
  sd ra, 8(sp)
  call vm_eval_block
  ld ra, 8(sp)
  addi sp, sp, 16
  ret

# Expects a1=cannot-return object receiver.
primitive_print_cannot_return:
  addi sp, sp, -16
  sd ra, 8(sp)
  mv t0, a1
  la a0, cannot_return_runtime_message
  call uart_puts
  ld ra, 8(sp)
  addi sp, sp, 16
  mv a1, t0
  li a0, 0
  ret

# Expects a1=receiver, a2=handler block. Pass-through for non-CannotReturn values.
primitive_on_cannot_return:
  li a0, 0
  ret

# Expects a1=CannotReturn receiver, a2=handler block.
primitive_handle_cannot_return:
  mv t0, a1               # capture CannotReturn object as handler argument
  mv a1, a2               # block receiver
  mv a2, t0               # handler arg (CannotReturn object)
  li a3, 0                # no lexical self for direct protocol send
  addi sp, sp, -16
  sd ra, 8(sp)
  call primitive_block_value_arg
  ld ra, 8(sp)
  addi sp, sp, 16
  ret

# Expects a1=receiver, a2=selector symbol object, a3=tagged argc.
primitive_does_not_understand_argc:
  addi sp, sp, -64
  sd ra, 56(sp)
  sd s0, 48(sp)
  sd s1, 40(sp)
  sd s2, 32(sp)
  sd a1, 24(sp)           # receiver for return value
  sd a2, 16(sp)           # selector symbol
  sd a3, 8(sp)            # tagged argc

  la a0, dnu_prefix_message
  call uart_puts

  ld t0, 16(sp)           # selector symbol object
  beqz t0, primitive_dnu_invalid_selector
  andi t1, t0, 1
  bnez t1, primitive_dnu_invalid_selector
  ld t2, OBJ_PROTO(t0)
  la t3, proto_symbol
  bne t2, t3, primitive_dnu_invalid_selector
  ld t4, OBJ_SLOTS(t0)    # selector bytes ptr
  ld t5, OBJ_SLOTS+8(t0)  # tagged length
  andi t6, t5, 1
  beqz t6, primitive_dnu_invalid_selector
  srai s1, t5, 1
  mv s0, t4
  li s2, 0
primitive_dnu_selector_loop:
  bgeu s2, s1, primitive_dnu_selector_done
  lbu a0, 0(s0)
  call uart_putc
  addi s0, s0, 1
  addi s2, s2, 1
  j primitive_dnu_selector_loop

primitive_dnu_invalid_selector:
  la a0, dnu_invalid_selector_message
  call uart_puts

primitive_dnu_selector_done:
  la a0, dnu_argc_message
  call uart_puts

  ld t0, 8(sp)            # tagged argc
  andi t1, t0, 1
  beqz t1, primitive_dnu_bad_argc
  srai a0, t0, 1
  j primitive_dnu_print_argc
primitive_dnu_bad_argc:
  li a0, -1
primitive_dnu_print_argc:
  call uart_putint
  li a0, 10
  call uart_putc

  ld a1, 24(sp)
  li a0, 0
  ld s2, 32(sp)
  ld s1, 40(sp)
  ld s0, 48(sp)
  ld ra, 56(sp)
  addi sp, sp, 64
  ret

# Expects a1=receiver. Returns a ByteArray image snapshot object.
primitive_save_image:
  addi sp, sp, -96
  sd ra, 88(sp)
  sd s0, 80(sp)
  sd s1, 72(sp)
  sd s2, 64(sp)
  sd s3, 56(sp)
  sd s4, 48(sp)

  la t0, vm_heap_ptr
  ld t1, 0(t0)            # heap ptr
  la t2, vm_heap
  bltu t1, t2, primitive_save_image_fail
  sub s1, t1, t2          # heap used bytes
  li t3, 65536
  bgtu s1, t3, primitive_save_image_fail

  la t0, vm_symbol_storage_used
  ld s3, 0(t0)            # symbol bytes used
  li t3, VM_SYMBOL_STORAGE_BYTES
  bgtu s3, t3, primitive_save_image_fail

  la t0, vm_block_storage_used
  ld s4, 0(t0)            # block bytes used
  li t3, VM_BLOCK_STORAGE_BYTES
  bgtu s4, t3, primitive_save_image_fail

  li t4, IMAGE_MIN_BYTES
  add s2, s1, t4          # total snapshot length
  add s2, s2, s3
  add s2, s2, s4
  li t5, VM_IMAGE_BUFFER_BYTES
  bgtu s2, t5, primitive_save_image_fail

  la s0, vm_image_buffer

  li t0, 'R'
  sb t0, 0(s0)
  li t0, 'C'
  sb t0, 1(s0)
  li t0, 'I'
  sb t0, 2(s0)
  li t0, 'M'
  sb t0, 3(s0)
  li t0, 2
  sb t0, 4(s0)
  sb zero, 5(s0)
  sb zero, 6(s0)
  sb zero, 7(s0)
  sd s1, 8(s0)            # heap used
  addi s0, s0, 16

  mv a0, s0
  la a1, vm_globals_valid
  li a2, 256
  call vm_copy_bytes
  addi s0, s0, 256

  mv a0, s0
  la a1, vm_globals_values
  li a2, 2048
  call vm_copy_bytes
  li t0, 2048
  add s0, s0, t0

  mv a0, s0
  la a1, vm_symbol_count
  li a2, 8
  call vm_copy_bytes
  addi s0, s0, 8

  mv a0, s0
  la a1, vm_symbol_data_ptrs
  li a2, 2048
  call vm_copy_bytes
  li t0, 2048
  add s0, s0, t0

  mv a0, s0
  la a1, vm_symbol_lengths
  li a2, 2048
  call vm_copy_bytes
  li t0, 2048
  add s0, s0, t0

  mv a0, s0
  la a1, vm_symbol_values
  li a2, 2048
  call vm_copy_bytes
  li t0, 2048
  add s0, s0, t0

  mv a0, s0
  la a1, vm_symbol_storage_used
  li a2, 8
  call vm_copy_bytes
  addi s0, s0, 8

  mv a0, s0
  la a1, vm_symbol_storage
  mv a2, s3
  call vm_copy_bytes
  add s0, s0, s3

  mv a0, s0
  la a1, vm_block_storage_used
  li a2, 8
  call vm_copy_bytes
  addi s0, s0, 8

  mv a0, s0
  la a1, vm_block_storage
  mv a2, s4
  call vm_copy_bytes
  add s0, s0, s4

  mv a0, s0
  la a1, vm_cannot_return_value
  li a2, 8
  call vm_copy_bytes
  addi s0, s0, 8

  mv a0, s0
  la a1, root_object_instance
  li a2, OBJ_BYTES
  call vm_copy_bytes
  li t0, OBJ_BYTES
  add s0, s0, t0

  mv a0, s0
  la a1, vm_heap
  mv a2, s1
  call vm_copy_bytes

  la a0, vm_image_buffer
  mv a1, s2
  call vm_make_byte_array_object
  bnez a0, primitive_save_image_fail
  j primitive_save_image_done

primitive_save_image_fail:
  li a0, -5
  li a1, 0

primitive_save_image_done:
  ld s4, 48(sp)
  ld s3, 56(sp)
  ld s2, 64(sp)
  ld s1, 72(sp)
  ld s0, 80(sp)
  ld ra, 88(sp)
  addi sp, sp, 96
  ret

# Expects a1=receiver, a2=image byte-array object. Restores VM snapshot.
primitive_load_image:
  addi sp, sp, -96
  sd ra, 88(sp)
  sd s0, 80(sp)
  sd s1, 72(sp)
  sd s2, 64(sp)
  sd s3, 56(sp)
  sd s4, 48(sp)
  sd a1, 40(sp)           # receiver

  mv s4, a2               # image object
  beqz s4, primitive_load_image_bad_type
  andi t0, s4, 1
  bnez t0, primitive_load_image_bad_type
  ld t1, OBJ_PROTO(s4)
  la t2, proto_byte_array
  bne t1, t2, primitive_load_image_bad_type

  ld s0, OBJ_SLOTS(s4)    # image bytes ptr
  ld t3, OBJ_SLOTS+8(s4)  # tagged image length
  andi t4, t3, 1
  beqz t4, primitive_load_image_bad_type
  srai s1, t3, 1          # image length

  li t0, IMAGE_MIN_BYTES
  bltu s1, t0, primitive_load_image_bad_format

  lbu t0, 0(s0)
  li t1, 'R'
  bne t0, t1, primitive_load_image_bad_format
  lbu t0, 1(s0)
  li t1, 'C'
  bne t0, t1, primitive_load_image_bad_format
  lbu t0, 2(s0)
  li t1, 'I'
  bne t0, t1, primitive_load_image_bad_format
  lbu t0, 3(s0)
  li t1, 'M'
  bne t0, t1, primitive_load_image_bad_format
  lbu t0, 4(s0)
  li t1, 2
  bne t0, t1, primitive_load_image_bad_format

  ld s2, 8(s0)            # heap used
  li t0, 65536
  bgtu s2, t0, primitive_load_image_bad_format
  li t1, IMAGE_MIN_BYTES
  add t1, t1, s2
  bgtu t1, s1, primitive_load_image_bad_format

  addi s3, s0, 16

  la a0, vm_globals_valid
  mv a1, s3
  li a2, 256
  call vm_copy_bytes
  addi s3, s3, 256

  la a0, vm_globals_values
  mv a1, s3
  li a2, 2048
  call vm_copy_bytes
  li t0, 2048
  add s3, s3, t0

  la a0, vm_symbol_count
  mv a1, s3
  li a2, 8
  call vm_copy_bytes
  addi s3, s3, 8

  la a0, vm_symbol_data_ptrs
  mv a1, s3
  li a2, 2048
  call vm_copy_bytes
  li t0, 2048
  add s3, s3, t0

  la a0, vm_symbol_lengths
  mv a1, s3
  li a2, 2048
  call vm_copy_bytes
  li t0, 2048
  add s3, s3, t0

  la a0, vm_symbol_values
  mv a1, s3
  li a2, 2048
  call vm_copy_bytes
  li t0, 2048
  add s3, s3, t0

  la a0, vm_symbol_storage_used
  mv a1, s3
  li a2, 8
  call vm_copy_bytes
  addi s3, s3, 8

  la t0, vm_symbol_storage_used
  ld s4, 0(t0)            # symbol bytes used
  li t1, VM_SYMBOL_STORAGE_BYTES
  bgtu s4, t1, primitive_load_image_bad_format
  add t0, s3, s4
  addi t0, t0, 8
  li t1, OBJ_BYTES
  add t0, t0, t1
  add t0, t0, s2
  add t1, s0, s1
  bgtu t0, t1, primitive_load_image_bad_format

  la a0, vm_symbol_storage
  mv a1, s3
  mv a2, s4
  call vm_copy_bytes
  add s3, s3, s4

  la a0, vm_block_storage_used
  mv a1, s3
  li a2, 8
  call vm_copy_bytes
  addi s3, s3, 8

  la t0, vm_block_storage_used
  ld t2, 0(t0)            # block bytes used
  li t1, VM_BLOCK_STORAGE_BYTES
  bgtu t2, t1, primitive_load_image_bad_format
  add t0, s3, t2
  addi t0, t0, 8
  li t1, OBJ_BYTES
  add t0, t0, t1
  add t0, t0, s2
  add t1, s0, s1
  bgtu t0, t1, primitive_load_image_bad_format

  la a0, vm_block_storage
  mv a1, s3
  mv a2, t2
  call vm_copy_bytes
  add s3, s3, t2

  la a0, vm_cannot_return_value
  mv a1, s3
  li a2, 8
  call vm_copy_bytes
  addi s3, s3, 8

  la a0, root_object_instance
  mv a1, s3
  li a2, OBJ_BYTES
  call vm_copy_bytes
  li t0, OBJ_BYTES
  add s3, s3, t0

  la a0, vm_heap
  mv a1, s3
  mv a2, s2
  call vm_copy_bytes

  la t0, vm_heap_ptr
  la t1, vm_heap
  add t1, t1, s2
  sd t1, 0(t0)

  la t0, vm_method_token_depth
  sd zero, 0(t0)
  la t0, vm_pending_return_token
  sd zero, 0(t0)

  ld a1, 40(sp)           # receiver
  li a0, 0
  j primitive_load_image_done

primitive_load_image_bad_type:
  li a0, -3
  li a1, 0
  j primitive_load_image_done

primitive_load_image_bad_format:
  li a0, -4
  li a1, 0

primitive_load_image_done:
  ld s4, 48(sp)
  ld s3, 56(sp)
  ld s2, 64(sp)
  ld s1, 72(sp)
  ld s0, 80(sp)
  ld ra, 88(sp)
  addi sp, sp, 96
  ret

# Expects a1=receiver, a2=image byte-array object. Emits host bridge payload over UART.
primitive_export_image:
  addi sp, sp, -96
  sd ra, 88(sp)
  sd s0, 80(sp)
  sd s1, 72(sp)
  sd s2, 64(sp)
  sd s3, 56(sp)
  sd s4, 48(sp)
  sd a1, 40(sp)           # receiver

  beqz a2, primitive_export_image_bad_type
  andi t0, a2, 1
  bnez t0, primitive_export_image_bad_type
  ld t1, OBJ_PROTO(a2)
  la t2, proto_byte_array
  bne t1, t2, primitive_export_image_bad_type

  ld s0, OBJ_SLOTS(a2)    # bytes ptr
  ld t3, OBJ_SLOTS+8(a2)  # tagged length
  andi t4, t3, 1
  beqz t4, primitive_export_image_bad_type
  srai s1, t3, 1

  li s2, 0
  li s4, 0                # checksum (u32 sum of bytes)
primitive_export_image_checksum_loop:
  bgeu s2, s1, primitive_export_image_checksum_done
  add t0, s0, s2
  lbu t1, 0(t0)
  add s4, s4, t1
  slli s4, s4, 32
  srli s4, s4, 32
  addi s2, s2, 1
  j primitive_export_image_checksum_loop

primitive_export_image_checksum_done:
  la a0, image_bridge_prefix_message
  call uart_puts
  mv a0, s1
  call uart_putint
  li a0, ' '
  call uart_putc
  mv a0, s4
  call uart_puthex_u32
  li a0, 10
  call uart_putc

  li s2, 0
primitive_export_image_loop:
  bgeu s2, s1, primitive_export_image_done_emit
  add t0, s0, s2
  lbu s3, 0(t0)
  srli a0, s3, 4
  call uart_puthex_nibble
  andi a0, s3, 0x0f
  call uart_puthex_nibble
  addi s2, s2, 1
  j primitive_export_image_loop

primitive_export_image_done_emit:
  li a0, 10
  call uart_putc
  ld a1, 40(sp)
  li a0, 0
  j primitive_export_image_done

primitive_export_image_bad_type:
  li a0, -3
  li a1, 0

primitive_export_image_done:
  ld s4, 48(sp)
  ld s3, 56(sp)
  ld s2, 64(sp)
  ld s1, 72(sp)
  ld s0, 80(sp)
  ld ra, 88(sp)
  addi sp, sp, 96
  ret

# Expects a1=receiver. Reads host bridge payload from UART and returns byte-array image.
primitive_import_image:
  addi sp, sp, -112
  sd ra, 104(sp)
  sd s0, 96(sp)
  sd s1, 88(sp)
  sd s2, 80(sp)
  sd s3, 72(sp)
  sd s4, 64(sp)
  sd s5, 56(sp)
  sd s6, 48(sp)

  li s0, 0                # parsed length
  li s4, 0                # parsed checksum (u32)
  li s6, 0                # parsed checksum hex digit count
primitive_import_image_len_loop:
  call uart_getc
  li t0, 13               # '\r'
  beq a0, t0, primitive_import_image_len_loop
  li t0, ' '
  beq a0, t0, primitive_import_image_checksum_loop
  li t0, 10               # '\n'
  beq a0, t0, primitive_import_image_bad_format
  li t0, '0'
  bltu a0, t0, primitive_import_image_bad_format
  li t1, '9'
  bgtu a0, t1, primitive_import_image_bad_format
  addi a0, a0, -'0'
  li t2, VM_IMAGE_BUFFER_BYTES
  li t3, 10
  mul t4, s0, t3
  add s0, t4, a0
  bgtu s0, t2, primitive_import_image_bad_format
  j primitive_import_image_len_loop

primitive_import_image_checksum_loop:
  call uart_getc
  li t0, 13               # '\r'
  beq a0, t0, primitive_import_image_checksum_loop
  li t0, 10               # '\n'
  beq a0, t0, primitive_import_image_checksum_done
  call vm_hex_char_to_nibble
  bltz a0, primitive_import_image_bad_format
  slli s4, s4, 4
  or s4, s4, a0
  addi s6, s6, 1
  li t0, 8
  bgtu s6, t0, primitive_import_image_bad_format
  j primitive_import_image_checksum_loop

primitive_import_image_checksum_done:
  li t0, 8
  bne s6, t0, primitive_import_image_bad_format

primitive_import_image_len_done:
  la s1, vm_image_buffer
  li s2, 0
  li s5, 0                # computed checksum (u32)
primitive_import_image_hex_loop:
  bgeu s2, s0, primitive_import_image_hex_done
  call uart_getc
  call vm_hex_char_to_nibble
  bltz a0, primitive_import_image_bad_format
  mv s3, a0
  call uart_getc
  call vm_hex_char_to_nibble
  bltz a0, primitive_import_image_bad_format
  slli s3, s3, 4
  or t0, s3, a0
  add t1, s1, s2
  sb t0, 0(t1)
  add s5, s5, t0
  slli s5, s5, 32
  srli s5, s5, 32
  addi s2, s2, 1
  j primitive_import_image_hex_loop

primitive_import_image_hex_done:
  call uart_getc            # consume trailing newline
  li t0, 13                 # '\r'
  beq a0, t0, primitive_import_image_hex_cr_done
  li t0, 10                 # '\n'
  bne a0, t0, primitive_import_image_bad_format
  j primitive_import_image_checksum_verify

primitive_import_image_hex_cr_done:
  call uart_getc
  li t0, 10                 # '\n'
  bne a0, t0, primitive_import_image_bad_format

primitive_import_image_checksum_verify:
  bne s5, s4, primitive_import_image_bad_format

  la a0, vm_image_buffer
  mv a1, s0
  call vm_make_byte_array_object
  bnez a0, primitive_import_image_bad_format
  j primitive_import_image_done

primitive_import_image_bad_format:
  li a0, -4
  li a1, 0

primitive_import_image_done:
  ld s6, 48(sp)
  ld s5, 56(sp)
  ld s4, 64(sp)
  ld s3, 72(sp)
  ld s2, 80(sp)
  ld s1, 88(sp)
  ld s0, 96(sp)
  ld ra, 104(sp)
  addi sp, sp, 112
  ret

# Expects a1=receiver. Creates image snapshot and exports it over host bridge.
primitive_save_image_to_host:
  addi sp, sp, -32
  sd ra, 24(sp)
  sd s0, 16(sp)
  sd s1, 8(sp)
  sd s2, 0(sp)

  mv s0, a1               # receiver
  call primitive_save_image
  bnez a0, primitive_save_image_to_host_done
  mv s1, a1               # image object
  mv a1, s0
  mv a2, s1
  call primitive_export_image
  j primitive_save_image_to_host_done

primitive_save_image_to_host_done:
  ld s2, 0(sp)
  ld s1, 8(sp)
  ld s0, 16(sp)
  ld ra, 24(sp)
  addi sp, sp, 32
  ret

# Expects a1=receiver. Imports image from host bridge and restores it into VM state.
primitive_load_image_from_host:
  addi sp, sp, -32
  sd ra, 24(sp)
  sd s0, 16(sp)
  sd s1, 8(sp)
  sd s2, 0(sp)

  mv s0, a1               # receiver
  call primitive_import_image
  bnez a0, primitive_load_image_from_host_done
  mv s1, a1               # image object
  mv a1, s0
  mv a2, s1
  call primitive_load_image
  j primitive_load_image_from_host_done

primitive_load_image_from_host_done:
  ld s2, 0(sp)
  ld s1, 8(sp)
  ld s0, 16(sp)
  ld ra, 24(sp)
  addi sp, sp, 32
  ret

# a0=block object, a1=lexical self, a2=args ptr, a3=passed arg count -> a0=status, a1=result
vm_eval_block:
  addi sp, sp, -160
  sd ra, 152(sp)
  sd s0, 144(sp)
  sd s1, 136(sp)
  sd s2, 128(sp)
  sd s3, 120(sp)
  sd s4, 112(sp)
  sd s5, 104(sp)
  sd s6, 96(sp)
  sd s7, 88(sp)
  sd s8, 80(sp)
  sd s9, 72(sp)
  sd s10, 64(sp)
  sd s11, 56(sp)

  mv s0, a0               # block object ptr
  mv s1, a1               # lexical self
  mv s2, a2               # args ptr
  mv s3, a3               # passed arg count

  beqz s0, vm_eval_block_fail_type
  andi t0, s0, 1
  bnez t0, vm_eval_block_fail_type
  ld t1, OBJ_PROTO(s0)
  la t2, proto_block
  bne t1, t2, vm_eval_block_fail_type

  ld s4, OBJ_SLOTS(s0)    # payload bytes ptr
  ld t0, OBJ_SLOTS+8(s0)  # tagged payload length
  andi t1, t0, 1
  beqz t1, vm_eval_block_fail_header
  srai t0, t0, 1
  add s6, s4, t0          # payload end ptr

  addi t2, s4, 8
  bgtu t2, s6, vm_eval_block_fail_header

  lbu t0, 0(s4)
  li t1, 'R'
  bne t0, t1, vm_eval_block_fail_header
  lbu t0, 1(s4)
  li t1, 'B'
  bne t0, t1, vm_eval_block_fail_header
  lbu t0, 2(s4)
  li t1, 'L'
  bne t0, t1, vm_eval_block_fail_header
  lbu t0, 3(s4)
  li t1, 'K'
  bne t0, t1, vm_eval_block_fail_header
  lbu t0, 4(s4)
  li t1, 2
  beq t0, t1, vm_eval_block_header_v2
  li t1, 3
  beq t0, t1, vm_eval_block_header_v3
  j vm_eval_block_fail_header

vm_eval_block_header_v2:
  li t2, 255
  addi t3, s4, 5          # arg-count byte ptr
  j vm_eval_block_header_ready

vm_eval_block_header_v3:
  addi t3, s4, 5          # primitive byte ptr
  bgeu t3, s6, vm_eval_block_fail_header
  lbu t2, 0(t3)           # declared primitive id
  addi t3, t3, 1          # arg-count byte ptr

vm_eval_block_header_ready:
  sd t2, 48(sp)           # declared primitive id (255 => none)
  bgeu t3, s6, vm_eval_block_fail_header
  lbu s7, 0(t3)           # declared arg count
  bltu s3, s7, vm_eval_block_fail_index

  addi t1, t3, 1          # arg-ref-count byte ptr
  bgeu t1, s6, vm_eval_block_fail_header
  lbu t6, 0(t1)           # arg-ref count
  bne t6, s7, vm_eval_block_fail_header
  addi s5, t1, 1          # arg-ref index bytes ptr
  add t2, s5, t6          # local-count byte ptr
  bgeu t2, s6, vm_eval_block_fail_header
  lbu t3, 0(t2)           # local count
  addi t4, t2, 1          # local-ref-count byte ptr
  bgeu t4, s6, vm_eval_block_fail_header
  lbu t5, 0(t4)           # local-ref count
  bne t5, t3, vm_eval_block_fail_header
  addi t4, t4, 1          # local-ref table ptr
  add t2, t4, t5          # constant-count byte ptr
  bgeu t2, s6, vm_eval_block_fail_header

  lbu t0, 0(t2)           # constant count
  sd t0, 0(sp)
  addi s8, t2, 1          # constants base ptr
  mv t2, s8               # constants walker ptr
  li t3, 0                # constants scanned
vm_eval_block_constants_scan_loop:
  bgeu t3, t0, vm_eval_block_constants_scan_done
  bgeu t2, s6, vm_eval_block_fail_header
  lbu t4, 0(t2)           # constant kind
  addi t2, t2, 1
  li t5, 0
  beq t4, t5, vm_eval_block_constants_scan_int
  li t5, 1
  beq t4, t5, vm_eval_block_constants_scan_len
  li t5, 2
  beq t4, t5, vm_eval_block_constants_scan_len
  li t5, 3
  beq t4, t5, vm_eval_block_constants_scan_len_u16
  j vm_eval_block_fail_header
vm_eval_block_constants_scan_int:
  addi t2, t2, 8
  bgtu t2, s6, vm_eval_block_fail_header
  addi t3, t3, 1
  j vm_eval_block_constants_scan_loop
vm_eval_block_constants_scan_len:
  bgeu t2, s6, vm_eval_block_fail_header
  lbu t4, 0(t2)           # payload length
  addi t2, t2, 1
  add t2, t2, t4
  bgtu t2, s6, vm_eval_block_fail_header
  addi t3, t3, 1
  j vm_eval_block_constants_scan_loop
vm_eval_block_constants_scan_len_u16:
  addi t4, t2, 2
  bgtu t4, s6, vm_eval_block_fail_header
  lbu t5, 0(t2)
  lbu t6, 1(t2)
  slli t6, t6, 8
  or t5, t5, t6           # payload length (u16)
  addi t2, t2, 2
  add t2, t2, t5
  bgtu t2, s6, vm_eval_block_fail_header
  addi t3, t3, 1
  j vm_eval_block_constants_scan_loop
vm_eval_block_constants_scan_done:
  sd t2, 24(sp)           # constants end ptr (selector_count byte)

  addi t3, t2, 1
  bgtu t3, s6, vm_eval_block_fail_header
  lbu t4, 0(t2)           # selector count
  sd t4, 8(sp)
  addi s9, t2, 1          # selectors base ptr

  mv t5, s9
  li t6, 0
vm_eval_block_selector_scan_loop:
  bgeu t6, t4, vm_eval_block_selector_scan_done
  bgeu t5, s6, vm_eval_block_fail_header
  lbu a4, 0(t5)
  addi t5, t5, 1
  add t5, t5, a4
  addi t6, t6, 1
  j vm_eval_block_selector_scan_loop

vm_eval_block_selector_scan_done:
  addi a4, t5, 1
  bgtu a4, s6, vm_eval_block_fail_header
  lbu a5, 0(t5)           # instruction count
  sd a5, 16(sp)
  addi s10, t5, 1         # instructions base ptr

  li a6, 3
  mul a7, a5, a6
  add a7, s10, a7
  bgtu a7, s6, vm_eval_block_fail_header

  # Recover block-local metadata after selector/instruction scans.
  mv t0, s5               # arg-ref index bytes ptr
  add t0, t0, s7          # local-count byte ptr
  bgeu t0, s6, vm_eval_block_fail_header
  lbu t1, 0(t0)           # local count
  addi t2, t0, 1          # local-ref-count byte ptr
  bgeu t2, s6, vm_eval_block_fail_header
  lbu t3, 0(t2)           # local-ref count
  bne t3, t1, vm_eval_block_fail_header
  addi t4, t2, 1          # local-ref table ptr
  add t5, t4, t3
  bgtu t5, s6, vm_eval_block_fail_header

  li t5, 32
  bgtu t1, t5, vm_eval_block_fail_index
  la t6, vm_block_stack   # locals base ptr
  mv t2, t6
  li t3, 0
vm_eval_block_locals_zero_loop:
  bgeu t3, t1, vm_eval_block_locals_zero_done
  sd zero, 0(t2)
  addi t2, t2, 8
  addi t3, t3, 1
  j vm_eval_block_locals_zero_loop
vm_eval_block_locals_zero_done:
  # Build one activation capture-env and reuse it for all nested closure constants
  # materialized during this block invocation (sibling closures share captured state).
  ld a0, OBJ_SLOTS+16(s0) # parent captured env ptr
  mv a1, s5               # current arg-name ref table ptr
  mv a2, s7               # current declared arg count
  mv a3, s2               # current args ptr
  mv a4, t4               # current local-name ref table ptr
  mv a5, t1               # current local count
  mv a6, t6               # current locals ptr
  call vm_make_block_env_from_context
  bnez a0, vm_eval_block_fail_header
  sd a1, 40(sp)           # activation env ptr

  # Reserve local scratch slots at bottom of vm_block_stack.
  mv t0, s5               # arg-ref index bytes ptr
  add t0, t0, s7          # local-count byte ptr
  lbu t1, 0(t0)           # local count
  la t2, vm_block_stack   # locals base ptr
  slli t1, t1, 3
  add t3, t2, t1
  sd t3, 32(sp)           # operand-stack base ptr (after local slots)
  mv s11, t3              # operand-stack top ptr

  # Smalltalk-style primitive declaration: attempt primitive first, fall back to body on failure.
  ld t0, 48(sp)           # declared primitive id (255 => none)
  li t1, 255
  beq t0, t1, vm_eval_block_start_loop
  li t1, 2
  bgtu s7, t1, vm_eval_block_start_loop

  mv a0, t0               # primitive id
  mv a1, s1               # receiver (lexical self)
  li a2, 0
  li a3, 0
  beqz s7, vm_eval_block_declared_primitive_call
  beqz s2, vm_eval_block_start_loop
  ld a2, 0(s2)
  li t1, 1
  beq s7, t1, vm_eval_block_declared_primitive_call
  ld a3, 8(s2)
vm_eval_block_declared_primitive_call:
  call primitive_dispatch
  beqz a0, vm_eval_block_exit
  li t1, 1
  beq a0, t1, vm_eval_block_exit

vm_eval_block_start_loop:
  li s6, 0                # instruction index

vm_eval_block_loop:
  ld t0, 16(sp)           # instruction count
  bgeu s6, t0, vm_eval_block_done

  li t1, 3
  mul t2, s6, t1
  add t3, s10, t2
  lbu t4, 0(t3)           # op
  lbu t5, 1(t3)           # op1
  lbu t6, 2(t3)           # op2

  li t0, BLOCK_OP_END
  beq t4, t0, vm_eval_block_done
  li t0, BLOCK_OP_PUSH_SELF
  beq t4, t0, vm_eval_block_push_self
  li t0, BLOCK_OP_PUSH_ARG
  beq t4, t0, vm_eval_block_push_arg
  li t0, BLOCK_OP_PUSH_CONST
  beq t4, t0, vm_eval_block_push_const
  li t0, BLOCK_OP_SEND
  beq t4, t0, vm_eval_block_send
  li t0, BLOCK_OP_DUP
  beq t4, t0, vm_eval_block_dup
  li t0, BLOCK_OP_POP
  beq t4, t0, vm_eval_block_pop
  li t0, BLOCK_OP_PUSH_LOCAL
  beq t4, t0, vm_eval_block_push_local
  li t0, BLOCK_OP_STORE_LOCAL
  beq t4, t0, vm_eval_block_store_local
  li t0, BLOCK_OP_PUSH_REF
  beq t4, t0, vm_eval_block_push_ref
  li t0, BLOCK_OP_STORE_REF
  beq t4, t0, vm_eval_block_store_ref
  li t0, BLOCK_OP_RETURN
  beq t4, t0, vm_eval_block_return
  j vm_eval_block_fail_header

vm_eval_block_push_self:
  sd s1, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_push_arg:
  bgeu t5, s7, vm_eval_block_fail_index
  bgeu t5, s3, vm_eval_block_fail_index
  beqz s2, vm_eval_block_fail_index
  slli t0, t5, 3
  add t1, s2, t0
  ld t2, 0(t1)
  sd t2, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_push_const:
  mv a0, s8               # constants base ptr
  ld a1, 24(sp)           # constants end ptr
  ld a2, 0(sp)            # constant count
  mv a3, t5               # constant index
  mv a4, s2               # current args ptr
  mv a5, s7               # current declared arg count
  mv a6, s5               # current arg-name ref table ptr
  ld a7, 40(sp)           # activation captured env ptr
  call vm_block_get_constant_value
  bnez a0, vm_eval_block_fail_index
  sd a1, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_send:
  li t0, 0
  beq t6, t0, vm_eval_block_send_unary
  li t0, 1
  beq t6, t0, vm_eval_block_send_binary
  li t0, 2
  beq t6, t0, vm_eval_block_send_keyword2
  j vm_eval_block_send_nary

vm_eval_block_send_unary:
  ld t0, 32(sp)           # stack base ptr
  beq s11, t0, vm_eval_block_fail_index

  mv a0, s9               # selectors base ptr
  ld a1, 8(sp)            # selector count
  mv a2, t5               # selector index
  call vm_block_selector_by_index
  bnez a0, vm_eval_block_fail_index

  ld a0, -8(s11)          # receiver value
  call vm_block_lookup_primitive_literal
  bltz a0, vm_eval_block_send_unary_fallback

  mv t0, a0               # primitive id
  ld a1, -8(s11)          # receiver
  li a2, 0
  li a3, 0
  mv a0, t0
  call primitive_dispatch
  beqz a0, vm_eval_block_send_unary_done
  li t1, 1
  beq a0, t1, vm_eval_block_propagate_return
  li t1, -6
  beq a0, t1, vm_eval_block_send_unary_cannot_return
  j vm_eval_block_send_unary_fallback

vm_eval_block_send_unary_cannot_return:
  call vm_make_cannot_return_value
  bnez a0, vm_eval_block_fail_send
  sd a1, -8(s11)
  j vm_eval_block_advance

vm_eval_block_send_unary_done:
  sd a1, -8(s11)
  j vm_eval_block_advance

vm_eval_block_send_unary_fallback:
  # Re-read current send selector index (op1) from bytecode stream.
  li t0, 3
  mul t1, s6, t0
  add t2, s10, t1
  lbu t3, 1(t2)
  mv a0, s9               # selectors base ptr
  ld a1, 8(sp)            # selector count
  mv a2, t3               # selector index
  call vm_block_selector_by_index
  bnez a0, vm_eval_block_fail_send
  ld a0, -8(s11)          # receiver value
  li a3, 0                # argc
  call vm_invoke_does_not_understand_literal
  bnez a0, vm_eval_block_fail_send
  sd a1, -8(s11)
  j vm_eval_block_advance

vm_eval_block_send_binary:
  ld t0, 32(sp)           # stack base ptr
  addi t1, t0, 16
  bltu s11, t1, vm_eval_block_fail_index

  mv a0, s9               # selectors base ptr
  ld a1, 8(sp)            # selector count
  mv a2, t5               # selector index
  call vm_block_selector_by_index
  bnez a0, vm_eval_block_fail_index

  ld a0, -16(s11)         # receiver value
  call vm_block_lookup_primitive_literal
  bltz a0, vm_eval_block_send_binary_fallback

  mv t0, a0               # primitive id
  ld a1, -16(s11)         # receiver
  ld a2, -8(s11)          # arg0
  li a3, 0
  mv a0, t0
  call primitive_dispatch
  beqz a0, vm_eval_block_send_binary_done
  li t1, 1
  beq a0, t1, vm_eval_block_propagate_return
  li t1, -6
  beq a0, t1, vm_eval_block_send_binary_cannot_return
  j vm_eval_block_send_binary_fallback

vm_eval_block_send_binary_cannot_return:
  call vm_make_cannot_return_value
  bnez a0, vm_eval_block_fail_send
  addi s11, s11, -16
  sd a1, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_send_binary_done:
  addi s11, s11, -16
  sd a1, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_send_binary_fallback:
  # Re-read current send selector index (op1) from bytecode stream.
  li t0, 3
  mul t1, s6, t0
  add t2, s10, t1
  lbu t3, 1(t2)
  mv a0, s9               # selectors base ptr
  ld a1, 8(sp)            # selector count
  mv a2, t3               # selector index
  call vm_block_selector_by_index
  bnez a0, vm_eval_block_fail_send
  ld a0, -16(s11)         # receiver value
  li a3, 1                # argc
  call vm_invoke_does_not_understand_literal
  bnez a0, vm_eval_block_fail_send
  addi s11, s11, -16
  sd a1, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_send_keyword2:
  ld t0, 32(sp)           # stack base ptr
  addi t1, t0, 24
  bltu s11, t1, vm_eval_block_fail_index

  mv a0, s9               # selectors base ptr
  ld a1, 8(sp)            # selector count
  mv a2, t5               # selector index
  call vm_block_selector_by_index
  bnez a0, vm_eval_block_fail_index

  ld a0, -24(s11)         # receiver value
  call vm_block_lookup_primitive_literal
  bltz a0, vm_eval_block_send_keyword2_fallback

  mv t0, a0               # primitive id
  ld a1, -24(s11)         # receiver
  ld a2, -16(s11)         # arg0
  ld a3, -8(s11)          # arg1
  mv a0, t0
  call primitive_dispatch
  beqz a0, vm_eval_block_send_keyword2_done
  li t1, 1
  beq a0, t1, vm_eval_block_propagate_return
  li t1, -6
  beq a0, t1, vm_eval_block_send_keyword2_cannot_return
  j vm_eval_block_send_keyword2_fallback

vm_eval_block_send_keyword2_cannot_return:
  call vm_make_cannot_return_value
  bnez a0, vm_eval_block_fail_send
  addi s11, s11, -24
  sd a1, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_send_keyword2_done:
  addi s11, s11, -24
  sd a1, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_send_keyword2_fallback:
  # Re-read current send selector index (op1) from bytecode stream.
  li t0, 3
  mul t1, s6, t0
  add t2, s10, t1
  lbu t3, 1(t2)
  mv a0, s9               # selectors base ptr
  ld a1, 8(sp)            # selector count
  mv a2, t3               # selector index
  call vm_block_selector_by_index
  bnez a0, vm_eval_block_fail_send
  ld a0, -24(s11)         # receiver value
  li a3, 2                # argc
  call vm_invoke_does_not_understand_literal
  bnez a0, vm_eval_block_fail_send
  addi s11, s11, -24
  sd a1, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_send_nary:
  # Requires receiver + argc arguments on the block eval stack.
  addi t0, t6, 1          # value count: receiver + args
  slli t0, t0, 3          # byte width
  ld t1, 32(sp)           # stack base ptr
  add t2, t1, t0
  bltu s11, t2, vm_eval_block_fail_index
  sd t0, 48(sp)           # preserve byte width across calls

  addi sp, sp, -16
  sd t6, 8(sp)            # preserve argc across selector lookup call
  mv a0, s9               # selectors base ptr
  ld a1, 8(sp)            # selector count
  mv a2, t5               # selector index
  call vm_block_selector_by_index
  ld t6, 8(sp)
  addi sp, sp, 16
  bnez a0, vm_eval_block_fail_index
  mv t4, a1               # selector bytes ptr
  mv t5, a2               # selector length

  ld t0, 48(sp)
  sub t3, s11, t0         # receiver slot ptr
  ld t0, 0(t3)            # receiver
  addi t2, t3, 8          # args ptr
  mv a0, t0               # receiver
  mv a1, t4               # selector bytes ptr
  mv a2, t5               # selector length
  mv a3, t2               # args ptr
  mv a4, t6               # argc
  call vm_invoke_dynamic_method_block_literal
  beqz a0, vm_eval_block_send_nary_apply
  li t1, 1
  beq a0, t1, vm_eval_block_propagate_return
  li t1, -6
  beq a0, t1, vm_eval_block_send_nary_cannot_return
  j vm_eval_block_send_nary_fallback

vm_eval_block_send_nary_cannot_return:
  addi sp, sp, -16
  sd t0, 8(sp)
  call vm_make_cannot_return_value
  ld t0, 8(sp)
  addi sp, sp, 16
  bnez a0, vm_eval_block_fail_send
  sub s11, s11, t0
  sd a1, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_send_nary_apply:
  ld t0, 48(sp)
  sub s11, s11, t0
  sd a1, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_send_nary_fallback:
  # Re-read current send selector index/argc from bytecode stream.
  li t0, 3
  mul t1, s6, t0
  add t2, s10, t1
  lbu t3, 1(t2)           # selector index

  mv a0, s9               # selectors base ptr
  ld a1, 8(sp)            # selector count
  mv a2, t3               # selector index
  call vm_block_selector_by_index
  bnez a0, vm_eval_block_fail_send

  li t0, 3
  mul t1, s6, t0
  add t2, s10, t1
  lbu a3, 2(t2)           # argc (raw)

  ld t0, 48(sp)
  sub t1, s11, t0
  ld a0, 0(t1)            # receiver
  call vm_invoke_does_not_understand_literal
  bnez a0, vm_eval_block_fail_send
  ld t0, 48(sp)
  sub s11, s11, t0
  sd a1, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_dup:
  ld t0, 32(sp)           # stack base ptr
  beq s11, t0, vm_eval_block_fail_index
  ld t1, -8(s11)
  sd t1, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_pop:
  ld t0, 32(sp)           # stack base ptr
  beq s11, t0, vm_eval_block_fail_index
  addi s11, s11, -8
  j vm_eval_block_advance

vm_eval_block_push_local:
  ld t0, 40(sp)           # activation captured env ptr
  beqz t0, vm_eval_block_fail_index
  ld t1, OBJ_SLOTS+40(t0) # tagged local count
  andi t2, t1, 1
  beqz t2, vm_eval_block_fail_index
  srai t1, t1, 1
  bgeu t5, t1, vm_eval_block_fail_index
  ld t2, OBJ_SLOTS+48(t0) # local values object ptr
  beqz t2, vm_eval_block_fail_index
  andi t3, t2, 1
  bnez t3, vm_eval_block_fail_index
  ld t3, OBJ_SLOT_COUNT(t2)
  bltu t3, t1, vm_eval_block_fail_index

  slli t3, t5, 3
  add t2, t2, t3
  addi t2, t2, OBJ_SLOTS
  ld t4, 0(t2)
  sd t4, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_store_local:
  ld t0, 32(sp)           # operand-stack base ptr
  beq s11, t0, vm_eval_block_fail_index

  ld t6, -8(s11)
  ld t0, 40(sp)           # activation captured env ptr
  beqz t0, vm_eval_block_fail_index
  ld t1, OBJ_SLOTS+40(t0) # tagged local count
  andi t2, t1, 1
  beqz t2, vm_eval_block_fail_index
  srai t1, t1, 1
  bgeu t5, t1, vm_eval_block_fail_index
  ld t2, OBJ_SLOTS+48(t0) # local values object ptr
  beqz t2, vm_eval_block_fail_index
  andi t3, t2, 1
  bnez t3, vm_eval_block_fail_index
  ld t3, OBJ_SLOT_COUNT(t2)
  bltu t3, t1, vm_eval_block_fail_index

  slli t3, t5, 3
  add t2, t2, t3
  addi t2, t2, OBJ_SLOTS
  sd t6, 0(t2)
  j vm_eval_block_advance

vm_eval_block_push_ref:
  # First resolve lexical captures from this block's declared arg-name table.
  mv t0, s5               # arg-name ref table ptr
  li t1, 0                # arg index
vm_eval_block_push_ref_arg_loop:
  bgeu t1, s7, vm_eval_block_push_ref_env
  add t2, t0, t1
  lbu t3, 0(t2)
  bne t3, t5, vm_eval_block_push_ref_arg_next
  bgeu t1, s3, vm_eval_block_fail_index
  beqz s2, vm_eval_block_fail_index
  slli t4, t1, 3
  add t6, s2, t4
  ld t2, 0(t6)
  sd t2, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance
vm_eval_block_push_ref_arg_next:
  addi t1, t1, 1
  j vm_eval_block_push_ref_arg_loop

vm_eval_block_push_ref_env:
  ld t6, 40(sp)           # activation captured env ptr
  beqz t6, vm_eval_block_push_ref_global
  addi sp, sp, -16
  sd t5, 8(sp)
  mv a0, t6
  mv a1, t5
  call vm_lookup_captured_ref_in_env
  ld t5, 8(sp)
  addi sp, sp, 16
  beqz a0, vm_eval_block_push_ref_env_hit
  j vm_eval_block_push_ref_global

vm_eval_block_push_ref_env_hit:
  sd a1, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_push_ref_global:
  la t0, vm_globals_valid
  add t0, t0, t5
  lbu t1, 0(t0)
  beqz t1, vm_eval_block_fail_index

  la t0, vm_globals_values
  slli t1, t5, 3
  add t0, t0, t1
  ld t2, 0(t0)
  sd t2, 0(s11)
  addi s11, s11, 8
  j vm_eval_block_advance

vm_eval_block_store_ref:
  ld t0, 32(sp)           # stack base ptr
  beq s11, t0, vm_eval_block_fail_index
  ld t6, -8(s11)          # value to store

  # First resolve assignment to current block argument refs.
  mv t0, s5               # arg-name ref table ptr
  li t1, 0
vm_eval_block_store_ref_arg_loop:
  bgeu t1, s7, vm_eval_block_store_ref_env
  add t2, t0, t1
  lbu t3, 0(t2)
  bne t3, t5, vm_eval_block_store_ref_arg_next
  bgeu t1, s3, vm_eval_block_fail_index
  beqz s2, vm_eval_block_fail_index
  slli t4, t1, 3
  add t2, s2, t4
  sd t6, 0(t2)
  j vm_eval_block_advance
vm_eval_block_store_ref_arg_next:
  addi t1, t1, 1
  j vm_eval_block_store_ref_arg_loop

vm_eval_block_store_ref_env:
  ld t0, 40(sp)           # activation captured env ptr
  beqz t0, vm_eval_block_store_ref_global
  addi sp, sp, -16
  sd t5, 8(sp)
  sd t6, 0(sp)
  mv a0, t0
  mv a1, t5               # ref index
  mv a2, t6               # value
  call vm_store_captured_ref_in_env
  ld t5, 8(sp)
  ld t6, 0(sp)
  addi sp, sp, 16
  beqz a0, vm_eval_block_advance

vm_eval_block_store_ref_global:
  la t0, vm_globals_values
  slli t1, t5, 3
  add t0, t0, t1
  sd t6, 0(t0)
  la t0, vm_globals_valid
  add t0, t0, t5
  li t1, 1
  sb t1, 0(t0)
  j vm_eval_block_advance

vm_eval_block_return:
  ld t0, 40(sp)           # activation captured env ptr
  beqz t0, vm_eval_block_fail_cannot_return
  ld t1, OBJ_SLOTS+56(t0) # home method token
  beqz t1, vm_eval_block_fail_cannot_return
  addi sp, sp, -16
  sd t0, 8(sp)
  mv a0, t1
  call vm_method_token_stack_contains
  ld t0, 8(sp)
  addi sp, sp, 16
  bnez a0, vm_eval_block_fail_cannot_return
  ld t1, OBJ_SLOTS+56(t0) # home method token
  la t2, vm_pending_return_token
  sd t1, 0(t2)

  ld t0, 32(sp)           # stack base ptr
  beq s11, t0, vm_eval_block_return_empty
  ld a1, -8(s11)
  li a0, 1
  j vm_eval_block_exit

vm_eval_block_return_empty:
  li a0, 1
  li a1, 0
  j vm_eval_block_exit

vm_eval_block_propagate_return:
  li a0, 1
  j vm_eval_block_exit

vm_eval_block_advance:
  addi s6, s6, 1
  j vm_eval_block_loop

vm_eval_block_done:
  ld t0, 32(sp)           # stack base ptr
  beq s11, t0, vm_eval_block_done_empty
  ld a1, -8(s11)
  li a0, 0
  j vm_eval_block_exit

vm_eval_block_done_empty:
  li a0, 0
  li a1, 0
  j vm_eval_block_exit

vm_eval_block_fail_send:
  li a0, -1
  li a1, 0
  j vm_eval_block_exit

vm_eval_block_fail_header:
  li a0, -1
  li a1, 0
  j vm_eval_block_exit

vm_eval_block_fail_type:
  li a0, -3
  li a1, 0
  j vm_eval_block_exit

vm_eval_block_fail_index:
  li a0, -4
  li a1, 0
  j vm_eval_block_exit

vm_eval_block_fail_cannot_return:
  li a0, -6
  li a1, 0
  j vm_eval_block_exit

vm_eval_block_exit:
  ld s11, 56(sp)
  ld s10, 64(sp)
  ld s9, 72(sp)
  ld s8, 80(sp)
  ld s7, 88(sp)
  ld s6, 96(sp)
  ld s5, 104(sp)
  ld s4, 112(sp)
  ld s3, 120(sp)
  ld s2, 128(sp)
  ld s1, 136(sp)
  ld s0, 144(sp)
  ld ra, 152(sp)
  addi sp, sp, 160
  ret

# a0=constants base ptr, a1=constants end ptr, a2=constant count, a3=constant index,
# a4=args ptr, a5=arg count, a6=arg-name refs ptr, a7=activation captured env ptr
# -> a0=status(0/-1), a1=value
vm_block_get_constant_value:
  addi sp, sp, -72
  sd ra, 64(sp)
  sd a1, 56(sp)           # constants end ptr
  sd a2, 48(sp)           # constant count
  sd a4, 40(sp)           # args ptr
  sd a5, 32(sp)           # arg count
  sd a6, 24(sp)           # arg-name refs ptr
  sd a7, 16(sp)           # activation captured env ptr

  bgeu a3, a2, vm_block_get_constant_value_fail

  mv t0, a0               # walker ptr
  li t1, 0                # current index

vm_block_get_constant_value_loop:
  ld t2, 56(sp)           # constants end ptr
  bgeu t0, t2, vm_block_get_constant_value_fail

  lbu t3, 0(t0)           # constant kind
  addi t0, t0, 1

  beq t1, a3, vm_block_get_constant_value_decode

  li t4, BLOCK_CONST_INT
  beq t3, t4, vm_block_get_constant_value_skip_int
  li t4, BLOCK_CONST_SYMBOL
  beq t3, t4, vm_block_get_constant_value_skip_len
  li t4, BLOCK_CONST_STRING
  beq t3, t4, vm_block_get_constant_value_skip_len
  li t4, BLOCK_CONST_BLOCK
  beq t3, t4, vm_block_get_constant_value_skip_len_u16
  j vm_block_get_constant_value_fail

vm_block_get_constant_value_skip_int:
  addi t0, t0, 8
  j vm_block_get_constant_value_next

vm_block_get_constant_value_skip_len:
  ld t2, 56(sp)           # constants end ptr
  bgeu t0, t2, vm_block_get_constant_value_fail
  lbu t5, 0(t0)           # payload length
  addi t0, t0, 1
  add t0, t0, t5
  j vm_block_get_constant_value_next

vm_block_get_constant_value_skip_len_u16:
  ld t2, 56(sp)           # constants end ptr
  addi t4, t0, 2
  bgtu t4, t2, vm_block_get_constant_value_fail
  lbu t5, 0(t0)
  lbu t6, 1(t0)
  slli t6, t6, 8
  or t5, t5, t6           # payload length (u16)
  addi t0, t0, 2
  add t0, t0, t5

vm_block_get_constant_value_next:
  ld t2, 56(sp)           # constants end ptr
  bgtu t0, t2, vm_block_get_constant_value_fail
  addi t1, t1, 1
  j vm_block_get_constant_value_loop

vm_block_get_constant_value_decode:
  li t4, BLOCK_CONST_INT
  beq t3, t4, vm_block_get_constant_value_decode_int
  li t4, BLOCK_CONST_SYMBOL
  beq t3, t4, vm_block_get_constant_value_decode_symbol
  li t4, BLOCK_CONST_STRING
  beq t3, t4, vm_block_get_constant_value_decode_string
  li t4, BLOCK_CONST_BLOCK
  beq t3, t4, vm_block_get_constant_value_decode_block
  j vm_block_get_constant_value_fail

vm_block_get_constant_value_decode_int:
  ld t2, 56(sp)           # constants end ptr
  addi t4, t0, 8
  bgtu t4, t2, vm_block_get_constant_value_fail
  ld t5, 0(t0)
  slli t5, t5, 1
  ori t5, t5, 1
  li a0, 0
  mv a1, t5
  j vm_block_get_constant_value_done

vm_block_get_constant_value_decode_symbol:
  ld t2, 56(sp)           # constants end ptr
  bgeu t0, t2, vm_block_get_constant_value_fail
  lbu t4, 0(t0)           # payload length
  addi t0, t0, 1
  add t5, t0, t4
  bgtu t5, t2, vm_block_get_constant_value_fail
  mv a0, t0
  mv a1, t4
  call vm_intern_symbol
  j vm_block_get_constant_value_done

vm_block_get_constant_value_decode_string:
  ld t2, 56(sp)           # constants end ptr
  bgeu t0, t2, vm_block_get_constant_value_fail
  lbu t4, 0(t0)           # payload length
  addi t0, t0, 1
  add t5, t0, t4
  bgtu t5, t2, vm_block_get_constant_value_fail
  mv a0, t0
  mv a1, t4
  call vm_make_string_object
  j vm_block_get_constant_value_done

vm_block_get_constant_value_decode_block:
  ld t2, 56(sp)           # constants end ptr
  addi t4, t0, 2
  bgtu t4, t2, vm_block_get_constant_value_fail
  lbu t5, 0(t0)
  lbu t6, 1(t0)
  slli t6, t6, 8
  or t5, t5, t6           # payload length (u16)
  addi t0, t0, 2
  add t4, t0, t5
  bgtu t4, t2, vm_block_get_constant_value_fail
  sd t0, 8(sp)            # nested payload ptr
  sd t5, 0(sp)            # nested payload len

  ld a0, 8(sp)            # nested block payload ptr
  ld a1, 0(sp)            # nested block payload len
  ld a2, 16(sp)           # shared activation env ptr
  call vm_make_block_object
  j vm_block_get_constant_value_done

vm_block_get_constant_value_fail:
  li a0, -1
  li a1, 0

vm_block_get_constant_value_done:
  ld ra, 64(sp)
  addi sp, sp, 72
  ret

# a0=parent env ptr, a1=arg-name refs ptr, a2=arg count, a3=args ptr,
# a4=local-name refs ptr, a5=local count, a6=locals ptr
# -> a0=status(0/-1), a1=env object ptr
vm_make_block_env_from_context:
  addi sp, sp, -104
  sd ra, 96(sp)
  sd a0, 88(sp)           # parent env ptr
  sd a1, 80(sp)           # arg-name refs ptr
  sd a2, 72(sp)           # arg count
  sd a3, 64(sp)           # args ptr
  sd a4, 56(sp)           # local-name refs ptr
  sd a5, 48(sp)           # local count
  sd a6, 40(sp)           # locals ptr
  sd zero, 24(sp)         # home method token

  # Determine lexical home method token: inherit from parent env when present,
  # otherwise bind to current dynamic method activation (if any).
  ld t0, 88(sp)           # parent env ptr
  beqz t0, vm_make_block_env_home_from_stack
  andi t1, t0, 1
  bnez t1, vm_make_block_env_home_from_stack
  ld t1, OBJ_PROTO(t0)
  la t2, proto_block_env
  bne t1, t2, vm_make_block_env_home_from_stack
  ld t1, OBJ_SLOT_COUNT(t0)
  li t2, 8
  bltu t1, t2, vm_make_block_env_home_from_stack
  ld t1, OBJ_SLOTS+56(t0)
  sd t1, 24(sp)
  j vm_make_block_env_home_ready
vm_make_block_env_home_from_stack:
  call vm_method_token_stack_top
  sd a0, 24(sp)
vm_make_block_env_home_ready:

  ld t0, 72(sp)
  li t1, OBJ_FIXED_SLOTS
  bgtu t0, t1, vm_make_block_env_fail
  ld t0, 48(sp)
  li t1, OBJ_FIXED_SLOTS
  bgtu t0, t1, vm_make_block_env_fail

  call vm_alloc_object
  bltz a0, vm_make_block_env_fail
  mv t0, a1               # env object
  sd t0, 32(sp)

  la t1, proto_block_env
  sd t1, OBJ_PROTO(t0)
  li t1, 8
  sd t1, OBJ_SLOT_COUNT(t0)

  ld t1, 88(sp)
  sd t1, OBJ_SLOTS(t0)    # parent env ptr
  ld t1, 80(sp)
  sd t1, OBJ_SLOTS+8(t0)  # arg-name refs ptr
  ld t1, 72(sp)
  slli t2, t1, 1
  ori t2, t2, 1
  sd t2, OBJ_SLOTS+16(t0) # tagged arg count
  sd zero, OBJ_SLOTS+24(t0) # arg values object ptr

  ld t1, 56(sp)
  sd t1, OBJ_SLOTS+32(t0) # local-name refs ptr
  ld t1, 48(sp)
  slli t2, t1, 1
  ori t2, t2, 1
  sd t2, OBJ_SLOTS+40(t0) # tagged local count
  sd zero, OBJ_SLOTS+48(t0) # local values object ptr
  ld t1, 24(sp)
  sd t1, OBJ_SLOTS+56(t0) # home method token

  # Materialize argument capture cells.
  ld t1, 72(sp)
  beqz t1, vm_make_block_env_build_locals
  ld t2, 64(sp)
  beqz t2, vm_make_block_env_fail
  call vm_alloc_object
  bltz a0, vm_make_block_env_fail
  mv t3, a1               # arg values object
  la t4, proto_object_array
  sd t4, OBJ_PROTO(t3)
  ld t4, 72(sp)
  sd t4, OBJ_SLOT_COUNT(t3)
  ld t2, 64(sp)
  li t0, 0
vm_make_block_env_copy_args_loop:
  bgeu t0, t4, vm_make_block_env_copy_args_done
  slli t1, t0, 3
  add t5, t2, t1
  ld t6, 0(t5)
  add t5, t3, t1
  addi t5, t5, OBJ_SLOTS
  sd t6, 0(t5)
  addi t0, t0, 1
  j vm_make_block_env_copy_args_loop
vm_make_block_env_copy_args_done:
  ld t5, 32(sp)
  sd t3, OBJ_SLOTS+24(t5)

vm_make_block_env_build_locals:
  # Materialize local capture cells.
  ld t1, 48(sp)
  beqz t1, vm_make_block_env_done
  ld t2, 40(sp)
  beqz t2, vm_make_block_env_fail
  call vm_alloc_object
  bltz a0, vm_make_block_env_fail
  mv t3, a1               # local values object
  la t4, proto_object_array
  sd t4, OBJ_PROTO(t3)
  ld t4, 48(sp)
  sd t4, OBJ_SLOT_COUNT(t3)
  ld t2, 40(sp)
  li t0, 0
vm_make_block_env_copy_locals_loop:
  bgeu t0, t4, vm_make_block_env_copy_locals_done
  slli t1, t0, 3
  add t5, t2, t1
  ld t6, 0(t5)
  add t5, t3, t1
  addi t5, t5, OBJ_SLOTS
  sd t6, 0(t5)
  addi t0, t0, 1
  j vm_make_block_env_copy_locals_loop
vm_make_block_env_copy_locals_done:
  ld t5, 32(sp)
  sd t3, OBJ_SLOTS+48(t5)

vm_make_block_env_done:
  ld t0, 32(sp)
  li a0, 0
  mv a1, t0
  j vm_make_block_env_exit

vm_make_block_env_fail:
  li a0, -1
  li a1, 0

vm_make_block_env_exit:
  ld ra, 96(sp)
  addi sp, sp, 104
  ret

# a0=env object ptr, a1=ref index -> a0=status(0/-1), a1=value
vm_lookup_captured_ref_in_env:
  mv t6, a0               # current env
  li a2, 0                # chain depth

vm_lookup_captured_ref_env_loop:
  beqz t6, vm_lookup_captured_ref_not_found
  addi a2, a2, 1
  li t1, 32
  bgtu a2, t1, vm_lookup_captured_ref_not_found
  andi t0, t6, 1
  bnez t0, vm_lookup_captured_ref_not_found
  ld t0, OBJ_PROTO(t6)
  la t1, proto_block_env
  bne t0, t1, vm_lookup_captured_ref_not_found

  ld t2, OBJ_SLOTS+16(t6) # tagged arg count
  andi t3, t2, 1
  beqz t3, vm_lookup_captured_ref_locals
  srai t2, t2, 1
  beqz t2, vm_lookup_captured_ref_locals
  li t1, OBJ_FIXED_SLOTS
  bgtu t2, t1, vm_lookup_captured_ref_locals

  ld t3, OBJ_SLOTS+8(t6)  # arg-name refs ptr
  beqz t3, vm_lookup_captured_ref_locals
  ld t4, OBJ_SLOTS+24(t6) # arg values object ptr
  beqz t4, vm_lookup_captured_ref_locals
  andi t5, t4, 1
  bnez t5, vm_lookup_captured_ref_locals
  ld t1, OBJ_SLOT_COUNT(t4)
  bltu t1, t2, vm_lookup_captured_ref_locals

  li t0, 0
vm_lookup_captured_ref_arg_loop:
  bgeu t0, t2, vm_lookup_captured_ref_locals
  add t1, t3, t0
  lbu t5, 0(t1)
  bne t5, a1, vm_lookup_captured_ref_arg_next
  slli t1, t0, 3
  add t1, t4, t1
  addi t1, t1, OBJ_SLOTS
  ld t5, 0(t1)
  li a0, 0
  mv a1, t5
  ret
vm_lookup_captured_ref_arg_next:
  addi t0, t0, 1
  j vm_lookup_captured_ref_arg_loop

vm_lookup_captured_ref_locals:
  ld t2, OBJ_SLOTS+40(t6) # tagged local count
  andi t3, t2, 1
  beqz t3, vm_lookup_captured_ref_next_env
  srai t2, t2, 1
  beqz t2, vm_lookup_captured_ref_next_env
  li t1, OBJ_FIXED_SLOTS
  bgtu t2, t1, vm_lookup_captured_ref_next_env

  ld t3, OBJ_SLOTS+32(t6) # local-name refs ptr
  beqz t3, vm_lookup_captured_ref_next_env
  ld t4, OBJ_SLOTS+48(t6) # local values object ptr
  beqz t4, vm_lookup_captured_ref_next_env
  andi t5, t4, 1
  bnez t5, vm_lookup_captured_ref_next_env
  ld t1, OBJ_SLOT_COUNT(t4)
  bltu t1, t2, vm_lookup_captured_ref_next_env

  li t0, 0
vm_lookup_captured_ref_local_loop:
  bgeu t0, t2, vm_lookup_captured_ref_next_env
  add t1, t3, t0
  lbu t5, 0(t1)
  bne t5, a1, vm_lookup_captured_ref_local_next
  slli t1, t0, 3
  add t1, t4, t1
  addi t1, t1, OBJ_SLOTS
  ld t5, 0(t1)
  li a0, 0
  mv a1, t5
  ret
vm_lookup_captured_ref_local_next:
  addi t0, t0, 1
  j vm_lookup_captured_ref_local_loop

vm_lookup_captured_ref_next_env:
  ld t6, OBJ_SLOTS(t6)    # parent env ptr
  j vm_lookup_captured_ref_env_loop

vm_lookup_captured_ref_not_found:
  li a0, -1
  li a1, 0
  ret

# a0=env object ptr, a1=ref index, a2=value -> a0=status(0/-1)
vm_store_captured_ref_in_env:
  mv t6, a0               # current env
  li a3, 0                # chain depth

vm_store_captured_ref_env_loop:
  beqz t6, vm_store_captured_ref_not_found
  addi a3, a3, 1
  li t1, 32
  bgtu a3, t1, vm_store_captured_ref_not_found
  andi t0, t6, 1
  bnez t0, vm_store_captured_ref_not_found
  ld t0, OBJ_PROTO(t6)
  la t1, proto_block_env
  bne t0, t1, vm_store_captured_ref_not_found

  ld t2, OBJ_SLOTS+16(t6) # tagged arg count
  andi t3, t2, 1
  beqz t3, vm_store_captured_ref_locals
  srai t2, t2, 1
  beqz t2, vm_store_captured_ref_locals
  li t1, OBJ_FIXED_SLOTS
  bgtu t2, t1, vm_store_captured_ref_locals

  ld t3, OBJ_SLOTS+8(t6)  # arg-name refs ptr
  beqz t3, vm_store_captured_ref_locals
  ld t4, OBJ_SLOTS+24(t6) # arg values object ptr
  beqz t4, vm_store_captured_ref_locals
  andi t5, t4, 1
  bnez t5, vm_store_captured_ref_locals
  ld t1, OBJ_SLOT_COUNT(t4)
  bltu t1, t2, vm_store_captured_ref_locals

  li t0, 0
vm_store_captured_ref_arg_loop:
  bgeu t0, t2, vm_store_captured_ref_locals
  add t1, t3, t0
  lbu t5, 0(t1)
  bne t5, a1, vm_store_captured_ref_arg_next
  slli t1, t0, 3
  add t1, t4, t1
  addi t1, t1, OBJ_SLOTS
  sd a2, 0(t1)
  li a0, 0
  ret
vm_store_captured_ref_arg_next:
  addi t0, t0, 1
  j vm_store_captured_ref_arg_loop

vm_store_captured_ref_locals:
  ld t2, OBJ_SLOTS+40(t6) # tagged local count
  andi t3, t2, 1
  beqz t3, vm_store_captured_ref_next_env
  srai t2, t2, 1
  beqz t2, vm_store_captured_ref_next_env
  li t1, OBJ_FIXED_SLOTS
  bgtu t2, t1, vm_store_captured_ref_next_env

  ld t3, OBJ_SLOTS+32(t6) # local-name refs ptr
  beqz t3, vm_store_captured_ref_next_env
  ld t4, OBJ_SLOTS+48(t6) # local values object ptr
  beqz t4, vm_store_captured_ref_next_env
  andi t5, t4, 1
  bnez t5, vm_store_captured_ref_next_env
  ld t1, OBJ_SLOT_COUNT(t4)
  bltu t1, t2, vm_store_captured_ref_next_env

  li t0, 0
vm_store_captured_ref_local_loop:
  bgeu t0, t2, vm_store_captured_ref_next_env
  add t1, t3, t0
  lbu t5, 0(t1)
  bne t5, a1, vm_store_captured_ref_local_next
  slli t1, t0, 3
  add t1, t4, t1
  addi t1, t1, OBJ_SLOTS
  sd a2, 0(t1)
  li a0, 0
  ret
vm_store_captured_ref_local_next:
  addi t0, t0, 1
  j vm_store_captured_ref_local_loop

vm_store_captured_ref_next_env:
  ld t6, OBJ_SLOTS(t6)    # parent env ptr
  j vm_store_captured_ref_env_loop

vm_store_captured_ref_not_found:
  li a0, -1
  ret

# a0=selectors base ptr, a1=selector count, a2=selector index
# -> a0=status(0/-1), a1=selector ptr, a2=selector length
vm_block_selector_by_index:
  bgeu a2, a1, vm_block_selector_by_index_fail
  mv t0, a0               # selector table walker
  li t1, 0                # current index
vm_block_selector_by_index_loop:
  lbu t2, 0(t0)           # current selector length
  addi t0, t0, 1
  beq t1, a2, vm_block_selector_by_index_found
  add t0, t0, t2
  addi t1, t1, 1
  j vm_block_selector_by_index_loop
vm_block_selector_by_index_found:
  mv a1, t0
  mv a2, t2
  li a0, 0
  ret
vm_block_selector_by_index_fail:
  li a0, -1
  li a1, 0
  li a2, 0
  ret

# a0=receiver value, a1=selector bytes ptr, a2=selector length -> a0=primitive id or -1
vm_block_lookup_primitive_literal:
  addi sp, sp, -16
  sd ra, 8(sp)
  sd a0, 0(sp)

  beqz a0, vm_block_lookup_primitive_not_found
  andi t0, a0, 1
  bnez t0, vm_block_lookup_primitive_integer

  ld t1, OBJ_PROTO(a0)
  beqz t1, vm_block_lookup_primitive_not_found
  mv a0, t1
  call vm_lookup_proto_chain
  j vm_block_lookup_primitive_done

vm_block_lookup_primitive_integer:
  la a0, proto_integer
  call vm_lookup_proto_chain
  j vm_block_lookup_primitive_done

vm_block_lookup_primitive_not_found:
  li a0, -1

vm_block_lookup_primitive_done:
  ld ra, 8(sp)
  addi sp, sp, 16
  ret

# Expects a1=receiver, returns receiver.
primitive_primitive_failed:
  li a0, 0
  ret

primitive_div_int_zero:
  li a0, -2
  li a1, 0
  ret

primitive_bad_type:
  li a0, -3
  li a1, 0
  ret

primitive_bad_index:
  li a0, -4
  li a1, 0
  ret

primitive_alloc_failed:
  li a0, -5
  li a1, 0
  ret

vm_alloc_object:
  la t0, vm_heap_ptr
  ld t1, 0(t0)
  beqz t1, vm_alloc_init
  j vm_alloc_ready

vm_alloc_init:
  la t1, vm_heap

vm_alloc_ready:
  li t2, OBJ_BYTES
  add t3, t1, t2
  la t4, vm_heap_end
  bgtu t3, t4, vm_alloc_fail

  sd t3, 0(t0)
  mv a1, t1
  li a0, 0
  ret

vm_alloc_fail:
  li a0, -1
  li a1, 0
  ret

primitive_unimplemented:
  li a0, -1
  li a1, 0
  ret

# a0 = byte
uart_putc:
  li t0, UART0_BASE
uart_wait_tx_ready:
  lbu t1, UART_LSR(t0)
  andi t1, t1, UART_LSR_THRE
  beqz t1, uart_wait_tx_ready
  sb a0, UART_THR(t0)
  ret

# -> a0 = byte
uart_getc:
  li t0, UART0_BASE
uart_wait_rx_ready:
  lbu t1, UART_LSR(t0)
  andi t1, t1, UART_LSR_DR
  beqz t1, uart_wait_rx_ready
  lbu a0, UART_RBR(t0)
  ret

# a0 = nibble(0..15)
uart_puthex_nibble:
  andi a0, a0, 0x0f
  li t0, 10
  bltu a0, t0, uart_puthex_nibble_digit
  addi a0, a0, 'a' - 10
  j uart_putc
uart_puthex_nibble_digit:
  addi a0, a0, '0'
  j uart_putc

# a0 = u32 value (low 32 bits emitted as 8 hex digits)
uart_puthex_u32:
  addi sp, sp, -16
  sd ra, 8(sp)
  sd s0, 0(sp)

  mv s0, a0
  srli a0, s0, 28
  call uart_puthex_nibble
  srli a0, s0, 24
  call uart_puthex_nibble
  srli a0, s0, 20
  call uart_puthex_nibble
  srli a0, s0, 16
  call uart_puthex_nibble
  srli a0, s0, 12
  call uart_puthex_nibble
  srli a0, s0, 8
  call uart_puthex_nibble
  srli a0, s0, 4
  call uart_puthex_nibble
  mv a0, s0
  call uart_puthex_nibble

  ld s0, 0(sp)
  ld ra, 8(sp)
  addi sp, sp, 16
  ret

# a0 = address of NUL-terminated string
uart_puts:
  addi sp, sp, -16
  sd ra, 8(sp)
  sd s0, 0(sp)

  mv s0, a0
uart_puts_loop:
  lbu t0, 0(s0)
  beqz t0, uart_puts_done
  mv a0, t0
  call uart_putc
  addi s0, s0, 1
  j uart_puts_loop

uart_puts_done:
  ld s0, 0(sp)
  ld ra, 8(sp)
  addi sp, sp, 16
  ret

# a0 = signed 64-bit integer
uart_putint:
  addi sp, sp, -48
  sd ra, 40(sp)
  sd s0, 32(sp)
  sd s1, 24(sp)
  sd s2, 16(sp)
  sd s3, 8(sp)

  mv s0, a0

  bnez s0, uart_putint_nonzero
  li a0, '0'
  call uart_putc
  j uart_putint_done

uart_putint_nonzero:
  bgez s0, uart_putint_abs_ready
  li a0, '-'
  call uart_putc
  neg s0, s0

uart_putint_abs_ready:
  la s1, intbuf_end
  li s2, 0

uart_putint_div_loop:
  li t0, 10
  remu t1, s0, t0
  divu s0, s0, t0
  addi t1, t1, '0'
  addi s1, s1, -1
  sb t1, 0(s1)
  addi s2, s2, 1
  bnez s0, uart_putint_div_loop

uart_putint_emit_loop:
  beqz s2, uart_putint_done
  lbu a0, 0(s1)
  call uart_putc
  addi s1, s1, 1
  addi s2, s2, -1
  j uart_putint_emit_loop

uart_putint_done:
  ld s3, 8(sp)
  ld s2, 16(sp)
  ld s1, 24(sp)
  ld s0, 32(sp)
  ld ra, 40(sp)
  addi sp, sp, 48
  ret

.section .rodata
boot_message:
  .asciz "recorz vm boot ok\n"
primitive_ready_message:
  .asciz "recorz primitives ready\n"
loop_message:
  .asciz "recorz interpreter loop\n"
vm_done_message:
  .asciz "recorz vm done\n"
vm_bad_header_message:
  .asciz "recorz vm error: bad bytecode header\n"
vm_bad_opcode_message:
  .asciz "recorz vm error: bad opcode\n"
vm_unsupported_send_message:
  .asciz "recorz vm error: unsupported send\n"
vm_primitive_failed_message:
  .asciz "recorz vm error: primitive failed\n"
vm_bad_ref_message:
  .asciz "recorz vm error: bad reference index\n"
vm_unbound_ref_message:
  .asciz "recorz vm error: unbound reference\n"
vm_div_zero_message:
  .asciz "recorz vm error: divide by zero\n"
vm_stack_underflow_message:
  .asciz "recorz vm error: stack underflow\n"
vm_cannot_return_message:
  .asciz "recorz vm error: cannot return\n"
cannot_return_runtime_message:
  .asciz "CannotReturn\n"
dnu_prefix_message:
  .asciz "recorz dnu: "
dnu_argc_message:
  .asciz " argc="
dnu_invalid_selector_message:
  .asciz "<invalid-selector>"
image_bridge_prefix_message:
  .asciz "RCIMG "

.align 3
proto_object:
  .dword 0
  .dword 13
  .dword proto_object_slots

.align 3
proto_slot:
  .dword proto_object
  .dword 3
  .dword proto_slot_slots

.align 3
proto_symbol:
  .dword proto_object
  .dword 0
  .dword 0

.align 3
proto_string:
  .dword proto_object
  .dword 3
  .dword proto_string_slots

.align 3
proto_float:
  .dword proto_object
  .dword 0
  .dword 0

.align 3
proto_scaled_decimal:
  .dword proto_object
  .dword 0
  .dword 0

.align 3
proto_block:
  .dword proto_object
  .dword 2
  .dword proto_block_slots

.align 3
proto_block_env:
  .dword proto_object
  .dword 0
  .dword 0

.align 3
proto_cannot_return:
  .dword proto_object
  .dword 2
  .dword proto_cannot_return_slots

.align 3
proto_object_array:
  .dword proto_object
  .dword 3
  .dword proto_object_array_slots

.align 3
proto_byte_array:
  .dword proto_object
  .dword 3
  .dword proto_byte_array_slots

.align 3
proto_integer:
  .dword proto_object
  .dword 5
  .dword proto_integer_slots

.align 3
proto_integer_slots:
  .dword selector_name_print
  .dword 5
  .dword PRIM_PRINT_INT

  .dword selector_name_plus
  .dword 1
  .dword PRIM_ADD_INT

  .dword selector_name_minus
  .dword 1
  .dword PRIM_SUB_INT

  .dword selector_name_mul
  .dword 1
  .dword PRIM_MUL_INT

  .dword selector_name_div
  .dword 1
  .dword PRIM_DIV_INT

.align 3
proto_object_slots:
  .dword selector_name_clone
  .dword 5
  .dword PRIM_CLONE_OBJECT

  .dword selector_name_add_method_do
  .dword 13
  .dword PRIM_ADD_METHOD

  .dword selector_name_add_slot
  .dword 14
  .dword PRIM_ADD_SLOT

  .dword selector_name_slot_named
  .dword 10
  .dword PRIM_SLOT_NAMED

  .dword selector_name_primitive_failed
  .dword 15
  .dword PRIM_PRIMITIVE_FAILED

  .dword selector_name_on_cannot_return
  .dword 15
  .dword PRIM_ON_CANNOT_RETURN

  .dword selector_name_does_not_understand_argc
  .dword 23
  .dword PRIM_DOES_NOT_UNDERSTAND_ARGC

  .dword selector_name_save_image
  .dword 9
  .dword PRIM_SAVE_IMAGE

  .dword selector_name_load_image
  .dword 10
  .dword PRIM_LOAD_IMAGE

  .dword selector_name_export_image
  .dword 12
  .dword PRIM_EXPORT_IMAGE

  .dword selector_name_import_image
  .dword 11
  .dword PRIM_IMPORT_IMAGE

  .dword selector_name_save_image_to_host
  .dword 15
  .dword PRIM_SAVE_IMAGE_TO_HOST

  .dword selector_name_load_image_from_host
  .dword 17
  .dword PRIM_LOAD_IMAGE_FROM_HOST

.align 3
proto_slot_slots:
  .dword selector_name_name
  .dword 4
  .dword PRIM_SLOT_NAME

  .dword selector_name_value
  .dword 5
  .dword PRIM_SLOT_VALUE

  .dword selector_name_value_put
  .dword 6
  .dword PRIM_SLOT_VALUE_PUT

.align 3
proto_string_slots:
  .dword selector_name_size
  .dword 4
  .dword PRIM_BYTES_SIZE

  .dword selector_name_at
  .dword 3
  .dword PRIM_BYTES_AT

  .dword selector_name_at_put
  .dword 7
  .dword PRIM_BYTES_AT_PUT

.align 3
proto_object_array_slots:
  .dword selector_name_size
  .dword 4
  .dword PRIM_OBJECT_ARRAY_SIZE

  .dword selector_name_at
  .dword 3
  .dword PRIM_OBJECT_ARRAY_AT

  .dword selector_name_at_put
  .dword 7
  .dword PRIM_OBJECT_ARRAY_AT_PUT

.align 3
proto_byte_array_slots:
  .dword selector_name_size
  .dword 4
  .dword PRIM_BYTES_SIZE

  .dword selector_name_at
  .dword 3
  .dword PRIM_BYTES_AT

  .dword selector_name_at_put
  .dword 7
  .dword PRIM_BYTES_AT_PUT

.align 3
proto_block_slots:
  .dword selector_name_value
  .dword 5
  .dword PRIM_BLOCK_VALUE

  .dword selector_name_value_put
  .dword 6
  .dword PRIM_BLOCK_VALUE_ARG

.align 3
proto_cannot_return_slots:
  .dword selector_name_print
  .dword 5
  .dword PRIM_PRINT_CANNOT_RETURN

  .dword selector_name_on_cannot_return
  .dword 15
  .dword PRIM_HANDLE_CANNOT_RETURN

selector_name_print:
  .ascii "print"
selector_name_plus:
  .ascii "+"
selector_name_minus:
  .ascii "-"
selector_name_mul:
  .ascii "*"
selector_name_div:
  .ascii "/"
selector_name_clone:
  .ascii "clone"
selector_name_add_method_do:
  .ascii "addMethod:do:"
selector_name_add_slot:
  .ascii "addSlot:value:"
selector_name_slot_named:
  .ascii "slotNamed:"
selector_name_primitive_failed:
  .ascii "primitiveFailed"
selector_name_on_cannot_return:
  .ascii "onCannotReturn:"
selector_name_does_not_understand_argc:
  .ascii "doesNotUnderstand:argc:"
selector_name_save_image:
  .ascii "saveImage"
selector_name_load_image:
  .ascii "loadImage:"
selector_name_export_image:
  .ascii "exportImage:"
selector_name_import_image:
  .ascii "importImage"
selector_name_save_image_to_host:
  .ascii "saveImageToHost"
selector_name_load_image_from_host:
  .ascii "loadImageFromHost"
selector_name_name:
  .ascii "name"
selector_name_size:
  .ascii "size"
selector_name_at:
  .ascii "at:"
selector_name_at_put:
  .ascii "at:put:"
selector_name_value:
  .ascii "value"
selector_name_value_put:
  .ascii "value:"
global_name_object:
  .ascii "Object"

.align 3
primitive_table:
  .dword primitive_noop
  .dword primitive_uart_putc
  .dword primitive_debug_break
  .rept 7
  .dword primitive_unimplemented
  .endr
  .dword primitive_print_int
  .dword primitive_add_int
  .dword primitive_sub_int
  .dword primitive_mul_int
  .dword primitive_div_int
  .rept 5
  .dword primitive_unimplemented
  .endr
  .dword primitive_clone_object
  .dword primitive_unimplemented
  .dword primitive_unimplemented
  .dword primitive_unimplemented
  .dword primitive_slot_name
  .dword primitive_slot_value
  .dword primitive_slot_value_put
  .dword primitive_add_slot
  .dword primitive_slot_named
  .dword primitive_add_method
  .dword primitive_unimplemented
  .dword primitive_primitive_failed
  .rept 8
  .dword primitive_unimplemented
  .endr
  .dword primitive_bytes_size
  .dword primitive_bytes_at
  .dword primitive_bytes_at_put
  .dword primitive_object_array_size
  .dword primitive_object_array_at
  .dword primitive_object_array_at_put
  .dword primitive_block_value
  .dword primitive_block_value_arg
  .dword primitive_print_cannot_return
  .dword primitive_on_cannot_return
  .dword primitive_handle_cannot_return
  .dword primitive_does_not_understand_argc
  .rept 76
  .dword primitive_unimplemented
  .endr
  .dword primitive_save_image
  .dword primitive_load_image
  .dword primitive_export_image
  .dword primitive_import_image
  .dword primitive_save_image_to_host
  .dword primitive_load_image_from_host
  .rept 122
  .dword primitive_unimplemented
  .endr

.section .data
.align 3
root_object_instance:
  .dword proto_object
  .dword 0
  .rept OBJ_FIXED_SLOTS
  .dword 0
  .endr

.section .bss
.align 3
vm_stack:
  .space VM_STACK_BYTES

.align 3
vm_block_stack:
  .space 512

.align 3
vm_block_args_tmp:
  .space 128

.align 3
vm_constants_values:
  .space 2048

.align 3
vm_globals_values:
  .space 2048

vm_globals_valid:
  .space 256

.align 3
vm_method_token_next:
  .space 8

.align 3
vm_method_token_depth:
  .space 8

.align 3
vm_method_token_stack:
  .space 512

.align 3
vm_pending_return_token:
  .space 8

.align 3
vm_symbol_count:
  .space 8

.align 3
vm_cannot_return_value:
  .space 8

.align 3
vm_symbol_data_ptrs:
  .space 2048

.align 3
vm_symbol_lengths:
  .space 2048

.align 3
vm_symbol_values:
  .space 2048

.align 3
vm_symbol_storage_used:
  .space 8

.align 3
vm_symbol_storage:
  .space VM_SYMBOL_STORAGE_BYTES

.align 3
vm_block_storage_used:
  .space 8

.align 3
vm_block_storage:
  .space VM_BLOCK_STORAGE_BYTES

.align 3
vm_image_buffer:
  .space VM_IMAGE_BUFFER_BYTES

.align 3
vm_heap_ptr:
  .space 8

.align 3
vm_heap:
  .space 65536
vm_heap_end:

.align 3
intbuf:
  .space 32
intbuf_end:
