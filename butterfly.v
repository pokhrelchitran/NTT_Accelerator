// 
// butterfly.v — Single Butterfly Unit for 8-point NTT
//
// Computes the Cooley-Tukey DIT butterfly:
//   u = (a + b*w) mod q
//   v = (a - b*w) mod q
//
// Parameters: q=17, so all values fit in 5 bits; products fit in 9 bits.
// 

module butterfly #(
    parameter DATA_WIDTH = 5,   // ceil(log2(q))  — values 0..16
    parameter Q          = 17
)(
    input  wire [DATA_WIDTH-1:0] a,
    input  wire [DATA_WIDTH-1:0] b,
    input  wire [DATA_WIDTH-1:0] w,   // twiddle factor
    output wire [DATA_WIDTH-1:0] u,   // a + b*w  mod q
    output wire [DATA_WIDTH-1:0] v    // a - b*w  mod q
);

    // 
    // Step 1: Modular multiplication  bw = b*w mod q
    // For small q (17) the product b*w <= 16*16 = 256, fits in 9 bits.
    // We reduce with a simple subtraction loop -- acceptable for q=17.
    // For large primes, replace with Barrett or Montgomery reduction.
    // 
    wire [8:0] prod = b * w;

    // Reduce: prod mod 17.  Max value 256, so at most 15 subtractions of 17.
    // We use a combinational divide-by-constant approach: prod - (prod/q)*q
    // Since q=17 is constant, synthesis will optimise this into a small LUT.
    wire [8:0] bw = prod - (prod / Q) * Q;

    // 
    // Step 2: Modular addition   u = (a + bw) mod q
    // 
    wire [5:0] sum = a + bw[4:0];
    assign u = (sum >= Q) ? (sum - Q) : sum[DATA_WIDTH-1:0];

    // 
    // Step 3: Modular subtraction  v = (a - bw) mod q
    // Add q before subtracting to keep result non-negative.
    // 
    wire [5:0] diff = a + Q - bw[4:0];
    assign v = (diff >= Q) ? (diff - Q) : diff[DATA_WIDTH-1:0];

endmodule
