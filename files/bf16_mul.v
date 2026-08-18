// =============================================================================
// Module: bf16_mul
// Description: Multiplies two bfloat16 numbers.
//
// How bfloat16 multiplication works:
//   1. Result sign = sign_a XOR sign_b
//   2. Result exponent = exp_a + exp_b - 127 (remove one bias)
//      (Both exponents are biased by 127, so their sum is biased by 254;
//       we subtract 127 to get back to a single-biased exponent.)
//   3. Result mantissa = mant_a * mant_b
//      (Both mantissas have an implicit leading 1, so the product is
//       a 16-bit x 16-bit = 32-bit number with the leading bit at position 14.)
//
// The raw product mantissa is 16 bits wide (8 x 8 = 16 bits).
// Normalization will handle any needed shift.
// =============================================================================

module bf16_mul (
    input         sign_a,
    input         sign_b,
    input  [7:0]  exp_a,
    input  [7:0]  exp_b,
    input  [7:0]  mant_a,         // 8-bit mantissa with implicit leading 1
    input  [7:0]  mant_b,

    output        result_sign,
    output [9:0]  result_exp_raw, // 10-bit to handle overflow detection
    output [15:0] result_mant     // Full 16-bit product
);

    // -------------------------------------------------------------------------
    // Step 1: Result sign is XOR of input signs
    // -------------------------------------------------------------------------
    assign result_sign = sign_a ^ sign_b;

    // -------------------------------------------------------------------------
    // Step 2: Add exponents and subtract the bias (127)
    //   We use 10 bits to detect overflow/underflow in exponent
    // -------------------------------------------------------------------------
    // exp_a and exp_b are biased: actual_exp = stored_exp - 127
    // actual_result_exp = (exp_a - 127) + (exp_b - 127) = exp_a + exp_b - 254
    // stored_result_exp = actual_result_exp + 127 = exp_a + exp_b - 127
    assign result_exp_raw = {2'b0, exp_a} + {2'b0, exp_b} - 10'd127;

    // -------------------------------------------------------------------------
    // Step 3: Multiply the mantissas
    //   Both are 8-bit values (with implicit leading 1), product is 16 bits.
    //   The product's MSB will be at bit 14 (if both leading bits are 1).
    // -------------------------------------------------------------------------
    assign result_mant = mant_a * mant_b;

endmodule
