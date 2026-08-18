// =============================================================================
// Module: bf16_align
// Description: Aligns the mantissas of two bfloat16 numbers before addition
//              or subtraction by right-shifting the smaller exponent's mantissa.
//
//              The number with the smaller exponent gets its mantissa shifted
//              right by the difference in exponents. This makes both numbers
//              have the same effective exponent before adding/subtracting.
// =============================================================================

module bf16_align (
    input  [7:0]  exp_a,          // Exponent of operand A
    input  [7:0]  exp_b,          // Exponent of operand B
    input  [7:0]  mant_a,         // Mantissa of A (8 bits, with implicit 1)
    input  [7:0]  mant_b,         // Mantissa of B (8 bits, with implicit 1)

    output [7:0]  aligned_exp,    // The larger of the two exponents
    output [15:0] aligned_mant_a, // Mantissa A shifted to match aligned_exp
    output [15:0] aligned_mant_b  // Mantissa B shifted to match aligned_exp
);

    // -------------------------------------------------------------------------
    // Step 1: Find the larger exponent and the shift amount
    // -------------------------------------------------------------------------
    wire        a_larger;
    wire [7:0]  shift_amt;

    assign a_larger   = (exp_a >= exp_b);
    assign aligned_exp = a_larger ? exp_a : exp_b;

    // shift_amt = |exp_a - exp_b|
    assign shift_amt  = a_larger ? (exp_a - exp_b) : (exp_b - exp_a);

    // -------------------------------------------------------------------------
    // Step 2: Extend mantissas to 16 bits for safe shifting
    //         Extra bits on the right are guard/sticky bits for rounding later
    // -------------------------------------------------------------------------
    wire [15:0] ext_mant_a = {mant_a, 8'b0};  // Extend A to 16 bits
    wire [15:0] ext_mant_b = {mant_b, 8'b0};  // Extend B to 16 bits

    // -------------------------------------------------------------------------
    // Step 3: Right-shift the mantissa of the SMALLER number
    //         The larger number keeps its mantissa unchanged.
    //         We limit shift to 15 to avoid shifting out all bits.
    // -------------------------------------------------------------------------
    wire [3:0] safe_shift = (shift_amt > 15) ? 4'd15 : shift_amt[3:0];

    assign aligned_mant_a = a_larger ? ext_mant_a : (ext_mant_a >> safe_shift);
    assign aligned_mant_b = a_larger ? (ext_mant_b >> safe_shift) : ext_mant_b;

endmodule
