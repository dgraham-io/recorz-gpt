.section .rodata
.globl recorz_program_blob
.globl recorz_program_blob_end

recorz_program_blob:
  .incbin "generated/smoke.bc"
recorz_program_blob_end:
