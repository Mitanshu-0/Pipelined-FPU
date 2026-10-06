// =============================================================================
// File: fpu_mul.v
// Module: FPU_mul_pipeline
// Description: 6-Stage Pipelined IEEE-754 Single-Precision Floating-Point
//              Multiplier supporting Normal numbers, Subnormals, Zeros,
//              Infinities, NaNs, and Round-to-Nearest-Even (RNE).
// =============================================================================

`timescale 1ns / 1ps

// =============================================================================
// Top-Level Module: FPU_mul_pipeline
// =============================================================================
module FPU_mul_pipeline (
    input  wire        clk,
    input  wire        reset,     // Synchronous active-high reset
    input  wire        enable,    // Transaction valid in

    input  wire [31:0] a,         // IEEE-754 single-precision operand A
    input  wire [31:0] b,         // IEEE-754 single-precision operand B

    output wire [31:0] result,    // IEEE-754 single-precision product
    output wire        valid,     // Transaction valid out (latency = 6 cycles)

    output wire        invalid,   // Invalid operation flag
    output wire        overflow,  // Overflow exception flag
    output wire        underflow, // Underflow exception flag
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
    wire        s1_zero_a, s1_zero_b;
    wire        s1_denorm_a, s1_denorm_b;
    wire        s1_inf_a, s1_inf_b;
    wire        s1_nan_a, s1_nan_b;

    // Stage 2 -> Stage 3
    wire        s2_valid;
    wire        s2_sign;
    wire [7:0]  s2_exp_a, s2_exp_b;
    wire [23:0] s2_mantissa_a, s2_mantissa_b;
    wire        s2_special;
    wire [31:0] s2_special_result;
    wire        s2_special_invalid;

    // Stage 3 -> Stage 4
    wire        s3_valid;
    wire        s3_sign;
    wire [7:0]  s3_exp_a, s3_exp_b;
    wire [47:0] s3_product;
    wire        s3_special;
    wire [31:0] s3_special_result;
    wire        s3_special_invalid;

    // Stage 4 -> Stage 5
    wire        s4_valid;
    wire        s4_sign;
    wire signed [11:0] s4_exponent;
    wire [47:0] s4_normalized_product;
    wire        s4_special;
    wire [31:0] s4_special_result;
    wire        s4_special_invalid;

    // Stage 5 -> Stage 6
    wire        s5_valid;
    wire        s5_sign;
    wire [7:0]  s5_exponent;
    wire [22:0] s5_fraction;
    wire        s5_zero, s5_inf;
    wire        s5_underflow, s5_overflow, s5_inexact;
    wire        s5_special;
    wire [31:0] s5_special_result;
    wire        s5_special_invalid;

    // -------------------------------------------------------------------------
    // Stage Instances
    // -------------------------------------------------------------------------
    mul_stage1_unpack u_stage1 (
        .clk         (clk),
        .reset       (reset),
        .valid_in    (enable),
        .a           (a),
        .b           (b),
        .valid_out   (s1_valid),
        .sign_a      (s1_sign_a),
        .sign_b      (s1_sign_b),
        .exp_a       (s1_exp_a),
        .exp_b       (s1_exp_b),
        .frac_a      (s1_frac_a),
        .frac_b      (s1_frac_b),
        .is_zero_a   (s1_zero_a),
        .is_zero_b   (s1_zero_b),
        .is_denorm_a (s1_denorm_a),
        .is_denorm_b (s1_denorm_b),
        .is_inf_a    (s1_inf_a),
        .is_inf_b    (s1_inf_b),
        .is_nan_a    (s1_nan_a),
        .is_nan_b    (s1_nan_b)
    );

    mul_stage2_special u_stage2 (
        .clk             (clk),
        .reset           (reset),
        .valid_in        (s1_valid),
        .sign_a          (s1_sign_a),
        .sign_b          (s1_sign_b),
        .exp_a           (s1_exp_a),
        .exp_b           (s1_exp_b),
        .frac_a          (s1_frac_a),
        .frac_b          (s1_frac_b),
        .is_zero_a       (s1_zero_a),
        .is_zero_b       (s1_zero_b),
        .is_denorm_a     (s1_denorm_a),
        .is_denorm_b     (s1_denorm_b),
        .is_inf_a        (s1_inf_a),
        .is_inf_b        (s1_inf_b),
        .is_nan_a        (s1_nan_a),
        .is_nan_b        (s1_nan_b),
        .valid_out       (s2_valid),
        .result_sign     (s2_sign),
        .effective_exp_a (s2_exp_a),
        .effective_exp_b (s2_exp_b),
        .mantissa_a      (s2_mantissa_a),
        .mantissa_b      (s2_mantissa_b),
        .special_case    (s2_special),
        .special_result  (s2_special_result),
        .special_invalid (s2_special_invalid)
    );

    mul_stage3_multiply u_stage3 (
        .clk                 (clk),
        .reset               (reset),
        .valid_in            (s2_valid),
        .result_sign         (s2_sign),
        .effective_exp_a     (s2_exp_a),
        .effective_exp_b     (s2_exp_b),
        .mantissa_a          (s2_mantissa_a),
        .mantissa_b          (s2_mantissa_b),
        .special_case        (s2_special),
        .special_result      (s2_special_result),
        .special_invalid     (s2_special_invalid),
        .valid_out           (s3_valid),
        .result_sign_out     (s3_sign),
        .effective_exp_a_out (s3_exp_a),
        .effective_exp_b_out (s3_exp_b),
        .product             (s3_product),
        .special_case_out    (s3_special),
        .special_result_out  (s3_special_result),
        .special_invalid_out (s3_special_invalid)
    );

    mul_stage4_normalize u_stage4 (
        .clk                 (clk),
        .reset               (reset),
        .valid_in            (s3_valid),
        .result_sign         (s3_sign),
        .effective_exp_a     (s3_exp_a),
        .effective_exp_b     (s3_exp_b),
        .product             (s3_product),
        .special_case        (s3_special),
        .special_result      (s3_special_result),
        .special_invalid     (s3_special_invalid),
        .valid_out           (s4_valid),
        .result_sign_out     (s4_sign),
        .result_exponent     (s4_exponent),
        .normalized_product  (s4_normalized_product),
        .special_case_out    (s4_special),
        .special_result_out  (s4_special_result),
        .special_invalid_out (s4_special_invalid)
    );

    mul_stage5_round u_stage5 (
        .clk                 (clk),
        .reset               (reset),
        .valid_in            (s4_valid),
        .result_sign         (s4_sign),
        .result_exponent     (s4_exponent),
        .normalized_product  (s4_normalized_product),
        .special_case        (s4_special),
        .special_result      (s4_special_result),
        .special_invalid     (s4_special_invalid),
        .valid_out           (s5_valid),
        .result_sign_out     (s5_sign),
        .final_exponent      (s5_exponent),
        .final_fraction      (s5_fraction),
        .final_is_zero       (s5_zero),
        .final_is_inf        (s5_inf),
        .final_underflow     (s5_underflow),
        .final_overflow      (s5_overflow),
        .final_inexact       (s5_inexact),
        .special_case_out    (s5_special),
        .special_result_out  (s5_special_result),
        .special_invalid_out (s5_special_invalid)
    );

    mul_stage6_pack u_stage6 (
        .clk             (clk),
        .reset           (reset),
        .valid_in        (s5_valid),
        .result_sign     (s5_sign),
        .final_exponent  (s5_exponent),
        .final_fraction  (s5_fraction),
        .final_is_zero   (s5_zero),
        .final_is_inf    (s5_inf),
        .final_underflow (s5_underflow),
        .final_overflow  (s5_overflow),
        .final_inexact   (s5_inexact),
        .special_case    (s5_special),
        .special_result  (s5_special_result),
        .special_invalid (s5_special_invalid),
        .valid_out       (valid),
        .result          (result),
        .invalid         (invalid),
        .overflow        (overflow),
        .underflow       (underflow),
        .inexact         (inexact)
    );

endmodule


// =============================================================================
// Stage 1: Operand Unpack & Classification
// =============================================================================
module mul_stage1_unpack (
    input  wire        clk,
    input  wire        reset,
    input  wire        valid_in,

    input  wire [31:0] a,
    input  wire [31:0] b,

    output reg         valid_out,
    output reg         sign_a,
    output reg         sign_b,
    output reg [7:0]   exp_a,
    output reg [7:0]   exp_b,
    output reg [22:0]  frac_a,
    output reg [22:0]  frac_b,
    output reg         is_zero_a,
    output reg         is_zero_b,
    output reg         is_denorm_a,
    output reg         is_denorm_b,
    output reg         is_inf_a,
    output reg         is_inf_b,
    output reg         is_nan_a,
    output reg         is_nan_b
);

    always @(posedge clk) begin
        if (reset) begin
            valid_out   <= 1'b0;
            sign_a      <= 1'b0;
            sign_b      <= 1'b0;
            exp_a       <= 8'd0;
            exp_b       <= 8'd0;
            frac_a      <= 23'd0;
            frac_b      <= 23'd0;
            is_zero_a   <= 1'b0;
            is_zero_b   <= 1'b0;
            is_denorm_a <= 1'b0;
            is_denorm_b <= 1'b0;
            is_inf_a    <= 1'b0;
            is_inf_b    <= 1'b0;
            is_nan_a    <= 1'b0;
            is_nan_b    <= 1'b0;
        end
        else begin
            valid_out <= valid_in;
            if (valid_in) begin
                sign_a <= a[31];
                exp_a  <= a[30:23];
                frac_a <= a[22:0];

                sign_b <= b[31];
                exp_b  <= b[30:23];
                frac_b <= b[22:0];

                is_zero_a   <= (a[30:23] == 8'd0)  && (a[22:0] == 23'd0);
                is_zero_b   <= (b[30:23] == 8'd0)  && (b[22:0] == 23'd0);
                is_denorm_a <= (a[30:23] == 8'd0)  && (a[22:0] != 23'd0);
                is_denorm_b <= (b[30:23] == 8'd0)  && (b[22:0] != 23'd0);
                is_inf_a    <= (a[30:23] == 8'hFF) && (a[22:0] == 23'd0);
                is_inf_b    <= (b[30:23] == 8'hFF) && (b[22:0] == 23'd0);
                is_nan_a    <= (a[30:23] == 8'hFF) && (a[22:0] != 23'd0);
                is_nan_b    <= (b[30:23] == 8'hFF) && (b[22:0] != 23'd0);
            end
        end
    end

endmodule


// =============================================================================
// Stage 2: Special Cases & Denormal Preparation
// =============================================================================
module mul_stage2_special (
    input  wire        clk,
    input  wire        reset,
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
    output reg         result_sign,
    output reg [7:0]   effective_exp_a,
    output reg [7:0]   effective_exp_b,
    output reg [23:0]  mantissa_a,
    output reg [23:0]  mantissa_b,
    output reg         special_case,
    output reg [31:0]  special_result,
    output reg         special_invalid
);

    always @(posedge clk) begin
        if (reset) begin
            valid_out       <= 1'b0;
            result_sign     <= 1'b0;
            effective_exp_a <= 8'd0;
            effective_exp_b <= 8'd0;
            mantissa_a      <= 24'd0;
            mantissa_b      <= 24'd0;
            special_case    <= 1'b0;
            special_result  <= 32'd0;
            special_invalid <= 1'b0;
        end
        else begin
            valid_out <= valid_in;
            if (valid_in) begin
                result_sign     <= sign_a ^ sign_b;
                special_case    <= 1'b0;
                special_result  <= 32'd0;
                special_invalid <= 1'b0;

                // NaN inputs: produces canonical NaN
                if (is_nan_a || is_nan_b) begin
                    special_case    <= 1'b1;
                    special_result  <= 32'h7FC00000;
                    special_invalid <= 1'b1;
                end
                // Inf * Zero: produces canonical NaN
                else if ((is_inf_a && is_zero_b) || (is_inf_b && is_zero_a)) begin
                    special_case    <= 1'b1;
                    special_result  <= 32'h7FC00000;
                    special_invalid <= 1'b1;
                end
                // Inf * Finite
                else if (is_inf_a || is_inf_b) begin
                    special_case   <= 1'b1;
                    special_result <= {sign_a ^ sign_b, 8'hFF, 23'd0};
                end
                // Zero * Finite
                else if (is_zero_a || is_zero_b) begin
                    special_case   <= 1'b1;
                    special_result <= {sign_a ^ sign_b, 31'd0};
                end
                // Finite non-zero operands
                else begin
                    if (is_denorm_a) begin
                        effective_exp_a <= 8'd1;
                        mantissa_a      <= {1'b0, frac_a};
                    end
                    else begin
                        effective_exp_a <= exp_a;
                        mantissa_a      <= {1'b1, frac_a};
                    end

                    if (is_denorm_b) begin
                        effective_exp_b <= 8'd1;
                        mantissa_b      <= {1'b0, frac_b};
                    end
                    else begin
                        effective_exp_b <= exp_b;
                        mantissa_b      <= {1'b1, frac_b};
                    end
                end
            end
        end
    end

endmodule


// =============================================================================
// Stage 3: 24 x 24 Mantissa Multiplication
// =============================================================================
module mul_stage3_multiply (
    input  wire        clk,
    input  wire        reset,
    input  wire        valid_in,

    input  wire        result_sign,
    input  wire [7:0]  effective_exp_a,
    input  wire [7:0]  effective_exp_b,
    input  wire [23:0] mantissa_a,
    input  wire [23:0] mantissa_b,
    input  wire        special_case,
    input  wire [31:0] special_result,
    input  wire        special_invalid,

    output reg         valid_out,
    output reg         result_sign_out,
    output reg [7:0]   effective_exp_a_out,
    output reg [7:0]   effective_exp_b_out,
    output reg [47:0]  product,
    output reg         special_case_out,
    output reg [31:0]  special_result_out,
    output reg         special_invalid_out
);

    always @(posedge clk) begin
        if (reset) begin
            valid_out           <= 1'b0;
            result_sign_out     <= 1'b0;
            effective_exp_a_out <= 8'd0;
            effective_exp_b_out <= 8'd0;
            product             <= 48'd0;
            special_case_out    <= 1'b0;
            special_result_out  <= 32'd0;
            special_invalid_out <= 1'b0;
        end
        else begin
            valid_out <= valid_in;
            if (valid_in) begin
                result_sign_out     <= result_sign;
                effective_exp_a_out <= effective_exp_a;
                effective_exp_b_out <= effective_exp_b;
                product             <= mantissa_a * mantissa_b;
                special_case_out    <= special_case;
                special_result_out  <= special_result;
                special_invalid_out <= special_invalid;
            end
        end
    end

endmodule


// =============================================================================
// Stage 4: Product Normalization & Exponent Calculation
// =============================================================================
module mul_stage4_normalize (
    input  wire        clk,
    input  wire        reset,
    input  wire        valid_in,

    input  wire        result_sign,
    input  wire [7:0]  effective_exp_a,
    input  wire [7:0]  effective_exp_b,
    input  wire [47:0] product,
    input  wire        special_case,
    input  wire [31:0] special_result,
    input  wire        special_invalid,

    output reg         valid_out,
    output reg         result_sign_out,
    output reg signed [11:0] result_exponent, // Unbiased exponent
    output reg [47:0]  normalized_product,
    output reg         special_case_out,
    output reg [31:0]  special_result_out,
    output reg         special_invalid_out
);

    reg [5:0] leading_one;
    reg       found_one;
    reg [47:0] normalized_product_next;
    reg signed [11:0] result_exponent_next;

    integer i;

    always @(*) begin
        leading_one             = 6'd0;
        found_one               = 1'b0;
        normalized_product_next = 48'd0;
        result_exponent_next    = 12'sd0;

        for (i = 47; i >= 0; i = i - 1) begin
            if (!found_one && product[i]) begin
                leading_one = i[5:0];
                found_one   = 1'b1;
            end
        end

        if (!found_one) begin
            normalized_product_next = 48'd0;
            result_exponent_next    = 12'sd0;
        end
        else begin
            normalized_product_next = product << (47 - leading_one);
            result_exponent_next =
                $signed({4'd0, effective_exp_a}) +
                $signed({4'd0, effective_exp_b}) +
                $signed({6'd0, leading_one}) -
                12'sd300;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            valid_out           <= 1'b0;
            result_sign_out     <= 1'b0;
            result_exponent     <= 12'sd0;
            normalized_product  <= 48'd0;
            special_case_out    <= 1'b0;
            special_result_out  <= 32'd0;
            special_invalid_out <= 1'b0;
        end
        else begin
            valid_out <= valid_in;
            if (valid_in) begin
                result_sign_out     <= result_sign;
                result_exponent     <= result_exponent_next;
                normalized_product  <= normalized_product_next;
                special_case_out    <= special_case;
                special_result_out  <= special_result;
                special_invalid_out <= special_invalid;
            end
        end
    end

endmodule


// =============================================================================
// Stage 5: GRS Rounding & Gradual Underflow
// =============================================================================
module mul_stage5_round (
    input  wire        clk,
    input  wire        reset,
    input  wire        valid_in,

    input  wire        result_sign,
    input  wire signed [11:0] result_exponent, // Unbiased exponent
    input  wire [47:0] normalized_product,
    input  wire        special_case,
    input  wire [31:0] special_result,
    input  wire        special_invalid,

    output reg         valid_out,
    output reg         result_sign_out,
    output reg [7:0]   final_exponent,
    output reg [22:0]  final_fraction,
    output reg         final_is_zero,
    output reg         final_is_inf,
    output reg         final_underflow,
    output reg         final_overflow,
    output reg         final_inexact,
    output reg         special_case_out,
    output reg [31:0]  special_result_out,
    output reg         special_invalid_out
);

    reg [23:0] significand;
    reg [24:0] rounded_significand;
    reg guard_bit, round_bit, sticky_bit, round_up;

    reg [47:0] subnormal_quotient;
    reg [47:0] remainder_bits;
    reg [47:0] half_value;
    integer shift_amount;
    reg signed [11:0] exp_work;

    reg [7:0]  final_exponent_next;
    reg [22:0] final_fraction_next;
    reg final_is_zero_next, final_is_inf_next;
    reg final_underflow_next, final_overflow_next, final_inexact_next;

    always @(*) begin
        significand         = 24'd0;
        rounded_significand = 25'd0;
        guard_bit           = 1'b0;
        round_bit           = 1'b0;
        sticky_bit          = 1'b0;
        round_up            = 1'b0;
        subnormal_quotient  = 48'd0;
        remainder_bits      = 48'd0;
        half_value          = 48'd0;
        shift_amount        = 0;
        exp_work            = result_exponent;

        final_exponent_next  = 8'd0;
        final_fraction_next  = 23'd0;
        final_is_zero_next   = 1'b0;
        final_is_inf_next    = 1'b0;
        final_underflow_next = 1'b0;
        final_overflow_next  = 1'b0;
        final_inexact_next   = 1'b0;

        if (special_case) begin
            final_exponent_next = 8'd0;
            final_fraction_next = 23'd0;
        end
        // Normal Result (unbiased exponent >= -126)
        else if (result_exponent >= -126) begin
            significand = normalized_product[47:24];
            guard_bit   = normalized_product[23];
            round_bit   = normalized_product[22];
            sticky_bit  = |normalized_product[21:0];

            round_up            = guard_bit && (round_bit || sticky_bit || significand[0]);
            rounded_significand = {1'b0, significand} + round_up;
            final_inexact_next  = guard_bit || round_bit || sticky_bit;

            if (rounded_significand[24]) begin
                exp_work = result_exponent + 1;
                if (exp_work > 127) begin
                    final_exponent_next = 8'hFF;
                    final_fraction_next = 23'd0;
                    final_is_inf_next   = 1'b1;
                    final_overflow_next = 1'b1;
                    final_inexact_next  = 1'b1;
                end
                else begin
                    final_exponent_next = exp_work + 127;
                    final_fraction_next = rounded_significand[23:1];
                end
            end
            else begin
                if (result_exponent > 127) begin
                    final_exponent_next = 8'hFF;
                    final_fraction_next = 23'd0;
                    final_is_inf_next   = 1'b1;
                    final_overflow_next = 1'b1;
                    final_inexact_next  = 1'b1;
                end
                else begin
                    final_exponent_next = result_exponent + 127;
                    final_fraction_next = rounded_significand[22:0];
                end
            end
        end
        // Subnormal / Gradual Underflow (unbiased exponent < -126)
        else begin
            shift_amount = -result_exponent - 102;

            if (shift_amount >= 48) begin
                subnormal_quotient = 48'd0;
                remainder_bits     = normalized_product;

                if (shift_amount == 48) begin
                    half_value = 48'h800000000000;
                    if (normalized_product > half_value)
                        subnormal_quotient = 48'd1;
                    else
                        subnormal_quotient = 48'd0; // Tie to even
                end
            end
            else begin
                subnormal_quotient = normalized_product >> shift_amount;
                remainder_bits     = normalized_product & ((48'h1 << shift_amount) - 1);
                half_value         = 48'h1 << (shift_amount - 1);

                if (remainder_bits > half_value) begin
                    subnormal_quotient = subnormal_quotient + 1'b1;
                end
                else if (remainder_bits == half_value) begin
                    if (subnormal_quotient[0]) // Tie-to-even
                        subnormal_quotient = subnormal_quotient + 1'b1;
                end
            end

            final_inexact_next = |remainder_bits;

            // Promotion to minimum normal
            if (subnormal_quotient >= 48'h000000800000) begin
                final_exponent_next  = 8'd1;
                final_fraction_next  = 23'd0;
                final_underflow_next = 1'b0; // Tininess after rounding
            end
            else begin
                final_exponent_next  = 8'd0;
                final_fraction_next  = subnormal_quotient[22:0];
                final_underflow_next = |remainder_bits;

                if (subnormal_quotient == 0)
                    final_is_zero_next = 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            valid_out           <= 1'b0;
            result_sign_out     <= 1'b0;
            final_exponent      <= 8'd0;
            final_fraction      <= 23'd0;
            final_is_zero       <= 1'b0;
            final_is_inf        <= 1'b0;
            final_underflow     <= 1'b0;
            final_overflow      <= 1'b0;
            final_inexact       <= 1'b0;
            special_case_out    <= 1'b0;
            special_result_out  <= 32'd0;
            special_invalid_out <= 1'b0;
        end
        else begin
            valid_out <= valid_in;
            if (valid_in) begin
                result_sign_out     <= result_sign;
                final_exponent      <= final_exponent_next;
                final_fraction      <= final_fraction_next;
                final_is_zero       <= final_is_zero_next;
                final_is_inf        <= final_is_inf_next;
                final_underflow     <= final_underflow_next;
                final_overflow      <= final_overflow_next;
                final_inexact       <= final_inexact_next;
                special_case_out    <= special_case;
                special_result_out  <= special_result;
                special_invalid_out <= special_invalid;
            end
        end
    end

endmodule


// =============================================================================
// Stage 6: IEEE-754 Result Packing
// =============================================================================
module mul_stage6_pack (
    input  wire        clk,
    input  wire        reset,
    input  wire        valid_in,

    input  wire        result_sign,
    input  wire [7:0]  final_exponent,
    input  wire [22:0] final_fraction,
    input  wire        final_is_zero,
    input  wire        final_is_inf,
    input  wire        final_underflow,
    input  wire        final_overflow,
    input  wire        final_inexact,
    input  wire        special_case,
    input  wire [31:0] special_result,
    input  wire        special_invalid,

    output reg         valid_out,
    output reg [31:0]  result,
    output reg         invalid,
    output reg         overflow,
    output reg         underflow,
    output reg         inexact
);

    always @(posedge clk) begin
        if (reset) begin
            valid_out <= 1'b0;
            result    <= 32'd0;
            invalid   <= 1'b0;
            overflow  <= 1'b0;
            underflow <= 1'b0;
            inexact   <= 1'b0;
        end
        else begin
            valid_out <= valid_in;
            if (valid_in) begin
                invalid   <= special_invalid;
                overflow  <= final_overflow;
                underflow <= final_underflow;
                inexact   <= final_inexact;

                if (special_case) begin
                    result <= special_result;
                end
                else if (final_is_inf) begin
                    result <= {result_sign, 8'hFF, 23'd0};
                end
                else if (final_is_zero) begin
                    result <= {result_sign, 31'd0};
                end
                else begin
                    result <= {result_sign, final_exponent, final_fraction};
                end
            end
        end
    end

endmodule
