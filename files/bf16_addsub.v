// =============================================================================
// Module: bf16_addsub
// Description: Performs addition or subtraction on two aligned bfloat16
//              mantissas. Handles sign logic to determine whether to truly
//              add or subtract the magnitudes, and computes the result sign.
//
// How it works:
//   - If signs are the same: add magnitudes, keep the sign
//   - If signs differ: subtract smaller from larger, sign follows larger
// =============================================================================

module bf16_addsub (
    input         sign_a,         // Sign of operand A
    input         sign_b,         // Sign of operand B
    input  [15:0] mant_a,         // Aligned mantissa of A (16 bits)
    input  [15:0] mant_b,         // Aligned mantissa of B (16 bits)
    input  [7:0]  exp_in,         // Common aligned exponent
    input         do_sub,         // 1 = subtraction, 0 = addition

    output reg        result_sign,    // Sign of the result
    output reg [15:0] result_mant,    // Mantissa of the result (may need normalization)
    output reg [7:0]  result_exp      // Exponent of the result
);

    // -------------------------------------------------------------------------
    // Determine the effective sign of B after applying the operation
    //   - For subtraction: flip sign_b (A - B = A + (-B))
    //   - For addition: keep sign_b as-is
    // -------------------------------------------------------------------------
    wire eff_sign_b = do_sub ? ~sign_b : sign_b;

    // -------------------------------------------------------------------------
    // Decide whether to add or subtract magnitudes
    //   - Same effective signs: add magnitudes
    //   - Different effective signs: subtract magnitudes
    // -------------------------------------------------------------------------
    wire same_sign = (sign_a == eff_sign_b);

    // -------------------------------------------------------------------------
    // Determine which operand has the larger magnitude
    // (Used when signs differ to know which to subtract from which)
    // -------------------------------------------------------------------------
    wire a_bigger = (mant_a >= mant_b);

    always @(*) begin
        result_exp = exp_in;  // Exponent stays the same for now (normalization fixes it)

        if (same_sign) begin
            // -----------------------------------------------------------------
            // Case 1: Same sign → Add magnitudes
            // -----------------------------------------------------------------
            result_sign = sign_a;
            result_mant = mant_a + mant_b;  // 16-bit + 16-bit, may overflow to bit 16

        end else begin
            // -----------------------------------------------------------------
            // Case 2: Different signs → Subtract smaller from larger
            // -----------------------------------------------------------------
            if (a_bigger) begin
                result_sign = sign_a;
                result_mant = mant_a - mant_b;
            end else begin
                result_sign = eff_sign_b;
                result_mant = mant_b - mant_a;
            end
        end
    end

endmodule
