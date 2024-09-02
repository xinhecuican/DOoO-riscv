#!/bin/bash

git clone --recursive https://github.com/riscv/riscv-gnu-toolchain
pushd riscv-gnu-toolchain
sed -i '3s/MULTILIB_OPTIONS = /&march=rv32ima\/march=rv32imaf\//' gcc/gcc/config/riscv/t-elf-multilib
sed -i '9arv32ima \\' gcc/gcc/config/riscv/t-elf-multilib
sed -i '10arv32imaf \\' gcc/gcc/config/riscv/t-elf-multilib
sed -i '24amarch=rv32ima/mabi=ilp32 \\' gcc/gcc/config/riscv/t-elf-multilib
sed -i '25amarch=rv32imaf/mabi=ilp32f \\' gcc/gcc/config/riscv/t-elf-multilib
./configure --with-arch=rv64gc --with-abi=lp64d --enable-multilib
sudo make -j8
popd
sudo rm -rf riscv-gnu-toolchain

git clone https://github.com/riscv/riscv-isa-sim.git
pushd riscv-isa-sim
mkdir build && cd build
./configure
make -j8
sudo make install
popd
sudo rm -rf riscv-isa-sim