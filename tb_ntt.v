// 
// tb_ntt.v — Testbench for 8-point NTT Accelerator
// Uses to load hex test vectors from files.
// 
`timescale 1ns/1ps

module tb_ntt;

    localparam N          = 8;
    localparam DATA_WIDTH = 5;
    localparam Q          = 17;

    reg                     clk, rst_n, start;
    reg  [DATA_WIDTH*N-1:0] coeff_in;
    wire [DATA_WIDTH*N-1:0] coeff_out;
    wire                    done;

    ntt_top #(.N(N),.DATA_WIDTH(DATA_WIDTH),.Q(Q),.LOG2N(3)) dut (
        .clk(clk),.rst_n(rst_n),.start(start),
        .coeff_in(coeff_in),.coeff_out(coeff_out),.done(done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Storage for test vectors
    reg [DATA_WIDTH-1:0] inp_mem  [0:N-1];
    reg [DATA_WIDTH-1:0] exp_mem  [0:N-1];
    reg [DATA_WIDTH-1:0] got      [0:N-1];

    integer i, pass_count, fail_count, cycle;
    reg test_ok;

    // Pack helper
    task pack_input;
        integer k;
        begin
            coeff_in = 0;
            for (k = 0; k < N; k = k + 1)
                coeff_in[k*DATA_WIDTH +: DATA_WIDTH] = inp_mem[k];
        end
    endtask

    // Unpack helper
    task unpack_output;
        integer k;
        begin
            for (k = 0; k < N; k = k + 1)
                got[k] = coeff_out[k*DATA_WIDTH +: DATA_WIDTH];
        end
    endtask

    task run_test_vec;
        input [255:0] in_file, exp_file;
        input integer test_id;
        begin
            $readmemh(in_file,  inp_mem);
            $readmemh(exp_file, exp_mem);
            pack_input;

            $write("Test %0d | in:  [", test_id);
            for (i=0;i<N;i=i+1) $write("%2d%s",inp_mem[i],(i<N-1)?",":"");
            $write("]\n");

            // Reset
            @(negedge clk); rst_n=0; start=0;
            @(negedge clk); @(negedge clk); rst_n=1;
            @(negedge clk);
            // Start
            start=1; @(negedge clk); start=0;

            // Wait for done
            cycle=0;
            while (!done && cycle < 200) begin
                @(posedge clk); #1; cycle=cycle+1;
            end

            if (!done) begin
                $display("  TIMEOUT!"); fail_count=fail_count+1;
            end else begin
                unpack_output;
                $write("        | exp: [");
                for (i=0;i<N;i=i+1) $write("%2d%s",exp_mem[i],(i<N-1)?",":"");
                $write("]\n");
                $write("        | got: [");
                for (i=0;i<N;i=i+1) $write("%2d%s",got[i],(i<N-1)?",":"");
                $write("]");

                test_ok=1;
                for (i=0;i<N;i=i+1)
                    if (got[i] !== exp_mem[i]) test_ok=0;

                if (test_ok) begin
                    $write("  PASS\n"); pass_count=pass_count+1;
                end else begin
                    $write("  FAIL\n"); fail_count=fail_count+1;
                    for (i=0;i<N;i=i+1)
                        if (got[i] !== exp_mem[i])
                            $display("  Mismatch[%0d]: exp=%0d got=%0d",i,exp_mem[i],got[i]);
                end
            end
            $write("\n");
        end
    endtask

    initial begin
        $display("=================================================");
        $display("  8-point NTT Accelerator — Simulation Results");
        $display("  n=8  q=17  omega=9");
        $display("=================================================\n");
        rst_n=0; start=0; coeff_in=0; pass_count=0; fail_count=0;
        repeat(4) @(negedge clk); rst_n=1;

        run_test_vec("input_0.hex","expected_0.hex",0);
        run_test_vec("input_1.hex","expected_1.hex",1);
        run_test_vec("input_2.hex","expected_2.hex",2);
        run_test_vec("input_3.hex","expected_3.hex",3);

        $display("=================================================");
        $display("  %0d PASSED  |  %0d FAILED  (of 4 tests)", pass_count, fail_count);
        $display("=================================================");
        if (fail_count==0) $display("  ALL TESTS PASSED");
        $finish;
    end

    initial begin
        $dumpfile("ntt_sim.vcd");
        $dumpvars(0, tb_ntt);
    end
endmodule
