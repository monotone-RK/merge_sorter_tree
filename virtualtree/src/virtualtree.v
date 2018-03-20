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
                     input  wire            DINs_VALID,
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
  wire enq       = DINs_VALID;

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


/***** An SRL(Shift Register LUT)-based FIFO                              *****/
/******************************************************************************/
module SRL_FIFO #(parameter                    FIFO_SIZE  = 4,   // size in log scale, 4 for 16 entry
                  parameter                    FIFO_WIDTH = 32)  // fifo width in bit
                 (input  wire                  CLK,
                  input  wire                  RST,
                  input  wire                  enq,
                  input  wire                  deq,
                  input  wire [FIFO_WIDTH-1:0] din,
                  output wire [FIFO_WIDTH-1:0] dot,
                  output wire                  emp,
                  output wire                  full,
                  output reg  [FIFO_SIZE:0]    cnt);

  reg  [FIFO_SIZE-1:0]  head;
  reg  [FIFO_WIDTH-1:0] mem [(1<<FIFO_SIZE)-1:0];
  
  assign emp  = (cnt==0);
  assign full = (cnt==(1<<FIFO_SIZE));
  assign dot  = mem[head];
    
  always @(posedge CLK) begin
    if (RST) begin
      cnt  <= 0;
      head <= {(FIFO_SIZE){1'b1}};
    end else begin
      case ({enq, deq})
        2'b01: begin cnt <= cnt - 1; head <= head - 1; end
        2'b10: begin cnt <= cnt + 1; head <= head + 1; end
      endcase
    end
  end

  integer i;
  always @(posedge CLK) begin
    if (enq) begin
      mem[0] <= din;
      for (i=1; i<(1<<FIFO_SIZE); i=i+1) mem[i] <= mem[i-1];
    end
  end
  
endmodule


/*****  A multi-channel FIFO                                              *****/
/******************************************************************************/
module MULTI_CHANNEL_FIFO #(parameter                    C_LOG      = 2,  // # of channels in log scale
                            parameter                    FIFO_SIZE  = 2,  // FIFO depth of each channel in log scale
                            parameter                    FIFO_WIDTH = 32)
                           (input  wire                  CLK,
                            input  wire                  RST,
                            input  wire                  enq,
                            input  wire [C_LOG-1:0]      enq_idx,
                            input  wire                  deq,
                            input  wire [C_LOG-1:0]      deq_idx,
                            input  wire [C_LOG-1:0]      _deq_idx,
                            input  wire [FIFO_WIDTH-1:0] din,
                            output reg  [FIFO_WIDTH-1:0] dot,
                            output wire [(1<<C_LOG)-1:0] emp,
                            output wire [(1<<C_LOG)-1:0] full);

  // FIFO_SIZE-1 -> FIFO_SIZE (to generate emp and full)
  reg [FIFO_SIZE:0] head_list [(1<<C_LOG)-1:0];
  reg [FIFO_SIZE:0] tail_list [(1<<C_LOG)-1:0];

  reg [FIFO_WIDTH-1:0] mem [(1<<(C_LOG+FIFO_SIZE))-1:0];
     
  genvar i;
  generate
    for (i=0; i<(1<<C_LOG); i=i+1) begin: channels
      assign emp[i]  = (head_list[i] == tail_list[i]);
      assign full[i] = (head_list[i] == {~tail_list[i][FIFO_SIZE], tail_list[i][FIFO_SIZE-1:0]});
    end
  endgenerate
  
  wire [(C_LOG+FIFO_SIZE)-1:0] raddr = {_deq_idx, head_list[_deq_idx][FIFO_SIZE-1:0]};
  wire [(C_LOG+FIFO_SIZE)-1:0] waddr = {enq_idx, tail_list[enq_idx][FIFO_SIZE-1:0]};
  
  always @(posedge CLK) dot <= mem[raddr];

  integer p;
  always @(posedge CLK) begin
    if (RST) begin
      for (p=0; p<(1<<C_LOG); p=p+1) begin
        head_list[p] <= 0; 
        tail_list[p] <= 0;
      end
    end else begin
      case ({enq, deq})
        2'b01: begin 
          head_list[deq_idx] <= head_list[deq_idx] + 1;
        end
        2'b10: begin 
          mem[waddr]         <= din;
          tail_list[enq_idx] <= tail_list[enq_idx] + 1; 
        end
        2'b11: begin 
          mem[waddr]         <= din; 
          head_list[deq_idx] <= head_list[deq_idx] + 1; 
          tail_list[enq_idx] <= tail_list[enq_idx] + 1; 
        end
      endcase
    end
  end
  
endmodule
  

/*****  A Block RAM-based buffer layer                                    *****/
/******************************************************************************/
module RAM_LAYER #(parameter                    W_LOG      = 2,
                   parameter                    FIFO_SIZE  = 2,
                   parameter                    FIFO_WIDTH = 32)
                  (input  wire                  CLK,
                   input  wire                  RST,
                   input  wire                  ENQ,
                   input  wire [W_LOG-1:0]      ENQ_IDX,
                   input  wire                  DEQ0,
                   input  wire                  DEQ1,
                   input  wire [W_LOG-2:0]      DEQ_IDX,
                   input  wire [W_LOG-2:0]      _DEQ_IDX,
                   input  wire [FIFO_WIDTH-1:0] DIN, 
                   output wire [FIFO_WIDTH-1:0] DOT0,
                   output wire [FIFO_WIDTH-1:0] DOT1,
                   output wire                  EMP0,
                   output wire                  EMP1);

  wire                      even_enq = &{ENQ, ~ENQ_IDX[0]};
  wire                      odd_enq  = &{ENQ,  ENQ_IDX[0]};
  wire [W_LOG-2:0]          enq_idx  = (ENQ_IDX >> 1);
  wire                      even_deq = DEQ0;
  wire                      odd_deq  = DEQ1;
  wire [W_LOG-2:0]          deq_idx  = DEQ_IDX;
  wire [W_LOG-2:0]          _deq_idx  = _DEQ_IDX;
  wire [FIFO_WIDTH-1:0]     din      = DIN;
  wire [FIFO_WIDTH-1:0]     even_dot, odd_dot;
  wire [(1<<(W_LOG-1))-1:0] even_emp, odd_emp;
  wire [(1<<(W_LOG-1))-1:0] even_full, odd_full;
  
  MULTI_CHANNEL_FIFO #((W_LOG-1), FIFO_SIZE, FIFO_WIDTH)
  even_numbered_fifo(CLK, RST, even_enq, enq_idx, even_deq, deq_idx, _deq_idx, din, 
                     even_dot, even_emp, even_full);
  MULTI_CHANNEL_FIFO #((W_LOG-1), FIFO_SIZE, FIFO_WIDTH)
  odd_numbered_fifo(CLK, RST, odd_enq, enq_idx, odd_deq, deq_idx, _deq_idx, din, 
                    odd_dot, odd_emp, odd_full);
  
  // Output
  assign DOT0 = even_dot;
  assign DOT1 = odd_dot;
  assign EMP0 = even_emp[_deq_idx];
  assign EMP1 = odd_emp[_deq_idx];
  
endmodule


/*****  A body of the sorter stage                                        *****/
/******************************************************************************/
module SORTER_STAGE_BODY #(parameter               W_LOG     = 2,
                           parameter               FIFO_SIZE = 2,
                           parameter               DATW      = 64,
                           parameter               KEYW      = 32) 
                          (input  wire             CLK,
                           input  wire             RST,
                           input  wire             QUEUE_IN_FULL,
                           input  wire [W_LOG-2:0] I_REQUEST,
                           input  wire             I_REQUEST_VALID,
                           input  wire [DATW-1:0]  DIN,
                           input  wire             DINEN,
                           input  wire [W_LOG-1:0] DIN_IDX,
                           output wire             QUEUE_FULL,
                           output wire [W_LOG-1:0] O_REQUEST,
                           output wire             O_REQUEST_VALID,
                           output wire [DATW-1:0]  DOT,
                           output wire             DOTEN,
                           output wire [W_LOG-2:0] DOT_IDX);
  
  function [W_LOG-1:0] request_gen;
    input [W_LOG-1:0] in;
    input [1:0]       sel;
    begin
      case (sel)
        2'b01: request_gen = (in << 1);
        2'b10: request_gen = (in << 1) + 1;
      endcase
    end
  endfunction
  
  wire             queue_enq;
  wire             queue_deq;
  wire [W_LOG-2:0] queue_din;
  wire [W_LOG-2:0] queue_dot;
  wire             queue_emp;
  wire             queue_ful; 
  wire [1:0]       queue_cnt; 
  
  wire             ram_layer_enq;
  wire [W_LOG-1:0] ram_layer_enq_idx;
  wire             ram_layer_deq0;
  wire             ram_layer_deq1;
  wire [W_LOG-2:0] ram_layer_deq_idx;
  wire [DATW-1:0]  ram_layer_din;
  wire [DATW-1:0]  ram_layer_dot0;
  wire [DATW-1:0]  ram_layer_dot1;
  wire             ram_layer_emp0;
  wire             ram_layer_emp1;

  reg              comp_data_ready;
  wire [DATW-1:0]  sorter_cell_dot;
  wire             sorter_cell_doten;

  reg  [1:0]       state;  // note!!!

  reg              req_state;
  reg [W_LOG-1:0]  request_4_emp;
  reg              request_valid;

  assign queue_enq         = I_REQUEST_VALID;
  assign queue_deq         = ~|{QUEUE_IN_FULL,queue_emp,ram_layer_emp0,ram_layer_emp1};
  assign queue_din         = I_REQUEST;

  assign ram_layer_enq     = DINEN;
  assign ram_layer_enq_idx = DIN_IDX;
  assign ram_layer_deq_idx = queue_dot;
  assign ram_layer_din     = DIN;
  
  TWO_ENTRY_FIFO #(W_LOG-1)
  request_queue(CLK, RST, queue_enq, queue_deq, queue_din, 
                queue_dot, queue_emp, queue_ful, queue_cnt);

  RAM_LAYER #(W_LOG, FIFO_SIZE, DATW)
  ram_layer(CLK, RST, ram_layer_enq, ram_layer_enq_idx, ram_layer_deq0, ram_layer_deq1, queue_dot_buf, queue_dot, ram_layer_din, 
            ram_layer_dot0, ram_layer_dot1, ram_layer_emp0, ram_layer_emp1);
  
  SORTER_CELL #(DATW, KEYW)
  sorter_cell(ram_layer_dot0, ram_layer_dot1, comp_data_ready, 
              ram_layer_deq0, ram_layer_deq1, sorter_cell_dot, sorter_cell_doten);

  always @(posedge CLK) begin
    if      (ram_layer_emp0) request_4_emp <= ({1'b0, queue_dot} << 1);
    else if (ram_layer_emp1) request_4_emp <= ({1'b0, queue_dot} << 1) + 1 ;
  end

  reg [W_LOG-2:0] queue_dot_buf;
  always @(posedge CLK) begin
    if (RST) begin
      queue_dot_buf   <= 0;
      state           <= 0;
      comp_data_ready <= 0;
      request_valid   <= 0;
    end else begin
      queue_dot_buf <= queue_dot;
      case (state)
        0: begin
          if (~|{QUEUE_IN_FULL,queue_emp}) begin
            request_valid <= 1;
            if (~|{ram_layer_emp0,ram_layer_emp1}) begin
              state           <= 1;
              comp_data_ready <= 1;
            end 
          end else begin
            request_valid <= 0;
          end
        end
        1: begin
          if (~|{queue_emp,ram_layer_emp0,ram_layer_emp1,(queue_dot_buf == queue_dot)}) begin
            state           <= 2;
          end else begin
            state           <= 0;
            comp_data_ready <= 0;
            request_valid   <= 0;
          end
        end
        2: begin
          if (~|{QUEUE_IN_FULL,queue_emp,ram_layer_emp0,ram_layer_emp1,(queue_dot_buf == queue_dot)}) begin
            state           <= 2;
          end else begin
            state           <= 0;
            comp_data_ready <= 0;
            request_valid   <= 0;
          end
        end
      endcase
    end
  end

  assign QUEUE_FULL = queue_ful;
  assign O_REQUEST  = (comp_data_ready) ? request_gen({1'b0, queue_dot_buf}, {ram_layer_deq1,ram_layer_deq0}) : request_4_emp;
  assign O_REQUEST_VALID = request_valid;
  assign DOT        = sorter_cell_dot;
  assign DOTEN      = sorter_cell_doten;
  assign DOT_IDX    = queue_dot_buf;

endmodule


/*****  A root of the sorter stage                                        *****/
/******************************************************************************/
module SORTER_STAGE_ROOT #(parameter              FIFO_SIZE = 2,
                           parameter              DATW      = 64,
                           parameter              KEYW      = 32) 
                          (input  wire            CLK,
                           input  wire            RST,
                           input  wire            QUEUE_IN_FULL,
                           input  wire            IN_FULL,
                           input  wire [DATW-1:0] DIN,
                           input  wire            DINEN,
                           input  wire            DIN_IDX,
                           output wire            O_REQUEST,
                           output wire            O_REQUEST_VALID,
                           output wire [DATW-1:0] DOT,
                           output wire            DOTEN);

  wire               fifo0_enq;
  wire               fifo0_deq;
  wire [DATW-1:0]    fifo0_din;
  wire [DATW-1:0]    fifo0_dot;
  wire               fifo0_emp;
  wire               fifo0_ful; 
  wire [FIFO_SIZE:0] fifo0_cnt; 

  wire               fifo1_enq;
  wire               fifo1_deq;
  wire [DATW-1:0]    fifo1_din;
  wire [DATW-1:0]    fifo1_dot;
  wire               fifo1_emp;
  wire               fifo1_ful; 
  wire [FIFO_SIZE:0] fifo1_cnt; 

  wire               comp_data_ready;
  wire [DATW-1:0]    sorter_cell_dot;
  wire               sorter_cell_doten;
  
  assign fifo0_enq = &{DINEN, ~DIN_IDX};
  assign fifo0_din = DIN;

  assign fifo1_enq = &{DINEN,  DIN_IDX};
  assign fifo1_din = DIN;

  assign comp_data_ready = ~|{IN_FULL,fifo0_emp,fifo1_emp};
  
  SRL_FIFO #(FIFO_SIZE, DATW)
  fifo0(CLK, RST, fifo0_enq, fifo0_deq, fifo0_din, 
        fifo0_dot, fifo0_emp, fifo0_ful ,fifo0_cnt);
  SRL_FIFO #(FIFO_SIZE, DATW)
  fifo1(CLK, RST, fifo1_enq, fifo1_deq, fifo1_din, 
        fifo1_dot, fifo1_emp, fifo1_ful ,fifo1_cnt);

  SORTER_CELL #(DATW, KEYW)
  sorter_cell(fifo0_dot, fifo1_dot, comp_data_ready, 
              fifo0_deq, fifo1_deq, sorter_cell_dot, sorter_cell_doten);

  // Output
  assign O_REQUEST       = (comp_data_ready) ? fifo1_deq : ~fifo0_emp;
  assign O_REQUEST_VALID = ~|{QUEUE_IN_FULL, IN_FULL};
  assign DOT             = sorter_cell_dot;
  assign DOTEN           = sorter_cell_doten;
  
endmodule


/***** A tree of sorter stage                                             *****/
/******************************************************************************/
module SORTER_STAGE_TREE #(parameter               W_LOG     = 2,
                           parameter               FIFO_SIZE = 2,
                           parameter               DATW      = 64,
                           parameter               KEYW      = 32)
                          (input  wire             CLK,
                           input  wire             RST, 
                           input  wire             QUEUE_IN_FULL,
                           input  wire             IN_FULL,
                           input  wire [DATW-1:0]  DIN,
                           input  wire             DINEN,
                           input  wire [W_LOG-1:0] DIN_IDX,
                           output wire [W_LOG-1:0] O_REQUEST,
                           output wire             O_REQUEST_VALID,
                           output wire [DATW-1:0]  DOT,
                           output wire             DOTEN);

  genvar i;
  generate
    for (i=0; i<W_LOG; i=i+1) begin: stage
      wire            queue_in_full;
      wire [DATW-1:0] din;
      wire            dinen;
      wire [i:0]      din_idx;
      wire [i:0]      o_request;
      wire            o_request_valid;
      wire [DATW-1:0] dot;
      wire            doten;
      if (i == 0) begin: root
        wire in_full;
        SORTER_STAGE_ROOT #(FIFO_SIZE, DATW, KEYW)
        sorter_stage_root(CLK, RST, queue_in_full, in_full, din, dinen, din_idx, 
                          o_request, o_request_valid, dot, doten);
      end else begin: body
        wire [i-1:0] i_request;
        wire         i_request_valid;
        wire         queue_full;
        wire [i-1:0] dot_idx;
        SORTER_STAGE_BODY #((i+1), FIFO_SIZE, DATW, KEYW)
        sorter_stage_body(CLK, RST, queue_in_full, i_request, i_request_valid, din, dinen, din_idx, 
                          queue_full, o_request, o_request_valid, dot, doten, dot_idx);
      end
    end
  endgenerate

  generate
    for (i=0; i<W_LOG; i=i+1) begin: connection
      if (i == W_LOG-1) begin
        assign stage[W_LOG-1].queue_in_full    = QUEUE_IN_FULL;
        assign O_REQUEST                       = stage[W_LOG-1].o_request;
        assign O_REQUEST_VALID                 = stage[W_LOG-1].o_request_valid;
        assign stage[W_LOG-1].din              = DIN;
        assign stage[W_LOG-1].dinen            = DINEN;
        assign stage[W_LOG-1].din_idx          = DIN_IDX;
      end else begin
        assign stage[i].queue_in_full          = stage[i+1].body.queue_full;
        assign stage[i+1].body.i_request       = stage[i].o_request;
        assign stage[i+1].body.i_request_valid = stage[i].o_request_valid;
        assign stage[i].din                    = stage[i+1].dot;
        assign stage[i].dinen                  = stage[i+1].doten;
        assign stage[i].din_idx                = stage[i+1].body.dot_idx;
      end
    end
  endgenerate
  
  assign stage[0].root.in_full = IN_FULL;
  assign DOT                   = stage[0].dot;
  assign DOTEN                 = stage[0].doten;

endmodule


/*****  A multi-channel FIFO with one entry                               *****/
/******************************************************************************/
module _MULTI_CHANNEL_FIFO #(parameter                    C_LOG      = 2,  // # of channels in log scale
                             parameter                    FIFO_WIDTH = 32)
                            (input  wire                  CLK,
                             input  wire                  RST,
                             input  wire                  enq,
                             input  wire [C_LOG-1:0]      enq_idx,
                             input  wire                  deq,
                             input  wire [C_LOG-1:0]      deq_idx,
                             input  wire [FIFO_WIDTH-1:0] din,
                             output reg  [FIFO_WIDTH-1:0] dot,
                             output wire [(1<<C_LOG)-1:0] emp,
                             output wire [(1<<C_LOG)-1:0] full);

  reg [(1<<C_LOG)-1:0] head_list;
  reg [(1<<C_LOG)-1:0] tail_list;

  reg [FIFO_WIDTH-1:0] mem [(1<<C_LOG)-1:0];
     
  genvar i;
  generate
    for (i=0; i<(1<<C_LOG); i=i+1) begin: channels
      assign emp[i]  = (head_list[i] ==  tail_list[i]);
      assign full[i] = (head_list[i] == ~tail_list[i]);
    end
  endgenerate
  
  wire [C_LOG-1:0] raddr = deq_idx;
  wire [C_LOG-1:0] waddr = enq_idx;
  
  always @(posedge CLK) dot <= mem[raddr];

  always @(posedge CLK) begin
    if (RST) begin
      head_list <= 0;
      tail_list <= 0;
    end else begin
      case ({enq, deq})
        2'b01: begin 
          head_list[deq_idx] <= ~head_list[deq_idx];
        end
        2'b10: begin 
          mem[waddr]         <= din;
          tail_list[enq_idx] <= ~tail_list[enq_idx]; 
        end
        2'b11: begin 
          mem[waddr]         <= din; 
          head_list[deq_idx] <= ~head_list[deq_idx]; 
          tail_list[enq_idx] <= ~tail_list[enq_idx]; 
        end
      endcase
    end
  end
  
endmodule
  

/***** A BlockRAM module                                                  *****/
/******************************************************************************/
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


/***** A tree filler                                                      *****/
/******************************************************************************/
module TREE_FILLER #(parameter                       W_LOG     = 2,
                     parameter                       P_LOG     = 3,  // sorting network size in log scale
                     parameter                       FIFO_SIZE = 2,
                     parameter                       DATW      = 64)
                    (input  wire                     CLK,
                     input  wire                     RST,
                     input  wire [W_LOG-1:0]         I_REQUEST,
                     input  wire                     I_REQUEST_VALID,
                     input  wire [(DATW<<P_LOG)-1:0] DIN,
                     input  wire                     DINEN,
                     input  wire [W_LOG-1:0]         DIN_IDX,
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

  wire                     mfifo_enq;
  wire [W_LOG-1:0]         mfifo_enq_idx;
  wire                     mfifo_deq;
  wire [W_LOG-1:0]         mfifo_deq_idx;
  wire [(DATW<<P_LOG)-1:0] mfifo_din;
  wire [(DATW<<P_LOG)-1:0] mfifo_dot;
  wire [(1<<W_LOG)-1:0]    mfifo_emp;
  wire [(1<<W_LOG)-1:0]    mfifo_ful;

  reg  [(DATW<<P_LOG)-1:0] shifted_data;

  reg  [P_LOG-1:0]         read_cnt [(1<<W_LOG)-1:0];
  reg  [W_LOG-1:0]         read_raddr;
  reg  [2:0]               read_state;
  reg                      state_one;
  reg                      data_ready;
  reg                      requeue_deq;
  reg  [(1<<W_LOG)-1:0]    almost_be_emp;
  reg                      init_done;
  reg [W_LOG-1:0]          init_deq_idx;

  assign queue_enq     = I_REQUEST_VALID && init_done;
  assign queue_deq     = state_one || &{requeue_deq,~queue_emp,(read_raddr == mfifo_deq_idx)};
  assign queue_din     = I_REQUEST;

  assign mfifo_enq     = DINEN;
  assign mfifo_enq_idx = DIN_IDX;
  assign mfifo_deq     = &{queue_deq,almost_be_emp[mfifo_deq_idx]};
  assign mfifo_deq_idx = (init_done) ? queue_dot : init_deq_idx;
  assign mfifo_din     = DIN;

  TWO_ENTRY_FIFO #(W_LOG)
  request_queue(CLK, RST, queue_enq, queue_deq, queue_din, 
                queue_dot, queue_emp, queue_ful, queue_cnt);

  _MULTI_CHANNEL_FIFO #(W_LOG, (DATW<<P_LOG))
  _multi_channel_fifo(CLK, RST, mfifo_enq, mfifo_enq_idx, mfifo_deq, mfifo_deq_idx, mfifo_din, 
                      mfifo_dot, mfifo_emp, mfifo_ful);

  always @(posedge CLK) begin
    shifted_data <= mfifo_dot >> (DATW * read_cnt[mfifo_deq_idx]);
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
      ////// for init (begin)
      init_done     <= 0;
      init_deq_idx  <= 0;
      ////// for init (end)
    end else begin
      case (read_state)
        ////// for init (begin)
        0: begin
          if (!init_done) begin if (!emp[mfifo_deq_idx]) read_state <= 1; end
          else            begin                          read_state <= 3; end
        end
        1: begin  // mfifo_dot has been set
          read_raddr              <= mfifo_deq_idx;
          read_state              <= 2;
          read_cnt[mfifo_deq_idx] <= read_cnt[mfifo_deq_idx] + 1;
          data_ready              <= 1;
        end
        2: begin  // shifted_data has been set
          if (read_cnt[mfifo_deq_idx] == (1<<FIFO_SIZE)) begin
            read_state   <= 0;
            data_ready   <= 0;
            init_deq_idx <= init_deq_idx + 1;
            if (init_deq_idx == (1<<W_LOG)-1) begin
              init_done <= 1;
            end
          end else begin
            read_cnt[mfifo_deq_idx] <= read_cnt[mfifo_deq_idx] + 1;
          end
        end
        ////// for init (end)
        3: begin
          data_ready <= 0;
          if (~|{queue_emp,emp[mfifo_deq_idx]}) begin
            read_state <= 4;
            state_one  <= 1;
          end
        end
        4: begin  // mfifo_dot has been set
          read_raddr                <= mfifo_deq_idx;
          read_state                <= (almost_be_emp[mfifo_deq_idx]) ? 3 : 5;
          state_one                 <= 0;
          read_cnt[mfifo_deq_idx]   <= read_cnt[mfifo_deq_idx] + 1;
          data_ready                <= 1;
          requeue_deq               <= 1;
          almost_be_emp[mfifo_deq_idx] <= (read_cnt[mfifo_deq_idx] == NUM_RECORD-2);
        end
        5: begin  // shifted_data has been set
          if (!queue_emp && (read_raddr == mfifo_deq_idx)) begin
            read_cnt[mfifo_deq_idx]      <= read_cnt[mfifo_deq_idx] + 1;
            almost_be_emp[mfifo_deq_idx] <= (read_cnt[mfifo_deq_idx] == NUM_RECORD-2);
            if (almost_be_emp[mfifo_deq_idx]) begin
              read_state  <= 3;
              requeue_deq <= 0;
            end
          end else begin
            read_state  <= 3;
            data_ready  <= 0;
            requeue_deq <= 0;
          end
        end
      endcase
    end
  end

  assign QUEUE_FULL = queue_ful;
  assign DOT        = shifted_data[DATW-1:0];
  assign DOTEN      = data_ready;
  assign DOT_IDX    = read_raddr;
  assign emp        = mfifo_emp;

endmodule  


/***** A virtual merge sorter tree                                       *****/
/******************************************************************************/
module vMERGE_SORTER_TREE #(parameter                       W_LOG     = 2,
                            parameter                       P_LOG     = 3,
                            parameter                       FIFO_SIZE = 2,
                            parameter                       DATW      = 64,
                            parameter                       KEYW      = 32)
                           (input  wire                     CLK,
                            input  wire                     RST, 
                            input  wire                     IN_FULL,
                            input  wire [(DATW<<P_LOG)-1:0] DIN,
                            input  wire                     DINEN,
                            input  wire [W_LOG-1:0]         DIN_IDX,
                            output wire [DATW-1:0]          DOT,
                            output wire                     DOTEN,
                            output wire [(1<<W_LOG)-1:0]    emp);

  wire [W_LOG-1:0]         tree_filler_i_request;
  wire                     tree_filler_i_request_valid;
  wire [(DATW<<P_LOG)-1:0] tree_filler_din;
  wire                     tree_filler_dinen;
  wire [W_LOG-1:0]         tree_filler_din_idx;
  wire                     tree_filler_queue_full;
  wire [DATW-1:0]          tree_filler_dot;
  wire                     tree_filler_doten;
  wire [W_LOG-1:0]         tree_filler_dot_idx;
  wire [(1<<W_LOG)-1:0]    tree_filler_emp;

  wire                     sorter_stage_tree_in_full;
  wire [DATW-1:0]          sorter_stage_tree_dot;
  wire                     sorter_stage_tree_doten;
  
  assign tree_filler_din           = DIN;
  assign tree_filler_dinen         = DINEN;
  assign tree_filler_din_idx       = DIN_IDX;

  assign sorter_stage_tree_in_full = IN_FULL;
  
  TREE_FILLER #(W_LOG, P_LOG, FIFO_SIZE, DATW)
  tree_filler(CLK, RST, tree_filler_i_request, tree_filler_i_request_valid, tree_filler_din, tree_filler_dinen, tree_filler_din_idx, 
              tree_filler_queue_full, tree_filler_dot, tree_filler_doten, tree_filler_dot_idx, tree_filler_emp);
  
  SORTER_STAGE_TREE #(W_LOG, FIFO_SIZE, DATW, KEYW)
  sorter_stage_tree(CLK, RST, tree_filler_queue_full, sorter_stage_tree_in_full, tree_filler_dot, tree_filler_doten, tree_filler_dot_idx, 
                     tree_filler_i_request, tree_filler_i_request_valid, sorter_stage_tree_dot, sorter_stage_tree_doten);
  
  // Output
  assign DOT   = sorter_stage_tree_dot;
  assign DOTEN = sorter_stage_tree_doten;
  assign emp   = tree_filler_emp;

endmodule  

`default_nettype wire
