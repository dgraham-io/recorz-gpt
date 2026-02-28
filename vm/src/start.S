.section .text.start
.globl _start

.extern vm_boot
.extern uart_puts

.extern __bss_start
.extern __bss_end
.extern __stack_top

_start:
  la sp, __stack_top

  la t0, __bss_start
  la t1, __bss_end
1:
  bgeu t0, t1, 2f
  sd zero, 0(t0)
  addi t0, t0, 8
  j 1b

2:
  la t0, trap_handler
  csrw mtvec, t0

  call vm_boot

3:
  wfi
  j 3b

trap_handler:
  addi sp, sp, -16
  sd ra, 8(sp)

  la a0, trap_message
  call uart_puts

  ld ra, 8(sp)
  addi sp, sp, 16

4:
  wfi
  j 4b

.section .rodata
trap_message:
  .asciz "recorz trap entered\n"
