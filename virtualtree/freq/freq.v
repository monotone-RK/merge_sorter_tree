//-----------------------------------------------------------------------------
// File          : freq.v
// Author        : Ryohei Kobayashi
// Created       : 16.12.2017
// Last modified : 16.12.2017
//-----------------------------------------------------------------------------
// Description :
// A project file to evaluate the maximum frequency of the virtual merge sorter tree
//-----------------------------------------------------------------------------
`default_nettype none
  
`define W_LOG     10
`define P_LOG      3
`define FIFO_SIZE  2
`define DATW      64
`define KEYW      32

module freq(input  wire CLK,
            input  wire RST_IN,
            output wire OUT);
  
  reg RST; always @(posedge CLK) RST <= RST_IN;
  
  reg  [(`DATW<<`P_LOG)-1:0] vmerge_sorter_tree_din;
  reg                        vmerge_sorter_tree_dinen;
  reg  [`W_LOG-1:0]          vmerge_sorter_tree_din_idx;
  wire [`DATW-1:0]           vmerge_sorter_tree_dot;
  wire                       vmerge_sorter_tree_doten;
  wire [(1<<`W_LOG)-1:0]     vmerge_sorter_tree_emp;

  always @(posedge CLK) begin
    if (RST) begin
      vmerge_sorter_tree_din     <= 1;
      vmerge_sorter_tree_dinen   <= 0;
      vmerge_sorter_tree_din_idx <= 0;
    end else begin
      vmerge_sorter_tree_din       <= vmerge_sorter_tree_din << 1;
      vmerge_sorter_tree_dinen     <= ~vmerge_sorter_tree_dinen;
      if (vmerge_sorter_tree_dinen) begin
        vmerge_sorter_tree_din_idx <= vmerge_sorter_tree_din_idx + 1;
      end
    end
  end
  
  vMERGE_SORTER_TREE #(`W_LOG, `P_LOG, `FIFO_SIZE, `DATW, `KEYW)
  vmerge_sorter_tree(CLK, RST, 1'b0, vmerge_sorter_tree_din, vmerge_sorter_tree_dinen, vmerge_sorter_tree_din_idx, 
                     vmerge_sorter_tree_dot, vmerge_sorter_tree_doten, vmerge_sorter_tree_emp);
  
  reg [`DATW-1:0] dot_buf; 
  always @(posedge CLK) begin
    if (vmerge_sorter_tree_doten) dot_buf <= vmerge_sorter_tree_dot;
  end

  assign OUT = ^dot_buf;

endmodule

`default_nettype wire
