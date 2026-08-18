// =============================================================================
// Module: bf16_normalize
// Description: Normalizes the result of addition/subtraction or multiplication.
//
// Normalization means adjusting the mantissa and exponent so that the
// result is in bfloat16 normal form:
//   - The mantissa should have the form 1.xxxxxxx (leading 1 just left of point)
//   - This means the mantissa (as an integer) should satisfy:
//       128 <= mantissa < 256  (for 8-bit representation)
//
// Two cases need handling:
//   1. Overflow (mantissa >= 256 after add): shift right, increment exponent
//   2. Leading zeros (mantissa < 128 after sub): shift left, decrement exponent
//
// Input mantissa is 16 bits wide (from alignment/product), with the
// significant bits somewhere in the upper half.
// =============================================================================

module bf16_normalize (
    input  [15:0] mant_in,        // Raw mantissa (16-bit, possibly unnormalized)
    input  [9:0]  exp_in,         // Exponent in (10-bit to handle overflow)
    input         is_mul,         // 1 if this came from multiplication

    output reg [7:0]  norm_mant,  // Normalized 8-bit mantissa (with leading 1)
    output reg [7:0]  norm_exp,   // Normalized exponent
    output reg        overflow,   // Exponent overflowed (result is Infinity)
    output reg        underflow   // Exponent underflowed (result is zero/subnormal)
);

    integer i;
    reg [15:0] shifted_mant;
    reg [9:0]  adjusted_exp;
    reg [4:0]  shift_count;

    always @(*) begin
        // Default outputs
        norm_mant  = 8'b0;
        norm_exp   = 8'b0;
        overflow   = 1'b0;
        underflow  = 1'b0;

        shifted_mant = mant_in;
        adjusted_exp = exp_in;
        shift_count  = 5'd0;

        // -----------------------------------------------------------------
        // Handle zero mantissa (result is zero)
        // -----------------------------------------------------------------
        if (mant_in == 16'b0) begin
            norm_mant = 8'b0;
            norm_exp  = 8'b0;
        end else begin

            // -------------------------------------------------------------
            // Case 1: Multiplication — product bit 14 may be set
            //   If bit 15 is set (mant >= 32768), shift right by 1
            //   If bit 14 is set (128*128 = product), that's normal
            // For multiplication, we need the leading 1 at bit 13 or 14.
            // -------------------------------------------------------------
            if (is_mul) begin
                // Product of two 8-bit numbers (each 128..255) gives 16384..65025
                // The leading 1 is at bit 14 or 15.
                if (shifted_mant[15]) begin
                    // Leading 1 at bit 15 → shift right 2 and add 2 to exp
                    shifted_mant = shifted_mant >> 2;
                    adjusted_exp = adjusted_exp + 10'd2;
                end else if (shifted_mant[14]) begin
                    // Leading 1 at bit 14 → shift right 1 and add 1 to exp
                    shifted_mant = shifted_mant >> 1;
                    adjusted_exp = adjusted_exp + 10'd1;
                end
                // After shifting, take the top 8 bits as mantissa
                norm_mant = shifted_mant[14:7];

            end else begin
                // -------------------------------------------------------------
                // Case 2: Addition/Subtraction
                // Mantissa is 16 bits, significant bits in upper region.
                // We need the leading 1 at bit 15 of a 16-bit value,
                // which corresponds to the 8-bit value 1.xxxxxxx.
                // After alignment, upper byte is the integer part.
                // -------------------------------------------------------------

                // Sub-case 2a: Carry-out from addition → bit 16 overflow
                // This means the sum > 0xFFFF, but since we use 16 bits,
                // check if bit 15 is set (carry means result >= 32768)
                if (shifted_mant[15]) begin
                    // Shift right by 1 (losing LSB, but top 8 bits are mantissa)
                    shifted_mant = shifted_mant >> 1;
                    adjusted_exp = adjusted_exp + 10'd1;
                end

                // Sub-case 2b: Left-normalize (find leading 1 in bits [14:7])
                // Shift left until bit 15 is 1
                if (!shifted_mant[15]) begin
                    // Count leading zeros and shift left
                    shift_count = 5'd0;
                    begin : norm_loop
                        for (i = 15; i >= 0; i = i - 1) begin
                            if (shifted_mant[i] == 1'b0 && shift_count == (15 - i))
                                shift_count = shift_count + 1;
                        end
                    end

                    // Simpler approach: shift left one bit at a time
                    shift_count = 5'd0;
                    while (!shifted_mant[15] && shift_count < 5'd15) begin
                        shifted_mant = shifted_mant << 1;
                        shift_count  = shift_count + 1;
                    end

                    // Decrease exponent by the number of left shifts
                    if (adjusted_exp > {5'b0, shift_count})
                        adjusted_exp = adjusted_exp - {5'b0, shift_count};
                    else begin
                        adjusted_exp = 10'd0;
                        underflow    = 1'b1;
                    end
                end

                // Top 8 bits: bit15 is the implicit 1, bits [14:8] are mantissa frac
                // We want 8 bits with implicit leading 1
                norm_mant = shifted_mant[15:8];
            end

            // -----------------------------------------------------------------
            // Check for exponent overflow / underflow
            // -----------------------------------------------------------------
            if (adjusted_exp >= 10'd255) begin
                overflow  = 1'b1;
                norm_exp  = 8'hFF;    // Infinity exponent
                norm_mant = 8'b10000000; // Infinity mantissa pattern
            end else if (adjusted_exp == 10'd0 || underflow) begin
                underflow = 1'b1;
                norm_exp  = 8'b0;
                norm_mant = 8'b0;
            end else begin
                norm_exp = adjusted_exp[7:0];
            end

        end
    end

endmodule
