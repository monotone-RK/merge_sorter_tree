/******************************************************************************/
/* A merge sorter tree                                       Ryohei Kobayashi */
/*                                                         Version 2017-12-09 */
/******************************************************************************/
`default_nettype none

/***** A sorter cell                                                      *****/
/******************************************************************************/
module SORTER_CELL #(parameter              DATW = 64,
                     parameter              KEYW = 32)
                    (input  wire [DATW-1:0] DIN0,
                     input  wire [DATW-1:0] DIN1,
                     input  wire            VLD0,
                     input  wire            VLD1,
                     input  wire            FULL,
                     output wire            DEQ0,
                     output wire            DEQ1,
                     output wire [DATW-1:0] DOUT,
                     output wire            DOUT_VLD);

  function [DATW-1:0] mux;
    input [DATW-1:0] a;
    input [DATW-1:0] b;
    input            sel;
    begin
      case (sel)
        1'b0: mux = a;
        1'b1: mux = b;
      endcase
    end
  endfunction

  wire comp_rslt = (DIN0[KEYW-1:0] < DIN1[KEYW-1:0]);
  wire enq       = &{(~FULL), VLD0, VLD1};

  assign DEQ0     = &{enq,  comp_rslt};
  assign DEQ1     = &{enq, ~comp_rslt};
  assign DOUT     = mux(DIN1, DIN0, comp_rslt);
  assign DOUT_VLD = enq;
  
endmodule


/***** A FIFO with only two entries                                       *****/
/******************************************************************************/
module TWO_ENTRY_FIFO #(parameter                    FIFO_WIDTH = 64)  // fifo width in bit
                       (input  wire                  CLK, 
                        input  wire                  RST, 
                        input  wire                  enq, 
                        input  wire                  deq, 
                        input  wire [FIFO_WIDTH-1:0] din, 
                        output wire [FIFO_WIDTH-1:0] dot, 
                        output wire                  emp, 
                        output wire                  full, 
                        output reg  [1:0]            cnt);
  
  reg                  head, tail;
  reg [FIFO_WIDTH-1:0] mem [1:0];

  assign emp  = (cnt == 0);
  assign full = (cnt == 2);
  assign dot  = mem[head];

  always @(posedge CLK) begin
    if (RST) {cnt, head, tail} <= 0;
    else begin
      case ({enq, deq})
        2'b01: begin                 head<=~head;              cnt<=cnt-1; end
        2'b10: begin mem[tail]<=din;              tail<=~tail; cnt<=cnt+1; end
        2'b11: begin mem[tail]<=din; head<=~head; tail<=~tail;             end
      endcase
    end
  end
  
endmodule


/***** A node of the merge sorter tree                                    *****/
/******************************************************************************/
module TREE_NODE #(parameter              DATW = 64,
                   parameter              KEYW = 32)
                  (input  wire            CLK,
                   input  wire            RST,
                   input  wire            IN_FULL,
                   input  wire [DATW-1:0] DIN0,
                   input  wire            ENQ0,
                   input  wire [DATW-1:0] DIN1,
                   input  wire            ENQ1,
                   output wire            FUL0,
                   output wire            FUL1,
                   output wire [DATW-1:0] DOUT,
                   output wire            DOUT_VLD);

  wire            fifo0_enq, fifo1_enq;
  wire            fifo0_deq, fifo1_deq;
  wire [DATW-1:0] fifo0_din, fifo1_din;
  wire [DATW-1:0] fifo0_dot, fifo1_dot;
  wire            fifo0_emp, fifo1_emp;
  wire            fifo0_ful, fifo1_ful;
  wire [1:0]      fifo0_cnt, fifo1_cnt;

  wire [DATW-1:0] scell_dot;
  wire            scell_doten;

  assign fifo0_enq = ENQ0;
  assign fifo1_enq = ENQ1;
  assign fifo0_din = DIN0;
  assign fifo1_din = DIN1;

  TWO_ENTRY_FIFO #(DATW)
  fifo0(CLK, RST, fifo0_enq, fifo0_deq, fifo0_din,
        fifo0_dot, fifo0_emp, fifo0_ful, fifo0_cnt);
  TWO_ENTRY_FIFO #(DATW)
  fifo1(CLK, RST, fifo1_enq, fifo1_deq, fifo1_din,
        fifo1_dot, fifo1_emp, fifo1_ful, fifo1_cnt);
  
  SORTER_CELL #(DATW, KEYW)
  sorter_cell(fifo0_dot, fifo1_dot, ~fifo0_emp, ~fifo1_emp, IN_FULL, 
              fifo0_deq, fifo1_deq, scell_dot, scell_doten);

  // Output  
  assign FUL0     = fifo0_ful;
  assign FUL1     = fifo1_ful;
  assign DOUT     = scell_dot;
  assign DOUT_VLD = scell_doten;
    
endmodule


/***** A merge sorter tree                                                *****/
/******************************************************************************/
module MERGE_SORTER_TREE #(parameter                       W_LOG = 2,
                           parameter                       DATW  = 64,
                           parameter                       KEYW  = 32)
                          (input  wire                     CLK,
                           input  wire                     RST,
                           input  wire                     IN_FULL,
                           input  wire [(DATW<<W_LOG)-1:0] DIN,
                           input  wire [(1<<W_LOG)-1:0]    DINEN,
                           output wire [(1<<W_LOG)-1:0]    FULL,
                           output wire [DATW-1:0]          DOT,
                           output wire                     DOTEN);

  genvar i, j;
  generate
    for (i=0; i<W_LOG; i=i+1) begin: level
      wire [(1<<(W_LOG-(i+1)))-1:0]    node_in_full;
      wire [(DATW<<(W_LOG-i))-1:0]     node_din;
      wire [(1<<(W_LOG-i))-1:0]        node_dinen;
      wire [(1<<(W_LOG-i))-1:0]        node_full;
      wire [(DATW<<(W_LOG-(i+1)))-1:0] node_dot;
      wire [(1<<(W_LOG-(i+1)))-1:0]    node_doten;
      for (j=0; j<(1<<(W_LOG-(i+1))); j=j+1) begin: nodes
        TREE_NODE #(DATW, KEYW)
        tree_node(CLK, RST, node_in_full[j], node_din[DATW*(2*j+1)-1:DATW*(2*j)], node_dinen[2*j], node_din[DATW*(2*j+2)-1:DATW*(2*j+1)], node_dinen[2*j+1], 
                  node_full[2*j], node_full[2*j+1], node_dot[DATW*(j+1)-1:DATW*j], node_doten[j]);
      end
    end
  endgenerate

  generate
    for (i=0; i<W_LOG; i=i+1) begin: connection
      if (i == 0) begin
        assign level[0].node_din   = DIN;
        assign level[0].node_dinen = DINEN;
        assign FULL                = level[0].node_full;
      end else begin
        assign level[i].node_din       = level[i-1].node_dot;
        assign level[i].node_dinen     = level[i-1].node_doten;
        assign level[i-1].node_in_full = level[i].node_full;
      end
    end
  endgenerate

  assign level[W_LOG-1].node_in_full = IN_FULL;
  assign DOT                         = level[W_LOG-1].node_dot;
  assign DOTEN                       = level[W_LOG-1].node_doten;
  
endmodule

`default_nettype wire
