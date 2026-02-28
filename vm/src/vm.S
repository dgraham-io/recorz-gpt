.equ UART0_BASE, 0x10000000
.equ UART_THR, 0
.equ UART_LSR, 5
.equ UART_LSR_THRE, 0x20

.equ VM_STACK_BYTES, 4096

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
.equ PRIM_PRIMITIVE_FAILED, 31

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
  mv t6, t3               # selector index
  beqz t4, op_send_unary
  li t0, 1
  beq t4, t0, op_send_binary
  li t0, 2
  beq t4, t0, op_send_keyword2
  j vm_unsupported_send

op_send_unary:
  la t0, vm_stack
  beq s4, t0, vm_stack_underflow

  # Lookup primitive in receiver prototype chain.
  ld a0, -8(s4)           # receiver value
  mv a1, t6               # selector index
  call vm_lookup_method_primitive
  bltz a0, vm_unsupported_send

  mv t0, a0               # primitive id
  ld a1, -8(s4)           # receiver value
  li a2, 0
  li a3, 0
  mv a0, t0
  call primitive_dispatch

  bnez a0, op_send_unary_fallback

  # Replace receiver with result.
  sd a1, -8(s4)
  j op_advance

op_send_unary_fallback:
  ld a1, -8(s4)           # receiver value
  call vm_invoke_primitive_failed
  bnez a0, vm_primitive_failed
  sd a1, -8(s4)
  j op_advance

op_send_binary:
  la t0, vm_stack
  addi t1, t0, 16
  bltu s4, t1, vm_stack_underflow

  # Lookup primitive in receiver prototype chain.
  ld a0, -16(s4)          # receiver value
  mv a1, t6               # selector index
  call vm_lookup_method_primitive
  bltz a0, vm_unsupported_send

  mv t0, a0               # primitive id
  ld a1, -16(s4)          # receiver value
  ld a2, -8(s4)           # argument value
  li a3, 0
  mv a0, t0
  call primitive_dispatch

  bnez a0, op_send_binary_fallback

  # Pop receiver+arg and push primitive result.
  addi s4, s4, -16
  sd a1, 0(s4)
  addi s4, s4, 8
  j op_advance

op_send_binary_fallback:
  ld a1, -16(s4)          # receiver value
  call vm_invoke_primitive_failed
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
  mv a1, t6               # selector index
  call vm_lookup_method_primitive
  bltz a0, vm_unsupported_send

  mv t0, a0               # primitive id
  ld a1, -24(s4)          # receiver value
  ld a2, -16(s4)          # arg0 value
  ld a3, -8(s4)           # arg1 value
  mv a0, t0
  call primitive_dispatch

  bnez a0, op_send_keyword2_fallback

  # Pop receiver+2 args and push primitive result.
  addi s4, s4, -24
  sd a1, 0(s4)
  addi s4, s4, 8
  j op_advance

op_send_keyword2_fallback:
  ld a1, -24(s4)          # receiver value
  call vm_invoke_primitive_failed
  bnez a0, vm_primitive_failed
  addi s4, s4, -24
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

  call vm_alloc_object
  bltz a0, vm_intern_symbol_fail
  mv t2, a1

  la t3, proto_symbol
  sd t3, OBJ_PROTO(t2)
  li t3, 2
  sd t3, OBJ_SLOT_COUNT(t2)
  ld t3, 24(sp)
  sd t3, OBJ_SLOTS(t2)
  ld t3, 16(sp)
  slli t3, t3, 1
  ori t3, t3, 1
  sd t3, OBJ_SLOTS+8(t2)

  ld t1, 8(sp)
  slli t3, t1, 3

  la t4, vm_symbol_data_ptrs
  add t4, t4, t3
  ld t5, 24(sp)
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
  andi a0, a1, 0xff
  call uart_putc
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
  bne t4, a2, primitive_add_slot_next

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
  bne t4, a2, primitive_slot_named_next

  ld a1, OBJ_SLOTS+8(t3)
  li a0, 0
  ret

primitive_slot_named_next:
  addi t1, t1, 1
  j primitive_slot_named_loop

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

.align 3
proto_object:
  .dword 0
  .dword 4
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
  .dword 0
  .dword 0

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

  .dword selector_name_add_slot
  .dword 14
  .dword PRIM_ADD_SLOT

  .dword selector_name_slot_named
  .dword 10
  .dword PRIM_SLOT_NAMED

  .dword selector_name_primitive_failed
  .dword 15
  .dword PRIM_PRIMITIVE_FAILED

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
selector_name_add_slot:
  .ascii "addSlot:value:"
selector_name_slot_named:
  .ascii "slotNamed:"
selector_name_primitive_failed:
  .ascii "primitiveFailed"
selector_name_name:
  .ascii "name"
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
  .dword primitive_unimplemented
  .dword primitive_unimplemented
  .dword primitive_primitive_failed
  .rept 224
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
vm_constants_values:
  .space 2048

.align 3
vm_globals_values:
  .space 2048

vm_globals_valid:
  .space 256

.align 3
vm_symbol_count:
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
vm_heap_ptr:
  .space 8

.align 3
vm_heap:
  .space 4096
vm_heap_end:

.align 3
intbuf:
  .space 32
intbuf_end:
