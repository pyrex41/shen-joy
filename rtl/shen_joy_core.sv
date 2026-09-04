module shen_joy_core #(
  parameter CODE_WORDS = 256,
  parameter DATA_WORDS = 64,
  parameter CODE_FILE = "conformance/core.hex"
) (
  input  logic        clock,
  input  logic        reset,
  output logic        halted,
  output logic [7:0]  status,
  output logic [31:0] result,
  output logic [63:0] steps
);
  logic [31:0] code [0:CODE_WORDS-1];
  logic [31:0] stack [0:DATA_WORDS-1];
  logic [31:0] instruction;
  logic [31:0] pc;
  logic [$clog2(DATA_WORDS+1)-1:0] sp;
  logic signed [31:0] a, b;
  logic signed [63:0] arithmetic;
  integer i;

  initial begin
    for (i=0; i<CODE_WORDS; i=i+1) code[i]=0;
    $readmemh(CODE_FILE, code);
  end

  always @* begin
    instruction = code[pc];
    a = sp >= 2 ? $signed(stack[sp-2]) >>> 2 : 0;
    b = sp >= 1 ? $signed(stack[sp-1]) >>> 2 : 0;
    case (instruction[31:24])
      8'd5: arithmetic = a+b;
      8'd6: arithmetic = a-b;
      default: arithmetic = a*b;
    endcase
  end

  always_ff @(posedge clock) begin
    if (reset) begin pc<=0; sp<=0; halted<=0; status<=0; result<=0; steps<=0; end
    else if (!halted) begin
      steps <= steps+1;
      case (instruction[31:24])
        8'd0: begin halted<=1; result<=sp?stack[sp-1]:0; end
        8'd1: begin
          if (sp==DATA_WORDS) begin halted<=1;status<=2;end
          else begin stack[sp]<={{6{instruction[23]}},instruction[23:0],2'b01};sp<=sp+1;pc<=pc+1;end
        end
        8'd2: begin
          if (sp==0) begin halted<=1;status<=1;end
          else if (sp==DATA_WORDS) begin halted<=1;status<=2;end
          else begin stack[sp]<=stack[sp-1];sp<=sp+1;pc<=pc+1;end
        end
        8'd3: if(sp==0)begin halted<=1;status<=1;end else begin sp<=sp-1;pc<=pc+1;end
        8'd4: if(sp<2)begin halted<=1;status<=1;end else begin stack[sp-1]<=stack[sp-2];stack[sp-2]<=stack[sp-1];pc<=pc+1;end
        8'd5,8'd6,8'd7: begin
          if(sp<2)begin halted<=1;status<=1;end
          else if(arithmetic < -536870912 || arithmetic > 536870911)begin halted<=1;status<=5;end
          else begin stack[sp-2]<={arithmetic[29:0],2'b01};sp<=sp-1;pc<=pc+1;end
        end
        8'd8: if(sp<2)begin halted<=1;status<=1;end else begin stack[sp-2]<=stack[sp-2]==stack[sp-1]?32'd6:32'd2;sp<=sp-1;pc<=pc+1;end
        8'd9: if(sp<2)begin halted<=1;status<=1;end else begin stack[sp-2]<=a<b?32'd6:32'd2;sp<=sp-1;pc<=pc+1;end
        8'd10: pc<=pc+1+{{8{instruction[23]}},instruction[23:0]};
        8'd11: if(sp==0)begin halted<=1;status<=1;end else if(stack[sp-1]==2)begin sp<=sp-1;pc<=pc+1+{{8{instruction[23]}},instruction[23:0]};end else if(stack[sp-1]==6)begin sp<=sp-1;pc<=pc+1;end else begin halted<=1;status<=4;end
        8'd20: if(sp==DATA_WORDS)begin halted<=1;status<=2;end else begin stack[sp]<=6;sp<=sp+1;pc<=pc+1;end
        8'd21: if(sp==DATA_WORDS)begin halted<=1;status<=2;end else begin stack[sp]<=2;sp<=sp+1;pc<=pc+1;end
        default: begin halted<=1;status<=9;end
      endcase
    end
  end
endmodule
