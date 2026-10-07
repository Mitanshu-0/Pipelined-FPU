//==============================================================
// IEEE-754 SINGLE-PRECISION 6-STAGE PIPELINED DIVIDER
//==============================================================
//
// PURE VERILOG-2001
//
// TOP MODULE:
//     FPU_div
//
// 6 PIPELINE STAGES:
//     S1 : Unpack + Classify
//     S2 : Special Cases + Metadata
//     S3 : Normalize Operands + Exponent Preparation
//     S4 : Restoring Mantissa Division
//     S5 : Normalize + G/R/S + Round + Exceptions
//     S6 : IEEE-754 Pack + Output
//
// IEEE-754 single precision:
//     Sign     = 1 bit
//     Exponent = 8 bits
//     Fraction = 23 bits
//
// NaN policy:
//     QNaN/SNaN are NOT distinguished.
//     All NaN results use 32'h7FC00000.
//
// Rounding:
//     Round-to-nearest-even
//
//==============================================================


//==============================================================
// STAGE 1
// UNPACK + CLASSIFY
//==============================================================

module fpu_div_stage1_unpack (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire [31:0] a,
    input  wire [31:0] b,

    output reg         valid_out,

    output reg         sign_a,
    output reg         sign_b,

    output reg  [7:0]  exp_a,
    output reg  [7:0]  exp_b,

    output reg  [22:0] frac_a,
    output reg  [22:0] frac_b,

    output reg         is_zero_a,
    output reg         is_zero_b,

    output reg         is_denorm_a,
    output reg         is_denorm_b,

    output reg         is_inf_a,
    output reg         is_inf_b,

    output reg         is_nan_a,
    output reg         is_nan_b
);

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            valid_out <= 1'b0;

            sign_a <= 1'b0;
            sign_b <= 1'b0;

            exp_a <= 8'h00;
            exp_b <= 8'h00;

            frac_a <= 23'h000000;
            frac_b <= 23'h000000;

            is_zero_a <= 1'b0;
            is_zero_b <= 1'b0;

            is_denorm_a <= 1'b0;
            is_denorm_b <= 1'b0;

            is_inf_a <= 1'b0;
            is_inf_b <= 1'b0;

            is_nan_a <= 1'b0;
            is_nan_b <= 1'b0;

        end
        else begin

            valid_out <= enable;

            if (enable) begin

                sign_a <= a[31];
                sign_b <= b[31];

                exp_a <= a[30:23];
                exp_b <= b[30:23];

                frac_a <= a[22:0];
                frac_b <= b[22:0];

                // Zero
                is_zero_a <= (a[30:23] == 8'h00) && (a[22:0] == 23'h000000);
                is_zero_b <= (b[30:23] == 8'h00) && (b[22:0] == 23'h000000);

                // Denormal / subnormal
                is_denorm_a <= (a[30:23] == 8'h00) && (a[22:0] != 23'h000000);
                is_denorm_b <= (b[30:23] == 8'h00) && (b[22:0] != 23'h000000);

                // Infinity
                is_inf_a <= (a[30:23] == 8'hFF) && (a[22:0] == 23'h000000);
                is_inf_b <= (b[30:23] == 8'hFF) && (b[22:0] == 23'h000000);

                // NaN
                is_nan_a <= (a[30:23] == 8'hFF) && (a[22:0] != 23'h000000);
                is_nan_b <= (b[30:23] == 8'hFF) && (b[22:0] != 23'h000000);

            end
        end
    end

endmodule


//==============================================================
// STAGE 2
// SPECIAL CASES + PASS METADATA
//==============================================================

module fpu_div_stage2_special (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        valid_in,

    input  wire        sign_a,
    input  wire        sign_b,

    input  wire [7:0]  exp_a,
    input  wire [7:0]  exp_b,

    input  wire [22:0] frac_a,
    input  wire [22:0] frac_b,

    input  wire        is_zero_a,
    input  wire        is_zero_b,

    input  wire        is_denorm_a,
    input  wire        is_denorm_b,

    input  wire        is_inf_a,
    input  wire        is_inf_b,

    input  wire        is_nan_a,
    input  wire        is_nan_b,

    output reg         valid_out,

    output reg         special_case,
    output reg  [31:0] special_result,

    output reg         div_by_zero,
    output reg         invalid,

    output reg         result_sign,

    output reg  [7:0]  exp_a_out,
    output reg  [7:0]  exp_b_out,

    output reg [22:0]  frac_a_out,
    output reg [22:0]  frac_b_out,

    output reg         is_zero_a_out,
    output reg         is_zero_b_out,

    output reg         is_denorm_a_out,
    output reg         is_denorm_b_out,

    output reg         is_inf_a_out,
    output reg         is_inf_b_out,

    output reg         is_nan_a_out,
    output reg         is_nan_b_out
);

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            valid_out <= 1'b0;

            special_case <= 1'b0;
            special_result <= 32'h00000000;

            div_by_zero <= 1'b0;
            invalid <= 1'b0;

            result_sign <= 1'b0;

            exp_a_out <= 8'h00;
            exp_b_out <= 8'h00;

            frac_a_out <= 23'h000000;
            frac_b_out <= 23'h000000;

            is_zero_a_out <= 1'b0;
            is_zero_b_out <= 1'b0;

            is_denorm_a_out <= 1'b0;
            is_denorm_b_out <= 1'b0;

            is_inf_a_out <= 1'b0;
            is_inf_b_out <= 1'b0;

            is_nan_a_out <= 1'b0;
            is_nan_b_out <= 1'b0;

        end
        else begin

            valid_out <= valid_in;

            special_case <= 1'b0;
            special_result <= 32'h00000000;

            div_by_zero <= 1'b0;
            invalid <= 1'b0;

            result_sign <= sign_a ^ sign_b;

            exp_a_out <= exp_a;
            exp_b_out <= exp_b;

            frac_a_out <= frac_a;
            frac_b_out <= frac_b;

            is_zero_a_out <= is_zero_a;
            is_zero_b_out <= is_zero_b;

            is_denorm_a_out <= is_denorm_a;
            is_denorm_b_out <= is_denorm_b;

            is_inf_a_out <= is_inf_a;
            is_inf_b_out <= is_inf_b;

            is_nan_a_out <= is_nan_a;
            is_nan_b_out <= is_nan_b;

            if (valid_in) begin

                // NaN input
                if (is_nan_a || is_nan_b) begin

                    special_case <= 1'b1;
                    special_result <= 32'h7FC00000;
                    invalid <= 1'b1;

                end

                // Infinity / Infinity -> NaN
                else if (is_inf_a && is_inf_b) begin

                    special_case <= 1'b1;
                    special_result <= 32'h7FC00000;
                    invalid <= 1'b1;

                end

                // Zero / Zero -> NaN
                else if (is_zero_a && is_zero_b) begin

                    special_case <= 1'b1;
                    special_result <= 32'h7FC00000;
                    invalid <= 1'b1;

                end

                // Infinity / Zero -> Infinity
                else if (is_inf_a && is_zero_b) begin

                    special_case <= 1'b1;
                    special_result <= {sign_a ^ sign_b, 8'hFF, 23'h000000};

                end

                // Finite nonzero / Zero -> Infinity
                else if (!is_zero_a && !is_inf_a && !is_nan_a && is_zero_b) begin

                    special_case <= 1'b1;
                    special_result <= {sign_a ^ sign_b, 8'hFF, 23'h000000};
                    div_by_zero <= 1'b1;

                end

                // Infinity / finite nonzero -> Infinity
                else if (is_inf_a && !is_zero_b && !is_inf_b && !is_nan_b) begin

                    special_case <= 1'b1;
                    special_result <= {sign_a ^ sign_b, 8'hFF, 23'h000000};

                end

                // Zero / finite nonzero or Infinity -> Zero
                else if (is_zero_a) begin

                    special_case <= 1'b1;
                    special_result <= {sign_a ^ sign_b, 8'h00, 23'h000000};

                end

                // Finite nonzero / Infinity -> Zero
                else if (!is_zero_a && !is_inf_a && !is_nan_a && is_inf_b) begin

                    special_case <= 1'b1;
                    special_result <= {sign_a ^ sign_b, 8'h00, 23'h000000};

                end

            end
        end
    end

endmodule


//==============================================================
// STAGE 3
// NORMALIZE OPERANDS + EXPONENT PREPARATION
//==============================================================

module fpu_div_stage3_prepare (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        valid_in,

    input  wire        special_case_in,
    input  wire [31:0] special_result_in,

    input  wire        div_by_zero_in,
    input  wire        invalid_in,

    input  wire        result_sign_in,

    input  wire [7:0]  exp_a,
    input  wire [7:0]  exp_b,

    input  wire [22:0] frac_a,
    input  wire [22:0] frac_b,

    input  wire        is_zero_a,
    input  wire        is_zero_b,

    input  wire        is_denorm_a,
    input  wire        is_denorm_b,

    input  wire        is_inf_a,
    input  wire        is_inf_b,

    input  wire        is_nan_a,
    input  wire        is_nan_b,

    output reg         valid_out,

    output reg         special_case_out,
    output reg  [31:0] special_result_out,

    output reg         div_by_zero_out,
    output reg         invalid_out,

    output reg         result_sign_out,

    output reg  [23:0] significand_a,
    output reg  [23:0] significand_b,

    output reg signed [11:0] exponent_out
);

    reg [23:0] sig_a_next;
    reg [23:0] sig_b_next;

    reg signed [11:0] exp_a_next;
    reg signed [11:0] exp_b_next;

    integer i;
    integer highest_a;
    integer highest_b;
    integer shift_a;
    integer shift_b;

    reg found_a;
    reg found_b;


    //--------------------------------------------------------------------------
    // Combinational normalization and exponent preparation
    //--------------------------------------------------------------------------

    always @* begin

        sig_a_next = 24'h000000;
        sig_b_next = 24'h000000;

        exp_a_next = 12'sd0;
        exp_b_next = 12'sd0;

        highest_a = 0;
        highest_b = 0;

        shift_a = 0;
        shift_b = 0;

        found_a = 1'b0;
        found_b = 1'b0;

        // Operand A
        if (!is_zero_a && !is_denorm_a && !is_inf_a && !is_nan_a) begin

            sig_a_next = {1'b1, frac_a};
            exp_a_next = $signed({1'b0, exp_a}) - 12'sd127;

        end
        else if (is_denorm_a) begin

            for (i = 22; i >= 0; i = i - 1) begin

                if (!found_a && frac_a[i]) begin
                    highest_a = i;
                    found_a = 1'b1;
                end

            end

            shift_a = 23 - highest_a;
            sig_a_next = {1'b0, frac_a} << shift_a;
            exp_a_next = highest_a - 12'sd149;

        end

        // Operand B
        if (!is_zero_b && !is_denorm_b && !is_inf_b && !is_nan_b) begin

            sig_b_next = {1'b1, frac_b};
            exp_b_next = $signed({1'b0, exp_b}) - 12'sd127;

        end
        else if (is_denorm_b) begin

            for (i = 22; i >= 0; i = i - 1) begin

                if (!found_b && frac_b[i]) begin
                    highest_b = i;
                    found_b = 1'b1;
                end

            end

            shift_b = 23 - highest_b;
            sig_b_next = {1'b0, frac_b} << shift_b;
            exp_b_next = highest_b - 12'sd149;

        end

    end


    //--------------------------------------------------------------------------
    // Pipeline register
    //--------------------------------------------------------------------------

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            valid_out <= 1'b0;

            special_case_out <= 1'b0;
            special_result_out <= 32'h00000000;

            div_by_zero_out <= 1'b0;
            invalid_out <= 1'b0;

            result_sign_out <= 1'b0;

            significand_a <= 24'h000000;
            significand_b <= 24'h000000;

            exponent_out <= 12'sd0;

        end
        else begin

            valid_out <= valid_in;

            special_case_out <= special_case_in;
            special_result_out <= special_result_in;

            div_by_zero_out <= div_by_zero_in;
            invalid_out <= invalid_in;

            result_sign_out <= result_sign_in;

            significand_a <= sig_a_next;
            significand_b <= sig_b_next;

            exponent_out <= exp_a_next - exp_b_next;

        end
    end

endmodule


//==============================================================
// STAGE 4
// RESTORING MANTISSA DIVISION
//==============================================================
//
// quotient_work:
//     [25]   = hidden bit
//     [24:2] = 23 fraction bits
//     [1]    = Guard
//     [0]    = Round
//
// remainder != 0 -> Sticky
//
// No separate subnormal divider.
// Stage 5 handles gradual underflow.
//
//==============================================================

module fpu_div_stage4_divide (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        valid_in,

    input  wire        special_case_in,
    input  wire [31:0] special_result_in,

    input  wire        div_by_zero_in,
    input  wire        invalid_in,

    input  wire        result_sign_in,

    input  wire [23:0] significand_a,
    input  wire [23:0] significand_b,

    input  wire signed [11:0] exponent_in,

    output reg         valid_out,

    output reg         special_case_out,
    output reg  [31:0] special_result_out,

    output reg         div_by_zero_out,
    output reg         invalid_out,

    output reg         result_sign_out,

    output reg  [32:0] quotient_out,
    output reg  [23:0] remainder_out,

    output reg signed [11:0] exponent_out
);

    reg [25:0] quotient_work;
    reg [24:0] remainder_work;
    reg signed [11:0] exponent_work;

    integer i;


    //--------------------------------------------------------------------------
    // Combinational restoring division
    //--------------------------------------------------------------------------

    always @* begin

        quotient_work = 26'h0000000;
        remainder_work = 25'h0000000;
        exponent_work = exponent_in;

        // Never perform mantissa division for special cases.
        if (valid_in && !special_case_in) begin

            // A/B >= 1
            if (significand_a >= significand_b) begin

                quotient_work[25] = 1'b1;
                remainder_work = {1'b0, significand_a} - {1'b0, significand_b};

            end

            // A/B < 1
            // Calculate 2A/B and reduce exponent by one.
            else begin

                quotient_work[25] = 1'b1;
                remainder_work = {significand_a, 1'b0} - {1'b0, significand_b};
                exponent_work = exponent_in - 12'sd1;

            end

            // Generate:
            // [24:2] = 23 fraction bits
            // [1]    = Guard
            // [0]    = Round
            for (i = 24; i >= 0; i = i - 1) begin

                remainder_work = remainder_work << 1;

                if (remainder_work >= {1'b0, significand_b}) begin

                    remainder_work = remainder_work - {1'b0, significand_b};
                    quotient_work[i] = 1'b1;

                end
                else begin

                    quotient_work[i] = 1'b0;

                end
            end

        end

    end


    //--------------------------------------------------------------------------
    // Pipeline register
    //--------------------------------------------------------------------------

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            valid_out <= 1'b0;

            special_case_out <= 1'b0;
            special_result_out <= 32'h00000000;

            div_by_zero_out <= 1'b0;
            invalid_out <= 1'b0;

            result_sign_out <= 1'b0;

            quotient_out <= 33'h000000000;
            remainder_out <= 24'h000000;

            exponent_out <= 12'sd0;

        end
        else begin

            valid_out <= valid_in;

            special_case_out <= special_case_in;
            special_result_out <= special_result_in;

            div_by_zero_out <= div_by_zero_in;
            invalid_out <= invalid_in;

            result_sign_out <= result_sign_in;

            quotient_out <= {7'b0000000, quotient_work};
            remainder_out <= remainder_work[23:0];
            exponent_out <= exponent_work;

        end
    end

endmodule


//==============================================================
// STAGE 5
// NORMALIZE + G/R/S + ROUND + EXCEPTIONS
//==============================================================
//
// Correct subnormal promotion:
//
//     rounded_ext[23] = 1
//
// means a rounded subnormal has reached 2^23 subnormal units,
// which is exactly the smallest normal number.
//
// Normal rounding carry:
//
//     rounded_ext[24] = 1
//
//==============================================================

module fpu_div_stage5_round (
    input wire         clk,
    input wire         rst_n,

    input wire         valid_in,

    input wire         special_case_in,
    input wire [31:0]  special_result_in,

    input wire         div_by_zero_in,
    input wire         invalid_in,

    input wire         result_sign_in,

    input wire [32:0]  quotient_in,
    input wire [23:0]  remainder_in,

    input wire signed [11:0] exponent_in,

    output reg         valid_out,

    output reg         special_case_out,
    output reg  [31:0] special_result_out,

    output reg         overflow_out,
    output reg         underflow_out,
    output reg         div_by_zero_out,
    output reg         invalid_out,
    output reg         inexact_out,

    output reg         result_sign_out,

    output reg  [7:0]  exponent_out,
    output reg [22:0]  fraction_out
);

    reg [23:0] mantissa;

    reg guard_bit;
    reg round_bit;
    reg sticky_bit;

    reg round_up;

    reg [24:0] rounded_ext;
    reg [23:0] rounded_mantissa;

    reg [26:0] round_value;
    reg [26:0] shifted_value;

    reg signed [11:0] work_exp;

    reg tiny_before_round;

    reg inexact_calc;
    reg overflow_calc;
    reg underflow_calc;

    reg [7:0] exponent_calc;
    reg [22:0] fraction_calc;

    integer shift_amount;


    //--------------------------------------------------------------------------
    // Shift right with Sticky jam
    //--------------------------------------------------------------------------

    function [26:0] shift_right_jam_27;

        input [26:0] value;
        input integer amount;

        reg [26:0] temp;
        reg sticky_local;

        integer j;

        begin

            temp = value;
            sticky_local = 1'b0;

            if (amount <= 0) begin

                shift_right_jam_27 = temp;

            end
            else if (amount < 27) begin

                for (j = 0; j < 27; j = j + 1) begin

                    if (j < amount)
                        sticky_local = sticky_local | temp[j];

                end

                temp = temp >> amount;
                temp[0] = temp[0] | sticky_local;

                shift_right_jam_27 = temp;

            end
            else begin

                shift_right_jam_27 = {26'h0000000, |temp};

            end

        end

    endfunction


    //--------------------------------------------------------------------------
    // Combinational rounding logic
    //--------------------------------------------------------------------------

    always @* begin

        mantissa = 24'h000000;

        guard_bit = 1'b0;
        round_bit = 1'b0;
        sticky_bit = 1'b0;

        round_up = 1'b0;

        rounded_ext = 25'h0000000;
        rounded_mantissa = 24'h000000;

        round_value = 27'h0000000;
        shifted_value = 27'h0000000;

        work_exp = exponent_in;

        tiny_before_round = 1'b0;

        // Special cases must not generate inexact.
        inexact_calc = 1'b0;

        overflow_calc = 1'b0;
        underflow_calc = 1'b0;

        exponent_calc = 8'h00;
        fraction_calc = 23'h000000;

        shift_amount = 0;

        // Process only a real finite division.
        if (valid_in && !special_case_in) begin

            // Stage 4 quotient:
            // [25]   = hidden bit
            // [24:2] = fraction
            // [1]    = Guard
            // [0]    = Round
            mantissa = quotient_in[25:2];
            guard_bit = quotient_in[1];
            round_bit = quotient_in[0];

            // Remainder provides Sticky.
            sticky_bit = (remainder_in != 24'h000000);

            // Complete G/R/S representation.
            round_value = {mantissa, guard_bit, round_bit, sticky_bit};

            // Initial inexact.
            inexact_calc = guard_bit | round_bit | sticky_bit;

            // Stage 4 already normalized the quotient.
            work_exp = exponent_in;

            // Determine whether result is below minimum normal exponent.
            tiny_before_round = (work_exp < -12'sd126);

            // Gradual underflow.
            if (tiny_before_round) begin

                shift_amount = -126 - work_exp;

                shifted_value = shift_right_jam_27(round_value, shift_amount);
                round_value = shifted_value;

            end

            // Extract G/R/S after possible subnormal shift.
            mantissa = round_value[26:3];
            guard_bit = round_value[2];
            round_bit = round_value[1];
            sticky_bit = round_value[0];

            // Recalculate inexact after the shift.
            inexact_calc = guard_bit | round_bit | sticky_bit;

            // Round-to-nearest-even.
            round_up = guard_bit && (round_bit || sticky_bit || mantissa[0]);

            // 25-bit addition keeps rounding carry.
            rounded_ext = {1'b0, mantissa} + {24'h000000, round_up};
            rounded_mantissa = rounded_ext[23:0];

            // SUBNORMAL RESULT
            if (tiny_before_round) begin

                // Tiny + inexact = underflow.
                underflow_calc = inexact_calc;

                // Subnormal promotion.
                if (rounded_ext[23]) begin

                    exponent_calc = 8'h01;
                    fraction_calc = 23'h000000;

                end
                else begin

                    exponent_calc = 8'h00;
                    fraction_calc = rounded_mantissa[22:0];

                end

            end

            // NORMAL RESULT
            else begin

                // Normal rounding carry.
                if (rounded_ext[24]) begin

                    rounded_mantissa = 24'h800000;
                    work_exp = work_exp + 12'sd1;

                end

                // Overflow after rounding.
                if (work_exp > 12'sd127) begin

                    exponent_calc = 8'hFF;
                    fraction_calc = 23'h000000;
                    overflow_calc = 1'b1;

                end
                else begin

                    exponent_calc = work_exp + 12'sd127;
                    fraction_calc = rounded_mantissa[22:0];

                end

            end

        end

    end


    //--------------------------------------------------------------------------
    // Pipeline register
    //--------------------------------------------------------------------------

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            valid_out <= 1'b0;

            special_case_out <= 1'b0;
            special_result_out <= 32'h00000000;

            overflow_out <= 1'b0;
            underflow_out <= 1'b0;

            div_by_zero_out <= 1'b0;
            invalid_out <= 1'b0;
            inexact_out <= 1'b0;

            result_sign_out <= 1'b0;

            exponent_out <= 8'h00;
            fraction_out <= 23'h000000;

        end
        else begin

            valid_out <= valid_in;

            special_case_out <= special_case_in;
            special_result_out <= special_result_in;

            result_sign_out <= result_sign_in;

            overflow_out <= overflow_calc;
            underflow_out <= underflow_calc;

            div_by_zero_out <= div_by_zero_in;
            invalid_out <= invalid_in;

            // Overflow is inexact.
            inexact_out <= inexact_calc || overflow_calc;

            exponent_out <= exponent_calc;
            fraction_out <= fraction_calc;

        end
    end

endmodule


//==============================================================
// STAGE 6
// IEEE-754 PACK + OUTPUT
//==============================================================

module fpu_div_stage6_pack (
    input wire         clk,
    input wire         rst_n,

    input wire         valid_in,

    input wire         special_case_in,
    input wire [31:0]  special_result_in,

    input wire         overflow_in,
    input wire         underflow_in,
    input wire         div_by_zero_in,
    input wire         invalid_in,
    input wire         inexact_in,

    input wire         result_sign_in,

    input wire  [7:0]  exponent_in,
    input wire [22:0]  fraction_in,

    output reg         valid_out,

    output reg  [31:0] result,

    output reg         overflow,
    output reg         underflow,
    output reg         div_by_zero,
    output reg         invalid,
    output reg         inexact
);

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            valid_out <= 1'b0;

            result <= 32'h00000000;

            overflow <= 1'b0;
            underflow <= 1'b0;
            div_by_zero <= 1'b0;
            invalid <= 1'b0;
            inexact <= 1'b0;

        end
        else begin

            valid_out <= valid_in;

            overflow <= overflow_in;
            underflow <= underflow_in;
            div_by_zero <= div_by_zero_in;
            invalid <= invalid_in;
            inexact <= inexact_in;

            if (valid_in) begin

                if (special_case_in) begin

                    result <= special_result_in;

                end
                else begin

                    result <= {result_sign_in, exponent_in, fraction_in};

                end

            end
            else begin

                result <= 32'h00000000;

            end

        end
    end

endmodule


//==============================================================
// TOP MODULE
//==============================================================

module FPU_div (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        enable,

    input  wire        clk,
    input  wire        rst_n,

    output wire [31:0] result,

    output wire        overflow,
    output wire        underflow,
    output wire        div_by_zero,
    output wire        invalid,
    output wire        inexact,

    output wire        valid_out
);


    //==========================================================
    // S1 SIGNALS
    //==========================================================

    wire        s1_valid;

    wire        s1_sign_a;
    wire        s1_sign_b;

    wire [7:0]  s1_exp_a;
    wire [7:0]  s1_exp_b;

    wire [22:0] s1_frac_a;
    wire [22:0] s1_frac_b;

    wire        s1_zero_a;
    wire        s1_zero_b;

    wire        s1_denorm_a;
    wire        s1_denorm_b;

    wire        s1_inf_a;
    wire        s1_inf_b;

    wire        s1_nan_a;
    wire        s1_nan_b;


    //==========================================================
    // S2 SIGNALS
    //==========================================================

    wire        s2_valid;

    wire        s2_special;
    wire [31:0] s2_special_result;

    wire        s2_div_by_zero;
    wire        s2_invalid;

    wire        s2_sign;

    wire [7:0]  s2_exp_a;
    wire [7:0]  s2_exp_b;

    wire [22:0] s2_frac_a;
    wire [22:0] s2_frac_b;

    wire        s2_zero_a;
    wire        s2_zero_b;

    wire        s2_denorm_a;
    wire        s2_denorm_b;

    wire        s2_inf_a;
    wire        s2_inf_b;

    wire        s2_nan_a;
    wire        s2_nan_b;


    //==========================================================
    // S3 SIGNALS
    //==========================================================

    wire        s3_valid;

    wire        s3_special;
    wire [31:0] s3_special_result;

    wire        s3_div_by_zero;
    wire        s3_invalid;

    wire        s3_sign;

    wire [23:0] s3_sig_a;
    wire [23:0] s3_sig_b;

    wire signed [11:0] s3_exponent;


    //==========================================================
    // S4 SIGNALS
    //==========================================================

    wire        s4_valid;

    wire        s4_special;
    wire [31:0] s4_special_result;

    wire        s4_div_by_zero;
    wire        s4_invalid;

    wire        s4_sign;

    wire [32:0] s4_quotient;
    wire [23:0] s4_remainder;

    wire signed [11:0] s4_exponent;


    //==========================================================
    // S5 SIGNALS
    //==========================================================

    wire        s5_valid;

    wire        s5_special;
    wire [31:0] s5_special_result;

    wire        s5_overflow;
    wire        s5_underflow;
    wire        s5_div_by_zero;
    wire        s5_invalid;
    wire        s5_inexact;

    wire        s5_sign;

    wire [7:0]  s5_exponent;
    wire [22:0] s5_fraction;


    //==========================================================
    // STAGE 1
    //==========================================================

    fpu_div_stage1_unpack u_stage1 (
        .clk          (clk),
        .rst_n        (rst_n),
        .enable       (enable),
        .a            (a),
        .b            (b),
        .valid_out    (s1_valid),
        .sign_a       (s1_sign_a),
        .sign_b       (s1_sign_b),
        .exp_a        (s1_exp_a),
        .exp_b        (s1_exp_b),
        .frac_a       (s1_frac_a),
        .frac_b       (s1_frac_b),
        .is_zero_a    (s1_zero_a),
        .is_zero_b    (s1_zero_b),
        .is_denorm_a  (s1_denorm_a),
        .is_denorm_b  (s1_denorm_b),
        .is_inf_a     (s1_inf_a),
        .is_inf_b     (s1_inf_b),
        .is_nan_a     (s1_nan_a),
        .is_nan_b     (s1_nan_b)
    );


    //==========================================================
    // STAGE 2
    //==========================================================

    fpu_div_stage2_special u_stage2 (
        .clk              (clk),
        .rst_n            (rst_n),
        .valid_in         (s1_valid),
        .sign_a           (s1_sign_a),
        .sign_b           (s1_sign_b),
        .exp_a            (s1_exp_a),
        .exp_b            (s1_exp_b),
        .frac_a           (s1_frac_a),
        .frac_b           (s1_frac_b),
        .is_zero_a        (s1_zero_a),
        .is_zero_b        (s1_zero_b),
        .is_denorm_a      (s1_denorm_a),
        .is_denorm_b      (s1_denorm_b),
        .is_inf_a         (s1_inf_a),
        .is_inf_b         (s1_inf_b),
        .is_nan_a         (s1_nan_a),
        .is_nan_b         (s1_nan_b),
        .valid_out        (s2_valid),
        .special_case     (s2_special),
        .special_result   (s2_special_result),
        .div_by_zero      (s2_div_by_zero),
        .invalid          (s2_invalid),
        .result_sign      (s2_sign),
        .exp_a_out        (s2_exp_a),
        .exp_b_out        (s2_exp_b),
        .frac_a_out       (s2_frac_a),
        .frac_b_out       (s2_frac_b),
        .is_zero_a_out    (s2_zero_a),
        .is_zero_b_out    (s2_zero_b),
        .is_denorm_a_out  (s2_denorm_a),
        .is_denorm_b_out  (s2_denorm_b),
        .is_inf_a_out     (s2_inf_a),
        .is_inf_b_out     (s2_inf_b),
        .is_nan_a_out     (s2_nan_a),
        .is_nan_b_out     (s2_nan_b)
    );


    //==========================================================
    // STAGE 3
    //==========================================================

    fpu_div_stage3_prepare u_stage3 (
        .clk                (clk),
        .rst_n              (rst_n),
        .valid_in           (s2_valid),
        .special_case_in    (s2_special),
        .special_result_in  (s2_special_result),
        .div_by_zero_in     (s2_div_by_zero),
        .invalid_in         (s2_invalid),
        .result_sign_in     (s2_sign),
        .exp_a              (s2_exp_a),
        .exp_b              (s2_exp_b),
        .frac_a             (s2_frac_a),
        .frac_b             (s2_frac_b),
        .is_zero_a          (s2_zero_a),
        .is_zero_b          (s2_zero_b),
        .is_denorm_a        (s2_denorm_a),
        .is_denorm_b        (s2_denorm_b),
        .is_inf_a           (s2_inf_a),
        .is_inf_b           (s2_inf_b),
        .is_nan_a           (s2_nan_a),
        .is_nan_b           (s2_nan_b),
        .valid_out          (s3_valid),
        .special_case_out   (s3_special),
        .special_result_out (s3_special_result),
        .div_by_zero_out    (s3_div_by_zero),
        .invalid_out        (s3_invalid),
        .result_sign_out    (s3_sign),
        .significand_a      (s3_sig_a),
        .significand_b      (s3_sig_b),
        .exponent_out       (s3_exponent)
    );


    //==========================================================
    // STAGE 4
    //==========================================================

    fpu_div_stage4_divide u_stage4 (
        .clk                (clk),
        .rst_n              (rst_n),
        .valid_in           (s3_valid),
        .special_case_in    (s3_special),
        .special_result_in  (s3_special_result),
        .div_by_zero_in     (s3_div_by_zero),
        .invalid_in         (s3_invalid),
        .result_sign_in     (s3_sign),
        .significand_a      (s3_sig_a),
        .significand_b      (s3_sig_b),
        .exponent_in        (s3_exponent),
        .valid_out          (s4_valid),
        .special_case_out   (s4_special),
        .special_result_out (s4_special_result),
        .div_by_zero_out    (s4_div_by_zero),
        .invalid_out        (s4_invalid),
        .result_sign_out    (s4_sign),
        .quotient_out       (s4_quotient),
        .remainder_out      (s4_remainder),
        .exponent_out       (s4_exponent)
    );


    //==========================================================
    // STAGE 5
    //==========================================================

    fpu_div_stage5_round u_stage5 (
        .clk                (clk),
        .rst_n              (rst_n),
        .valid_in           (s4_valid),
        .special_case_in    (s4_special),
        .special_result_in  (s4_special_result),
        .div_by_zero_in     (s4_div_by_zero),
        .invalid_in         (s4_invalid),
        .result_sign_in     (s4_sign),
        .quotient_in        (s4_quotient),
        .remainder_in       (s4_remainder),
        .exponent_in        (s4_exponent),
        .valid_out          (s5_valid),
        .special_case_out   (s5_special),
        .special_result_out (s5_special_result),
        .overflow_out       (s5_overflow),
        .underflow_out      (s5_underflow),
        .div_by_zero_out    (s5_div_by_zero),
        .invalid_out        (s5_invalid),
        .inexact_out        (s5_inexact),
        .result_sign_out    (s5_sign),
        .exponent_out       (s5_exponent),
        .fraction_out       (s5_fraction)
    );


    //==========================================================
    // STAGE 6
    //==========================================================

    fpu_div_stage6_pack u_stage6 (
        .clk                (clk),
        .rst_n              (rst_n),
        .valid_in           (s5_valid),
        .special_case_in    (s5_special),
        .special_result_in  (s5_special_result),
        .overflow_in        (s5_overflow),
        .underflow_in       (s5_underflow),
        .div_by_zero_in     (s5_div_by_zero),
        .invalid_in         (s5_invalid),
        .inexact_in         (s5_inexact),
        .result_sign_in     (s5_sign),
        .exponent_in        (s5_exponent),
        .fraction_in        (s5_fraction),
        .valid_out          (valid_out),
        .result             (result),
        .overflow           (overflow),
        .underflow          (underflow),
        .div_by_zero        (div_by_zero),
        .invalid            (invalid),
        .inexact            (inexact)
    );

endmodule
