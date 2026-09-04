module conformance_tb #(
  parameter CODE_FILE="conformance/core.hex",
  parameter integer EXPECTED=37,
  parameter integer EXPECTED_STATUS=0,
  parameter integer EXPECTED_STEPS=6
);
  logic clock=0, reset=1, halted;
  logic [7:0] status; logic [31:0] result; logic [63:0] steps;
  shen_joy_core #(.CODE_FILE(CODE_FILE)) dut(.clock(clock),.reset(reset),.halted(halted),.status(status),.result(result),.steps(steps));
  always #5 clock=~clock;
  initial begin
    #12 reset=0;
    repeat(100) begin
      @(posedge clock);
      if(halted) begin
        $display("RESULT=%0d STATUS=%0d STEPS=%0d",$signed(result)>>>2,status,steps);
        if(status==EXPECTED_STATUS && ($signed(result)>>>2)==EXPECTED && steps==EXPECTED_STEPS) $finish(0); else $fatal(1,"conformance mismatch");
      end
    end
    $fatal(1,"timeout");
  end
endmodule
