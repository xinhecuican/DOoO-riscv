#!/bin/bash

install_dependencies() {
	sudo apt-get update
    sudo apt-get install autoconf automake autotools-dev curl python3 python3-pip libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev ninja-build git cmake libglib2.0-dev libslirp-dev
    sudo apt-get install -y gcc-11 g++-11 build-essential cmake tclsh ant default-jre swig google-perftools libgoogle-perftools-dev python3 python3-dev python3-pip uuid uuid-dev tcl-dev flex libfl-dev git pkg-config libreadline-dev bison libffi-dev wget python3-orderedmultidict
    sudo apt-get install git help2man perl python3 make
    sudo apt-get install g++  # Alternatively, clang
    sudo apt-get install libfl2
    sudo apt-get install libfl-dev
    sudo apt-get install zlibc zlib1g zlib1g-dev
    sudo apt-get install ccache
    sudo apt-get install mold
    sudo apt-get install libgoogle-perftools-dev numactl
    sudo apt-get install perl-doc
    sudo apt-get install git autoconf flex bison
    sudo apt-get install libsdl2-dev
    sudo apt-get install device-tree-compiler
    sudo apt-get install clang libsqlite3-dev
}

install_riscv_gnu_toolchain() {
    git clone --recursive https://github.com/riscv/riscv-gnu-toolchain
    pushd riscv-gnu-toolchain
	pushd gcc/gcc/config/riscv
	./multilib-generator rv32im-ilp32-- rv32ima-ilp32-- rv32imaf-ilp32f-- rv32imafc-ilp32f-- > t-linux-multilib
	popd
    ./configure --with-arch=rv64gc --with-abi=lp64d --enable-multilib --prefix=/opt/riscv
    sudo make linux -j`nproc`
    popd
    sudo rm -rf riscv-gnu-toolchain
}

install_riscv_isa_sim() {
    git clone https://github.com/riscv/riscv-isa-sim.git
    pushd riscv-isa-sim
    mkdir build && cd build
    ../configure
    make -j`nproc`
    sudo make install
    popd
    sudo rm -rf riscv-isa-sim
}

install_verilator() {
    git clone https://github.com/verilator/verilator
    pushd verilator
    git checkout v5.024-61-gee130cb20
    autoconf
    ./configure
    make -j `nproc`
    sudo make install
    popd
    sudo rm -rf verilator
}

install_dramsim3() {
    git clone https://github.com/OpenXiangShan/DRAMsim3.git ../utils/difftest/DRAMsim3
    cd ../utils/difftest/DRAMsim3
    git checkout fca1245acfff01a4f18830cd15675e904564aa2a
    mkdir build && cd build
    cmake -D COSIM=1 ..
    make -j`nproc`
}

install_yosys() {
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
}

install_dependencies
args=("$@")
for arg in "${args[@]}"; do
    case $arg in
        --riscv-gnu-toolchain) install_riscv_gnu_toolchain ;;
        --riscv-isa-sim) install_riscv_isa_sim ;;
        --verilator) install_verilator ;;
        --dramsim3) install_dramsim3 ;;
        --yosys) install_yosys ;;
        --all) 
            install_dependencies
            install_riscv_gnu_toolchain
            install_riscv_isa_sim
            install_verilator
            install_dramsim3
            install_yosys
            ;;
        *) 
            echo "Unknown option: $1"
            echo "Usage: $0 [--riscv-gnu-toolchain] [--riscv-isa-sim] [--verilator] [--dramsim3] [--synlig] [--all]"
            exit 1
            ;;
    esac
    shift
done
