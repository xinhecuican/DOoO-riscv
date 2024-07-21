
LOG_PATH=log/
SEED=1168
S=0
E=2000
WB=0
WE=0
I ?= utils/NEMU/ready-to-run/microbench.bin

emu:
	make -C utils/difftest emu -j `nproc`

emu-run: emu
	mkdir -p $(LOG_PATH)
	build/emu -i "${I}" --diff=utils/NEMU/build/riscv64-nemu-interpreter-so -s 1168 -b ${S} -e ${E} -B $(WB) -E $(WE) --dump-wave --log-path=${LOG_PATH}

clean:
	make -C utils/difftest clean
