// =============================================================================
// File: fpu_div.v
// Module: FPU_div
// Description: 6-Stage Pipelined IEEE-754 Single-Precision Floating-Point
//              Divider supporting Normal numbers, Subnormals, Zeros,
//              Infinities, NaNs, and Round-to-Nearest-Even (RNE).
// =============================================================================

`timescale 1ns / 1ps

`define FP_ZERO 3'd0
`define FP_SUB  3'd1
`define FP_NORM 3'd2
`define FP_INF  3'd3
`define FP_NAN  3'd4

`define CANONICAL_NAN 32'h7FC00000

// =============================================================================
// Top-Level Module: FPU_div
// =============================================================================
module FPU_div (
    input  wire        clk,
    input  wire        rst_n,     // Asynchronous active-low reset
    input  wire        enable,    // Transaction valid in

    input  wire [31:0] a,         // IEEE-754 single-precision dividend
    input  wire [31:0] b,         // IEEE-754 single-precision divisor

    output wire [31:0] result,    // IEEE-754 single-precision quotient
    output wire        valid_out, // Transaction valid out (latency = 6 cycles)

    output wire        overflow,  // Overflow exception flag
    output wire        underflow, // Underflow exception flag
    output wire        div_by_zero, // Division-by-zero flag
    output wire        invalid,   // Invalid operation flag
    output wire        inexact    // Inexact exception flag
);

    // -------------------------------------------------------------------------
    // Internal Pipeline Wires
    // -------------------------------------------------------------------------
    // Stage 1 -> Stage 2
    wire        s1_valid;
    wire        s1_sign_a, s1_sign_b;
    wire [7:0]  s1_exp_a, s1_exp_b;
    wire [22:0] s1_frac_a, s1_frac_b;
    wire [2:0]  s1_class_a, s1_class_b;

    // Stage 2 -> Stage 3
    wire        s2_valid;
    wire        s2_special;
    wire [31:0] s2_special_result;
    wire        s2_div_by_zero, s2_invalid;
    wire        s2_sign;
    wire [7:0]  s2_exp_a, s2_exp_b;
    wire [22:0] s2_frac_a, s2_frac_b;
    wire [2:0]  s2_class_a, s2_class_b;

    // Stage 3 -> Stage 4
    wire        s3_valid;
    wire        s3_special;
    wire [31:0] s3_special_result;
    wire        s3_div_by_zero, s3_invalid;
    wire        s3_sign;
    wire [23:0] s3_sig_a, s3_sig_b;
    wire signed [11:0] s3_exponent;

    // Stage 4 -> Stage 5
    wire        s4_valid;
    wire        s4_special;
    wire [31:0] s4_special_result;
    wire        s4_div_by_zero, s4_invalid;
    wire        s4_sign;
    wire [32:0] s4_quotient;
    wire [23:0] s4_remainder;
    wire        s4_subnormal_direct;
    wire [23:0] s4_subnormal_mantissa;
    wire        s4_subnormal_inexact;
    wire signed [11:0] s4_exponent;

    // Stage 5 -> Stage 6
    wire        s5_valid;
    wire        s5_special;
    wire [31:0] s5_special_result;
    wire        s5_overflow, s5_underflow, s5_div_by_zero, s5_invalid, s5_inexact;
    wire        s5_sign;
    wire [7:0]  s5_exponent;
    wire [22:0] s5_fraction;

    // -------------------------------------------------------------------------
    // Stage 1: Unpack and Classify Operands
    // -------------------------------------------------------------------------
    fpu_div_stage1_unpack u_stage1 (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (enable),
        .a          (a),
        .b          (b),
        .valid_out  (s1_valid),
        .sign_a     (s1_sign_a),
        .sign_b     (s1_sign_b),
        .exp_a      (s1_exp_a),
        .exp_b      (s1_exp_b),
        .frac_a     (s1_frac_a),
        .frac_b     (s1_frac_b),
        .class_a    (s1_class_a),
        .class_b    (s1_class_b)
    );

    // -------------------------------------------------------------------------
    // Stage 2: Special Cases and Result Sign Detection
    // -------------------------------------------------------------------------
    fpu_div_stage2_special u_stage2 (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid_in       (s1_valid),
        .sign_a         (s1_sign_a),
        .sign_b         (s1_sign_b),
        .exp_a          (s1_exp_a),
        .exp_b          (s1_exp_b),
        .frac_a         (s1_frac_a),
        .frac_b         (s1_frac_b),
        .class_a        (s1_class_a),
        .class_b        (s1_class_b),
        .valid_out      (s2_valid),
        .special_case   (s2_special),
        .special_result (s2_special_result),
        .div_by_zero    (s2_div_by_zero),
        .invalid        (s2_invalid),
        .result_sign    (s2_sign),
        .exp_a_out      (s2_exp_a),
        .exp_b_out      (s2_exp_b),
        .frac_a_out     (s2_frac_a),
        .frac_b_out     (s2_frac_b),
        .class_a_out    (s2_class_a),
        .class_b_out    (s2_class_b)
    );

    // -------------------------------------------------------------------------
    // Stage 3: Significand Alignment and Exponent Calculation
    // -------------------------------------------------------------------------
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
        .class_a            (s2_class_a),
        .class_b            (s2_class_b),
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

    // -------------------------------------------------------------------------
    // Stage 4: Long Division Core and Subnormal Evaluation
    // -------------------------------------------------------------------------
    fpu_div_stage4_divide u_stage4 (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .valid_in               (s3_valid),
        .special_case_in        (s3_special),
        .special_result_in      (s3_special_result),
        .div_by_zero_in         (s3_div_by_zero),
        .invalid_in             (s3_invalid),
        .result_sign_in         (s3_sign),
        .significand_a          (s3_sig_a),
        .significand_b          (s3_sig_b),
        .exponent_in            (s3_exponent),
        .valid_out              (s4_valid),
        .special_case_out       (s4_special),
        .special_result_out     (s4_special_result),
        .div_by_zero_out        (s4_div_by_zero),
        .invalid_out            (s4_invalid),
        .result_sign_out        (s4_sign),
        .quotient_out           (s4_quotient),
        .remainder_out          (s4_remainder),
        .subnormal_direct_out   (s4_subnormal_direct),
        .subnormal_mantissa_out (s4_subnormal_mantissa),
        .subnormal_inexact_out  (s4_subnormal_inexact),
        .exponent_out           (s4_exponent)
    );

    // -------------------------------------------------------------------------
    // Stage 5: Normalization, Round-to-Nearest-Even, and Exceptions
    // -------------------------------------------------------------------------
    fpu_div_stage5_round u_stage5 (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .valid_in               (s4_valid),
        .special_case_in        (s4_special),
        .special_result_in      (s4_special_result),
        .div_by_zero_in         (s4_div_by_zero),
        .invalid_in             (s4_invalid),
        .result_sign_in         (s4_sign),
        .quotient_in            (s4_quotient),
        .remainder_in           (s4_remainder),
        .subnormal_direct_in    (s4_subnormal_direct),
        .subnormal_mantissa_in  (s4_subnormal_mantissa),
        .subnormal_inexact_in   (s4_subnormal_inexact),
        .exponent_in            (s4_exponent),
        .valid_out              (s5_valid),
        .special_case_out       (s5_special),
        .special_result_out     (s5_special_result),
        .overflow_out           (s5_overflow),
        .underflow_out          (s5_underflow),
        .div_by_zero_out        (s5_div_by_zero),
        .invalid_out            (s5_invalid),
        .inexact_out            (s5_inexact),
        .result_sign_out        (s5_sign),
        .exponent_out           (s5_exponent),
        .fraction_out           (s5_fraction)
    );

    // -------------------------------------------------------------------------
    // Stage 6: IEEE-754 Output Formatting and Packing
    // -------------------------------------------------------------------------
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


// =============================================================================
// Stage 1: Unpack and Classify Operands
// =============================================================================
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
    output reg  [2:0]  class_a,
    output reg  [2:0]  class_b
);

    function [2:0] classify_fp;
        input [7:0]  exponent;
        input [22:0] fraction;
        begin
            if (exponent == 8'h00) begin
                if (fraction == 23'd0)
                    classify_fp = `FP_ZERO;
                else
                    classify_fp = `FP_SUB;
            end
            else if (exponent == 8'hFF) begin
                if (fraction == 23'd0)
                    classify_fp = `FP_INF;
                else
                    classify_fp = `FP_NAN;
            end
            else begin
                classify_fp = `FP_NORM;
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            sign_a    <= 1'b0;
            sign_b    <= 1'b0;
            exp_a     <= 8'h00;
            exp_b     <= 8'h00;
            frac_a    <= 23'd0;
            frac_b    <= 23'd0;
            class_a   <= `FP_ZERO;
            class_b   <= `FP_ZERO;
        end
        else begin
            valid_out <= enable;
            sign_a    <= a[31];
            sign_b    <= b[31];
            exp_a     <= a[30:23];
            exp_b     <= b[30:23];
            frac_a    <= a[22:0];
            frac_b    <= b[22:0];
            class_a   <= classify_fp(a[30:23], a[22:0]);
            class_b   <= classify_fp(b[30:23], b[22:0]);
        end
    end

endmodule


// =============================================================================
// Stage 2: Special Cases and Result Sign Detection
// =============================================================================
module fpu_div_stage2_special (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        valid_in,
    input  wire        sign_a,
    input  wire        sign_b,
    input  wire  [7:0] exp_a,
    input  wire  [7:0] exp_b,
    input  wire [22:0] frac_a,
    input  wire [22:0] frac_b,
    input  wire  [2:0] class_a,
    input  wire  [2:0] class_b,

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
    output reg  [2:0]  class_a_out,
    output reg  [2:0]  class_b_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out      <= 1'b0;
            special_case   <= 1'b0;
            special_result <= 32'd0;
            div_by_zero    <= 1'b0;
            invalid        <= 1'b0;
            result_sign    <= 1'b0;
            exp_a_out      <= 8'h00;
            exp_b_out      <= 8'h00;
            frac_a_out     <= 23'd0;
            frac_b_out     <= 23'd0;
            class_a_out    <= `FP_ZERO;
            class_b_out    <= `FP_ZERO;
        end
        else begin
            valid_out      <= valid_in;
            special_case   <= 1'b0;
            special_result <= 32'd0;
            div_by_zero    <= 1'b0;
            invalid        <= 1'b0;
            result_sign    <= sign_a ^ sign_b;

            exp_a_out      <= exp_a;
            exp_b_out      <= exp_b;
            frac_a_out     <= frac_a;
            frac_b_out     <= frac_b;
            class_a_out    <= class_a;
            class_b_out    <= class_b;

            if (valid_in) begin
                if ((class_a == `FP_NAN) || (class_b == `FP_NAN)) begin
                    special_case   <= 1'b1;
                    special_result <= `CANONICAL_NAN;
                    invalid        <= 1'b1;
                end
                else if ((class_a == `FP_INF) && (class_b == `FP_INF)) begin
                    special_case   <= 1'b1;
                    special_result <= `CANONICAL_NAN;
                    invalid        <= 1'b1;
                end
                else if ((class_a == `FP_ZERO) && (class_b == `FP_ZERO)) begin
                    special_case   <= 1'b1;
                    special_result <= `CANONICAL_NAN;
                    invalid        <= 1'b1;
                end
                else if ((class_a == `FP_INF) && (class_b == `FP_ZERO)) begin
                    special_case   <= 1'b1;
                    special_result <= {sign_a ^ sign_b, 8'hFF, 23'd0};
                end
                else if (((class_a == `FP_NORM) || (class_a == `FP_SUB)) && (class_b == `FP_ZERO)) begin
                    special_case   <= 1'b1;
                    special_result <= {sign_a ^ sign_b, 8'hFF, 23'd0};
                    div_by_zero    <= 1'b1;
                end
                else if ((class_a == `FP_INF) && ((class_b == `FP_NORM) || (class_b == `FP_SUB))) begin
                    special_case   <= 1'b1;
                    special_result <= {sign_a ^ sign_b, 8'hFF, 23'd0};
                end
                else if (class_a == `FP_ZERO) begin
                    special_case   <= 1'b1;
                    special_result <= {sign_a ^ sign_b, 8'h00, 23'd0};
                end
                else if (((class_a == `FP_NORM) || (class_a == `FP_SUB)) && (class_b == `FP_INF)) begin
                    special_case   <= 1'b1;
                    special_result <= {sign_a ^ sign_b, 8'h00, 23'd0};
                end
            end
        end
    end

endmodule


// =============================================================================
// Stage 3: Significand Alignment and Exponent Calculation
// =============================================================================
module fpu_div_stage3_prepare (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        valid_in,
    input  wire        special_case_in,
    input  wire [31:0] special_result_in,
    input  wire        div_by_zero_in,
    input  wire        invalid_in,
    input  wire        result_sign_in,

    input  wire  [7:0] exp_a,
    input  wire  [7:0] exp_b,
    input  wire [22:0] frac_a,
    input  wire [22:0] frac_b,
    input  wire  [2:0] class_a,
    input  wire  [2:0] class_b,

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
    integer highest_a, highest_b;
    integer shift_a, shift_b;
    reg     found_a, found_b;

    always @* begin
        sig_a_next = 24'd0;
        sig_b_next = 24'd0;
        exp_a_next = 12'sd0;
        exp_b_next = 12'sd0;
        highest_a  = 0;
        highest_b  = 0;
        shift_a    = 0;
        shift_b    = 0;
        found_a    = 1'b0;
        found_b    = 1'b0;

        if (class_a == `FP_NORM) begin
            sig_a_next = {1'b1, frac_a};
            exp_a_next = $signed({1'b0, exp_a}) - 12'sd127;
        end
        else if (class_a == `FP_SUB) begin
            for (i = 22; i >= 0; i = i - 1) begin
                if (!found_a && frac_a[i]) begin
                    highest_a = i;
                    found_a   = 1'b1;
                end
            end
            shift_a    = 23 - highest_a;
            sig_a_next = {1'b0, frac_a} << shift_a;
            exp_a_next = highest_a - 12'sd149;
        end

        if (class_b == `FP_NORM) begin
            sig_b_next = {1'b1, frac_b};
            exp_b_next = $signed({1'b0, exp_b}) - 12'sd127;
        end
        else if (class_b == `FP_SUB) begin
            for (i = 22; i >= 0; i = i - 1) begin
                if (!found_b && frac_b[i]) begin
                    highest_b = i;
                    found_b   = 1'b1;
                end
            end
            shift_b    = 23 - highest_b;
            sig_b_next = {1'b0, frac_b} << shift_b;
            exp_b_next = highest_b - 12'sd149;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out          <= 1'b0;
            special_case_out   <= 1'b0;
            special_result_out <= 32'd0;
            div_by_zero_out    <= 1'b0;
            invalid_out        <= 1'b0;
            result_sign_out    <= 1'b0;
            significand_a      <= 24'd0;
            significand_b      <= 24'd0;
            exponent_out       <= 12'sd0;
        end
        else begin
            valid_out          <= valid_in;
            special_case_out   <= special_case_in;
            special_result_out <= special_result_in;
            div_by_zero_out    <= div_by_zero_in;
            invalid_out        <= invalid_in;
            result_sign_out    <= result_sign_in;
            significand_a      <= sig_a_next;
            significand_b      <= sig_b_next;
            exponent_out       <= exp_a_next - exp_b_next;
        end
    end

endmodule


// =============================================================================
// Stage 4: Long Division Core and Subnormal Evaluation
// =============================================================================
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

    output reg         subnormal_direct_out,
    output reg  [23:0] subnormal_mantissa_out,
    output reg         subnormal_inexact_out,
    output reg signed [11:0] exponent_out
);

    reg [50:0] quotient_work;
    reg [24:0] remainder_work;
    reg        input_bit;

    reg        subnormal_direct_work;
    reg [23:0] subnormal_mantissa_work;
    reg        subnormal_inexact_work;

    reg [46:0] subnormal_numerator;
    reg [46:0] subnormal_quotient;
    reg [24:0] subnormal_remainder;
    reg [24:0] subnormal_twice_remainder;

    reg [150:0] scaled_divisor;
    reg [150:0] scaled_twice_a;

    integer subnormal_shift;
    integer i, j;

    always @* begin
        quotient_work             = 51'd0;
        remainder_work            = 25'd0;
        input_bit                 = 1'b0;

        subnormal_direct_work     = 1'b0;
        subnormal_mantissa_work   = 24'd0;
        subnormal_inexact_work    = 1'b0;

        subnormal_numerator       = 47'd0;
        subnormal_quotient        = 47'd0;
        subnormal_remainder       = 25'd0;
        subnormal_twice_remainder = 25'd0;

        scaled_divisor            = 151'd0;
        scaled_twice_a            = 151'd0;

        subnormal_shift           = 0;

        if (valid_in && !special_case_in) begin
            for (i = 0; i < 51; i = i + 1) begin
                if (i < 24)
                    input_bit = significand_a[23-i];
                else
                    input_bit = 1'b0;

                remainder_work = {remainder_work[23:0], input_bit};

                if (remainder_work >= {1'b0, significand_b}) begin
                    remainder_work = remainder_work - {1'b0, significand_b};
                    quotient_work  = {quotient_work[49:0], 1'b1};
                end
                else begin
                    quotient_work  = {quotient_work[49:0], 1'b0};
                end
            end

            if ((exponent_in < -12'sd126) || ((exponent_in == -12'sd126) && (significand_a < significand_b))) begin
                subnormal_direct_work = 1'b1;
                subnormal_shift       = exponent_in + 12'sd149;

                if (subnormal_shift >= 0) begin
                    subnormal_numerator = {23'd0, significand_a} << subnormal_shift;
                    subnormal_quotient  = 47'd0;
                    subnormal_remainder = 25'd0;

                    for (j = 46; j >= 0; j = j - 1) begin
                        subnormal_remainder = {subnormal_remainder[23:0], subnormal_numerator[j]};

                        if (subnormal_remainder >= {1'b0, significand_b}) begin
                            subnormal_remainder   = subnormal_remainder - {1'b0, significand_b};
                            subnormal_quotient[j] = 1'b1;
                        end
                        else begin
                            subnormal_quotient[j] = 1'b0;
                        end
                    end

                    subnormal_twice_remainder = subnormal_remainder << 1;

                    if ((subnormal_twice_remainder > {1'b0, significand_b}) ||
                        ((subnormal_twice_remainder == {1'b0, significand_b}) && subnormal_quotient[0])) begin
                        subnormal_mantissa_work = subnormal_quotient[23:0] + 24'd1;
                    end
                    else begin
                        subnormal_mantissa_work = subnormal_quotient[23:0];
                    end

                    subnormal_inexact_work = (subnormal_remainder != 25'd0);
                end
                else begin
                    scaled_divisor = {127'd0, significand_b} << (-subnormal_shift);
                    scaled_twice_a = {127'd0, significand_a} << 1;

                    if (scaled_twice_a > scaled_divisor)
                        subnormal_mantissa_work = 24'd1;
                    else
                        subnormal_mantissa_work = 24'd0;

                    subnormal_inexact_work = 1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out              <= 1'b0;
            special_case_out       <= 1'b0;
            special_result_out     <= 32'd0;
            div_by_zero_out        <= 1'b0;
            invalid_out            <= 1'b0;
            result_sign_out        <= 1'b0;
            quotient_out           <= 33'd0;
            remainder_out          <= 24'd0;
            subnormal_direct_out   <= 1'b0;
            subnormal_mantissa_out <= 24'd0;
            subnormal_inexact_out  <= 1'b0;
            exponent_out           <= 12'sd0;
        end
        else begin
            valid_out              <= valid_in;
            special_case_out       <= special_case_in;
            special_result_out     <= special_result_in;
            div_by_zero_out        <= div_by_zero_in;
            invalid_out            <= invalid_in;
            result_sign_out        <= result_sign_in;

            quotient_out           <= {quotient_work[27:0], 5'b00000};
            remainder_out          <= remainder_work[23:0];
            subnormal_direct_out   <= subnormal_direct_work;
            subnormal_mantissa_out <= subnormal_mantissa_work;
            subnormal_inexact_out  <= subnormal_inexact_work;
            exponent_out           <= exponent_in;
        end
    end

endmodule


// =============================================================================
// Stage 5: Normalization, Round-to-Nearest-Even, and Exceptions
// =============================================================================
module fpu_div_stage5_round (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        valid_in,
    input  wire        special_case_in,
    input  wire [31:0] special_result_in,
    input  wire        div_by_zero_in,
    input  wire        invalid_in,
    input  wire        result_sign_in,

    input  wire [32:0] quotient_in,
    input  wire [23:0] remainder_in,

    input  wire        subnormal_direct_in,
    input  wire [23:0] subnormal_mantissa_in,
    input  wire        subnormal_inexact_in,

    input  wire signed [11:0] exponent_in,

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

    reg [32:0]        normalized_q;
    reg signed [11:0] work_exp;
    reg [23:0]        mantissa;
    reg               guard_bit, round_bit, sticky_bit;
    reg               round_up;
    reg [24:0]        rounded_ext;
    reg [23:0]        rounded_mantissa;
    reg [26:0]        round_value;
    reg [26:0]        shifted_value;
    reg               tiny_before_round;
    reg               inexact_calc;
    reg               overflow_calc, underflow_calc;
    reg [7:0]         exponent_calc;
    reg [22:0]        fraction_calc;
    integer           shift_amount;

    function [26:0] shift_right_jam_27;
        input [26:0] value;
        input integer amount;
        reg [26:0]   temp;
        reg          sticky_local;
        integer      j;
        begin
            temp         = value;
            sticky_local = 1'b0;

            if (amount <= 0) begin
                shift_right_jam_27 = temp;
            end
            else if (amount < 27) begin
                for (j = 0; j < 27; j = j + 1) begin
                    if (j < amount)
                        sticky_local = sticky_local | temp[j];
                end
                temp               = temp >> amount;
                temp[0]            = temp[0] | sticky_local;
                shift_right_jam_27 = temp;
            end
            else begin
                shift_right_jam_27 = {26'd0, |temp};
            end
        end
    endfunction

    always @* begin
        normalized_q      = quotient_in;
        work_exp          = exponent_in;
        mantissa          = 24'd0;
        guard_bit         = 1'b0;
        round_bit         = 1'b0;
        sticky_bit        = 1'b0;
        round_up          = 1'b0;
        rounded_ext       = 25'd0;
        rounded_mantissa  = 24'd0;
        round_value       = 27'd0;
        shifted_value     = 27'd0;
        tiny_before_round = 1'b0;
        inexact_calc      = 1'b0;
        overflow_calc     = 1'b0;
        underflow_calc    = 1'b0;
        exponent_calc     = 8'd0;
        fraction_calc     = 23'd0;
        shift_amount      = 0;

        if (valid_in && !special_case_in) begin
            if (subnormal_direct_in) begin
                exponent_calc  = 8'h00;
                fraction_calc  = subnormal_mantissa_in[22:0];
                inexact_calc   = subnormal_inexact_in;
                underflow_calc = subnormal_inexact_in;

                if (subnormal_mantissa_in[23]) begin
                    exponent_calc = 8'h01;
                    fraction_calc = 23'd0;
                end
            end
            else begin
                if (!normalized_q[32]) begin
                    normalized_q = normalized_q << 1;
                    work_exp     = work_exp - 12'sd1;
                end

                mantissa   = {1'b1, normalized_q[31:9]};
                guard_bit  = normalized_q[8];
                round_bit  = normalized_q[7];
                sticky_bit = (|normalized_q[6:0]) || (remainder_in != 24'd0);

                round_value       = {mantissa, guard_bit, round_bit, sticky_bit};
                tiny_before_round = (work_exp < -12'sd126);

                if (tiny_before_round) begin
                    shift_amount  = -126 - work_exp;
                    shifted_value = shift_right_jam_27(round_value, shift_amount);
                    round_value   = shifted_value;
                end

                mantissa   = round_value[26:3];
                guard_bit  = round_value[2];
                round_bit  = round_value[1];
                sticky_bit = round_value[0];

                inexact_calc     = guard_bit || round_bit || sticky_bit;
                round_up         = guard_bit && (round_bit || sticky_bit || mantissa[0]);
                rounded_ext      = {1'b0, mantissa} + {24'd0, round_up};
                rounded_mantissa = rounded_ext[23:0];

                if (tiny_before_round) begin
                    underflow_calc = inexact_calc;
                    if (rounded_ext[24]) begin
                        exponent_calc = 8'h01;
                        fraction_calc = 23'd0;
                    end
                    else begin
                        exponent_calc = 8'h00;
                        fraction_calc = rounded_mantissa[22:0];
                    end
                end
                else begin
                    if (rounded_ext[24]) begin
                        rounded_mantissa = 24'h800000;
                        work_exp         = work_exp + 12'sd1;
                    end

                    if (work_exp > 12'sd127) begin
                        exponent_calc = 8'hFF;
                        fraction_calc = 23'd0;
                        overflow_calc = 1'b1;
                    end
                    else begin
                        exponent_calc = work_exp + 12'sd127;
                        fraction_calc = rounded_mantissa[22:0];
                    end
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out          <= 1'b0;
            special_case_out   <= 1'b0;
            special_result_out <= 32'd0;
            overflow_out       <= 1'b0;
            underflow_out      <= 1'b0;
            div_by_zero_out    <= 1'b0;
            invalid_out        <= 1'b0;
            inexact_out        <= 1'b0;
            result_sign_out    <= 1'b0;
            exponent_out       <= 8'h00;
            fraction_out       <= 23'd0;
        end
        else begin
            valid_out          <= valid_in;
            special_case_out   <= special_case_in;
            special_result_out <= special_result_in;
            result_sign_out    <= result_sign_in;

            overflow_out       <= overflow_calc;
            underflow_out      <= underflow_calc;
            div_by_zero_out    <= div_by_zero_in;
            invalid_out        <= invalid_in;
            inexact_out        <= inexact_calc || overflow_calc;
            exponent_out       <= exponent_calc;
            fraction_out       <= fraction_calc;
        end
    end

endmodule


// =============================================================================
// Stage 6: IEEE-754 Output Formatting and Packing
// =============================================================================
module fpu_div_stage6_pack (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        valid_in,
    input  wire        special_case_in,
    input  wire [31:0] special_result_in,
    input  wire        overflow_in,
    input  wire        underflow_in,
    input  wire        div_by_zero_in,
    input  wire        invalid_in,
    input  wire        inexact_in,
    input  wire        result_sign_in,

    input  wire  [7:0] exponent_in,
    input  wire [22:0] fraction_in,

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
            valid_out   <= 1'b0;
            result      <= 32'd0;
            overflow    <= 1'b0;
            underflow   <= 1'b0;
            div_by_zero <= 1'b0;
            invalid     <= 1'b0;
            inexact     <= 1'b0;
        end
        else begin
            valid_out   <= valid_in;
            overflow    <= overflow_in;
            underflow   <= underflow_in;
            div_by_zero <= div_by_zero_in;
            invalid     <= invalid_in;
            inexact     <= inexact_in;

            if (valid_in) begin
                if (special_case_in) begin
                    result <= special_result_in;
                end
                else begin
                    result <= {result_sign_in, exponent_in, fraction_in};
                end
            end
            else begin
                result <= 32'd0;
            end
        end
    end

endmodule
