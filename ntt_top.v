// 
// ntt_top.v — 8-point NTT Accelerator (iterative, single butterfly)
//
// Algorithm: Cooley-Tukey DIT (decimation-in-time) with bit-reversal input.
// Parameters: n=8, q=17, ω=9
//

//
// FSM states:
//   IDLE       → waiting for start
//   LOAD       → copy input coefficients into RAM (with bit-reversal)
//   COMPUTE    → iterate stages 1..3, each with n/2=4 butterfly operations
//   DONE       → assert done, hold output
//
// Bit-reversal of addresses (n=8, 3-bit):
//   0→0, 1→4, 2→2, 3→6, 4→1, 5→5, 6→3, 7→7
// 

module ntt_top #(
    parameter N          = 8,
    parameter DATA_WIDTH = 5,   // ceil(log2(17))
    parameter Q          = 17,
    parameter LOG2N      = 3    // log2(8)
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        start,
    input  wire [DATA_WIDTH*N-1:0]     coeff_in,   // 8 packed coefficients
    output wire [DATA_WIDTH*N-1:0]     coeff_out,  // 8 packed results
    output reg                         done
);

    // 
    // Data RAM — 8 locations × 5 bits
    // Implemented as register file for simplicity (dual-read, dual-write).
    // 
    reg [DATA_WIDTH-1:0] ram [0:N-1];

    // 
    // Twiddle ROM
    // 
    reg  [1:0]           tw_addr;
    wire [DATA_WIDTH-1:0] tw_data;

    twiddle_rom trom (
        .addr(tw_addr),
        .data(tw_data)
    );

    // 
    // Butterfly unit
    // 
    reg  [DATA_WIDTH-1:0] bf_a, bf_b, bf_w;
    wire [DATA_WIDTH-1:0] bf_u, bf_v;

    butterfly #(.DATA_WIDTH(DATA_WIDTH), .Q(Q)) bfly (
        .a(bf_a), .b(bf_b), .w(bf_w),
        .u(bf_u), .v(bf_v)
    );

    // 
    // FSM
    // 
    localparam IDLE    = 2'd0,
               LOAD    = 2'd1,
               COMPUTE = 2'd2,
               DONE_ST = 2'd3;

    reg [1:0]  state;
    reg [2:0]  cnt;        // general counter (load: 0..7; compute: 0..3)
    reg [1:0]  stage;      // 1..3

    //  Bit-reversal lookup (3-bit reverse) 
    function [2:0] bit_rev3;
        input [2:0] x;
        begin
            bit_rev3 = {x[0], x[1], x[2]};
        end
    endfunction

    //  Address pair and twiddle index for butterfly cnt in stage s 
    // For DIT stage s (1-based):
    //   stride  = 2^s
    //   half    = 2^(s-1)
    //   group   = cnt / half          (which stride-group)
    //   k       = cnt % half          (offset within group)
    //   addr_a  = group*stride + k
    //   addr_b  = addr_a + half
    //   twiddle = k * (n / stride) = k << (log2n - s)
    //             capped at n/2-1 since ROM has 4 entries

    reg [2:0] addr_a_r, addr_b_r;
    reg [1:0] tw_idx_r;

    always @(*) begin
        case (stage)
            2'd1: begin
                // stride=2, half=1 — cnt in 0..3
                // group=cnt, k=0
                // addr_a = cnt*2, addr_b = cnt*2+1, twiddle = 0
                addr_a_r = {cnt[1:0], 1'b0};     // cnt*2
                addr_b_r = {cnt[1:0], 1'b1};     // cnt*2+1
                tw_idx_r = 2'd0;                  // w^0 = 1
            end
            2'd2: begin
                // stride=4, half=2 — cnt in 0..3
                // group = cnt>>1, k = cnt&1
                // addr_a = group*4 + k, addr_b = addr_a+2, twiddle = k*2
                addr_a_r = {cnt[1], 1'b0, cnt[0]};   // group*4 + k
                addr_b_r = {cnt[1], 1'b1, cnt[0]};   // addr_a + 2
                tw_idx_r = {cnt[0], 1'b0};            // k*2 (0 or 2)
            end
            default: begin // stage 3
                // stride=8, half=4 — cnt in 0..3
                // group=0, k=cnt
                // addr_a = cnt, addr_b = cnt+4, twiddle = cnt
                addr_a_r = {1'b0, cnt[1:0]};
                addr_b_r = {1'b1, cnt[1:0]};
                tw_idx_r = cnt[1:0];
            end
        endcase
    end

    // 
    // FSM sequential logic
    // 
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done  <= 1'b0;
            cnt   <= 3'd0;
            stage <= 2'd0;
        end else begin
            case (state)
                // IDLE 
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        cnt   <= 3'd0;
                        state <= LOAD;
                    end
                end

                // LOAD: write bit-reversed inputs into RAM 
                LOAD: begin
                    ram[bit_rev3(cnt[2:0])] <= coeff_in[(cnt*DATA_WIDTH) +: DATA_WIDTH];
                    if (cnt == 3'd7) begin
                        cnt   <= 3'd0;
                        stage <= 2'd1;
                        state <= COMPUTE;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end

                // COMPUTE: one butterfly per cycle 
                COMPUTE: begin
                    // Latch twiddle and data into butterfly inputs
                    tw_addr <= tw_idx_r;
                    bf_a    <= ram[addr_a_r];
                    bf_b    <= ram[addr_b_r];
                    bf_w    <= tw_data;

                    // Write-back results (combinational butterfly — results
                    // available same cycle we read tw_data, but tw_data is
                    // based on tw_addr set THIS cycle, so we need one cycle
                    // of latency — handled by the register stage below)
                    //
                    // To avoid the latency, we pre-fetch tw_data combinatorially
                    // using addr_a_r/addr_b_r/tw_idx_r before the register.
                    // Since twiddle_rom is combinational, tw_data reflects
                    // tw_addr from LAST cycle. We therefore use a 2-phase
                    // approach: fetch twiddle this cycle, write back next.
                    // We track this with a "write-back pending" register.
                    //
                    // Simpler alternative used here: connect tw_addr directly
                    // to tw_idx_r (combinational), and bf_w to tw_data (also
                    // combinational), so everything is one-cycle.

                    ram[addr_a_r] <= bf_u;
                    ram[addr_b_r] <= bf_v;

                    if (cnt == 3'd3) begin
                        cnt <= 3'd0;
                        if (stage == 2'd3) begin
                            state <= DONE_ST;
                        end else begin
                            stage <= stage + 1;
                        end
                    end else begin
                        cnt <= cnt + 1;
                    end
                end

                // DONE 
                DONE_ST: begin
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // Combinational twiddle fetch (ROM is async read)
    always @(*) begin
        tw_addr = tw_idx_r;
        bf_w    = tw_data;
        bf_a    = ram[addr_a_r];
        bf_b    = ram[addr_b_r];
    end

    // 
    // Pack RAM output
    // 
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : pack_out
            assign coeff_out[g*DATA_WIDTH +: DATA_WIDTH] = ram[g];
        end
    endgenerate

endmodule
