`default_nettype none

`include "virtualtree.v"
  
`define W_LOG            6
`define P_LOG            3
`define Q_SIZE           2
`define FIFO_SIZE        2
`define DATW            64
`define KEYW            32
`define DATANUM_PER_WAY 1024
  
  
module tb_SORTER_STAGE_TREE_RANDOM();
  reg CLK; initial begin CLK=0; forever #50 CLK=~CLK; end
  reg RST; initial begin RST=1; #400 RST=0; end
  
  reg [`KEYW-1:0]            datamem [`DATANUM_PER_WAY*(1<<`W_LOG)-1:0];
  reg [31:0]                 index [(1<<`W_LOG)-1:0];
  reg [31:0]                 read_cnt [(1<<`W_LOG)-1:0];

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
  
  initial begin
    $readmemh("initdata.hex", datamem, 0, `DATANUM_PER_WAY*(1<<`W_LOG)-1);
  end

  genvar i;
  generate
    for (i=0; i<(1<<`W_LOG); i=i+1) begin: way
      always @(posedge CLK) begin
        if (RST) begin
          index[i]    <= `DATANUM_PER_WAY * i;
          read_cnt[i] <= 0;
        end else if ((queue_dot == i) && !queue_emp && (read_cnt[i] != `DATANUM_PER_WAY)) begin
          index[i]    <= index[i] + 1;
          read_cnt[i] <= read_cnt[i] + 1;
        end
      end
    end
  endgenerate

  assign queue_enq                 = tree_filler_i_request_valid;
  assign queue_deq                 = !queue_emp;
  assign queue_din                 = tree_filler_i_request;

  assign tree_filler_queue_full    = queue_ful;
  assign sorter_stage_tree_in_full = 1'b0;
  assign tree_filler_dot           = (read_cnt[queue_dot] != `DATANUM_PER_WAY) ? {{(`DATW-`KEYW){1'b1}}, datamem[index[queue_dot]]} : {(`DATW){1'b1}};
  assign tree_filler_doten         = queue_deq;
  assign tree_filler_dot_idx       = queue_dot;

  DFIFO #(`Q_SIZE, `W_LOG)
  request_queue(CLK, RST, queue_enq, queue_deq, queue_din, 
                queue_dot, queue_emp, queue_ful, queue_cnt);

  SORTER_STAGE_TREE #(`W_LOG, `Q_SIZE, `FIFO_SIZE, `DATW, `KEYW)
  sorter_stage_tree(CLK, RST, tree_filler_queue_full, sorter_stage_tree_in_full, tree_filler_dot, tree_filler_doten, tree_filler_dot_idx, 
                    tree_filler_i_request, tree_filler_i_request_valid, sorter_stage_tree_dot, sorter_stage_tree_doten);


  ////// for debugging
  reg [31:0] sorter_stage_tree_dotnum;
  reg        sort_done;
  reg [31:0] cycle;

  reg [31:0] perf_cnt;
  reg        count_start;
  
  // show result
  always @(posedge CLK) begin
    if (!RST && !sort_done) begin
      $write("%d | %d ", cycle, queue_cnt);
      if (tree_filler_doten) $write("%08x(%4d) ", tree_filler_dot[`KEYW-1:0], tree_filler_dot_idx);
      else $write("               ");
      $write("||");
      $write("state: %d ", sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.state);
      $write("| %b %b %b %b ", sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.QUEUE_IN_FULL, sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.queue_emp, sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.ram_layer_emp0, sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.ram_layer_emp1);
      $write("| %d ", sorter_stage_tree.stage[`W_LOG-1].body.sorter_stage_body.queue_cnt);
      if (sorter_stage_tree.stage[`W_LOG-1].o_request_valid) $write(" %4d ", sorter_stage_tree.stage[`W_LOG-1].o_request);
      else $write("      ");
      if (sorter_stage_tree.stage[`W_LOG-1].doten) $write("%08x(%3d) ", sorter_stage_tree.stage[`W_LOG-1].dot[`KEYW-1:0], sorter_stage_tree.stage[`W_LOG-1].body.dot_idx);
      else $write("              ");
      $write("||");
      $write("state: %d ", sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.state);
      $write("| %b %b %b %b ", sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.QUEUE_IN_FULL, sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.queue_emp, sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.ram_layer_emp0, sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.ram_layer_emp1);
      $write("| %d ", sorter_stage_tree.stage[`W_LOG-2].body.sorter_stage_body.queue_cnt);
      if (sorter_stage_tree.stage[`W_LOG-2].o_request_valid) $write(" %3d ", sorter_stage_tree.stage[`W_LOG-2].o_request);
      else $write("     ");
      if (sorter_stage_tree.stage[`W_LOG-2].doten) $write("%08x(%3d) ", sorter_stage_tree.stage[`W_LOG-2].dot[`KEYW-1:0], sorter_stage_tree.stage[`W_LOG-2].body.dot_idx);
      else $write("              ");
      $write("||");
      if (sorter_stage_tree_doten) $write(" %08x ", sorter_stage_tree_dot[`KEYW-1:0]);
      $write("\n");
      $fflush();
    end
  end

  // simulation finish condition
  always @(posedge CLK) begin
    if (RST) begin
      cycle <= 0;
    end else begin
      if (!sort_done) cycle <= cycle + 1;
      // if (cycle >= 1000) $finish();
    end
  end
  
  always @(posedge CLK) begin
    if (RST) begin
      perf_cnt    <= 0;
      count_start <= 0;
    end else begin
      if ((sorter_stage_tree_doten || count_start) && !sort_done) begin
        perf_cnt <= perf_cnt + 1;
      end
      if (sorter_stage_tree_doten) count_start <= 1;
    end
  end

  always @(posedge CLK) begin
    if (RST) begin
      sorter_stage_tree_dotnum <= 0;
      sort_done                <= 0;
    end else begin
      if (sorter_stage_tree_doten && !sort_done) begin
        sorter_stage_tree_dotnum <= sorter_stage_tree_dotnum + 1;
        sort_done                <= (sorter_stage_tree_dotnum == `DATANUM_PER_WAY*(1<<`W_LOG)-1);
      end
    end
  end
  
  always @(posedge CLK) begin
    if (sort_done) begin: simulation_finish
      $write("\nIt takes %d (%d) cycles\n", cycle, perf_cnt);
      $write("Sorting finished!\n");
      $finish();
    end
  end

  // simulation result is stored for verification using std::sort
  integer fp;
  initial begin fp = $fopen("log.txt", "w"); end
  always @(posedge CLK) begin
    if (sorter_stage_tree_doten && !sort_done) begin
      $fwrite(fp, "%08x\n", sorter_stage_tree_dot[`KEYW-1:0]);
      $fflush();
    end
    if (sort_done) $fclose(fp);
  end

  // always @(posedge CLK) begin
  //   if (!RST) begin
  //     $write("%08x", datamem[cycle]);
  //     $write("\n");
  //     $fflush();
  //   end
  // end
  
  // reg [31:0] cycle;
  // always @(posedge CLK) begin
  //   if (RST) begin
  //     cycle <= 0;
  //   end else begin
  //     cycle <= cycle + 1;
  //     if (cycle >= `DATANUM_PER_WAY*(1<<`W_LOG)-1) $finish();
  //   end
  // end
  
endmodule
  
`default_nettype wire
