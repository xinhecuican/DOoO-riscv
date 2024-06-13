
WAVE_PATH=build/wave.vcd
SEED=1168
S=0
E=2000
I ?= utils/NEMU/ready-to-run/microbench.bin

emu:
	make -C utils/difftest emu -j `nproc`

emu-run: emu
	build/emu -i "${I}" --diff=utils/NEMU/build/riscv64-nemu-interpreter-so -s 1168 -b ${S} -e ${E} --dump-wave --wave-path=${WAVE_PATH}

clean:
	rm -f ${WAVE_PATH}
	make -C utils/difftest clean
