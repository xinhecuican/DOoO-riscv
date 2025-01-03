#!/bin/bash
set -e
rv32i=(
    "add" "addi" "and" "andi" "auipc" "beq" "bge" "bge"
    "bgeu" "blt" "bltu" "bne" "jal" "jalr" "lb" "lbu"
    "lh" "lhu" "lui" "lw" "or" "ori" "sb" "sh" "sll"
    "slli" "slt" "slti" "sltiu" "sltu" "sra" "srai"
    "srl" "srli" "sub" "sw" "xor" "xori" "fence_i"
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

rv32a=(
    "amoadd_w" "amoand_w" "amomax_w" "amomaxu_w" "amomin_w" 
    "amominu_w" "amoor_w" "amoswap_w" "amoxor_w" "lrsc"
)
rv32a_prefix="utils/riscv-tests/isa/rv32ua-p-"

rv32f=(
    "fclass" "fcmp" "fcvt" "fcvt_w" "fmin" "fadd" "fmadd" 
    "recoding" "fdiv"
)
rv32f_prefix="utils/riscv-tests/isa/rv32uf-p-"

benchmarks=(
    "median" "memcpy" "multiply" "qsort" "rsort" "dhrystone" "towers" "spmv"
    "mt-matmul" "mt-memcpy" "mm" "coremark"
)
benchmarks_prefix="utils/riscv-tests/benchmarks/"

select_tests=()

if [ $# -eq 0 ]; then
    echo "请至少提供一个参数来选择测试列表"
    exit 1
fi

args=("$@")

if [[ " ${args[@]} " =~ " all " ]]; then
    args=("rv32i" "rv32m" "rv32s" "rv32a" "rv32f" "benchmarks")
fi

for arg in "${args[@]}"; do
    case $arg in
        rv32i)
            for test in "${rv32i[@]}"; do
                selected_tests+=("${test}:${rv32i_prefix}${test}.bin")
            done
            ;;
        rv32m)
            for test in "${rv32m[@]}"; do
                selected_tests+=("${test}:${rv32m_prefix}${test}.bin")
            done
            ;;
        rv32s)
            for test in "${rv32s[@]}"; do
                selected_tests+=("${test}:${rv32s_prefix}${test}.bin")
            done
            ;;
        rv32a)
            for test in "${rv32a[@]}"; do
                selected_tests+=("${test}:${rv32a_prefix}${test}.bin")
            done
            ;;
        rv32f)
            for test in "${rv32f[@]}"; do
                selected_tests+=("${test}:${rv32f_prefix}${test}.bin")
            done
            ;;
        benchmarks)
            for test in "${benchmarks[@]}"; do
                selected_tests+=("${test}:${benchmarks_prefix}${test}.riscv.bin")
            done
            ;;
        *)
            # Check if the argument is in the benchmarks array
            if [[ " ${benchmarks[@]} " =~ " ${arg} " ]]; then
                selected_tests+=("${arg}:${benchmarks_prefix}${arg}.riscv.bin")
            else
                echo "未知的参数: $arg"
            fi
            ;;
    esac
done

current_time=log/$(date +"%Y-%m-%d_%H-%M-%S")
for test in "${selected_tests[@]}"; do
    test_name=$(echo "$test" | cut -d ':' -f 1)
    test_path=$(echo "$test" | cut -d ':' -f 2)
    make emu-run S=0 E=0 I=$test_path EMU_TRACE=0 LOG_PATH=${current_time}/
    mv ${current_time}/perf_0.log ${current_time}/${test_name}.log
done