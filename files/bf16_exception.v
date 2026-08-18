// =============================================================================
// Module: bf16_exception
// Description: Detects and handles special cases in bfloat16 arithmetic.
//              This module checks inputs for special values (NaN, Infinity,
//              Zero) and computes the correct output for those cases.
//
// Exception rules (IEEE-style):
//   - Any NaN input → output NaN
//   - Inf + Inf (same sign) → Inf
//   - Inf - Inf (or Inf + (-Inf)) → NaN  (indeterminate)
//   - Inf * 0 → NaN
//   - Zero * anything → Zero
//   - Normal + Zero → Normal
// =============================================================================

module bf16_exception (
    input         sign_a,
    input         sign_b,
    input         is_zero_a,
    input         is_zero_b,
    input         is_inf_a,
    input         is_inf_b,
    input         is_nan_a,
    input         is_nan_b,
    input         do_sub,         // 1 = subtraction (flips B's effective sign)
    input  [1:0]  mode,           // 00=add, 01=sub, 10=mul

    output reg    special_case,   // 1 = a special case was detected
    output reg    out_nan,        // Output should be NaN
    output reg    out_inf,        // Output should be Infinity
    output reg    out_inf_sign,   // Sign of infinity output
    output reg    out_zero,       // Output should be Zero
    output reg    out_zero_sign   // Sign of zero output
);

    // Effective sign of B after operation (sub flips it)
    wire eff_sign_b = do_sub ? ~sign_b : sign_b;

    always @(*) begin
        // Default: no special case
        special_case  = 1'b0;
        out_nan       = 1'b0;
        out_inf       = 1'b0;
        out_inf_sign  = 1'b0;
        out_zero      = 1'b0;
        out_zero_sign = 1'b0;

        // -----------------------------------------------------------------
        // Rule 1: Any NaN input → NaN output
        // -----------------------------------------------------------------
        if (is_nan_a || is_nan_b) begin
            special_case = 1'b1;
            out_nan      = 1'b1;
        end

        // -----------------------------------------------------------------
        // Rule 2: Multiplication with zero → Zero
        // -----------------------------------------------------------------
        else if (mode == 2'b10 && (is_zero_a || is_zero_b)) begin
            if (is_inf_a || is_inf_b) begin
                // Inf * 0 = NaN
                special_case = 1'b1;
                out_nan      = 1'b1;
            end else begin
                special_case  = 1'b1;
                out_zero      = 1'b1;
                out_zero_sign = sign_a ^ sign_b;
            end
        end

        // -----------------------------------------------------------------
        // Rule 3: Infinity cases
        // -----------------------------------------------------------------
        else if (is_inf_a || is_inf_b) begin
            special_case = 1'b1;

            if (is_inf_a && is_inf_b) begin
                // Inf OP Inf
                if (sign_a == eff_sign_b) begin
                    // Inf + Inf (same sign) → Inf
                    out_inf      = 1'b1;
                    out_inf_sign = sign_a;
                end else begin
                    // Inf - Inf → NaN (undefined)
                    out_nan = 1'b1;
                end
            end else if (is_inf_a) begin
                // Inf OP normal → Inf
                out_inf      = 1'b1;
                out_inf_sign = sign_a;
            end else begin
                // normal OP Inf → Inf
                out_inf      = 1'b1;
                out_inf_sign = eff_sign_b;
            end
        end

        // -----------------------------------------------------------------
        // Rule 4: One operand is zero (add/sub only; mul handled above)
        // -----------------------------------------------------------------
        else if (is_zero_a && is_zero_b) begin
            special_case  = 1'b1;
            out_zero      = 1'b1;
            out_zero_sign = 1'b0;  // +0
        end
        // If only one is zero, the other is normal → not a special case
        // (The main datapath handles it correctly)
    end

endmodule
