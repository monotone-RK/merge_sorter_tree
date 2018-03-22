/******************************************************************************/
/* A test bench                                              Ryohei Kobayashi */
/*                                                         Version 2017-12-14 */
/******************************************************************************/
`default_nettype none
  
`include "virtualtree.v"

// `define W_LOG      5
`define W_LOG      6
`define P_LOG      3
`define FIFO_SIZE  2
`define DATW      64
`define KEYW      32

module tb_vMERGE_SORTER_TREE();
  reg CLK; initial begin CLK=0; forever #50 CLK=~CLK; end
  reg RST; initial begin RST=1; #400 RST=0; end

  wire [(`DATW<<(`W_LOG+`P_LOG))-1:0] tree_filler_din_all_way;
  wire [(`DATW<<(`W_LOG+`P_LOG))-1:0] tree_filler_din_shifted;
  wire [(1<<`W_LOG)-1:0]              tree_filler_dinen_all_way;
  
  wire [(`DATW<<`P_LOG)-1:0]          vmerge_sorter_tree_din;
  wire                                vmerge_sorter_tree_dinen;
  wire [`W_LOG-1:0]                   vmerge_sorter_tree_din_idx;
  wire [`DATW-1:0]                    vmerge_sorter_tree_dot;
  wire                                vmerge_sorter_tree_doten;
  wire [(1<<`W_LOG)-1:0]              vmerge_sorter_tree_emp;
  
  reg  [`W_LOG-1:0]                   round_robin_sel;

  reg  [`DATW-1:0]                    check_record;
  
  genvar i, j;
  generate
    for (i=0; i<(1<<`W_LOG); i=i+1) begin: way
      wire [(`DATW<<`P_LOG)-1:0] din_per_way;
      for (j=0; j<(1<<`P_LOG); j=j+1) begin: record
        wire [`KEYW-1:0] init_key = i + 1 + j * (1<<`W_LOG);
        reg  [`DATW-1:0] init_record;
        always @(posedge CLK) begin
          if      (RST)                          init_record <= {{(`DATW-`KEYW){1'b1}}, init_key};
          else if (tree_filler_dinen_all_way[i]) init_record <= init_record + (1<<(`W_LOG+`P_LOG));
        end
        assign din_per_way[`DATW*(j+1)-1:`DATW*j] = init_record;
      end
      assign tree_filler_din_all_way[(`DATW<<`P_LOG)*(i+1)-1:(`DATW<<`P_LOG)*i] = din_per_way;
      assign tree_filler_dinen_all_way[i]                                       = (round_robin_sel == i) && vmerge_sorter_tree_emp[i];
    end
  endgenerate
  
  always @(posedge CLK) begin
    if (RST) round_robin_sel <= 0;
    else     round_robin_sel <= round_robin_sel + 1;
  end

  assign tree_filler_din_shifted    = (tree_filler_din_all_way >> ((`DATW<<`P_LOG) * round_robin_sel));
  assign vmerge_sorter_tree_din     = tree_filler_din_shifted[(`DATW<<`P_LOG)-1:0];
  assign vmerge_sorter_tree_dinen   = (|tree_filler_dinen_all_way) && (~RST);
  assign vmerge_sorter_tree_din_idx = round_robin_sel;
  
  vMERGE_SORTER_TREE #(`W_LOG, `P_LOG, `FIFO_SIZE, `DATW, `KEYW)
  vmerge_sorter_tree(CLK, RST, 1'b0, vmerge_sorter_tree_din, vmerge_sorter_tree_dinen, vmerge_sorter_tree_din_idx, 
                     vmerge_sorter_tree_dot, vmerge_sorter_tree_doten, vmerge_sorter_tree_emp);

  // show result
  always @(posedge CLK) begin
    if (!RST) begin
      $write("| %d, %b ", round_robin_sel, vmerge_sorter_tree_emp);
      $write("| %b ", vmerge_sorter_tree.tree_filler.init_done);
      $write("| %d ", vmerge_sorter_tree.tree_filler.queue_cnt);
      $write("|state: %d ", vmerge_sorter_tree.tree_filler.read_state);
      if (vmerge_sorter_tree.tree_filler_doten) $write("%8d(%4d) ", vmerge_sorter_tree.tree_filler_dot[`KEYW-1:0], vmerge_sorter_tree.tree_filler_dot_idx);
      else $write("               ");
      $write("||");
      $write("state: %d ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.state);
      $write("| %b %b ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.QUEUE_IN_FULL, vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.queue_emp);
      $write("| %d ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.queue_cnt);
      if (vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].o_request_valid) $write(" %4d ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].o_request);
      else $write("      ");
      if (vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].doten) $write("%8d(%3d) ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].dot[`KEYW-1:0], vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].body.dot_idx);
      else $write("              ");
      $write("||");
      $write("state: %d ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.state);
      $write("| %b %b ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.QUEUE_IN_FULL, vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.queue_emp);
      $write("| %d ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.queue_cnt);
      if (vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].o_request_valid) $write(" %3d ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].o_request);
      else $write("     ");
      if (vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].doten) $write("%8d(%3d) ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].dot[`KEYW-1:0], vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].body.dot_idx);
      else $write("              ");
      $write("||");
      if (vmerge_sorter_tree_doten) $write(" %d ", vmerge_sorter_tree_dot[`KEYW-1:0]);
      $write("\n");
      $fflush();
    end
  end

  // error checker
  always @(posedge CLK) begin
    if (RST) begin
      check_record <= {{(`DATW-`KEYW){1'b1}}, `KEYW'b1};
    end else begin
      if (vmerge_sorter_tree_doten) begin
        check_record <= check_record + 1;
        if (vmerge_sorter_tree_dot != check_record) begin
          $write("\nError!\n");
          $write("%d %d\n", vmerge_sorter_tree_dot[`KEYW-1:0], check_record[`KEYW-1:0]);
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
      // if (cycle >= 1000) $finish();
      if (cycle >= 10000) $finish();
    end
  end

endmodule

`default_nettype wire
