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

git clone https://github.com/verilator/verilator
pushd verilator
git checkout v5.024-61-gee130cb20
autoconf
./configure
make -j `nproc`
sudo make install
popd
sudo rm -rf verilator

git clone https://github.com/OpenXiangShan/DRAMsim3.git ../utils/difftest/DRAMsim3
cd ../utils/difftest/DRAMsim3
mkdir build && cd build
cmake -D COSIM=1 ..
make -j`nproc`

sudo apt install -y gcc-11 g++-11 build-essential cmake tclsh ant default-jre swig google-perftools libgoogle-perftools-dev python3 python3-dev python3-pip uuid uuid-dev tcl-dev flex libfl-dev git pkg-config libreadline-dev bison libffi-dev wget python3-orderedmultidict
git clone https://github.com/chipsalliance/synlig.git
pushd synlig
    git submodule sync
    git submodule update --init --recursive third_party/{surelog,yosys}
    make install -j$(nproc)
    cd out/release
    sudo mv bin/* /usr/local/bin
    sudo mv lib/* /usr/local/lib
    sudo mv share/* /usr/local/share
    cd ../..
popd
rm -rf synlig