// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Michael Schaffner <schaffner@iis.ee.ethz.ch>, ETH Zurich
// Date: 26.11.2018
// Description: Simple hello world program that prints 32 times "hello world".
//
// UART Code retrieved from Ariane OpenPiton Linux Bootloader

#include <stdio.h>
#include <stdint.h>

#define UART_BASE 0xFFF0C2C000

#define UART_RBR UART_BASE + 0
#define UART_THR UART_BASE + 0
#define UART_INTERRUPT_ENABLE UART_BASE + 1
#define UART_INTERRUPT_IDENT UART_BASE + 2
#define UART_FIFO_CONTROL UART_BASE + 2
#define UART_LINE_CONTROL UART_BASE + 3
#define UART_MODEM_CONTROL UART_BASE + 4
#define UART_LINE_STATUS UART_BASE + 5
#define UART_MODEM_STATUS UART_BASE + 6
#define UART_DLAB_LSB UART_BASE + 0
#define UART_DLAB_MSB UART_BASE + 1

void write_reg_u8(uintptr_t addr, uint8_t value) {
    volatile uint8_t *loc_addr = (volatile uint8_t *)addr;
    *loc_addr = value;
}

uint8_t read_reg_u8(uintptr_t addr) {
    return *(volatile uint8_t *)addr;
}

int is_transmit_empty() {
    return read_reg_u8(UART_LINE_STATUS) & 0x20;
}

void write_serial(char a) {
    while (is_transmit_empty() == 0) {};
    write_reg_u8(UART_THR, a);
}

void init_uart(uint32_t freq, uint32_t baud) {
    uint32_t divisor = freq / (baud << 4);

    write_reg_u8(UART_INTERRUPT_ENABLE, 0x00);          // Disable all interrupts
    write_reg_u8(UART_LINE_CONTROL, 0x80);              // Enable DLAB (set baud rate divisor)
    write_reg_u8(UART_DLAB_LSB, divisor);               // divisor (lo byte)
    write_reg_u8(UART_DLAB_MSB, (divisor >> 8) & 0xFF); // divisor (hi byte)
    write_reg_u8(UART_LINE_CONTROL, 0x03);              // 8 bits, no parity, one stop bit
    write_reg_u8(UART_MODEM_CONTROL, 0x20);             // Autoflow mode
}

// returns number of characters printed
int print_uart(const char *str) {
    int num = 0;
    const char *cur = &str[0];
    while (*cur != '\0') {
        write_serial((uint8_t)*cur);
        ++cur;
        ++num;
    }
    return num;
}

int main(int argc, char ** argv) {
    
    //UART FREQ = 100000000
    init_uart(100000000, 115200);

    //Wait for UART Init
    while ((read_reg_u8(UART_MODEM_STATUS) & 0xF0) != 0xF0) {};

    print_uart("This is a test!\r\n");

    for (int k = 0; k < 32; k++) {
        // assemble number and print
        printf("Hello world, I am HART %d! Counting (%d of 32)...\r\n", argv[0][0], k);
    }
    
    printf("Done!\r\n");
    
    return 0;
}
