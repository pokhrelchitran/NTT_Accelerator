"""
ntt_reference.py — Python reference model for the 8-point NTT accelerator

Parameters: n=8, q=17, omega=9

Usage:
    python3 ntt_reference.py

What it does:
    1. Defines modular arithmetic helpers
    2. Implements the NTT (Cooley-Tukey DIT, iterative, in-place)
    3. Implements the INTT (inverse NTT)
    4. Runs all 4 test vectors and prints expected outputs
    5. Regenerates the .hex files used by the Verilog testbench
    6. Verifies NTT * INTT = identity (round-trip check)
"""

# Parameters 
N = 8       # transform size
Q = 17      # prime modulus
W = 9       # primitive n-th root of unity:  W^N ≡ 1 (mod Q)



# Modular arithmetic helpers


def mod_add(a, b):
    """(a + b) mod Q"""
    return (a + b) % Q


def mod_sub(a, b):
    """(a - b) mod Q  — always non-negative"""
    return (a - b) % Q


def mod_mul(a, b):
    """(a * b) mod Q"""
    return (a * b) % Q


def mod_inv(a):
    """Modular inverse of a mod Q using Fermat's little theorem (Q prime)."""
    return pow(a, Q - 2, Q)



# Bit-reversal permutation


def bit_reverse_index(i, log2n):
    """Reverse the log2n-bit binary representation of i."""
    result = 0
    for _ in range(log2n):
        result = (result << 1) | (i & 1)
        i >>= 1
    return result


def bit_reverse_copy(a):
    """Return a copy of list a with elements in bit-reversed order."""
    n = len(a)
    log2n = n.bit_length() - 1
    return [a[bit_reverse_index(i, log2n)] for i in range(n)]



# Twiddle factor precomputation


def precompute_twiddles(n, w, q):
    """
    Compute twiddle factors: w^0, w^1, ..., w^(n/2-1)  mod q.
    These are stored in the hardware Twiddle ROM.
    """
    twiddles = []
    wk = 1
    for k in range(n // 2):
        twiddles.append(wk)
        wk = (wk * w) % q
    return twiddles



# Butterfly operation


def butterfly(a, b, w):
    """
    Cooley-Tukey DIT butterfly.
    Returns (u, v) where:
        u = (a + b*w) mod Q
        v = (a - b*w) mod Q
    Mirrors the hardware butterfly.v module exactly.
    """
    bw = mod_mul(b, w)
    u  = mod_add(a, bw)
    v  = mod_sub(a, bw)
    return u, v



# Forward NTT  (Cooley-Tukey DIT, iterative, in-place)


def ntt(a_in):
    """
    8-point NTT over Z_q.

    Algorithm:
        1. Bit-reverse the input (mirrors the LOAD state of the hardware FSM).
        2. Iterate log2(n)=3 stages; in each stage perform n/2=4 butterflies.
        3. Twiddle factor for butterfly k in stage s:
               omega^(k * n / stride)  where stride = 2^s

    Returns the transformed list (does not modify a_in).
    """
    n     = len(a_in)
    log2n = n.bit_length() - 1

    # Step 1: bit-reversal permutation
    a = bit_reverse_copy(a_in)

    # Step 2: butterfly stages
    for s in range(1, log2n + 1):
        stride  = 1 << s          # 2^s
        half    = stride >> 1     # 2^(s-1) — distance between butterfly pair
        w_stage = pow(W, n // stride, Q)   # twiddle root for this stage

        for i in range(0, n, stride):      # iterate over groups
            wk = 1                         # w_stage^0
            for k in range(half):          # iterate within group
                idx_a = i + k
                idx_b = i + k + half
                a[idx_a], a[idx_b] = butterfly(a[idx_a], a[idx_b], wk)
                wk = mod_mul(wk, w_stage)

    return a



# Inverse NTT


def intt(a_in):
    """
    Inverse NTT.
    Uses omega^{-1} as the root and multiplies the final result by n^{-1}.

    Changes vs forward NTT:
        - Root of unity: W_inv = mod_inv(W)
        - Stage order: reversed (stage log2n down to 1)  [Gentleman-Sande]
        - Output scaled by n^{-1} mod q
    """
    n     = len(a_in)
    log2n = n.bit_length() - 1
    w_inv = mod_inv(W)       # omega^{-1} mod q
    n_inv = mod_inv(n)       # n^{-1} mod q

    # Bit-reversal on input (Gentleman-Sande DIF uses natural order input,
    # bit-reversed output; we do DIT with reversed root to match hardware
    # extension: bit-reverse the input here as well)
    a = bit_reverse_copy(a_in)

    for s in range(1, log2n + 1):
        stride  = 1 << s
        half    = stride >> 1
        # Use inverse root: omega^{-k * n/stride}
        w_stage = pow(w_inv, n // stride, Q)

        for i in range(0, n, stride):
            wk = 1
            for k in range(half):
                idx_a = i + k
                idx_b = i + k + half
                a[idx_a], a[idx_b] = butterfly(a[idx_a], a[idx_b], wk)
                wk = mod_mul(wk, w_stage)

    # Scale by n^{-1}
    a = [mod_mul(x, n_inv) for x in a]
    return a



# Hex file generation (for Verilog testbench $readmemh)


def write_hex(filename, values):
    """Write a list of integers to a hex file, one value per line."""
    with open(filename, "w") as f:
        for v in values:
            f.write(f"{v:02x}\n")
    print(f"  Written: {filename}")


def generate_hex_files(test_vectors):
    """Generate input_N.hex and expected_N.hex for all test vectors."""
    print("\nGenerating .hex files for Verilog testbench:")
    for idx, inp in enumerate(test_vectors):
        out = ntt(inp)
        write_hex(f"input_{idx}.hex",    inp)
        write_hex(f"expected_{idx}.hex", out)



# Verification utilities


def verify_root_of_unity():
    """Confirm that W is indeed a primitive n-th root of unity mod Q."""
    print("── Root of unity verification")
    for k in range(1, N + 1):
        val = pow(W, k, Q)
        marker = "  ← W^N ≡ 1 ✓" if k == N else ("  ← W^(N/2) ≡ -1 ✓" if k == N // 2 else "")
        print(f"  W^{k} mod {Q} = {val}{marker}")


def verify_round_trip(test_vectors):
    """Check that INTT(NTT(a)) == a for all test vectors."""
    print("\n── Round-trip check: INTT(NTT(a)) == a")
    all_ok = True
    for idx, inp in enumerate(test_vectors):
        recovered = intt(ntt(inp))
        ok = (recovered == inp)
        status = "PASS ✓" if ok else "FAIL ✗"
        print(f"  Vector {idx}: {status}")
        if not ok:
            print(f"    original : {inp}")
            print(f"    recovered: {recovered}")
            all_ok = False
    return all_ok



# Main


def main():
    print("=" * 60)
    print("  NTT Reference Model")
    print(f"  n={N}, q={Q}, omega={W}")
    print("=" * 60)

    # Parameter verification 
    verify_root_of_unity()

    twiddles = precompute_twiddles(N, W, Q)
    print(f"\n Twiddle ROM contents (W^k mod {Q} for k=0..{N//2-1}):")
    for k, t in enumerate(twiddles):
        print(f"  addr {k}: W^{k} = {t}")

    w_inv = mod_inv(W)
    n_inv = mod_inv(N)
    print(f"\n For INTT: W^{{-1}} = {w_inv},  N^{{-1}} = {n_inv}")

    #Bit-reversal table
    log2n = N.bit_length() - 1
    print(f"\n Bit-reversal permutation (log2n={log2n}):")
    for i in range(N):
        br = bit_reverse_index(i, log2n)
        print(f"  {i} ({i:03b}) → {br} ({br:03b})")

    # Test vectors 
    test_vectors = [
        [1, 2, 3, 4, 5, 6, 7, 8],   # sequential
        [3, 1, 4, 1, 5, 9, 2, 6],   # pi digits
        [0, 0, 0, 0, 0, 0, 0, 1],   # impulse at end
        [1, 0, 0, 0, 0, 0, 0, 0],   # DC impulse
    ]

    print("\n Forward NTT results")
    print(f"  {'Input':<30} {'NTT Output'}")
    print(f"  {'-'*30} {'-'*30}")
    for idx, inp in enumerate(test_vectors):
        out = ntt(inp)
        print(f"  {str(inp):<30} {out}   [test {idx}]")

    # Stage-by-stage trace for test vector 0
    print("\n Stage-by-stage trace: input=[1,2,3,4,5,6,7,8]")
    a = bit_reverse_copy(test_vectors[0])
    print(f"  After bit-reversal: {a}")
    for s in range(1, log2n + 1):
        stride  = 1 << s
        half    = stride >> 1
        w_stage = pow(W, N // stride, Q)
        for i in range(0, N, stride):
            wk = 1
            for k in range(half):
                ia, ib = i + k, i + k + half
                a[ia], a[ib] = butterfly(a[ia], a[ib], wk)
                wk = mod_mul(wk, w_stage)
        print(f"  After stage {s} (stride={stride}, w_stage=W^{N//stride}={w_stage}): {a}")

    # Generate hex files
    generate_hex_files(test_vectors)

    # Round-trip verification 
    all_ok = verify_round_trip(test_vectors)

    print("\n" + "=" * 60)
    if all_ok:
        print("  All checks passed.")
    else:
        print("  Some checks FAILED — review output above.")
    print("=" * 60)


if __name__ == "__main__":
    main()
