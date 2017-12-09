//-----------------------------------------------------------------------------
// File          : freq.v
// Author        : Ryohei Kobayashi
// Created       : 09.12.2017
// Last modified : 09.12.2017
//-----------------------------------------------------------------------------
// Description :
// A project file to evaluate the maximum frequency of the merge sorter tree
//-----------------------------------------------------------------------------
`default_nettype none

`define W_LOG  9
`define DATW  64
`define KEYW  32
  
module freq(input  wire CLK,
            input  wire RST_IN,
            output wire OUT);

  reg RST; always @(posedge CLK) RST <= RST_IN;
     
  wire [(`DATW<<`W_LOG)-1:0] merge_sorter_tree_din;
  wire [(1<<`W_LOG)-1:0]     merge_sorter_tree_dinen;
  wire [(1<<`W_LOG)-1:0]     merge_sorter_tree_ful;
  wire [`DATW-1:0]           merge_sorter_tree_dot;
  wire                       merge_sorter_tree_doten;
  
  assign merge_sorter_tree_dinen = ~merge_sorter_tree_ful;
  
  genvar i;
  generate
    for (i=0; i<(1<<`W_LOG); i=i+1) begin: loop
      wire [`KEYW-1:0] init_key = (1<<`W_LOG) - i;
      reg  [`DATW-1:0] init_record;
      always @(posedge CLK) begin
        if      (RST)                        init_record <= {{(`DATW-`KEYW){1'b1}}, init_key};
        else if (merge_sorter_tree_dinen[i]) init_record <= init_record + (1<<`W_LOG);
      end
      assign merge_sorter_tree_din[`DATW*(i+1)-1:`DATW*i] = init_record;
    end
  endgenerate

  MERGE_SORTER_TREE #(`W_LOG, `DATW, `KEYW)
  merge_sorter_tree(CLK, RST, 1'b0, merge_sorter_tree_din, merge_sorter_tree_dinen, 
                    merge_sorter_tree_ful, merge_sorter_tree_dot, merge_sorter_tree_doten);

  reg [`DATW-1:0] dot_buf; 
  always @(posedge CLK) begin
    if (merge_sorter_tree_doten) dot_buf <= merge_sorter_tree_dot;
  end

  assign OUT = ^dot_buf;
  
endmodule

`default_nettype wire
