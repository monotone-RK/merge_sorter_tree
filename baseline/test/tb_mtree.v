/******************************************************************************/
/* A test bench                                              Ryohei Kobayashi */
/*                                                         Version 2017-12-09 */
/******************************************************************************/
`default_nettype none
  
`include "mtree.v"

`define W_LOG 10
`define DATW  64
`define KEYW  32
  
module tb_MERGE_SORTER_TREE();
  reg CLK; initial begin CLK=0; forever #50 CLK=~CLK; end
  reg RST; initial begin RST=1; #400 RST=0; end
  
  wire [(`DATW<<`W_LOG)-1:0] merge_sorter_tree_din;
  wire [(1<<`W_LOG)-1:0]     merge_sorter_tree_dinen;
  wire [(1<<`W_LOG)-1:0]     merge_sorter_tree_ful;
  wire [`DATW-1:0]           merge_sorter_tree_dot;
  wire                       merge_sorter_tree_doten;

  reg [`DATW-1:0]            check_record;

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

  // show result
  always @(posedge CLK) begin
    if (merge_sorter_tree_doten) begin
      $write("%d", merge_sorter_tree_dot[`KEYW-1:0]);
      $write("\n");
      $fflush();
    end
  end

  // error checker
  always @(posedge CLK) begin
    if (RST) begin
      check_record <= {{(`DATW-`KEYW){1'b1}}, `KEYW'b1};
    end else begin
      if (merge_sorter_tree_doten) begin
        check_record <= check_record + 1;
        if (merge_sorter_tree_dot != check_record) begin
          $write("\nError!\n");
          $write("%d %d\n", merge_sorter_tree_dot, check_record);
          $finish();
        end
      end
    end
  end
  
  // simulation finish condition
  reg [31:0] cycle;
  always @(posedge CLK) begin
    if (RST) begin
      cycle <= 0;
    end else begin
      cycle <= cycle + 1;
      if (cycle >= 200) $finish();
    end
  end

endmodule

`default_nettype wire
