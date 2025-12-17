#!/bin/bash
# Clean compilation script for new PUF/TRNG protocols

# Remove old compiled files
echo "Cleaning old compilation..."
rm -rf work

# Create work library
vlib work

# Compile files in dependency order
echo "Compiling fuzzyextractor.v..."
vlog +acc fuzzyextractor.v || exit 1

echo "Compiling secure_key_system.v..."
vlog +acc secure_key_system.v || exit 1

echo "Compiling HMAC files..."
vlog +acc hmac_controller.v || exit 1
vlog +acc hmac_top.v || exit 1

echo "Compiling Keccak/SHA3 files..."
vlog +acc keccak_top.v || exit 1
vlog +acc keccak.v || exit 1
vlog +acc f_permutation.v || exit 1
vlog +acc round.v || exit 1
vlog +acc rconst.v || exit 1
vlog +acc padder.v || exit 1
vlog +acc padder1.v || exit 1

echo "Compiling testbench..."
vlog +acc secure_key_system_tb_new.v || exit 1

echo ""
echo "==================================="
echo "Compilation successful!"
echo "==================================="
echo ""
echo "To run simulation, use:"
echo "  vsim -c secure_key_system_tb_new -do \"run -all; quit\""
echo ""
