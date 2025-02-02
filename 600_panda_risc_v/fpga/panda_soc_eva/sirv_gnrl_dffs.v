/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

`timescale 1ns / 1ps

`define DISABLE_SV_ASSERTION

 /*                                                                      
 Copyright 2018 Nuclei System Technology, Inc.                
                                                                         
 Licensed under the Apache License, Version 2.0 (the "License");         
 you may not use this file except in compliance with the License.        
 You may obtain a copy of the License at                                 
                                                                         
     http://www.apache.org/licenses/LICENSE-2.0                          
                                                                         
  Unless required by applicable law or agreed to in writing, software    
 distributed under the License is distributed on an "AS IS" BASIS,       
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and     
 limitations under the License.                                          
 */                                                                      
                                                                         
                                                                         
                                                                         
//=====================================================================
//
// Designer   : Bob Hu
//
// Description:
//  All of the general DFF and Latch modules
//
// ====================================================================

//


//
// ===========================================================================
//
// Description:
//  Verilog module sirv_gnrl DFF with Load-enable and Reset
//  Default reset value is 1
//
// ===========================================================================

module sirv_gnrl_dfflrs # (
  parameter DW = 32
) (

  input               lden, 
  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout,

  input               clk,
  input               rst_n
);

reg [DW-1:0] qout_r;

always @(posedge clk or negedge rst_n)
begin : DFFLRS_PROC
  if (rst_n == 1'b0)
    qout_r <= {DW{1'b1}};
  else if (lden == 1'b1)
    qout_r <= #1 dnxt;
end

assign qout = qout_r;

`ifndef FPGA_SOURCE//{
`ifndef DISABLE_SV_ASSERTION//{
//synopsys translate_off
sirv_gnrl_xchecker # (
  .DW(1)
) sirv_gnrl_xchecker(
  .i_dat(lden),
  .clk  (clk)
);
//synopsys translate_on
`endif//}
`endif//}
    

endmodule
// ===========================================================================
//
// Description:
//  Verilog module sirv_gnrl DFF with Load-enable and Reset
//  Default reset value is 0
//
// ===========================================================================

module sirv_gnrl_dfflr # (
  parameter DW = 32
) (

  input               lden, 
  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout,

  input               clk,
  input               rst_n
);

reg [DW-1:0] qout_r;

always @(posedge clk or negedge rst_n)
begin : DFFLR_PROC
  if (rst_n == 1'b0)
    qout_r <= {DW{1'b0}};
  else if (lden == 1'b1)
    qout_r <= #1 dnxt;
end

assign qout = qout_r;

`ifndef FPGA_SOURCE//{
`ifndef DISABLE_SV_ASSERTION//{
//synopsys translate_off
sirv_gnrl_xchecker # (
  .DW(1)
) sirv_gnrl_xchecker(
  .i_dat(lden),
  .clk  (clk)
);
//synopsys translate_on
`endif//}
`endif//}
    

endmodule
// ===========================================================================
//
// Description:
//  Verilog module sirv_gnrl DFF with Load-enable, no reset 
//
// ===========================================================================

module sirv_gnrl_dffl # (
  parameter DW = 32
) (

  input               lden, 
  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout,

  input               clk 
);

reg [DW-1:0] qout_r;

always @(posedge clk)
begin : DFFL_PROC
  if (lden == 1'b1)
    qout_r <= #1 dnxt;
end

assign qout = qout_r;

`ifndef FPGA_SOURCE//{
`ifndef DISABLE_SV_ASSERTION//{
//synopsys translate_off
sirv_gnrl_xchecker # (
  .DW(1)
) sirv_gnrl_xchecker(
  .i_dat(lden),
  .clk  (clk)
);
//synopsys translate_on
`endif//}
`endif//}
    

endmodule
// ===========================================================================
//
// Description:
//  Verilog module sirv_gnrl DFF with Reset, no load-enable
//  Default reset value is 1
//
// ===========================================================================

module sirv_gnrl_dffrs # (
  parameter DW = 32
) (

  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout,

  input               clk,
  input               rst_n
);

reg [DW-1:0] qout_r;

always @(posedge clk or negedge rst_n)
begin : DFFRS_PROC
  if (rst_n == 1'b0)
    qout_r <= {DW{1'b1}};
  else                  
    qout_r <= #1 dnxt;
end

assign qout = qout_r;

endmodule
// ===========================================================================
//
// Description:
//  Verilog module sirv_gnrl DFF with Reset, no load-enable
//  Default reset value is 0
//
// ===========================================================================

module sirv_gnrl_dffr # (
  parameter DW = 32
) (

  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout,

  input               clk,
  input               rst_n
);

reg [DW-1:0] qout_r;

always @(posedge clk or negedge rst_n)
begin : DFFR_PROC
  if (rst_n == 1'b0)
    qout_r <= {DW{1'b0}};
  else                  
    qout_r <= #1 dnxt;
end

assign qout = qout_r;

endmodule
// ===========================================================================
//
// Description:
//  Verilog module for general latch 
//
// ===========================================================================

module sirv_gnrl_ltch # (
  parameter DW = 32
) (

  //input               test_mode,
  input               lden, 
  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout
);

reg [DW-1:0] qout_r;

always @ * 
begin : LTCH_PROC
  if (lden == 1'b1)
    qout_r <= dnxt;
end

//assign qout = test_mode ? dnxt : qout_r;
assign qout = qout_r;

`ifndef FPGA_SOURCE//{
`ifndef DISABLE_SV_ASSERTION//{
//synopsys translate_off
always_comb
begin
  CHECK_THE_X_VALUE:
    assert (lden !== 1'bx) 
    else $fatal ("\n Error: Oops, detected a X value!!! This should never happen. \n");
end

//synopsys translate_on
`endif//}
`endif//}
    

endmodule
