//****************************************************************
// December 6, 2022
//
// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
// 
//   http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.
//
// Date: 2022-11-18
// Project: OmniXtend Remote Agent
// Comments: Reset Controller for OmniXtend Network Bridge and RISC-V CPU
//
//********************************
// File history:
//   2022-11-18: Original
//****************************************************************

module rstctrl_oxbridge #(
        parameter        MODE_MII2MAC =    0,   //Delay TYPE between PHY reset and MAC Reset (0=Reset done, 1=Status good)

        parameter       DELAY_MAC2RXD = 1023,   //Delay Cycles between MAC reset and RX Reset
        parameter       WIDTH_MAC2RXD =   10,   //Number of bits to hold above value

        parameter       DELAY_RXD2OXC =   31,   //Delay Cycles between RX Reset (or MAC reset) and OX Core Reset
        parameter       WIDTH_RXD2OXC =    5,   //Number of bits to hold above value
        parameter        MODE_RXD2OXC =    0,   //Delay mode for OX Core (0=Starts after RX Reset, 1=Starts after MAC reset)

        parameter       DELAY_OXC2CPU =   31,   //Delay Cycles between OX Core Reset and CPU reset
        parameter       WIDTH_OXC2CPU =    5    //Number of bits to hold above value
    )
    (
        input           clk,
        input           rst_,

        input           stat_phy_rst,
        input           stat_phy_good,

        output reg      reset_mii_,
        output reg      reset_mac_,
        output reg      reset_rxd_,
        output reg      reset_oxc_,
        output reg      reset_cpu_
    );

    wire ready_mac = (MODE_MII2MAC) ? stat_phy_good : stat_phy_rst;
    wire ready_rxd;
    wire ready_oxc;
    wire ready_cpu;

    always @(posedge clk) begin

        if (!rst_) begin
            reset_mii_  <= 1'b0;
            reset_mac_  <= 1'b0;
            reset_rxd_  <= 1'b0;
            reset_oxc_  <= 1'b0;
            reset_cpu_  <= 1'b0;
        end
        else begin
            reset_mii_  <= 1'b1;        //PHY reset releases immediately
            reset_mac_  <= ready_mac;   //LMAC reset released after PHY reset complete
            reset_rxd_  <= ready_rxd;   //Release LMAC RX Reset 1024 cycles after LMAC reset deassertion
            reset_oxc_  <= ready_oxc;   //OX Core reset released 32 Cycles after LMAC RX is enabled
            reset_cpu_  <= ready_cpu;   //Release CPU reset 32 cycles after OX Core reset released
        end


    end


    //Delay LMAC RX Enable for 1024 cycles after reset deassertion
    delayline #(WIDTH_MAC2RXD) dly_ready_rxd (
        .clk    (clk),
        .in     (ready_mac),
        .out    (ready_rxd),
        .delay  (DELAY_MAC2RXD)
    );

    //Delay OX Core reset for 32 cycles after LMAC RX enable
    delayline #(WIDTH_RXD2OXC) dly_ready_oxc (
        .clk    (clk),
        .in     (MODE_RXD2OXC ? ready_mac : ready_rxd),
        .out    (ready_oxc),
        .delay  (DELAY_RXD2OXC)
    );

    //Release CPU reset 32 cycles after OX Core reset released
    delayline #(WIDTH_OXC2CPU) dly_ready_cpu (
        .clk    (clk),
        .in     (ready_oxc),
        .out    (ready_cpu),
        .delay  (DELAY_OXC2CPU)
    );


endmodule