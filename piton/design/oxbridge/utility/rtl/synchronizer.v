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
// Date: 2022-11-22
// Project: N/A
// Comments: Simple Register Based Synchronizer
//
//********************************
// File history:
//   2022-11-22: Original
//****************************************************************

`timescale 1ns / 1ps


module synchronizer_reg
    #(
        parameter   WIDTH       = 1,    //Signal width
        parameter   STAGES      = 2     //Number of stages (Minimum 2)
    )(
        input                   clk,    //i-1
    
        input      [WIDTH-1:0]  in,     //i-WIDTH
        output reg [WIDTH-1:0]  out     //o-WIDTH

    );

    //A register for all but one stage ('out' is the last one)
    reg [WIDTH-1:0] stage [STAGES-2:0];

    //Input goes to stage 0, last stage goes to output
    always @ (posedge clk) begin
        stage[0] <= in;
        out      <= stage[STAGES-2];
    end
    
    genvar i;
    generate
        for (i=1; i<STAGES-1; i=i+1) begin
            always@(posedge clk) stage[i] <= stage[i-1];
        end
    endgenerate

endmodule