// =============================================================================
// Module: bf16_round
// Description: Applies round-to-nearest-even (IEEE default) to the normalized
//              mantissa. The normalized mantissa is 8 bits; the lowest bit
//              of the 7-bit stored fraction is rounded based on guard bits.
//
// bfloat16 stores only 7 fractional bits, so the 8th bit (bit 0 of norm_mant)
// is the "round bit". We round up if round_bit=1 and the result is odd,
// or if there are sticky bits set (lower bits that were shifted out).
//
// For simplicity, we implement round-to-nearest (ties round up).
// =============================================================================

module bf16_round (
    input  [7:0]  norm_mant,      // Normalized 8-bit mantissa from normalizer
    input  [7:0]  norm_exp,       // Normalized exponent
    input         guard_bit,      // Guard bit: first bit shifted out during normalization
    input         sticky_bit,     // Sticky bit: OR of all bits below guard bit

    output [7:0]  rounded_mant,   // Rounded mantissa (7-bit fraction will be taken)
    output [7:0]  rounded_exp     // Rounded exponent (may increment if carry)
);

    // -------------------------------------------------------------------------
    // Round-to-nearest: round up if guard bit is 1 AND
    //   (sticky bit is 1 OR the LSB of the mantissa is 1 — round half to even)
    // -------------------------------------------------------------------------
    wire round_up = guard_bit & (sticky_bit | norm_mant[0]);

    // -------------------------------------------------------------------------
    // Add the rounding increment to the mantissa
    // -------------------------------------------------------------------------
    wire [8:0] mant_rounded = {1'b0, norm_mant} + {8'b0, round_up};

    // -------------------------------------------------------------------------
    // If rounding caused a carry (mantissa overflowed to 9 bits),
    // shift right and increment the exponent.
    // -------------------------------------------------------------------------
    assign rounded_mant = mant_rounded[8] ? mant_rounded[8:1] : mant_rounded[7:0];
    assign rounded_exp  = (mant_rounded[8] && norm_exp != 8'hFF) ?
                          (norm_exp + 8'd1) : norm_exp;

endmodule


// =============================================================================
// Module: bf16_encoder
// Description: Encodes the final sign, exponent, and mantissa back into
//              the 16-bit bfloat16 format.
//
// bfloat16 format: [15]=sign, [14:7]=exponent, [6:0]=mantissa fraction
// The mantissa fraction is the lower 7 bits of the 8-bit mantissa
// (the leading 1 is implicit and NOT stored).
// =============================================================================

module bf16_encoder (
    input         sign,
    input  [7:0]  exponent,       // 8-bit biased exponent
    input  [7:0]  mantissa,       // 8-bit mantissa (bit 7 = implicit leading 1)

    input         force_zero,     // Override: output +0
    input         force_inf,      // Override: output signed infinity
    input         force_nan,      // Override: output canonical NaN

    output [15:0] bf16_out        // Encoded bfloat16 result
);

    wire [15:0] normal_encode = {sign, exponent, mantissa[6:0]};
    wire [15:0] zero_encode   = {sign, 15'b0};
    wire [15:0] inf_encode    = {sign, 8'hFF, 7'b0};
    wire [15:0] nan_encode    = 16'h7FC0;  // Canonical quiet NaN

    assign bf16_out = force_nan  ? nan_encode  :
                      force_inf  ? inf_encode  :
                      force_zero ? zero_encode :
                                   normal_encode;

endmodule
