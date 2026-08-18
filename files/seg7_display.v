// =============================================================================
// Module: seg7_display
// Description: Drives the four 7-segment displays on the Basys 3 board.
//              Displays a 16-bit hex value (4 hex digits) using time-division
//              multiplexing (TDM). Each digit is shown in turn at ~1kHz.
//
// Basys 3 has a common-anode display:
//   - Digit enable (AN) is ACTIVE LOW  (0 = digit ON)
//   - Segment enable (seg) is ACTIVE LOW (0 = segment ON)
//
// 7-segment encoding (active low) for segments: CA CB CC CD CE CF CG DP
//   The segments are labeled a-g:
//        a
//       ---
//   f |   | b
//     | g |
//       ---
//   e |   | c
//     |   |
//       ---
//        d    (dp = decimal point)
//
// Segment bit order: {CA, CB, CC, CD, CE, CF, CG} = {a, b, c, d, e, f, g}
// =============================================================================

module seg7_display (
    input        clk,             // System clock (from push button)
    input        reset,           // Active-high reset
    input [15:0] hex_value,       // 16-bit value to display as 4 hex digits

    output reg [3:0] an,          // Anode select: active low, one-hot
    output reg [6:0] seg          // Segment select: active low
);

    // -------------------------------------------------------------------------
    // We need a free-running counter to multiplex the display.
    // Since clk is a button (slow), we use it directly but the display will
    // cycle through digits on each clock edge.
    // For actual hardware, you'd use the 100MHz clock for TDM.
    // Here we use a simple 2-bit counter to select which digit to show.
    // -------------------------------------------------------------------------
    reg [1:0] digit_sel;  // Which of the 4 digits to show (0-3)

    // Cycle digit on each clock
    always @(posedge clk or posedge reset) begin
        if (reset)
            digit_sel <= 2'b00;
        else
            digit_sel <= digit_sel + 1;
    end

    // -------------------------------------------------------------------------
    // Select which 4-bit nibble to display based on digit_sel
    // digit 0 = leftmost  = bits [15:12]
    // digit 1             = bits [11:8]
    // digit 2             = bits [7:4]
    // digit 3 = rightmost = bits [3:0]
    // -------------------------------------------------------------------------
    reg [3:0] current_nibble;

    always @(*) begin
        case (digit_sel)
            2'b00: begin current_nibble = hex_value[15:12]; an = 4'b1110; end
            2'b01: begin current_nibble = hex_value[11:8];  an = 4'b1101; end
            2'b10: begin current_nibble = hex_value[7:4];   an = 4'b1011; end
            2'b11: begin current_nibble = hex_value[3:0];   an = 4'b0111; end
            default: begin current_nibble = 4'b0; an = 4'b1111; end
        endcase
    end

    // -------------------------------------------------------------------------
    // Hex digit to 7-segment decoder (active low: 0 = segment ON)
    // Segment order: {a, b, c, d, e, f, g} = {CA,CB,CC,CD,CE,CF,CG}
    // -------------------------------------------------------------------------
    always @(*) begin
        case (current_nibble)
            4'h0: seg = 7'b000_0001;  // 0
            4'h1: seg = 7'b100_1111;  // 1
            4'h2: seg = 7'b001_0010;  // 2
            4'h3: seg = 7'b000_0110;  // 3
            4'h4: seg = 7'b100_1100;  // 4
            4'h5: seg = 7'b010_0100;  // 5
            4'h6: seg = 7'b010_0000;  // 6
            4'h7: seg = 7'b000_1111;  // 7
            4'h8: seg = 7'b000_0000;  // 8
            4'h9: seg = 7'b000_0100;  // 9
            4'hA: seg = 7'b000_1000;  // A
            4'hB: seg = 7'b110_0000;  // b
            4'hC: seg = 7'b011_0001;  // C
            4'hD: seg = 7'b100_0010;  // d
            4'hE: seg = 7'b011_0000;  // E
            4'hF: seg = 7'b011_1000;  // F
            default: seg = 7'b111_1111; // All off
        endcase
    end

endmodule


// =============================================================================
// Module: seg7_display_fast
// Description: Version for use with 100MHz clock (proper TDM at ~1kHz per digit)
//              Used in the actual top module for correct display behavior.
// =============================================================================

module seg7_display_fast (
    input        clk_100mhz,      // 100 MHz system clock
    input        reset,
    input [15:0] hex_value,

    output reg [3:0] an,
    output reg [6:0] seg
);

    // Divide 100MHz clock to get ~1kHz refresh (100,000 cycles per digit)
    // With 4 digits, full refresh = ~250Hz
    reg [16:0] clk_div;
    reg [1:0]  digit_sel;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            clk_div   <= 0;
            digit_sel <= 0;
        end else begin
            if (clk_div == 17'd99999) begin
                clk_div   <= 0;
                digit_sel <= digit_sel + 1;
            end else begin
                clk_div <= clk_div + 1;
            end
        end
    end

    reg [3:0] current_nibble;

    always @(*) begin
        case (digit_sel)
            2'b00: begin current_nibble = hex_value[15:12]; an = 4'b1110; end
            2'b01: begin current_nibble = hex_value[11:8];  an = 4'b1101; end
            2'b10: begin current_nibble = hex_value[7:4];   an = 4'b1011; end
            2'b11: begin current_nibble = hex_value[3:0];   an = 4'b0111; end
            default: begin current_nibble = 4'b0; an = 4'b1111; end
        endcase
    end

    always @(*) begin
        case (current_nibble)
            4'h0: seg = 7'b000_0001;
            4'h1: seg = 7'b100_1111;
            4'h2: seg = 7'b001_0010;
            4'h3: seg = 7'b000_0110;
            4'h4: seg = 7'b100_1100;
            4'h5: seg = 7'b010_0100;
            4'h6: seg = 7'b010_0000;
            4'h7: seg = 7'b000_1111;
            4'h8: seg = 7'b000_0000;
            4'h9: seg = 7'b000_0100;
            4'hA: seg = 7'b000_1000;
            4'hB: seg = 7'b110_0000;
            4'hC: seg = 7'b011_0001;
            4'hD: seg = 7'b100_0010;
            4'hE: seg = 7'b011_0000;
            4'hF: seg = 7'b011_1000;
            default: seg = 7'b111_1111;
        endcase
    end

endmodule
