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


module freq(input  wire CLK,
            input  wire RST_IN,
            output wire OUT);
  
  reg RST; always @(posedge CLK) RST <= RST_IN;
  
  wire [`W_LOG-1:0]                   tree_filler_i_request;
  wire                                tree_filler_i_request_valid;
  reg  [(`DATW<<`P_LOG)-1:0]          tree_filler_din;
  reg                                 tree_filler_dinen;
  reg [`W_LOG-1:0]                    tree_filler_waddr;
  wire                                tree_filler_queue_full;
  wire [`DATW-1:0]                    tree_filler_dot;
  wire                                tree_filler_doten;
  wire [`W_LOG-1:0]                   tree_filler_dot_idx;
  wire [(1<<`W_LOG)-1:0]              tree_filler_emp;

  wire [`DATW-1:0]                    vmerge_sorter_tree_dot;
  wire                                vmerge_sorter_tree_doten;

  always @(posedge CLK) begin
    if (RST) begin
      tree_filler_din   <= 0;
      tree_filler_dinen <= 0;
      tree_filler_waddr <= 1;
    end else begin
      tree_filler_din   <= tree_filler_din + 1;
      tree_filler_dinen <= ~tree_filler_dinen;
      tree_filler_waddr <= {tree_filler_waddr[0], tree_filler_waddr[`W_LOG-1:1]};
    end
  end
  
  TREE_FILLER #(`W_LOG, `P_LOG)
  tree_filler(CLK, RST, tree_filler_i_request, tree_filler_i_request_valid, tree_filler_din, tree_filler_dinen, tree_filler_waddr, 
              tree_filler_queue_full, tree_filler_dot, tree_filler_doten, tree_filler_dot_idx, tree_filler_emp);
  
  vMERGE_SORTER_TREE #(`W_LOG, `FIFO_SIZE, `DATW, `KEYW)
  vmerge_sorter_tree(CLK, RST, tree_filler_queue_full, 1'b0, tree_filler_dot, tree_filler_doten, tree_filler_dot_idx, 
                     tree_filler_i_request, tree_filler_i_request_valid, vmerge_sorter_tree_dot, vmerge_sorter_tree_doten);

  reg [`DATW-1:0] dot_buf; 
  always @(posedge CLK) begin
    if (vmerge_sorter_tree_doten) dot_buf <= vmerge_sorter_tree_dot;
  end

  assign OUT = ^dot_buf;

endmodule

`default_nettype wire
