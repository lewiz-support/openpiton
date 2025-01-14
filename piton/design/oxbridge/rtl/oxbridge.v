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
// Date: 2022-11-14
// Project: OmniXtend Remote Agent
// Comments: NoC to OmniXtend Network Bridge for RISC-V CPU
//
//********************************
// File history:
//   2022-11-14: Original
//****************************************************************

//TODO: guard this whole file with "`ifdef OXAGENT_EN"?

//If running a synthesis, automatically use LMAC and PHY IP
//  Vivado automatically defines SYNTHESIS when running a synthesis
`ifdef SYNTHESIS
    `define USEIPNET
`endif


module oxbridge #(
        parameter   DELAY_TIME  = 400,
        parameter   DELAY_WIDTH =  16,

        parameter   NOC_WIDTH   =  64,

        parameter   SRC_MAC     = 48'h001232_FFFF18,
        parameter   DST_MAC     = 48'h001232_FFFFFA
    )
    (
        input                       reset_mii_,
        input                       reset_mac_,
        input                       reset_rxd_,
        input                       reset_oxc_,


        //Free Running and System Clock
        input                       mclk,
        input                       sclk,

        //GT Reference Clock
        input                       gt_refclk_p,        //i-1, Differential GT Reference Clock (Positive)
        input                       gt_refclk_n,        //i-1, Differential GT Reference Clock (Negative)
        output                      gt_refclk,          //o-1, PHY generated ref clock

        //GT Signals
        input      [1-1:0]          gt_rxp_in,          //i-1, ANALOG QSFP RX Serial Lane (Positive)
        input      [1-1:0]          gt_rxn_in,          //i-1, ANALOG QSFP RX Serial Lane (Negative)
        output     [1-1:0]          gt_txp_out,         //o-1, ANALOG QSFP TX Serial Lane (Positive)
        output     [1-1:0]          gt_txn_out,         //o-1, ANALOG QSFP TX Serial Lane (Negative)

        //NOC from CPU Chipset (TX Path)
        input      [NOC_WIDTH-1:0]  noc_in_data,        //i-NOC_WIDTH, Incoming NOC Command Data
        input                       noc_in_valid,       //i-1, Incoming NOC Command Data Valid
        output                      noc_in_ready,       //o-1, OX Bridge Ready for NOC Commands

        //NOC to CPU Chipset (RX Path)
        output     [NOC_WIDTH-1:0]  noc_out_data,       //o-NOC_WIDTH, Outgoing NOC Response Data
        output                      noc_out_valid,      //o-1, Outgoing NOC Response Data Valid
        input                       noc_out_ready,      //i-1, CPU Ready for NOC Responses

        //Status
        output                      stat_phy_rst,       //o-1, PHY reset completed
        output                      stat_phy_good       //o-1, PHY reset completed AND status is good

    ); // I/O ports



    //================================================================//
    //  Clocks

    wire    rx_clk_out; //PHY: RX SERDES Clock (not necessarily in sync with rxrecclk)
    wire    tx_mii_clk; //PHY: TX SERDES & MII Clock
    wire    rxrecclk;   //PHY: Clock recovered from GT RX


    //================================================================//
    //  PHY Reset Detection

    //Status & Other Generated Signals
    wire    reset_usr_tx;   //TX Reset Generated by PHY
    wire    reset_usr_rx;   //RX Reset Generated by PHY
    wire    phy_rxgood;     //PHY RX Status
    wire    phy_txbad;      //PHY TX Status


//If using PHY, detect its reset status
//Otherwise, bypass detector
`ifdef USEIPNET
    //Double Buffer reset_usr_*x
    wire reset_usr_rx_mclk;
    wire reset_usr_tx_mclk;
    synchronizer_reg sync_reset_usr_rx (mclk, reset_usr_rx, reset_usr_rx_mclk);
    synchronizer_reg sync_reset_usr_tx (mclk, reset_usr_tx, reset_usr_tx_mclk);

    //Double Buffer PHY status
    wire phy_rxgood_mclk;
    wire phy_txbad_mclk;
    synchronizer_reg sync_phy_rxgood (mclk, phy_rxgood, phy_rxgood_mclk);
    synchronizer_reg sync_phy_txbad  (mclk, phy_txbad,  phy_txbad_mclk );

    //PHY Reset Detection/Controller
    rstctrl_phy rstctrl_phy(
        .clk        (mclk),
        .reset_     (reset_mii_),

        .rst_rx     (reset_usr_rx_mclk),
        .rst_tx     (reset_usr_tx_mclk),

        .stat_rx    (phy_rxgood_mclk),
        .stat_tx    (!phy_txbad_mclk),

        .rst_done   (stat_phy_rst),
        .stat_good  (stat_phy_good)
    );
`else
    assign stat_phy_rst  = 1'b1;
    assign stat_phy_good = 1'b1;
`endif

    //================================================================//


    //================================================================//
    //  NOC Delay Unit

    //Connection between NOC Delay Unit and OX Core
    wire                        noc_tmp_ready;
    wire                        noc_tmp_valid;

    //Delay Status
    wire                        noc_dlya;

    //Delay time value driven by VIO
    wire [DELAY_WIDTH-1:0]      delay_time;


    //AXIS/NoC Delay Unit
    //Enforces minimum cycles between NoC requests
    axis_delay #(
        .DELAY_WIDTH        (DELAY_WIDTH)   //Delay counter width
    ) delay (
        .clk                (sclk),         //i-1
        .reset_             (reset_mac_),   //i-1

        //AXIS Bus In
        .axis_m_tvalid      (noc_in_valid), //i-1, Valid signal from master
        .axis_m_tlast       (0),            //i-1, Last signal from master
        .axis_m_tready      (noc_in_ready), //o-1, Ready signal to master

        //AXIS Bus Out
        .axis_s_tvalid      (noc_tmp_valid),//o-1, Valid signal to slave
        .axis_s_tready      (noc_tmp_ready),//i-1, Ready signal from slave

        //Control IO
        .enable             (|delay_time),  //i-1, Enable the delay
        .mode               (0),            //i-1, If asserted, delay triggers on valid/last, otherwise on ready
        .delay              (delay_time),   //i-DELAY_WIDTH, Delay time in cycles
        .active             (noc_dlya),     //o-1, Asserted while the delay is currently active

        //Debug
        .test               ()              //o-1 debug
    );

//////For synthesis, use a VIO to control delay
//////Otherwise use parameter 'DELAY_TIME'
////`ifdef SYNTHESIS
////    //Real-time configurable delay through debug core
////    vio_1x16 vio_dly (
////        .clk                (sclk),         //i-1
////        .probe_out0         (delay_time)    //o-16
////    );
////`else
    assign delay_time = DELAY_TIME;
////`endif



    //================================================================//
    //  OX_CORE

    //OX_CORE Configuration
    wire            prb_ack_mode    = 0;
    wire            lewiz_noc_mode  = 0;

    //TX to LMAC
    wire [255:0]    ox2m_tx_data;
    wire            ox2m_tx_wren;
    wire            ox2m_tx_full;
    wire [12:0]     ox2m_tx_usedw;

    //RX from LMAC
    wire [63:0]     m2ox_rxi_data;
    wire            m2ox_rxi_rden;
    wire            m2ox_rxi_empty;
    wire [12:0]     m2ox_rxi_usedw;

    wire [255:0]    m2ox_rxp_data;
    wire            m2ox_rxp_rden;
    wire            m2ox_rxp_empty;
    wire [12:0]     m2ox_rxp_usedw;

    //Used Word Lines are all 13-bit for the sake of the ILA
    //Tie down any unused bits
    assign  m2ox_rxi_usedw[12:10]   = 'b0;


    OX_CORE #(
        .SRC_MAC    (SRC_MAC),

        //If using simulated endpoint, Dst MAC must be all zero
        `ifndef USEIPNET
            .DST_MAC    (48'b0)
        `else
            .DST_MAC    (DST_MAC)
        `endif
    )
    OX_CORE_U1  (
        .clk                        (sclk),
        .rst_                       (reset_oxc_),

        //config signals
        //  prback_mode: 0 = ProbeAck with Data; 1 = ProbeAck with no data (for testing only)
        .prb_ack_mode               (prb_ack_mode),                 //i-1

        //  lewiz_noc_mode: 0 = standard NOC protocol mode (max datasize = 64 bytes)
        //                  1 = LeWiz NOC mode, extended data size to 2KBytes
        .lewiz_noc_mode             (lewiz_noc_mode),

        //--------------------------------//

        //TX Path from NOC
        .noc_in_data                (noc_in_data),                  // i-64
        .noc_in_valid               (noc_tmp_valid),                // i-1
        .noc_in_ready               (noc_tmp_ready),                // o-1

        //RX Path to NOC
        .noc_out_data               (noc_out_data),                 // o-64
        .noc_out_valid              (noc_out_valid),                // o-1
        .noc_out_ready              (noc_out_ready),                // i-1

        //--------------------------------//

        //TX Path to LMAC
        .ox2m_tx_data               (ox2m_tx_data),                 // o-256
        .ox2m_tx_we                 (ox2m_tx_wren),                 // o-1
        .m2ox_tx_fifo_full          (ox2m_tx_full),                 // o-1
        .m2ox_tx_fifo_wrused        (ox2m_tx_usedw),                // i-13
    //  .ox2m_tx_be                 (),                             //(optional) Byte enable

        //RX Path from LMAC
        .m2ox_rx_ipcs_data          ({48'b0,m2ox_rxi_data[63:48]}), // i-64     //NOTE: LMAC IPCS has byte count in upper 16,
        .ox2m_rx_ipcs_rden          (m2ox_rxi_rden),                // o-1      //      but OX_CORE expects it in lower 16
        .m2ox_rx_ipcs_empty         (m2ox_rxi_empty),               // i-1
        .m2ox_rx_ipcs_usedword      (m2ox_rxi_usedw),               // i-7

        .m2ox_rx_pkt_data           (m2ox_rxp_data),                // i-256
        .ox2m_rx_pkt_rden           (m2ox_rxp_rden),                // o-1
        .m2ox_rx_pkt_empty          (m2ox_rxp_empty),               // i-1
        .m2ox_rx_pkt_usedword       (m2ox_rxp_usedw),               // i-7
        .ox2m_rx_pkt_rd_cycle       ()
    );



//If running synthesis, use LMAC and PHY
`ifdef USEIPNET

    //================================================================//
    //  LMAC

    //LMAC Mode Control Signals
    wire                        fail_over = 1'b0;

//  wire    [ 31:0]             fmac_ctrl  = 32'h00000808;  //Enable CRC checking and Broadcast reception
    wire    [ 31:0]             fmac_ctrl  = 32'h00000008;  //Enable CRC checking, no Broadcast reception
    wire    [ 31:0]             fmac_ctrl1 = 32'h000005ee;

    wire    [ 31:0]             mac_pause_value = 32'hffff0000;
    wire    [ 47:0]             mac_addr0 = SRC_MAC;

    wire                        FIFO_OV_IPEND;


    //----------------------------------------------------------------//
    //  CGMII Signals

    wire        [255:0]         cgmii_txd;              //DATA_WIDTH
    wire        [31:0]          cgmii_txc;              //CTRL_WIDTH

    wire        [255:0]         cgmii_rxd;              //DATA_WIDTH
    wire        [31:0]          cgmii_rxc;              //CTRL_WIDTH

    `ifdef SYNTHESIS
    //Hardwire CGMII portion not driven by PHY
    assign                      cgmii_rxd[255:64] = {24{8'h07}};
    assign                      cgmii_rxc[31:8] = 24'hFFFFFF;
    `endif

    LMAC_CORE_TOP LMAC (
        //Clocks and Reset
        .clk                        (sclk),                 //i-1, User Clock
        .xA_clk                     (tx_mii_clk),           //i-1, XGMII/CGMII clock
        .reset_                     (reset_mac_),           //i-1, FMAC specific reset (also follows PCIE RST)
        .cgmii_reset_               (reset_mii_),           //i-1, Internally unused

        //Mode Control
        .mode_10G                   (1'b1),                 //i-1, Activate speed mode  10G (selected)
        .mode_25G                   (1'b0),                 //i-1, Activate speed mode  25G
        .mode_40G                   (1'b0),                 //i-1, Activate speed mode  40G
        .mode_50G                   (1'b0),                 //i-1, Activate speed mode  50G
        .mode_100G                  (1'b0),                 //i-1, Activate speed mode 100G

        .TCORE_MODE                 (1'b1),                 //i-1, if TOE Core = 1  //26 JUNE 2018: forced to zero because it is not used.

        //----------------------------------------------------------------//

        //TX Path FIFO Interface
        .tx_mac_data                (ox2m_tx_data),         //i-256
        .tx_mac_wr                  (ox2m_tx_wren),         //i-1
        .tx_mac_full                (ox2m_tx_full),         //o-1
        .tx_mac_usedw               (ox2m_tx_usedw),        //o-13

        //RX Path Packet FIFO Interface
        .rx_mac_data                (m2ox_rxp_data),        //o-256
        .rx_mac_rd                  (m2ox_rxp_rden),        //i-1
        .rx_mac_empty               (m2ox_rxp_empty),       //o-1
        .rx_mac_ctrl                (m2ox_rxp_ctrl),        //o-8, rsvd, pkt_end, pkt_start    //TODO: Port is actually 32-bit??
        .rx_mac_rdusedw             (m2ox_rxp_usedw),       //o-13
        .rx_mac_usedw_dbg           (   ),                  //o-12
        .rx_mac_full_dbg            (   ),                  //o-1

        //RX Path IPCS FIFO Interface
        .ipcs_fifo_dout             (m2ox_rxi_data),        //o-64
        .cs_fifo_rd_en              (m2ox_rxi_rden),        //i-1
        .cs_fifo_empty              (m2ox_rxi_empty),       //o-1
        .ipcs_fifo_rdusedw          (m2ox_rxi_usedw),       //o-10


        //----------------------------------------------------------------//
        //CGMII Signals
        .cgmii_txd                  (cgmii_txd),                //o-256
        .cgmii_txc                  (cgmii_txc),                //o-32

        .cgmii_rxd                  (cgmii_rxd),                //i-256
        .cgmii_rxc                  (cgmii_rxc),                //i-32

        .cgmii_led_                 (2'b0),                     //i-2

        .xauiA_linkup               (),                         //o-1, link up for either 10G or 10G mode  //TODO: 10 or 10 ???? (10 or 100?)


        //----------------------------------------------------------------//
        //Register Interface

        .host_addr_reg              (16'b0),                    //i-16, Register read address (UNUSED)
        .SYS_ADDR                   (4'b0),                     //i-4,  system assigned addr for the FMAC (UNUSED)
        .reg_rd_start               (1'b0),                     //i-1,  Start Register Read (UNUSED)
        .reg_rd_done_out            (),                         //o-1,  Register Read Done(UNUSED)
        .FMAC_REGDOUT               (),                         //o-32, Read Data Out (UNUSED)


        //----------------------------------------------------------------//

        //From mac_register
        .fail_over                  (fail_over),                //i-1
        .fmac_ctrl                  (fmac_ctrl),                //i-32
        .fmac_ctrl1                 (fmac_ctrl1),               //i-32

        //----------------------------------------------------------------//

        .fmac_rxd_en                (reset_rxd_),               //i-1, 13jul11

        .mac_pause_value            (mac_pause_value),          //i-32
        .mac_addr0                  (mac_addr0),                //i-48

        .FIFO_OV_IPEND              (FIFO_OV_IPEND)             //o-1

    );


    //================================================================//
    //  PHY

    //For other GT loopback options please change the value appropriately
    //For example, for internal loopback gt_loopback_in[2:0] = 3'b010;
    //For more information and settings on loopback, refer GT Transceivers user guide
    wire [2:0]      gt_loopback_in_0 = 3'b000;

    //From PHY User Manual:
    //  The rx_core_clk signal is used to clock the receive AXI4-Stream interface.
    //  When FIFO is not included, it must be driven by rx_clk_out. When FIFO is
    //  included, rx_core_clk can be driven by tx_clk_out, rx_clk_out, or another
    //  asynchronous clock at the same frequency.
    //
    //NOTE: In PHY only config, FIFO appears to be present regardless of FIFO enable config

    wire            reset_gtwiz_tx = 1'b0;
    wire            reset_gtwiz_rx = 1'b0;
    wire            gtpowergood_out;

    wire            qpllreset_in_0 = 1'b0;
    //WARNING: Changing qpllreset_in_0 value may impact or disturb other cores in case of multicore
    //         User should take care of this while changing.

    phy_10g_eth_xil PHY (

        //----------------------------------------------------------------//
        //  Clock I/O

        .gt_refclk_p                            (gt_refclk_p),          //i-1, Differential Reference Clock In (positive)
        .gt_refclk_n                            (gt_refclk_n),          //i-1, Differential Reference Clock In (negative)
        .gt_refclk_out                          (gt_refclk),            //o-1, Reference Clock Out (single ended, gated by gtpowergood)

        .dclk                                   (mclk),                 //i-1, system clock. Non-gated (also not synchronous to gt_refclk)

        .tx_mii_clk_0                           (tx_mii_clk),           //o-1, TX MII Interface Clock
        .rx_clk_out_0                           (rx_clk_out),           //o-1,

        .rxrecclkout_0                          (rxrecclk),             //o-1, Clock recovered from GT RX

    //  .rx_core_clk_0                          (rx_clk_out),           //i-1, RX MII Interface Clock
        .rx_core_clk_0                          (tx_mii_clk),           //i-1, RX MII Interface Clock


        .txoutclksel_in_0                       (3'b101),               //i-3, Should not be changed, as per gtwizard
        .rxoutclksel_in_0                       (3'b101),               //i-3, Should not be changed, as per gtwizard


        //----------------------------------------------------------------//
        //Resets

        .sys_reset                              (!reset_mii_),          //i-1, Full system reset. Resets GT then MII module

        .rx_reset_0                             (!reset_mii_),          //i-1, MII module RX path reset (also issued by GT module)
        .user_rx_reset_0                        (reset_usr_rx),         //o-1, = rx_reset_0 || rx_reset_internal (from GT module)

        .tx_reset_0                             (!reset_mii_),          //i-1, MII module TX path reset (also issued by GT module)
        .user_tx_reset_0                        (reset_usr_tx),         //o-1, = tx_reset_0 || tx_reset_internal (from GT module)

        //Analog Resets?
        .qpllreset_in_0                         (qpllreset_in_0),       //i-1, pll reset (internally issued by GT module's powergood)
        .gtwiz_reset_tx_datapath_0              (reset_gtwiz_tx),       //i-1, GT module RX path reset (internally asserted during sys reset)
        .gtwiz_reset_rx_datapath_0              (reset_gtwiz_rx),       //i-1, GT module TX path reset (internally asserted during sys reset)


        //----------------------------------------------------------------//

        .gtpowergood_out_0(gtpowergood_out),                            //o-1, gtpowergood_out_0
        .gt_loopback_in_0(gt_loopback_in_0),                            //i-3, gt_loopback_in_0


        //----------------------------------------------------------------//
        //MII TX and RX

        `ifdef SYNTHESIS
        .rx_mii_d_0                             (cgmii_rxd[63:0]),      //o-64, rx_mii_d_0
        .rx_mii_c_0                             (cgmii_rxc[7:0]),       //o-8,  rx_mii_c_0
        `endif

        .tx_mii_d_0                             (cgmii_txd[63:0]),      //i-64, tx_mii_d_0
        .tx_mii_c_0                             (cgmii_txc[7:0]),       //i-8,  tx_mii_c_0


        //----------------------------------------------------------------//
        //GT TX and RX

        .gt_txp_out                             (gt_txp_out),           //o-1, gt_txp_out
        .gt_txn_out                             (gt_txn_out),           //o-1, gt_txn_out

        //In simulations, connect GT as loopback
        `ifdef SYNTHESIS
        .gt_rxp_in                              (gt_rxp_in),            //i-1, gt_rxp_in
        .gt_rxn_in                              (gt_rxn_in),            //i-1, gt_rxn_in
        `else
        .gt_rxp_in                              (gt_txp_out),           //i-1, gt_rxp_in
        .gt_rxn_in                              (gt_txn_out),           //i-1, gt_rxn_in
        `endif

        //----------------------------------------------------------------//
        //Network Status Output Signals

        .stat_rx_framing_err_0                  (),                     //o-1,
        .stat_rx_framing_err_valid_0            (),                     //o-1,
        .stat_rx_local_fault_0                  (),                     //o-1,
        .stat_rx_block_lock_0                   (),                     //o-1,
        .stat_rx_valid_ctrl_code_0              (),                     //o-1,
        .stat_rx_status_0                       (phy_rxgood),           //o-1, Asserted when PHY RX status is good
        .stat_rx_hi_ber_0                       (),                     //o-1,
        .stat_rx_bad_code_0                     (),                     //o-1,
        .stat_rx_bad_code_valid_0               (),                     //o-1,
        .stat_rx_error_0                        (),                     //o-8,
        .stat_rx_error_valid_0                  (),                     //o-1,
        .stat_rx_fifo_error_0                   (),                     //o-1,

        .stat_tx_local_fault_0                  (phy_txbad),            //o-1,


        //----------------------------------------------------------------//
        //Control Inputs for Test Pattern Generation

        .ctl_rx_test_pattern_0                  (1'b0),                 //i-1,  ctl_rx_test_pattern_0
        .ctl_rx_data_pattern_select_0           (1'b0),                 //i-1,  ctl_rx_data_pattern_select_0
        .ctl_rx_test_pattern_enable_0           (1'b0),                 //i-1,  ctl_rx_test_pattern_enable_0
        .ctl_rx_prbs31_test_pattern_enable_0    (1'b0),                 //i-1,  ctl_rx_prbs31_test_pattern_enable_0

        .ctl_tx_test_pattern_0                  (1'b0),                 //i-1,  ctl_tx_test_pattern_0
        .ctl_tx_test_pattern_enable_0           (1'b0),                 //i-1,  ctl_tx_test_pattern_enable_0
        .ctl_tx_test_pattern_select_0           (1'b0),                 //i-1,  ctl_tx_test_pattern_select_0
        .ctl_tx_data_pattern_select_0           (1'b0),                 //i-1,  ctl_tx_data_pattern_select_0
        .ctl_tx_test_pattern_seed_a_0           (58'd0),                //i-58, ctl_tx_test_pattern_seed_a_0
        .ctl_tx_test_pattern_seed_b_0           (58'd0),                //i-58, ctl_tx_test_pattern_seed_b_0
        .ctl_tx_prbs31_test_pattern_enable_0    (1'b0)                  //i-1,  ctl_tx_prbs31_test_pattern_enable_0
    );



    //================================================================//
    //  ILAs

    `ifdef ILA_ENABLE
    //WARNING: MII operates on a faster clock than this ILA
    //TODO: FIFOs for CGMII

    ila_noc_fmac_mii ila_fpga (
        .clk        (sclk),             //i-1,   Clock

        .probe0     (noc_in_data),      //i-64,  noc_in_data
        .probe1     (noc_in_valid),     //i-1,   noc_in_valid
        .probe2     (noc_in_ready),     //i-1,   noc_in_ready

        .probe3     (noc_out_data),     //i-64,  noc_out_data
        .probe4     (noc_out_valid),    //i-1,   noc_out_valid
        .probe5     (noc_out_ready),    //i-1,   noc_out_ready

        .probe6     (ox2m_tx_data),     //i-256, ox2m_tx_data
        .probe7     (ox2m_tx_wren),     //i-1,   ox2m_tx_wren
        .probe8     (ox2m_tx_full),     //i-1,   ox2m_tx_full
        .probe9     (ox2m_tx_usedw),    //i-13,  ox2m_tx_usedw
    ////.probe6     ({
    ////                OX_CORE_U1.OR1.m2ox_u1.rx_state,
    ////
    ////                OX_CORE_U1.OR1.SM.update_seq_state,
    ////                OX_CORE_U1.OR1.SM.update_ack_state,
    ////                OX_CORE_U1.OR1.SM.send_req_state,
    ////                OX_CORE_U1.OR1.SM.master_state,
    ////
    ////                OX_CORE_U1.OR1.oxm2ackm_done,
    ////                OX_CORE_U1.OR1.oxm2ackm_accept,
    ////                OX_CORE_U1.OR1.oxm2ackm_busy,
    ////                OX_CORE_U1.OR1.ackmtotx_busy,
    ////                OX_CORE_U1.OR1.oxm2ackm_chk_req,
    ////                OX_CORE_U1.OR1.oxm2ackm_new_ack_num,
    ////                OX_CORE_U1.OR1.oxm2ackm_new_seq_num
    ////            }),         //i-256,
    ////
    ////.probe7     ('b0),         //i-1,
    ////.probe8     ('b0),         //i-1,
    ////.probe9     ('b0),         //i-13,

        .probe10    (m2ox_rxp_data),        //i-256, m2ox_rxp_data
        .probe11    (m2ox_rxp_rden),        //i-1,   m2ox_rxp_rden
        .probe12    (m2ox_rxp_empty),       //i-1,   m2ox_rxp_empty
        .probe13    (m2ox_rxp_usedw),       //i-13,  m2ox_rxp_usedw

        .probe14    (m2ox_rxi_data[63:48]), //i-16,  m2ox_rxi_data
        .probe15    (m2ox_rxi_rden),        //i-1,   m2ox_rxi_rden
        .probe16    (m2ox_rxi_empty),       //i-1,   m2ox_rxi_empty
        .probe17    (m2ox_rxi_usedw),       //i-13,  m2ox_rxi_usedw

        .probe18    (cgmii_txd[63:0]),      //i-64, cgmii_txd
        .probe19    (cgmii_txc[ 7:0]),      //i-8,  cgmii_txc

    ////.probe18    (OX_CORE_U1.OR1.ox2f_rx_header_i),      //i-64,
    ////.probe19    (8'b0),      //i-8,

        .probe20    (cgmii_rxd[63:0]),      //i-64, cgmii_rxd
        .probe21    (cgmii_rxc[ 7:0]),      //i-8,  cgmii_rxc

        .probe22    (noc_tmp_valid),        //i-1,
        .probe23    (noc_tmp_ready),        //i-1,
        .probe24    (noc_dlya),             //i-1,


        .probe25    (OX_CORE_U1.OR1.ox2f_rx_data_we_i),    //i-1,
        .probe26    (OX_CORE_U1.OR1.ox2f_rx_bcnt_we_i),    //i-1,
        .probe27    (OX_CORE_U1.OR1.ox2f_rx_header_we_i),  //i-1,
        .probe28    (OX_CORE_U1.OR1.ox2f_rx_addr_we_i),    //i-1,
        .probe29    (OX_CORE_U1.OR1.ox2f_rx_mask_we_i),    //i-1,

        .probe30    (reset_mii_),           //i-1,
        .probe31    (reset_usr_tx_mclk),    //i-1,
        .probe32    (reset_usr_rx_mclk),    //i-1,
        .probe33    (reset_mac_),           //i-1,
        .probe34    (reset_rxd_),           //i-1,
        .probe35    (reset_oxc_),           //i-1,

        .probe36    (phy_rxgood_mclk),
        .probe37    (phy_txbad_mclk)
    );
    `endif


//Otherwise, Pure RTL Simulation with NETE and Endpoint
`else

    assign gt_refclk = mclk;

    assign reset_usr_rx = 1'b0;
    assign reset_usr_tx = 1'b0;

    assign reset_usr_tx     = 1'b0;
    assign reset_usr_rx     = 1'b0;
    assign phy_rxgood       = 1'b0;
    assign phy_txbad        = 1'b0;
    assign stat_phy_rst     = 1'b0;
    assign stat_phy_good    = 1'b0;
    assign ready_lmac       = 1'b0;

    assign m2ox_rxi_data[47:0] = 'b0;

    wire [63:0]         n2ept_data;
    wire [ 7:0]         n2ept_keep;
    wire                n2ept_valid;
    wire                n2ept_last;
    wire                n2ept_rdy;
    wire [3:0]          n2ept_dest;

    wire [63:0]         ept2n_data;
    wire [ 7:0]         ept2n_keep;
    wire                ept2n_valid;
    wire                ept2n_last;
    wire                ept2n_rdy;
    wire [3:0]          ept2n_dest;

	NETE_MASTER     NETE_MASTER (
        .clk                    (sclk),
        .rst_                   (reset_mac_),

        //----------------------------------------------------------------//

        // TX FIFO I/O  (Connecting to FIFO) from Lewiz to endpoint
        .ox2m_tx_data           (ox2m_tx_data),         // i-256
        .ox2m_tx_we             (ox2m_tx_wren),         // i-1
        .m2ox_tx_fifo_full      (ox2m_tx_full),         // o -1

        // NETE_TX (OX Core to Endpoint)
        .sfp_axis_rx_0_tdata    (n2ept_data),           // o-64
        .sfp_axis_rx_0_tkeep    (n2ept_keep),           // o-8
        .sfp_axis_rx_0_tvalid   (n2ept_valid),          // o-1
        .sfp_axis_rx_0_tlast    (n2ept_last),           // o-1
        .sfp_axis_tx_0_tready   (n2ept_rdy),            // i-1
        .sfp_axis_rx_0_tDest    (n2ept_dest),           // o-4

        //----------------------------------------------------------------//

        // NETE_RX (Endpoint to OX Core)
        .axi_in_data            (ept2n_data),           // i-64
        .axi_in_keep            (ept2n_keep),           // i-8
        .axi_in_valid           (ept2n_valid),          // i-1
        .axi_in_last            (ept2n_last),           // i-1
        .axi_in_rdy             (ept2n_rdy),            // o-1
        .axi_in_dest            (ept2n_dest),           // i-4

        // RX FIFO I/O (Connecting FIFO to OX)
        .pkt_data_out           (m2ox_rxp_data),        // o-256
        .pkt_rden               (m2ox_rxp_rden),        // i-1
        .pkt_empty              (m2ox_rxp_empty),       // o-1
        .pkt_usedword           (m2ox_rxp_usedw),       // o-7

        .ipcs_data_out          (m2ox_rxi_data[63:48]), // o-64
        .ipcs_rden              (m2ox_rxi_rden),        // i-1
        .ipcs_empty             (m2ox_rxi_empty),       // o-1
        .ipcs_usedword          (m2ox_rxi_usedw)        // o-7
    );


    //WD Endpoint
    mkOmnixtendEndpointBRAM     endpoint(
        .sconfig_axi_aclk        (sclk),                // i-1 config clk
        .sconfig_axi_aresetn     (reset_mac_),          // i-1 config reset
        .sconfig_axi_arready     (),                    // o-1
        .sconfig_axi_arvalid     (1'b0),                // i-1
        .sconfig_axi_araddr      (16'b0),               // i-16
        .sconfig_axi_arprot      (3'b0),                // i-3
        .sconfig_axi_rvalid      (),                    // o-1
        .sconfig_axi_rready      (1'b0),                // i-1
        .sconfig_axi_rdata       (),                    // o-64
        .sconfig_axi_rresp       (),                    // o-2
        .sconfig_axi_awready     (),                    // o-1
        .sconfig_axi_awvalid     (1'b0),                // i-1
        .sconfig_axi_awaddr      (16'b0),               // i-16
        .sconfig_axi_awprot      (3'b0),                // i-3
        .sconfig_axi_wready      (),                    // o-1
        .sconfig_axi_wvalid      (1'b0),                // i-1
        .sconfig_axi_wdata       (64'b0),               // i-64
        .sconfig_axi_wstrb       (8'b0),                // i-8
        .sconfig_axi_bvalid      (),                    // o-1
        .sconfig_axi_bready      (1'b0),                // i-1
        .sconfig_axi_bresp       (),                    // o-2

        .interrupt               (),                    // o-1


        .sfp_axis_tx_aclk_0      (sclk),                // i-1  tx clk
        .sfp_axis_tx_aresetn_0   (reset_mac_),          // i-1  tx reset
        .sfp_axis_tx_0_tdata     (ept2n_data),          // o-64 from endpoint to Lewiz
        .sfp_axis_tx_0_tkeep     (ept2n_keep),          // o-8  from endpoint to Lewiz
        .sfp_axis_tx_0_tvalid    (ept2n_valid),         // o-1  from endpoint to Lewiz  -- to system
        .sfp_axis_tx_0_tlast     (ept2n_last),          // o-1  from endpoint to Lewiz
        .sfp_axis_tx_0_tready    (ept2n_rdy),           // i-1  from Lewiz to endpoint  -- to system
        .sfp_axis_tx_0_tDest     (ept2n_dest),          // o-4  from endpoint to Lewiz


        .sfp_axis_rx_aclk_0      (sclk),                // i-1  rx clk
        .sfp_axis_rx_aresetn_0   (reset_mac_),          // i-1  rx reset
        .sfp_axis_rx_0_tdata     (n2ept_data),          // i-64 from Lewiz to endpoint
        .sfp_axis_rx_0_tkeep     (n2ept_keep),          // i-8  from Lewiz to endpoint
        .sfp_axis_rx_0_tvalid    (n2ept_valid),         // i-1  from Lewiz to endpoint
        .sfp_axis_rx_0_tlast     (n2ept_last),          // i-1  from Lewiz to endpoint
        .sfp_axis_rx_0_tready    (n2ept_rdy),           // o-1  from endpoint to Lewiz
        .sfp_axis_rx_0_tDest     (n2ept_dest)           // i-4  from Lewiz to endpoint
    );
`endif

endmodule
