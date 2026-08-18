// =============================================================================
// Module: bf16_decoder
// Description: Decodes a 16-bit bfloat16 number into its components:
//              sign (1 bit), exponent (8 bits), mantissa (7 bits).
//              Also detects special values: zero, infinity, NaN.
//
// bfloat16 format:
//   [15]     = sign bit
//   [14:7]   = exponent (8 bits, biased by 127)
//   [6:0]    = mantissa (7 bits, implicit leading 1 for normal numbers)
// =============================================================================

module bf16_decoder (
    input  [15:0] bf16_in,       // Raw 16-bit bfloat16 input

    output        sign,           // Sign bit: 0 = positive, 1 = negative
    output [7:0]  exponent,       // Raw biased exponent (0-255)
    output [7:0]  mantissa,       // 8-bit mantissa: {1, frac[6:0]} for normal numbers
                                  //                 {0, frac[6:0]} for subnormals/zero

    output        is_zero,        // High if value is +0 or -0
    output        is_inf,         // High if value is +Inf or -Inf
    output        is_nan          // High if value is NaN (quiet or signaling)
);

    // -------------------------------------------------------------------------
    // Extract raw fields directly from the 16-bit input
    // -------------------------------------------------------------------------
    assign sign     = bf16_in[15];
    assign exponent = bf16_in[14:7];

    // -------------------------------------------------------------------------
    // Build the full mantissa:
    //   - For normal numbers (exponent != 0), add the implicit leading 1
    //   - For subnormal numbers (exponent == 0), leading bit is 0
    // -------------------------------------------------------------------------
    wire [6:0] frac = bf16_in[6:0];  // fractional part of mantissa

    assign mantissa = (exponent != 8'b0) ? {1'b1, frac} : {1'b0, frac};

    // -------------------------------------------------------------------------
    // Detect special values
    // -------------------------------------------------------------------------
    assign is_zero = (exponent == 8'b0) && (frac == 7'b0);
    assign is_inf  = (exponent == 8'hFF) && (frac == 7'b0);
    assign is_nan  = (exponent == 8'hFF) && (frac != 7'b0);

endmodule
