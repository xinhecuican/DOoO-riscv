#!/bin/bash

git clone https://github.com/OpenXiangShan/DRAMsim3.git ../utils/difftest/DRAMsim3
cd ../utils/difftest/DRAMsim3
mkdir build && cd build
cmake -D COSIM=1 ..
make -j`nproc`