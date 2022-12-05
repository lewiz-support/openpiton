#!/bin/bash

cd "$(dirname "$0")"
if [ x"${ARIANE_ROOT}" == "x" ]; then 
    echo "Error: ARIANE_ROOT not defined"
else
    cp gen_rom.py $ARIANE_ROOT/bootrom/gen_rom.py
fi