#!/bin/bash

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