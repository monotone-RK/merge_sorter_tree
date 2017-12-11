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


/***** A BlockRAM-based FIFO                                              *****/
/******************************************************************************/
module BFIFO #(parameter                    FIFO_SIZE  =  4,  // size in log scale, 4 for 16 entry
               parameter                    FIFO_WIDTH = 32)  // fifo width in bit
              (input  wire                  CLK, 
               input  wire                  RST, 
               input  wire                  enq, 
               input  wire                  deq, 
               input  wire [FIFO_WIDTH-1:0] din, 
               output reg  [FIFO_WIDTH-1:0] dot, 
               output wire                  emp, 
               output wire                  full, 
               output reg  [FIFO_SIZE:0]    cnt);
  
  reg [FIFO_SIZE-1:0]  head, tail;
  reg [FIFO_WIDTH-1:0] mem [(1<<FIFO_SIZE)-1:0];

  assign emp  = (cnt==0);
  assign full = (cnt==(1<<FIFO_SIZE));
  
  always @(posedge CLK) dot <= mem[head];
  
  always @(posedge CLK) begin
    if (RST) {cnt, head, tail} <= 0;
    else begin
      case ({enq, deq})
        2'b01: begin                 head<=head+1;               cnt<=cnt-1; end
        2'b10: begin mem[tail]<=din;               tail<=tail+1; cnt<=cnt+1; end
        2'b11: begin mem[tail]<=din; head<=head+1; tail<=tail+1;             end
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
  
  wire [(C_LOG+FIFO_SIZE)-1:0] raddr = {deq_idx, head_list[deq_idx][FIFO_SIZE-1:0]};
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
  wire [FIFO_WIDTH-1:0]     din      = DIN;
  wire [FIFO_WIDTH-1:0]     even_dot, odd_dot;
  wire [(1<<(W_LOG-1))-1:0] even_emp, odd_emp;
  wire [(1<<(W_LOG-1))-1:0] even_full, odd_full;
  
  MULTI_CHANNEL_FIFO #((W_LOG-1), FIFO_SIZE, FIFO_WIDTH)
  even_numbered_fifo(CLK, RST, even_enq, enq_idx, even_deq, deq_idx, din, 
                     even_dot, even_emp, even_full);
  MULTI_CHANNEL_FIFO #((W_LOG-1), FIFO_SIZE, FIFO_WIDTH)
  odd_numbered_fifo(CLK, RST, odd_enq, enq_idx, odd_deq, deq_idx, din, 
                    odd_dot, odd_emp, odd_full);
  
  // Output
  assign DOT0 = even_dot;
  assign DOT1 = odd_dot;
  assign EMP0 = even_emp[deq_idx];
  assign EMP1 = odd_emp[deq_idx];
  
endmodule


/*****  A sorter stage                                                    *****/
/******************************************************************************/
module SORTER_STAGE #(parameter               W_LOG     = 2,
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

  reg              state;  // note!!!

  reg              req_state;
  reg [W_LOG-1:0]  request_4_emp;
  reg              request_valid;

  assign queue_enq         = I_REQUEST_VALID;
  assign queue_deq         = comp_data_ready;
  assign queue_din         = I_REQUEST;

  assign ram_layer_enq     = DINEN;
  assign ram_layer_enq_idx = DIN_IDX;
  assign ram_layer_deq_idx = queue_dot;
  assign ram_layer_din     = DIN;
  
  TWO_ENTRY_FIFO #(W_LOG-1)
  request_queue(CLK, RST, queue_enq, queue_deq, queue_din, 
                queue_dot, queue_emp, queue_ful, queue_cnt);

  RAM_LAYER #(W_LOG, FIFO_SIZE, DATW)
  ram_layer(CLK, RST, ram_layer_enq, ram_layer_enq_idx, ram_layer_deq0, ram_layer_deq1, ram_layer_deq_idx, ram_layer_din, 
            ram_layer_dot0, ram_layer_dot1, ram_layer_emp0, ram_layer_emp1);
  
  SORTER_CELL #(DATW, KEYW)
  sorter_cell(ram_layer_dot0, ram_layer_dot1, comp_data_ready, 
              ram_layer_deq0, ram_layer_deq1, sorter_cell_dot, sorter_cell_doten);

  always @(posedge CLK) begin
    if      (ram_layer_emp0) request_4_emp <= ({1'b0, queue_dot} << 1);
    else if (ram_layer_emp1) request_4_emp <= ({1'b0, queue_dot} << 1) + 1 ;
  end

  always @(posedge CLK) begin
    if (RST) begin
      req_state     <= 0;
      request_valid <= 0;
    end else begin
      case (req_state)
        0: begin
          if (~|{QUEUE_IN_FULL,queue_emp}) begin
            req_state     <= 1;
            request_valid <= 1;
          end
        end
        1: begin
          req_state     <= 0;
          request_valid <= 0;
        end
      endcase
    end
  end

  always @(posedge CLK) begin
    if (RST) begin
      state           <= 0;
      comp_data_ready <= 0;
    end else begin
      case (state)
        0: begin
          if (~|{QUEUE_IN_FULL,queue_emp,ram_layer_emp0,ram_layer_emp1}) begin
            state           <= 1;
            comp_data_ready <= 1;
          end
        end
        1: begin
          state           <= 0;
          comp_data_ready <= 0;
        end
      endcase
    end
  end

  // Output
  assign QUEUE_FULL      = queue_ful;
  assign O_REQUEST       = (comp_data_ready) ? request_gen({1'b0, queue_dot}, {ram_layer_deq1,ram_layer_deq0}) : request_4_emp;
  assign O_REQUEST_VALID = request_valid;
  assign DOT             = sorter_cell_dot;
  assign DOTEN           = sorter_cell_doten;
  assign DOT_IDX         = queue_dot;
  
endmodule

`default_nettype wire
