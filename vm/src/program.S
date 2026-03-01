.section .program, "a"
.globl recorz_program_blob
.globl recorz_program_blob_end

recorz_program_blob:
  .incbin "generated/program.bc"
recorz_program_blob_end:
