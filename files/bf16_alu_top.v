// =============================================================================
// Module: bf16_alu_top
// Description: Top-level module for the BFloat16 ALU on Basys 3.
//
// ---- OPERATION OVERVIEW ----
// This module ties together all sub-modules to compute:
//   result = A op B  (where op is add, sub, or mul based on mode)
//
// ---- BASYS 3 I/O MAPPING ----
//   SW[15:0]  → 16-bit input value (shared for A and B, loaded separately)
//   SW[1:0]   → mode select (00=add, 01=sub, 10=mul)  [loaded with B]
//   BTNC      → Manual clock (compute/capture)
//   BTNL      → Load operand A from switches
//   BTNR      → Load operand B from switches (SW[15:2]) + mode (SW[1:0])
//   BTNU      → Reset
//   LED[15:0] → Result bfloat16 value (raw bits)
//   LED[2]    → Overflow indicator
//   LED[1]    → Underflow indicator
//   LED[0]    → NaN / Invalid indicator
//   AN[3:0]   → 7-segment anode select
//   SEG[6:0]  → 7-segment cathode select
//
// ---- HOW TO USE ----
//   1. Set switches to your desired A value
//   2. Press BTNL to latch A
//   3. Set switches to your desired B value + mode (SW[1:0])
//   4. Press BTNR to latch B and mode
//   5. Press BTNC to compute the result
//   6. Read result on 7-segment display (4 hex digits)
//   7. Check LEDs for overflow/underflow/NaN flags
// =============================================================================

module bf16_alu_top (
    // Clock and control
    input        clk_100mhz,     // 100 MHz oscillator (W5 on Basys 3)
    input        btnC,           // Center button: compute clock
    input        btnL,           // Left button:   load A
    input        btnR,           // Right button:  load B + mode
    input        btnU,   
    input        btnD,        // Up button:     reset

    // Switch inputs
    input  [15:0] sw,            // 16 slide switches

    // LED outputs
    output  reg [15:0] led,           // Raw result bits on LEDs
    

    // 7-segment display
    output [3:0]  an,            // Anode select (active low)
    output [6:0]  seg            // Segment select (active low)
);

    // =========================================================================
    // WIRE DECLARATIONS
    // =========================================================================

wire         led_overflow;  // Overflow flag
wire     led_underflow; // Underflow flag
wire      led_nan;       // NaN / Invalid flag

    // Debounced button signals
    wire btn_clk_clean;
    wire btn_load_a;
    wire btn_load_b;
    wire btn_reset;

    // Registered operands
    wire [15:0] operand_a;
    wire [15:0] operand_b;
    reg  [1:0]  mode_reg;        // Operation mode: 00=add, 01=sub, 10=mul

    // Decoder outputs for A
    wire        sign_a, is_zero_a, is_inf_a, is_nan_a;
    wire [7:0]  exp_a, mant_a;

    // Decoder outputs for B
    wire        sign_b, is_zero_b, is_inf_b, is_nan_b;
    wire [7:0]  exp_b, mant_b;

    // Exception handler outputs
    wire        special_case;
    wire        exc_nan, exc_inf, exc_inf_sign, exc_zero, exc_zero_sign;

    // Alignment outputs (for add/sub path)
    wire [7:0]  aligned_exp;
    wire [15:0] aligned_mant_a;
    wire [15:0] aligned_mant_b;

    // Add/sub result
    wire        addsub_sign;
    wire [15:0] addsub_mant;
    wire [7:0]  addsub_exp;

    // Multiply result
    wire        mul_sign;
    wire [9:0]  mul_exp_raw;
    wire [15:0] mul_mant;

    // Mux between add/sub and mul paths
    reg         arith_sign;
    reg [9:0]   arith_exp;
    reg [15:0]  arith_mant;

    // Normalization outputs
    wire [7:0]  norm_mant;
    wire [7:0]  norm_exp;
    wire        norm_overflow;
    wire        norm_underflow;

    // Rounding outputs
    wire [7:0]  round_mant;
    wire [7:0]  round_exp;

    // Final result
    wire [15:0] result_bf16;
    wire        flag_overflow;
    wire        flag_underflow;
    wire        flag_nan;

    // Result register (latched on btn_clk_clean)
    reg [15:0]  result_reg;
    reg         overflow_reg;
    reg         underflow_reg;
    reg         nan_reg;

    // =========================================================================
    // STEP 1: DEBOUNCE BUTTONS
    // =========================================================================

    btn_debounce deb_clk (
        .clk_100mhz (clk_100mhz),
        .btn_raw    (btnC),
        .btn_clean  (btn_clk_clean)
    );

    btn_debounce deb_la (
        .clk_100mhz (clk_100mhz),
        .btn_raw    (btnL),
        .btn_clean  (btn_load_a)
    );

    btn_debounce deb_rb (
        .clk_100mhz (clk_100mhz),
        .btn_raw    (btnR),
        .btn_clean  (btn_load_b)
    );

    btn_debounce deb_rst (
        .clk_100mhz (clk_100mhz),
        .btn_raw    (btnU),
        .btn_clean  (btn_reset)
    );

    // =========================================================================
    // STEP 2: INPUT REGISTERS (latch A and B from switches)
    // =========================================================================

    input_reg u_input_reg (
        .clk    (clk_100mhz),
        .reset  (btn_reset),
        .load_a (btn_load_a),
        .load_b (btn_load_b),
        .sw_in  (sw),
        .reg_a  (operand_a),
        .reg_b  (operand_b)
    );

    // Latch mode from SW[1:0] when B is loaded
    always @(posedge clk_100mhz or posedge btn_reset) begin
        if (btn_reset)
            mode_reg <= 2'b00;
        else if (btn_load_b==1'B1)
            mode_reg <= sw[1:0];
    end

    // =========================================================================
    // STEP 3: DECODE BOTH INPUTS
    // =========================================================================

    bf16_decoder u_dec_a (
        .bf16_in  (operand_a),
        .sign     (sign_a),
        .exponent (exp_a),
        .mantissa (mant_a),
        .is_zero  (is_zero_a),
        .is_inf   (is_inf_a),
        .is_nan   (is_nan_a)
    );

    bf16_decoder u_dec_b (
        .bf16_in  (operand_b),
        .sign     (sign_b),
        .exponent (exp_b),
        .mantissa (mant_b),
        .is_zero  (is_zero_b),
        .is_inf   (is_inf_b),
        .is_nan   (is_nan_b)
    );

    // =========================================================================
    // STEP 4: EXCEPTION HANDLER
    // =========================================================================

    bf16_exception u_exc (
        .sign_a      (sign_a),
        .sign_b      (sign_b),
        .is_zero_a   (is_zero_a),
        .is_zero_b   (is_zero_b),
        .is_inf_a    (is_inf_a),
        .is_inf_b    (is_inf_b),
        .is_nan_a    (is_nan_a),
        .is_nan_b    (is_nan_b),
        .do_sub      (mode_reg == 2'b01),
        .mode        (mode_reg),
        .special_case(special_case),
        .out_nan     (exc_nan),
        .out_inf     (exc_inf),
        .out_inf_sign(exc_inf_sign),
        .out_zero    (exc_zero),
        .out_zero_sign(exc_zero_sign)
    );

    // =========================================================================
    // STEP 5a: ALIGNMENT (for add/sub path)
    // =========================================================================

    bf16_align u_align (
        .exp_a        (exp_a),
        .exp_b        (exp_b),
        .mant_a       (mant_a),
        .mant_b       (mant_b),
        .aligned_exp  (aligned_exp),
        .aligned_mant_a(aligned_mant_a),
        .aligned_mant_b(aligned_mant_b)
    );

    // =========================================================================
    // STEP 5b: ADD/SUBTRACT
    // =========================================================================

    bf16_addsub u_addsub (
        .sign_a     (sign_a),
        .sign_b     (sign_b),
        .mant_a     (aligned_mant_a),
        .mant_b     (aligned_mant_b),
        .exp_in     (aligned_exp),
        .do_sub     (mode_reg == 2'b01),
        .result_sign(addsub_sign),
        .result_mant(addsub_mant),
        .result_exp (addsub_exp)
    );

    // =========================================================================
    // STEP 5c: MULTIPLY
    // =========================================================================

    bf16_mul u_mul (
        .sign_a       (sign_a),
        .sign_b       (sign_b),
        .exp_a        (exp_a),
        .exp_b        (exp_b),
        .mant_a       (mant_a),
        .mant_b       (mant_b),
        .result_sign  (mul_sign),
        .result_exp_raw(mul_exp_raw),
        .result_mant  (mul_mant)
    );

    // =========================================================================
    // STEP 6: MUX — SELECT ADD/SUB OR MUL RESULT
    // =========================================================================

    always @(*) begin
        if (mode_reg == 2'b10) begin
            // Multiplication path
            arith_sign = mul_sign;
            arith_exp  = mul_exp_raw;
            arith_mant = mul_mant;
        end else begin
            // Addition/Subtraction path
            arith_sign = addsub_sign;
            arith_exp  = {2'b0, addsub_exp};
            arith_mant = addsub_mant;
        end
    end

    // =========================================================================
    // STEP 7: NORMALIZE
    // =========================================================================

    bf16_normalize u_norm (
        .mant_in   (arith_mant),
        .exp_in    (arith_exp),
        .is_mul    (mode_reg == 2'b10),
        .norm_mant (norm_mant),
        .norm_exp  (norm_exp),
        .overflow  (norm_overflow),
        .underflow (norm_underflow)
    );

    // =========================================================================
    // STEP 8: ROUND
    // =========================================================================

    bf16_round u_round (
        .norm_mant   (norm_mant),
        .norm_exp    (norm_exp),
        .guard_bit   (1'b0),   // Simplified: no guard bits tracked yet
        .sticky_bit  (1'b0),
        .rounded_mant(round_mant),
        .rounded_exp (round_exp)
    );

    // =========================================================================
    // STEP 9: EXCEPTION / NORMAL PATH FLAGS
    // =========================================================================

    assign flag_overflow  = special_case ? exc_inf   : norm_overflow;
    assign flag_underflow = special_case ? 1'b0      : norm_underflow;
    assign flag_nan       = special_case ? exc_nan   : 1'b0;

    // =========================================================================
    // STEP 10: ENCODE OUTPUT
    // =========================================================================

    bf16_encoder u_enc (
        .sign      (special_case ? (exc_inf ? exc_inf_sign : arith_sign) : arith_sign),
        .exponent  (round_exp),
        .mantissa  (round_mant),
        .force_zero(special_case ? exc_zero : norm_underflow),
        .force_inf (special_case ? exc_inf  : norm_overflow),
        .force_nan (special_case ? exc_nan  : 1'b0),
        .bf16_out  (result_bf16)
    );

    // =========================================================================
    // STEP 11: LATCH RESULT ON BUTTON CLOCK
    // =========================================================================

    always @(posedge btn_clk_clean or posedge btn_reset) begin
        if (btn_reset) begin
            result_reg   <= 16'b0;
            overflow_reg <= 1'b0;
            underflow_reg<= 1'b0;
            nan_reg      <= 1'b0;
        end else begin
            result_reg   <= result_bf16;
            overflow_reg <= flag_overflow;
            underflow_reg<= flag_underflow;
            nan_reg      <= flag_nan;
        end
    end

    // =========================================================================
    // STEP 12: OUTPUTS
    // =========================================================================

    // LEDs show raw result bits and flags
      assign led_overflow  = overflow_reg;
    assign led_underflow = underflow_reg;
    assign led_nan       = nan_reg;
    always@(posedge clk_100mhz or posedge btnD)begin 
    if (btnD)
    led[2:0] <={led_overflow,led_underflow,led_nan};
       else
        led <= result_reg;

    end 
    
  

    // 7-segment display shows result as 4 hex digits
    seg7_display_fast u_seg7 (
        .clk_100mhz (clk_100mhz),
        .reset      (btn_reset),
        .hex_value  (result_reg),
        .an         (an),
        .seg        (seg)
    );

endmodule
