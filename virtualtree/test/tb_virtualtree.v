/******************************************************************************/
/* A test bench                                              Ryohei Kobayashi */
/*                                                         Version 2017-12-14 */
/******************************************************************************/
`default_nettype none
  
`include "virtualtree.v"

`define W_LOG      3
`define P_LOG      3
`define FIFO_SIZE  2
`define DATW      64
`define KEYW      32

module BRAM #(parameter               M_LOG = 2,  // memory size in log scale
              parameter               DATW  = 64)
             (input  wire             CLK,
              input  wire             WE,
              input  wire [M_LOG-1:0] RADDR,
              input  wire [M_LOG-1:0] WADDR,
              input  wire [DATW-1:0]  DIN,
              output reg  [DATW-1:0]  DOT);

  reg [DATW-1:0] mem [(1<<M_LOG)-1:0];
  
  always @(posedge CLK) DOT  <= mem[RADDR];
  always @(posedge CLK) if (WE) mem[WADDR] <= DIN;
  
endmodule  


module TREE_FILLER #(parameter                       W_LOG = 2,
                     parameter                       P_LOG = 3,  // sorting network size in log scale
                     parameter                       DATW  = 64)
                    (input  wire                     CLK,
                     input  wire                     RST,
                     input  wire [W_LOG-1:0]         I_REQUEST,
                     input  wire                     I_REQUEST_VALID,
                     input  wire [(DATW<<P_LOG)-1:0] DIN,
                     input  wire                     DINEN,
                     input  wire [W_LOG-1:0]         WADDR,
                     output wire                     QUEUE_FULL,
                     output wire [DATW-1:0]          DOT,
                     output wire                     DOTEN,
                     output wire [W_LOG-1:0]         DOT_IDX,
                     output wire [(1<<W_LOG)-1:0]    emp);
  
  localparam NUM_RECORD = (1<<P_LOG);

  wire                     queue_enq;
  wire                     queue_deq;
  wire [W_LOG-1:0]         queue_din;
  wire [W_LOG-1:0]         queue_dot;
  wire                     queue_emp;
  wire                     queue_ful; 
  wire [1:0]               queue_cnt; 

  wire                     bram_we;
  wire [W_LOG-1:0]         bram_raddr;
  wire [W_LOG-1:0]         bram_waddr;
  wire [(DATW<<P_LOG)-1:0] bram_din;
  wire [(DATW<<P_LOG)-1:0] bram_dot;

  wire                     enq;
  wire                     deq;
  
  reg  [(DATW<<P_LOG)-1:0] shifted_data;

  reg  [P_LOG-1:0]         read_cnt [(1<<W_LOG)-1:0];
  reg  [W_LOG-1:0]         read_raddr;
  reg  [1:0]               read_state;
  reg                      state_one;
  reg                      data_ready;
  reg                      requeue_deq;
  reg  [(1<<W_LOG)-1:0]    almost_be_emp;

  reg [(1<<W_LOG)-1:0]     head_list;
  reg [(1<<W_LOG)-1:0]     tail_list;
  
  assign queue_enq  = I_REQUEST_VALID;
  assign queue_deq  = state_one || &{requeue_deq,~queue_emp,(read_raddr == bram_raddr)};
  assign queue_din  = I_REQUEST;

  assign bram_we    = DINEN;
  assign bram_raddr = queue_dot;
  assign bram_waddr = WADDR;
  assign bram_din   = DIN;

  assign enq        = DINEN;
  assign deq        = &{queue_deq,almost_be_emp[bram_raddr]};

  genvar i;
  generate
    for (i=0; i<(1<<W_LOG); i=i+1) begin: channels
      assign emp[i] = (head_list[i] == tail_list[i]);
    end
  endgenerate

  TWO_ENTRY_FIFO #(W_LOG)
  request_queue(CLK, RST, queue_enq, queue_deq, queue_din, 
                queue_dot, queue_emp, queue_ful, queue_cnt);

  BRAM #(W_LOG, (DATW<<P_LOG))
  bram(CLK, bram_we, bram_raddr, bram_waddr, bram_din, bram_dot);

  always @(posedge CLK) begin
    shifted_data <= bram_dot >> (DATW * read_cnt[bram_raddr]);
  end

  integer p;  
  always @(posedge CLK) begin
    if (RST) begin
      for (p=0; p<(1<<W_LOG); p=p+1) read_cnt[p] <= 0;
      read_raddr    <= 0;
      read_state    <= 0;
      state_one     <= 0;
      data_ready    <= 0;
      requeue_deq   <= 0;
      almost_be_emp <= 0;
    end else begin
      case (read_state)
        0: begin
          data_ready <= 0;
          if (~|{queue_emp,emp[bram_raddr]}) begin
            read_state <= 1;
            state_one  <= 1;
          end
        end
        1: begin  // bram_dot has been set
          read_raddr                <= bram_raddr;
          read_state                <= (almost_be_emp[bram_raddr]) ? 0 : 2;
          state_one                 <= 0;
          read_cnt[bram_raddr]      <= read_cnt[bram_raddr] + 1;
          data_ready                <= 1;
          requeue_deq               <= 1;
          almost_be_emp[bram_raddr] <= (read_cnt[bram_raddr] == NUM_RECORD-2);
        end
        2: begin  // shifted_data has been set
          if (!queue_emp && (read_raddr == bram_raddr)) begin
            read_cnt[bram_raddr]      <= read_cnt[bram_raddr] + 1;
            almost_be_emp[bram_raddr] <= (read_cnt[bram_raddr] == NUM_RECORD-2);
            if (almost_be_emp[bram_raddr]) begin
              read_state  <= 0;
              requeue_deq <= 0;
            end
          end else begin
            read_state  <= 0;
            data_ready  <= 0;
            requeue_deq <= 0;
          end
        end
      endcase
    end
  end
  
  always @(posedge CLK) begin
    if (RST) begin
      head_list <= 0;
      tail_list <= 0;
    end else begin
      case ({enq, deq})
        2'b01: begin 
          head_list[bram_raddr] <= ~head_list[bram_raddr]; 
        end
        2'b10: begin 
          tail_list[bram_waddr] <= ~tail_list[bram_waddr];
        end
        2'b11: begin
          head_list[bram_raddr] <= ~head_list[bram_raddr];
          tail_list[bram_waddr] <= ~tail_list[bram_waddr]; 
        end
      endcase
    end
  end
  
  assign QUEUE_FULL = queue_ful;
  assign DOT        = shifted_data[DATW-1:0];
  assign DOTEN      = data_ready;
  assign DOT_IDX    = read_raddr;

endmodule  


module tb_vMERGE_SORTER_TREE();
  reg CLK; initial begin CLK=0; forever #50 CLK=~CLK; end
  reg RST; initial begin RST=1; #400 RST=0; end
  
  wire [`W_LOG-1:0]                   tree_filler_i_request;
  wire                                tree_filler_i_request_valid;
  wire [(`DATW<<(`W_LOG+`P_LOG))-1:0] tree_filler_din_all_way;
  wire [(`DATW<<(`W_LOG+`P_LOG))-1:0] tree_filler_din_shifted;
  wire [(`DATW<<`P_LOG)-1:0]          tree_filler_din;
  wire [(1<<`W_LOG)-1:0]              tree_filler_dinen_all_way;
  wire                                tree_filler_dinen;
  wire [`W_LOG-1:0]                   tree_filler_waddr;
  wire                                tree_filler_queue_full;
  wire [`DATW-1:0]                    tree_filler_dot;
  wire                                tree_filler_doten;
  wire [`W_LOG-1:0]                   tree_filler_dot_idx;
  wire [(1<<`W_LOG)-1:0]              tree_filler_emp;

  reg  [`W_LOG-1:0]                   round_robin_sel;

  // reg [`DATW-1:0]                     check_record;

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
      assign tree_filler_dinen_all_way[i]                                       = (round_robin_sel == i) && tree_filler_emp[i];
    end
  endgenerate

  always @(posedge CLK) begin
    if (RST) round_robin_sel <= 0;
    else     round_robin_sel <= round_robin_sel + 1;
  end

  assign tree_filler_din_shifted = (tree_filler_din_all_way >> ((`DATW<<`P_LOG) * round_robin_sel));
  assign tree_filler_din         = tree_filler_din_shifted[(`DATW<<`P_LOG)-1:0];
  assign tree_filler_dinen       = (|tree_filler_dinen_all_way) && (~RST);
  assign tree_filler_waddr       = round_robin_sel;

  TREE_FILLER #(`W_LOG, `P_LOG)
  tree_filler(CLK, RST, tree_filler_i_request, tree_filler_i_request_valid, tree_filler_din, tree_filler_dinen, tree_filler_waddr, 
              tree_filler_queue_full, tree_filler_dot, tree_filler_doten, tree_filler_dot_idx, tree_filler_emp);
  
  // vMERGE_SORTER_TREE #(`W_LOG, `FIFO_SIZE, `DATW, `KEYW)
  // vmerge_sorter_tree(CLK, RST, tree_filler_queue_full, 1'b0, );

  // show result
  always @(posedge CLK) begin
    if (tree_filler_dinen) begin
      case (`P_LOG)
        1: $write("%d %d | %d, %b", tree_filler_din[(`KEYW+`DATW*1)-1:`DATW*1], tree_filler_din[(`KEYW+`DATW*0)-1:`DATW*0], round_robin_sel, tree_filler_emp);
        2: $write("%d %d %d %d | %d, %b", tree_filler_din[(`KEYW+`DATW*3)-1:`DATW*3], tree_filler_din[(`KEYW+`DATW*2)-1:`DATW*2], tree_filler_din[(`KEYW+`DATW*1)-1:`DATW*1], tree_filler_din[(`KEYW+`DATW*0)-1:`DATW*0], round_robin_sel, tree_filler_emp);
        3: $write("%d %d %d %d %d %d %d %d | %d, %b", tree_filler_din[(`KEYW+`DATW*7)-1:`DATW*7], tree_filler_din[(`KEYW+`DATW*6)-1:`DATW*6], tree_filler_din[(`KEYW+`DATW*5)-1:`DATW*5], tree_filler_din[(`KEYW+`DATW*4)-1:`DATW*4], tree_filler_din[(`KEYW+`DATW*3)-1:`DATW*3], tree_filler_din[(`KEYW+`DATW*2)-1:`DATW*2], tree_filler_din[(`KEYW+`DATW*1)-1:`DATW*1], tree_filler_din[(`KEYW+`DATW*0)-1:`DATW*0], round_robin_sel, tree_filler_emp);
      endcase
      $write("\n");
      $fflush();
    end
  end
  // always @(posedge CLK) begin
  //   if (merge_sorter_tree_doten) begin
  //     $write("%d", merge_sorter_tree_dot[`KEYW-1:0]);
  //     $write("\n");
  //     $fflush();
  //   end
  // end

  // // error checker
  // always @(posedge CLK) begin
  //   if (RST) begin
  //     check_record <= {{(`DATW-`KEYW){1'b1}}, `KEYW'b1};
  //   end else begin
  //     if (merge_sorter_tree_doten) begin
  //       check_record <= check_record + 1;
  //       if (merge_sorter_tree_dot != check_record) begin
  //         $write("\nError!\n");
  //         $write("%d %d\n", merge_sorter_tree_dot, check_record);
  //         $finish();
  //       end
  //     end
  //   end
  // end
  
  // simulation finish condition
  reg [31:0] cycle;
  always @(posedge CLK) begin
    if (RST) begin
      cycle <= 0;
    end else begin
      cycle <= cycle + 1;
      if (cycle >= 10) $finish();
    end
  end

endmodule

`default_nettype wire
