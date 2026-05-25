// 
// twiddle_rom.v — ROM storing precomputed twiddle factors
//
// Twiddle factors: w^k mod q for k = 0..3, where w=9, q=17
//   w^0 = 1
//   w^1 = 9
//   w^2 = 13   (81 mod 17)
//   w^3 = 15   (729 mod 17)
//
// The NTT controller provides an index (0..3); this ROM returns the value.
//

module twiddle_rom #(
    parameter DATA_WIDTH = 5,
    parameter ADDR_WIDTH = 2    // 4 entries: indices 0..3
)(
    input  wire [ADDR_WIDTH-1:0] addr,
    output reg  [DATA_WIDTH-1:0] data
);

    // Synchronous-read not needed — purely combinational ROM.
    always @(*) begin
        case (addr)
            2'd0: data = 5'd1;   // w^0 = 1
            2'd1: data = 5'd9;   // w^1 = 9
            2'd2: data = 5'd13;  // w^2 = 13
            2'd3: data = 5'd15;  // w^3 = 15
            default: data = 5'd0;
        endcase
    end

endmodule
