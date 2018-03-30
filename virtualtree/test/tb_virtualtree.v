/******************************************************************************/
/* A test bench                                              Ryohei Kobayashi */
/*                                                         Version 2017-12-14 */
/******************************************************************************/
`default_nettype none
  
`include "virtualtree.v"

// `define W_LOG      6
`define W_LOG      7
`define P_LOG      3
`define Q_SIZE     2
`define FIFO_SIZE  2
`define DATW      64
`define KEYW      32

module tb_SORTER_STAGE_TREE();
  reg CLK; initial begin CLK=0; forever #50 CLK=~CLK; end
  reg RST; initial begin RST=1; #400 RST=0; end

  wire [(`DATW<<`W_LOG)-1:0] tree_filler_din_all_way;
  wire [(`DATW<<`W_LOG)-1:0] tree_filler_din_shifted;
  wire [(1<<`W_LOG)-1:0]     tree_filler_dinen_all_way;
  
  wire                       queue_enq;
  wire                       queue_deq;
  wire [`W_LOG-1:0]          queue_din;
  wire [`W_LOG-1:0]          queue_dot;
  wire                       queue_emp;
  wire                       queue_ful; 
  wire [`Q_SIZE:0]           queue_cnt; 

  wire [`W_LOG-1:0]          tree_filler_i_request;
  wire                       tree_filler_i_request_valid;
  wire                       tree_filler_queue_full;
  wire [`DATW-1:0]           tree_filler_dot;
  wire                       tree_filler_doten;
  wire [`W_LOG-1:0]          tree_filler_dot_idx;
  
  wire                       sorter_stage_tree_in_full;
  wire [`DATW-1:0]           sorter_stage_tree_dot;
  wire                       sorter_stage_tree_doten;
  
  reg  [`DATW-1:0]           check_record;
  
  genvar i;
  generate
    for (i=0; i<(1<<`W_LOG); i=i+1) begin: way
      wire [`KEYW-1:0] init_key = i + 1;
      reg  [`DATW-1:0] init_record;
      always @(posedge CLK) begin
        if      (RST)                          init_record <= {{(`DATW-`KEYW){1'b1}}, init_key};
        else if (tree_filler_dinen_all_way[i]) init_record <= init_record + (1<<`W_LOG);
      end
      assign tree_filler_din_all_way[`DATW*(i+1)-1:`DATW*i] = init_record;
      assign tree_filler_dinen_all_way[i]                   = (queue_dot == i) && !queue_emp;
    end
  endgenerate

  assign tree_filler_din_shifted   = (tree_filler_din_all_way >> (`DATW * queue_dot));

  assign queue_enq                 = tree_filler_i_request_valid;
  assign queue_deq                 = !queue_emp;
  assign queue_din                 = tree_filler_i_request;

  assign tree_filler_queue_full    = queue_ful;
  assign sorter_stage_tree_in_full = 1'b0;
  assign tree_filler_dot           = tree_filler_din_shifted[`DATW-1:0];
  assign tree_filler_doten         = queue_deq;
  assign tree_filler_dot_idx       = queue_dot;

  DFIFO #(`Q_SIZE, `W_LOG)
  request_queue(CLK, RST, queue_enq, queue_deq, queue_din, 
                queue_dot, queue_emp, queue_ful, queue_cnt);

  SORTER_STAGE_TREE #(`W_LOG, `Q_SIZE, `FIFO_SIZE, `DATW, `KEYW)
  sorter_stage_tree(CLK, RST, tree_filler_queue_full, sorter_stage_tree_in_full, tree_filler_dot, tree_filler_doten, tree_filler_dot_idx, 
                    tree_filler_i_request, tree_filler_i_request_valid, sorter_stage_tree_dot, sorter_stage_tree_doten);

  // show result
  always @(posedge CLK) begin
    if (!RST) begin
      $write("| %d ", queue_cnt);
      if (tree_filler_doten) $write("%8d(%4d) ", tree_filler_dot[`KEYW-1:0], tree_filler_dot_idx);
      else $write("               ");
      $write("||");
      $write("state: %d ", sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.state);
      $write("| %b %b %b %b, %d %d, %b %b ", sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.QUEUE_IN_FULL, sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.queue_emp, sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.ram_layer_emp0, sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.ram_layer_emp1, sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.queue_dot_buf, sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.queue_dot, sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.same_request_buf, sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.same_request);
      $write("| %d ", sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.queue_cnt);
      if (sorter_stage_tree.stage[`W_LOG-1].o_request_valid) $write(" %4d ", sorter_stage_tree.stage[`W_LOG-1].o_request);
      else $write("      ");
      if (sorter_stage_tree.stage[`W_LOG-1].doten) $write("%8d(%3d) ", sorter_stage_tree.stage[`W_LOG-1].dot[`KEYW-1:0], sorter_stage_tree.stage[`W_LOG-1].body.dot_idx);
      else $write("              ");
      $write("||");
      $write("state: %d ", sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.state);
      $write("| %b %b %b %b, %d %d, %b %b ", sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.QUEUE_IN_FULL, sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.queue_emp, sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.ram_layer_emp0, sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.ram_layer_emp1, sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.queue_dot_buf, sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.queue_dot, sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.same_request_buf, sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.same_request);
      $write("| %d ", sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.queue_cnt);
      if (sorter_stage_tree.stage[`W_LOG-2].o_request_valid) $write(" %3d ", sorter_stage_tree.stage[`W_LOG-2].o_request);
      else $write("     ");
      if (sorter_stage_tree.stage[`W_LOG-2].doten) $write("%8d(%3d) ", sorter_stage_tree.stage[`W_LOG-2].dot[`KEYW-1:0], sorter_stage_tree.stage[`W_LOG-2].body.dot_idx);
      else $write("              ");
      $write("||");
      if (sorter_stage_tree_doten) $write(" %d ", sorter_stage_tree_dot[`KEYW-1:0]);
      $write("\n");
      $fflush();
    end
  end

  // error checker
  always @(posedge CLK) begin
    if (RST) begin
      check_record <= {{(`DATW-`KEYW){1'b1}}, `KEYW'b1};
    end else begin
      if (sorter_stage_tree_doten) begin
        check_record <= check_record + 1;
        if (sorter_stage_tree_dot != check_record) begin
          $write("\nError!\n");
          $write("%d %d\n", sorter_stage_tree_dot[`KEYW-1:0], check_record[`KEYW-1:0]);
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



// module tb_vMERGE_SORTER_TREE();
//   reg CLK; initial begin CLK=0; forever #50 CLK=~CLK; end
//   reg RST; initial begin RST=1; #400 RST=0; end

//   wire [(`DATW<<(`W_LOG+`P_LOG))-1:0] tree_filler_din_all_way;
//   wire [(`DATW<<(`W_LOG+`P_LOG))-1:0] tree_filler_din_shifted;
//   wire [(1<<`W_LOG)-1:0]              tree_filler_dinen_all_way;
  
//   wire [(`DATW<<`P_LOG)-1:0]          vmerge_sorter_tree_din;
//   wire                                vmerge_sorter_tree_dinen;
//   wire [`W_LOG-1:0]                   vmerge_sorter_tree_din_idx;
//   wire [`DATW-1:0]                    vmerge_sorter_tree_dot;
//   wire                                vmerge_sorter_tree_doten;
//   wire [(1<<`W_LOG)-1:0]              vmerge_sorter_tree_emp;
  
//   reg  [`W_LOG-1:0]                   round_robin_sel;

//   reg  [`DATW-1:0]                    check_record;
  
//   genvar i, j;
//   generate
//     for (i=0; i<(1<<`W_LOG); i=i+1) begin: way
//       wire [(`DATW<<`P_LOG)-1:0] din_per_way;
//       for (j=0; j<(1<<`P_LOG); j=j+1) begin: record
//         wire [`KEYW-1:0] init_key = i + 1 + j * (1<<`W_LOG);
//         reg  [`DATW-1:0] init_record;
//         always @(posedge CLK) begin
//           if      (RST)                          init_record <= {{(`DATW-`KEYW){1'b1}}, init_key};
//           else if (tree_filler_dinen_all_way[i]) init_record <= init_record + (1<<(`W_LOG+`P_LOG));
//         end
//         assign din_per_way[`DATW*(j+1)-1:`DATW*j] = init_record;
//       end
//       assign tree_filler_din_all_way[(`DATW<<`P_LOG)*(i+1)-1:(`DATW<<`P_LOG)*i] = din_per_way;
//       assign tree_filler_dinen_all_way[i]                                       = (round_robin_sel == i) && vmerge_sorter_tree_emp[i];
//     end
//   endgenerate
  
//   always @(posedge CLK) begin
//     if (RST) round_robin_sel <= 0;
//     else     round_robin_sel <= round_robin_sel + 1;
//   end

//   assign tree_filler_din_shifted    = (tree_filler_din_all_way >> ((`DATW<<`P_LOG) * round_robin_sel));
//   assign vmerge_sorter_tree_din     = tree_filler_din_shifted[(`DATW<<`P_LOG)-1:0];
//   assign vmerge_sorter_tree_dinen   = (|tree_filler_dinen_all_way) && (~RST);
//   assign vmerge_sorter_tree_din_idx = round_robin_sel;
  
//   vMERGE_SORTER_TREE #(`W_LOG, `P_LOG, `Q_SIZE, `FIFO_SIZE, `DATW, `KEYW)
//   vmerge_sorter_tree(CLK, RST, 1'b0, vmerge_sorter_tree_din, vmerge_sorter_tree_dinen, vmerge_sorter_tree_din_idx, 
//                      vmerge_sorter_tree_dot, vmerge_sorter_tree_doten, vmerge_sorter_tree_emp);

//   // show result
//   always @(posedge CLK) begin
//     if (!RST) begin
//       $write("| %d, %b ", round_robin_sel, vmerge_sorter_tree_emp);
//       $write("| %b ", vmerge_sorter_tree.tree_filler.init_done);
//       $write("|state: %d ", vmerge_sorter_tree.tree_filler.read_state);
//       $write("| %d ", vmerge_sorter_tree.tree_filler.queue_cnt);
//       if (vmerge_sorter_tree.tree_filler_doten) $write("%8d(%4d) ", vmerge_sorter_tree.tree_filler_dot[`KEYW-1:0], vmerge_sorter_tree.tree_filler_dot_idx);
//       else $write("               ");
//       $write("||");
//       $write("state: %d ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.state);
//       $write("| %b %b %b %b ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.QUEUE_IN_FULL, vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.queue_emp, vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.ram_layer_emp0, vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.ram_layer_emp1);
//       $write("| %d ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.queue_cnt);
//       if (vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].o_request_valid) $write(" %4d ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].o_request);
//       else $write("      ");
//       if (vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].doten) $write("%8d(%3d) ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].dot[`KEYW-1:0], vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-1].body.dot_idx);
//       else $write("              ");
//       $write("||");
//       $write("state: %d ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.state);
//       $write("| %b %b %b %b ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.QUEUE_IN_FULL, vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.queue_emp, vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.ram_layer_emp0, vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.ram_layer_emp1);
//       $write("| %d ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.queue_cnt);
//       if (vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].o_request_valid) $write(" %3d ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].o_request);
//       else $write("     ");
//       if (vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].doten) $write("%8d(%3d) ", vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].dot[`KEYW-1:0], vmerge_sorter_tree.sorter_stage_tree.stage[`W_LOG-2].body.dot_idx);
//       else $write("              ");
//       $write("||");
//       if (vmerge_sorter_tree_doten) $write(" %d ", vmerge_sorter_tree_dot[`KEYW-1:0]);
//       $write("\n");
//       $fflush();
//     end
//   end

//   // error checker
//   always @(posedge CLK) begin
//     if (RST) begin
//       check_record <= {{(`DATW-`KEYW){1'b1}}, `KEYW'b1};
//     end else begin
//       if (vmerge_sorter_tree_doten) begin
//         check_record <= check_record + 1;
//         if (vmerge_sorter_tree_dot != check_record) begin
//           $write("\nError!\n");
//           $write("%d %d\n", vmerge_sorter_tree_dot[`KEYW-1:0], check_record[`KEYW-1:0]);
//           $finish();
//         end
//       end
//     end
//   end

//   // simulation finish condition
//   reg [31:0] cycle;
//   always @(posedge CLK) begin
//     if (RST) begin
//       cycle <= 0;
//     end else begin
//       cycle <= cycle + 1;
//       // if (cycle >= 1000) $finish();
//       if (cycle >= 10000) $finish();
//     end
//   end

// endmodule

`default_nettype wire
