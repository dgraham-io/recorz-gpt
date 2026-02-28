.PHONY: test-host fixture vm-build vm-run vm-clean

test-host:
	PYTHONPATH=src python3 -m unittest discover -s tests -v

fixture:
	PYTHONPATH=src python3 scripts/generate_fixture.py \
		docs/code_example.md \
		--ast-out docs/fixtures/code_example.ast.json \
		--bytecode-out docs/fixtures/code_example.bytecode.json

vm-build:
	$(MAKE) -C vm all

vm-run: vm-build
	scripts/run_qemu_vm.sh vm/build/recorz.elf

vm-clean:
	$(MAKE) -C vm clean
