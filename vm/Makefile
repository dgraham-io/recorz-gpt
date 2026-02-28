CROSS ?= riscv64-unknown-elf

CC := $(CROSS)-gcc
OBJCOPY := $(CROSS)-objcopy

BUILD_DIR := build
GENERATED_DIR := generated
ELF := $(BUILD_DIR)/recorz.elf
BIN := $(BUILD_DIR)/recorz.bin
PROGRAM_SRC := programs/smoke.rcz
PROGRAM_BC := $(GENERATED_DIR)/smoke.bc

SRCS := src/start.S src/vm.S src/program.S

CFLAGS := -march=rv64imac_zicsr -mabi=lp64 -mcmodel=medany -ffreestanding -nostdlib -nostartfiles
LDFLAGS := -T linker.ld -nostdlib -Wl,--build-id=none

.PHONY: all clean run FORCE

all: $(ELF) $(BIN)

$(ELF): $(SRCS) linker.ld $(PROGRAM_BC) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRCS)

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(PROGRAM_BC): FORCE $(PROGRAM_SRC) ../scripts/compile_vm_bytecode.py ../src/recorz/parser.py ../src/recorz/lexer.py ../src/recorz/bytecode.py | $(GENERATED_DIR)
	PYTHONPATH=../src python3 ../scripts/compile_vm_bytecode.py $(PROGRAM_SRC) $(PROGRAM_BC)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(GENERATED_DIR):
	mkdir -p $(GENERATED_DIR)

run: $(ELF)
	../scripts/run_qemu_vm.sh $(ELF)

clean:
	rm -f $(ELF) $(BIN) $(PROGRAM_BC)

FORCE:
