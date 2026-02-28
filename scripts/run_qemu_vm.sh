#!/usr/bin/env bash
set -euo pipefail

ELF_PATH=${1:-vm/build/recorz.elf}

exec qemu-system-riscv64 \
  -machine virt \
  -nographic \
  -bios none \
  -kernel "$ELF_PATH" \
  -serial stdio \
  -monitor none
