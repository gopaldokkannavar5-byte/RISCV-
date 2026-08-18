// =============================================================================
// Module: input_reg
// Description: Captures input switches into a register on the rising edge
//              of the clock (push button). This creates a clean, registered
//              version of the switch inputs.
//
// On Basys 3:
//   - SW[15:0] are 16 slide switches
//   - We use SW[15:0] for operand A and B alternately,
//     or in this design, A = SW[15:0] on one board side, B from another register.
//
// Note: Since the Basys 3 only has 16 switches but we need two 16-bit inputs,
// the design loads A and B separately using button presses.
// - BTNC (center button) = manual clock
// - BTNL (left button)   = load A from SW[15:0]
// - BTNR (right button)  = load B from SW[15:0]
// =============================================================================

module input_reg (
    input        clk,             // Push button: rising edge triggers
    input        reset,           // Active-high reset (BTNU)
    input        load_a,          // Load operand A (BTNL)
    input        load_b,          // Load operand B (BTNR)
    input [15:0] sw_in,           // Switch inputs

    output reg [15:0] reg_a,      // Registered operand A
    output reg [15:0] reg_b       // Registered operand B
);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            reg_a <= 16'b0;
            reg_b <= 16'b0;
        end else begin
            // Load A when load_a button is pressed
            if (load_a)
                reg_a <= sw_in;

            // Load B when load_b button is pressed
            if (load_b)
                reg_b <= sw_in;
        end
    end

endmodule


// =============================================================================
// Module: btn_debounce
// Description: Simple push-button debouncer using a counter.
//              Buttons on Basys 3 can bounce (rapidly toggle) when pressed.
//              This module waits for the signal to be stable for ~20ms
//              before passing it through.
//
// With 100MHz clock: 20ms = 2,000,000 cycles
// =============================================================================

module btn_debounce (
    input  clk_100mhz,   // 100 MHz system clock
    input  btn_raw,      // Raw button input
    output btn_clean     // Debounced single-pulse output
);

    reg [21:0] counter;
    reg        btn_prev;
    reg        btn_stable;
    reg        btn_pulse;

    assign btn_clean = btn_pulse;

    always @(posedge clk_100mhz) begin
        btn_pulse <= 1'b0;  // Default: no pulse

        if (btn_raw != btn_stable) begin
            // Button state changed; start/reset counter
            counter <= 22'd0;
        end else if (counter < 22'd2000000) begin
            counter <= counter + 1;
        end else begin
            // Counter reached threshold: state is stable
            if (btn_stable != btn_prev) begin
                btn_prev  <= btn_stable;
                // Generate a single pulse on rising edge of stable signal
                if (btn_stable)
                    btn_pulse <= 1'b1;
            end
        end

        // Always track the current state
        btn_stable <= btn_raw;
    end

endmodule
