#!/bin/bash
set -e
rv32i=(
    "add" "addi" "and" "andi" "auipc" "beq" "bge" "bge"
    "bgeu" "blt" "bltu" "bne" "jal" "jalr" "lb" "lbu"
    "lh" "lhu" "lui" "lw" "or" "ori" "sb" "sh" "sll"
    "slli" "slt" "slti" "sltiu" "sltu" "sra" "srai"
    "srl" "srli" "sub" "sw" "xor" "xori"
)
rv32i_prefix="utils/riscv-tests/isa/rv32ui-p-"

rv32m=(
    "div" "divu" "mul" "mulh" "mulhsu" "mulhu" "rem" "remu"
)
rv32m_prefix="utils/riscv-tests/isa/rv32um-p-"

rv32s=(
    "csr" "sbreak" "scall" "ill_csr" "dirty" "lam" "wfi"
)
rv32s_prefix="utils/riscv-tests/isa/rv32si-p-"

benchmarks=(
    "median" "memcpy" "multiply" "qsort" "rsort" "uart" "towers"
)
benchmarks_prefix="utils/riscv-tests/benchmarks/"

select_tests=()

if [ $# -eq 0 ]; then
    echo "请至少提供一个参数来选择测试列表"
    exit 1
fi

for arg in "$@"; do
    case $arg in
        rv32i)
            for test in "${rv32i[@]}"; do
                selected_tests+=("${rv32i_prefix}${test}.bin")
            done
            ;;
        rv32m)
            for test in "${rv32m[@]}"; do
                selected_tests+=("${rv32m_prefix}${test}.bin")
            done
            ;;
        rv32s)
            for test in "${rv32s[@]}"; do
                selected_tests+=("${rv32s_prefix}${test}.bin")
            done
            ;;
        benchmarks)
            for test in "${benchmarks[@]}"; do
                selected_tests+=("${benchmarks_prefix}${test}.riscv.bin")
            done
            ;;
        *)
            # Check if the argument is in the benchmarks array
            if [[ " ${benchmarks[@]} " =~ " ${arg} " ]]; then
                selected_tests+=("${benchmarks_prefix}${arg}.riscv.bin")
            else
                echo "未知的参数: $arg"
            fi
            ;;
    esac
done

for test in "${selected_tests[@]}"; do
    make emu-run S=0 E=0 I=$test EMU_TRACE=0
done