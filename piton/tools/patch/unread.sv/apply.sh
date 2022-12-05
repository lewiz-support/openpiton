#!/bin/bash

if [ x"${ARIANE_ROOT}" == "x" ]; then 
    echo "Error: ARIANE_ROOT not defined"
else
    if ! grep -q 'wire d = !d_i;' $ARIANE_ROOT/src/common_cells/src/unread.sv; then
        sed -i 's/endmodule/\n    wire d = !d_i;\n\nendmodule/g' $ARIANE_ROOT/src/common_cells/src/unread.sv
    fi
fi


