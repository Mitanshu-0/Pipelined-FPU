// =============================================================================
// File: fpu_add_sub.v
// Module: fpu_add_sub_top
// Description: 8-Stage Pipelined IEEE-754 Single-Precision Floating-Point
//              Adder / Subtractor supporting Normal numbers, Subnormals,
//              Zeros, Infinities, NaNs, and Round-to-Nearest-Even (RNE).
//              Includes synchronous pipeline stall and flush control.
// =============================================================================

`timescale 1ns / 1ps

// =============================================================================
// Top-Level Module: fpu_add_sub_top
// =============================================================================
module fpu_add_sub_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,     // Backpressure from downstream consumer (active-high)
    input  wire        flush,     // Pipeline flush (active-high)

    input  wire        valid_in,  // Input transaction valid
    input  wire [31:0] operand_a, // IEEE-754 single-precision operand A
    input  wire [31:0] operand_b, // IEEE-754 single-precision operand B
    input  wire        op_sub,    // Operation select: 0 = Add, 1 = Subtract

    output wire        OUT_valid,
    output wire [31:0] OUT_result,
    output wire        OUT_flag_invalid,
    output wire        OUT_flag_overflow,
    output wire        OUT_flag_underflow,
    output wire        OUT_flag_inexact
);

    // -------------------------------------------------------------------------
    // Pipeline Registers Wires
    // -------------------------------------------------------------------------
    // PR12: Stage 1 -> Stage 2
    wire              PR12_valid;
    wire              PR12_a_sign;
    wire signed [9:0] PR12_a_exponent;
    wire [23:0]       PR12_a_mantissa;
    wire              PR12_a_is_zero, PR12_a_is_denorm, PR12_a_is_inf, PR12_a_is_nan, PR12_a_is_snan;
    wire              PR12_b_sign;
    wire signed [9:0] PR12_b_exponent;
    wire [23:0]       PR12_b_mantissa;
    wire              PR12_b_is_zero, PR12_b_is_denorm, PR12_b_is_inf, PR12_b_is_nan, PR12_b_is_snan;
    wire              PR12_op_sub;

    // PR23: Stage 2 -> Stage 3
    wire              PR23_valid;
    wire              PR23_a_sign;
    wire signed [9:0] PR23_a_exponent;
    wire [23:0]       PR23_a_mantissa;
    wire              PR23_b_sign;
    wire signed [9:0] PR23_b_exponent;
    wire [23:0]       PR23_b_mantissa;
    wire              PR23_effective_op_sub;
    wire              PR23_special_valid;
    wire [31:0]       PR23_special_result;
    wire              PR23_invalid_op;

    // PR34: Stage 3 -> Stage 4
    wire              PR34_valid;
    wire              PR34_big_sign;
    wire signed [9:0] PR34_big_exponent;
    wire [23:0]       PR34_big_mantissa;
    wire              PR34_small_sign;
    wire signed [9:0] PR34_small_exponent;
    wire [23:0]       PR34_small_mantissa;
    wire [9:0]        PR34_exponent_diff;
    wire              PR34_result_sign;
    wire              PR34_effective_op_sub;
    wire              PR34_special_valid;
    wire [31:0]       PR34_special_result;
    wire              PR34_invalid_op;

    // PR45: Stage 4 -> Stage 5
    wire              PR45_valid;
    wire              PR45_result_sign;
    wire signed [9:0] PR45_result_exponent;
    wire [26:0]       PR45_big_extended;
    wire [26:0]       PR45_small_extended_aligned;
    wire              PR45_effective_op_sub;
    wire              PR45_special_valid;
    wire [31:0]       PR45_special_result;
    wire              PR45_invalid_op;

    // PR56: Stage 5 -> Stage 6
    wire              PR56_valid;
    wire              PR56_result_sign;
    wire signed [9:0] PR56_result_exponent;
    wire [27:0]       PR56_mantissa_sum;
    wire              PR56_special_valid;
    wire [31:0]       PR56_special_result;
    wire              PR56_invalid_op;

    // PR67: Stage 6 -> Stage 7
    wire              PR67_valid;
    wire              PR67_result_sign;
    wire signed [9:0] PR67_result_exponent;
    wire [23:0]       PR67_result_mantissa;
    wire [2:0]        PR67_grs_bits;
    wire              PR67_is_denormal_result;
    wire              PR67_overflow_flag;
    wire              PR67_result_is_zero;
    wire              PR67_special_valid;
    wire [31:0]       PR67_special_result;
    wire              PR67_invalid_op;

    // PR78: Stage 7 -> Stage 8
    wire              PR78_valid;
    wire              PR78_result_sign;
    wire signed [9:0] PR78_result_exponent;
    wire [23:0]       PR78_result_mantissa;
    wire              PR78_result_is_zero;
    wire              PR78_overflow_flag;
    wire              PR78_underflow_flag;
    wire              PR78_inexact_flag;
    wire              PR78_special_valid;
    wire [31:0]       PR78_special_result;
    wire              PR78_invalid_op;

    // -------------------------------------------------------------------------
    // Stage Instances
    // -------------------------------------------------------------------------
    fpu_stage1_unpack u_stage1 (
        .clk              (clk),
        .rst_n            (rst_n),
        .stall            (stall),
        .flush            (flush),
        .valid_in         (valid_in),
        .operand_a        (operand_a),
        .operand_b        (operand_b),
        .op_sub           (op_sub),
        .PR12_valid       (PR12_valid),
        .PR12_a_sign      (PR12_a_sign),
        .PR12_a_exponent  (PR12_a_exponent),
        .PR12_a_mantissa  (PR12_a_mantissa),
        .PR12_a_is_zero   (PR12_a_is_zero),
        .PR12_a_is_denorm (PR12_a_is_denorm),
        .PR12_a_is_inf    (PR12_a_is_inf),
        .PR12_a_is_nan    (PR12_a_is_nan),
        .PR12_a_is_snan   (PR12_a_is_snan),
        .PR12_b_sign      (PR12_b_sign),
        .PR12_b_exponent  (PR12_b_exponent),
        .PR12_b_mantissa  (PR12_b_mantissa),
        .PR12_b_is_zero   (PR12_b_is_zero),
        .PR12_b_is_denorm (PR12_b_is_denorm),
        .PR12_b_is_inf    (PR12_b_is_inf),
        .PR12_b_is_nan    (PR12_b_is_nan),
        .PR12_b_is_snan   (PR12_b_is_snan),
        .PR12_op_sub      (PR12_op_sub)
    );

    fpu_stage2_special u_stage2 (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .stall                 (stall),
        .flush                 (flush),
        .PR12_valid            (PR12_valid),
        .PR12_a_sign           (PR12_a_sign),
        .PR12_a_exponent       (PR12_a_exponent),
        .PR12_a_mantissa       (PR12_a_mantissa),
        .PR12_a_is_zero        (PR12_a_is_zero),
        .PR12_a_is_inf         (PR12_a_is_inf),
        .PR12_a_is_nan         (PR12_a_is_nan),
        .PR12_a_is_snan        (PR12_a_is_snan),
        .PR12_b_sign           (PR12_b_sign),
        .PR12_b_exponent       (PR12_b_exponent),
        .PR12_b_mantissa       (PR12_b_mantissa),
        .PR12_b_is_zero        (PR12_b_is_zero),
        .PR12_b_is_inf         (PR12_b_is_inf),
        .PR12_b_is_nan         (PR12_b_is_nan),
        .PR12_b_is_snan        (PR12_b_is_snan),
        .PR12_op_sub           (PR12_op_sub),
        .PR23_valid            (PR23_valid),
        .PR23_a_sign           (PR23_a_sign),
        .PR23_a_exponent       (PR23_a_exponent),
        .PR23_a_mantissa       (PR23_a_mantissa),
        .PR23_b_sign           (PR23_b_sign),
        .PR23_b_exponent       (PR23_b_exponent),
        .PR23_b_mantissa       (PR23_b_mantissa),
        .PR23_effective_op_sub (PR23_effective_op_sub),
        .PR23_special_valid    (PR23_special_valid),
        .PR23_special_result   (PR23_special_result),
        .PR23_invalid_op       (PR23_invalid_op)
    );

    fpu_stage3_compare u_stage3 (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .stall                  (stall),
        .flush                  (flush),
        .PR23_valid             (PR23_valid),
        .PR23_a_sign            (PR23_a_sign),
        .PR23_a_exponent        (PR23_a_exponent),
        .PR23_a_mantissa        (PR23_a_mantissa),
        .PR23_b_sign            (PR23_b_sign),
        .PR23_b_exponent        (PR23_b_exponent),
        .PR23_b_mantissa        (PR23_b_mantissa),
        .PR23_effective_op_sub  (PR23_effective_op_sub),
        .PR23_special_valid     (PR23_special_valid),
        .PR23_special_result    (PR23_special_result),
        .PR23_invalid_op        (PR23_invalid_op),
        .PR34_valid             (PR34_valid),
        .PR34_big_sign          (PR34_big_sign),
        .PR34_big_exponent      (PR34_big_exponent),
        .PR34_big_mantissa      (PR34_big_mantissa),
        .PR34_small_sign        (PR34_small_sign),
        .PR34_small_exponent    (PR34_small_exponent),
        .PR34_small_mantissa    (PR34_small_mantissa),
        .PR34_exponent_diff     (PR34_exponent_diff),
        .PR34_result_sign       (PR34_result_sign),
        .PR34_effective_op_sub  (PR34_effective_op_sub),
        .PR34_special_valid     (PR34_special_valid),
        .PR34_special_result    (PR34_special_result),
        .PR34_invalid_op        (PR34_invalid_op)
    );

    fpu_stage4_align u_stage4 (
        .clk                          (clk),
        .rst_n                        (rst_n),
        .stall                        (stall),
        .flush                        (flush),
        .PR34_valid                   (PR34_valid),
        .PR34_big_sign                (PR34_big_sign),
        .PR34_big_exponent            (PR34_big_exponent),
        .PR34_big_mantissa            (PR34_big_mantissa),
        .PR34_small_sign              (PR34_small_sign),
        .PR34_small_exponent          (PR34_small_exponent),
        .PR34_small_mantissa          (PR34_small_mantissa),
        .PR34_exponent_diff           (PR34_exponent_diff),
        .PR34_result_sign             (PR34_result_sign),
        .PR34_effective_op_sub        (PR34_effective_op_sub),
        .PR34_special_valid           (PR34_special_valid),
        .PR34_special_result          (PR34_special_result),
        .PR34_invalid_op              (PR34_invalid_op),
        .PR45_valid                   (PR45_valid),
        .PR45_result_sign             (PR45_result_sign),
        .PR45_result_exponent         (PR45_result_exponent),
        .PR45_big_extended            (PR45_big_extended),
        .PR45_small_extended_aligned  (PR45_small_extended_aligned),
        .PR45_effective_op_sub        (PR45_effective_op_sub),
        .PR45_special_valid           (PR45_special_valid),
        .PR45_special_result          (PR45_special_result),
        .PR45_invalid_op              (PR45_invalid_op)
    );

    fpu_stage5_arith u_stage5 (
        .clk                          (clk),
        .rst_n                        (rst_n),
        .stall                        (stall),
        .flush                        (flush),
        .PR45_valid                   (PR45_valid),
        .PR45_result_sign             (PR45_result_sign),
        .PR45_result_exponent         (PR45_result_exponent),
        .PR45_big_extended            (PR45_big_extended),
        .PR45_small_extended_aligned  (PR45_small_extended_aligned),
        .PR45_effective_op_sub        (PR45_effective_op_sub),
        .PR45_special_valid           (PR45_special_valid),
        .PR45_special_result          (PR45_special_result),
        .PR45_invalid_op              (PR45_invalid_op),
        .PR56_valid                   (PR56_valid),
        .PR56_result_sign             (PR56_result_sign),
        .PR56_result_exponent         (PR56_result_exponent),
        .PR56_mantissa_sum            (PR56_mantissa_sum),
        .PR56_special_valid           (PR56_special_valid),
        .PR56_special_result          (PR56_special_result),
        .PR56_invalid_op              (PR56_invalid_op)
    );

    fpu_stage6_normalize u_stage6 (
        .clk                     (clk),
        .rst_n                   (rst_n),
        .stall                   (stall),
        .flush                   (flush),
        .PR56_valid              (PR56_valid),
        .PR56_result_sign        (PR56_result_sign),
        .PR56_result_exponent    (PR56_result_exponent),
        .PR56_mantissa_sum       (PR56_mantissa_sum),
        .PR56_special_valid      (PR56_special_valid),
        .PR56_special_result     (PR56_special_result),
        .PR56_invalid_op         (PR56_invalid_op),
        .PR67_valid              (PR67_valid),
        .PR67_result_sign        (PR67_result_sign),
        .PR67_result_exponent    (PR67_result_exponent),
        .PR67_result_mantissa    (PR67_result_mantissa),
        .PR67_grs_bits           (PR67_grs_bits),
        .PR67_is_denormal_result (PR67_is_denormal_result),
        .PR67_overflow_flag      (PR67_overflow_flag),
        .PR67_result_is_zero     (PR67_result_is_zero),
        .PR67_special_valid      (PR67_special_valid),
        .PR67_special_result     (PR67_special_result),
        .PR67_invalid_op         (PR67_invalid_op)
    );

    fpu_stage7_round u_stage7 (
        .clk                     (clk),
        .rst_n                   (rst_n),
        .stall                   (stall),
        .flush                   (flush),
        .PR67_valid              (PR67_valid),
        .PR67_result_sign        (PR67_result_sign),
        .PR67_result_exponent    (PR67_result_exponent),
        .PR67_result_mantissa    (PR67_result_mantissa),
        .PR67_grs_bits           (PR67_grs_bits),
        .PR67_is_denormal_result (PR67_is_denormal_result),
        .PR67_overflow_flag      (PR67_overflow_flag),
        .PR67_result_is_zero     (PR67_result_is_zero),
        .PR67_special_valid      (PR67_special_valid),
        .PR67_special_result     (PR67_special_result),
        .PR67_invalid_op         (PR67_invalid_op),
        .PR78_valid              (PR78_valid),
        .PR78_result_sign        (PR78_result_sign),
        .PR78_result_exponent    (PR78_result_exponent),
        .PR78_result_mantissa    (PR78_result_mantissa),
        .PR78_result_is_zero     (PR78_result_is_zero),
        .PR78_overflow_flag      (PR78_overflow_flag),
        .PR78_underflow_flag     (PR78_underflow_flag),
        .PR78_inexact_flag       (PR78_inexact_flag),
        .PR78_special_valid      (PR78_special_valid),
        .PR78_special_result     (PR78_special_result),
        .PR78_invalid_op         (PR78_invalid_op)
    );

    fpu_stage8_pack u_stage8 (
        .clk                 (clk),
        .rst_n               (rst_n),
        .stall               (stall),
        .flush               (flush),
        .PR78_valid          (PR78_valid),
        .PR78_result_sign    (PR78_result_sign),
        .PR78_result_exponent(PR78_result_exponent),
        .PR78_result_mantissa(PR78_result_mantissa),
        .PR78_result_is_zero (PR78_result_is_zero),
        .PR78_overflow_flag  (PR78_overflow_flag),
        .PR78_underflow_flag (PR78_underflow_flag),
        .PR78_inexact_flag   (PR78_inexact_flag),
        .PR78_special_valid  (PR78_special_valid),
        .PR78_special_result (PR78_special_result),
        .PR78_invalid_op     (PR78_invalid_op),
        .OUT_valid           (OUT_valid),
        .OUT_result          (OUT_result),
        .OUT_flag_invalid    (OUT_flag_invalid),
        .OUT_flag_overflow   (OUT_flag_overflow),
        .OUT_flag_underflow  (OUT_flag_underflow),
        .OUT_flag_inexact    (OUT_flag_inexact)
    );

endmodule


// =============================================================================
// Stage 1: Operand Unpack & Classification
// =============================================================================
module fpu_stage1_unpack (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    input  wire        valid_in,
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    input  wire        op_sub,

    output reg          PR12_valid,
    output reg          PR12_a_sign,
    output reg  signed [9:0] PR12_a_exponent,
    output reg  [23:0]  PR12_a_mantissa,
    output reg          PR12_a_is_zero,
    output reg          PR12_a_is_denorm,
    output reg          PR12_a_is_inf,
    output reg          PR12_a_is_nan,
    output reg          PR12_a_is_snan,

    output reg          PR12_b_sign,
    output reg  signed [9:0] PR12_b_exponent,
    output reg  [23:0]  PR12_b_mantissa,
    output reg          PR12_b_is_zero,
    output reg          PR12_b_is_denorm,
    output reg          PR12_b_is_inf,
    output reg          PR12_b_is_nan,
    output reg          PR12_b_is_snan,

    output reg          PR12_op_sub
);

    localparam signed [9:0] BIAS       = 10'sd127;
    localparam signed [9:0] DENORM_EXP = -10'sd126;

    wire stage_active = valid_in;

    reg           a_sign_calc;
    reg  signed [9:0] a_exponent_calc;
    reg  [23:0]  a_mantissa_calc;
    reg           a_zero_calc, a_denorm_calc, a_inf_calc, a_nan_calc, a_snan_calc;

    reg           b_sign_calc;
    reg  signed [9:0] b_exponent_calc;
    reg  [23:0]  b_mantissa_calc;
    reg           b_zero_calc, b_denorm_calc, b_inf_calc, b_nan_calc, b_snan_calc;

    always @(*) begin
        a_sign_calc = 1'b0; a_exponent_calc = 10'sd0; a_mantissa_calc = 24'd0;
        a_zero_calc = 1'b0; a_denorm_calc = 1'b0; a_inf_calc = 1'b0; a_nan_calc = 1'b0; a_snan_calc = 1'b0;
        b_sign_calc = 1'b0; b_exponent_calc = 10'sd0; b_mantissa_calc = 24'd0;
        b_zero_calc = 1'b0; b_denorm_calc = 1'b0; b_inf_calc = 1'b0; b_nan_calc = 1'b0; b_snan_calc = 1'b0;

        if (stage_active) begin
            a_sign_calc = operand_a[31];
            begin : decode_a
                reg [7:0]  a_exp_raw;
                reg [22:0] a_frac_raw;
                reg        a_exp_is_zero, a_exp_is_ones, a_frac_is_zero;
                a_exp_raw      = operand_a[30:23];
                a_frac_raw     = operand_a[22:0];
                a_exp_is_zero  = (a_exp_raw == 8'd0);
                a_exp_is_ones  = (a_exp_raw == 8'd255);
                a_frac_is_zero = (a_frac_raw == 23'd0);

                a_zero_calc     = a_exp_is_zero & a_frac_is_zero;
                a_denorm_calc   = a_exp_is_zero & ~a_frac_is_zero;
                a_inf_calc      = a_exp_is_ones & a_frac_is_zero;
                a_nan_calc      = a_exp_is_ones & ~a_frac_is_zero;
                a_snan_calc     = a_nan_calc & ~a_frac_raw[22];
                a_mantissa_calc = {~a_exp_is_zero, a_frac_raw};
                a_exponent_calc = a_exp_is_zero ? DENORM_EXP : ($signed({2'b00, a_exp_raw}) - BIAS);
            end

            b_sign_calc = operand_b[31];
            begin : decode_b
                reg [7:0]  b_exp_raw;
                reg [22:0] b_frac_raw;
                reg        b_exp_is_zero, b_exp_is_ones, b_frac_is_zero;
                b_exp_raw      = operand_b[30:23];
                b_frac_raw     = operand_b[22:0];
                b_exp_is_zero  = (b_exp_raw == 8'd0);
                b_exp_is_ones  = (b_exp_raw == 8'd255);
                b_frac_is_zero = (b_frac_raw == 23'd0);

                b_zero_calc     = b_exp_is_zero & b_frac_is_zero;
                b_denorm_calc   = b_exp_is_zero & ~b_frac_is_zero;
                b_inf_calc      = b_exp_is_ones & b_frac_is_zero;
                b_nan_calc      = b_exp_is_ones & ~b_frac_is_zero;
                b_snan_calc     = b_nan_calc & ~b_frac_raw[22];
                b_mantissa_calc = {~b_exp_is_zero, b_frac_raw};
                b_exponent_calc = b_exp_is_zero ? DENORM_EXP : ($signed({2'b00, b_exp_raw}) - BIAS);
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            PR12_valid      <= 1'b0;
            PR12_a_sign     <= 1'b0; PR12_a_exponent <= 10'sd0; PR12_a_mantissa <= 24'd0;
            PR12_a_is_zero  <= 1'b0; PR12_a_is_denorm<= 1'b0;   PR12_a_is_inf   <= 1'b0;
            PR12_a_is_nan   <= 1'b0; PR12_a_is_snan  <= 1'b0;
            PR12_b_sign     <= 1'b0; PR12_b_exponent <= 10'sd0; PR12_b_mantissa <= 24'd0;
            PR12_b_is_zero  <= 1'b0; PR12_b_is_denorm<= 1'b0;   PR12_b_is_inf   <= 1'b0;
            PR12_b_is_nan   <= 1'b0; PR12_b_is_snan  <= 1'b0;
            PR12_op_sub     <= 1'b0;
        end
        else if (flush) begin
            PR12_valid <= 1'b0;
        end
        else if (!stall) begin
            PR12_valid      <= valid_in;
            PR12_a_sign     <= a_sign_calc;
            PR12_a_exponent <= a_exponent_calc;
            PR12_a_mantissa <= a_mantissa_calc;
            PR12_a_is_zero  <= a_zero_calc;
            PR12_a_is_denorm<= a_denorm_calc;
            PR12_a_is_inf   <= a_inf_calc;
            PR12_a_is_nan   <= a_nan_calc;
            PR12_a_is_snan  <= a_snan_calc;

            PR12_b_sign     <= b_sign_calc;
            PR12_b_exponent <= b_exponent_calc;
            PR12_b_mantissa <= b_mantissa_calc;
            PR12_b_is_zero  <= b_zero_calc;
            PR12_b_is_denorm<= b_denorm_calc;
            PR12_b_is_inf   <= b_inf_calc;
            PR12_b_is_nan   <= b_nan_calc;
            PR12_b_is_snan  <= b_snan_calc;

            PR12_op_sub     <= stage_active ? op_sub : 1'b0;
        end
    end

endmodule


// =============================================================================
// Stage 2: Special Case Detection & Exception Handling
// =============================================================================
module fpu_stage2_special (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    input  wire        PR12_valid,
    input  wire        PR12_a_sign,
    input  wire signed [9:0] PR12_a_exponent,
    input  wire [23:0] PR12_a_mantissa,
    input  wire        PR12_a_is_zero,
    input  wire        PR12_a_is_inf,
    input  wire        PR12_a_is_nan,
    input  wire        PR12_a_is_snan,

    input  wire        PR12_b_sign,
    input  wire signed [9:0] PR12_b_exponent,
    input  wire [23:0] PR12_b_mantissa,
    input  wire        PR12_b_is_zero,
    input  wire        PR12_b_is_inf,
    input  wire        PR12_b_is_nan,
    input  wire        PR12_b_is_snan,

    input  wire        PR12_op_sub,

    output reg         PR23_valid,
    output reg         PR23_a_sign,
    output reg  signed [9:0] PR23_a_exponent,
    output reg  [23:0] PR23_a_mantissa,

    output reg         PR23_b_sign,
    output reg  signed [9:0] PR23_b_exponent,
    output reg  [23:0] PR23_b_mantissa,

    output reg         PR23_effective_op_sub,
    output reg         PR23_special_valid,
    output reg  [31:0] PR23_special_result,
    output reg         PR23_invalid_op
);

    localparam [31:0] QNAN = 32'h7FC0_0000;

    wire stage_active = PR12_valid;

    reg        effective_op_sub_calc;
    reg        b_effective_sign_calc;
    reg        special_valid_calc;
    reg [31:0] special_result_calc;
    reg        invalid_op_calc;

    always @(*) begin
        effective_op_sub_calc = 1'b0;
        b_effective_sign_calc = 1'b0;
        special_valid_calc    = 1'b0;
        special_result_calc   = 32'd0;
        invalid_op_calc       = 1'b0;

        if (stage_active) begin
            effective_op_sub_calc = PR12_op_sub ^ PR12_a_sign ^ PR12_b_sign;
            b_effective_sign_calc = PR12_op_sub ? ~PR12_b_sign : PR12_b_sign;

            // NaN operands
            if (PR12_a_is_nan || PR12_b_is_nan) begin
                special_valid_calc  = 1'b1;
                special_result_calc = QNAN;
                invalid_op_calc     = PR12_a_is_snan | PR12_b_is_snan;
            end
            // Infinity arithmetic
            else if (PR12_a_is_inf && PR12_b_is_inf) begin
                if (PR12_a_sign != b_effective_sign_calc) begin
                    special_valid_calc  = 1'b1;
                    special_result_calc = QNAN;
                    invalid_op_calc     = 1'b1; // Inf - Inf is invalid
                end else begin
                    special_valid_calc  = 1'b1;
                    special_result_calc = {PR12_a_sign, 8'hFF, 23'd0};
                end
            end
            else if (PR12_a_is_inf) begin
                special_valid_calc  = 1'b1;
                special_result_calc = {PR12_a_sign, 8'hFF, 23'd0};
            end
            else if (PR12_b_is_inf) begin
                special_valid_calc  = 1'b1;
                special_result_calc = {b_effective_sign_calc, 8'hFF, 23'd0};
            end
            // Zero arithmetic
            else if (PR12_a_is_zero && PR12_b_is_zero) begin
                special_valid_calc  = 1'b1;
                special_result_calc = (PR12_a_sign & b_effective_sign_calc) ? {1'b1, 31'd0} : {1'b0, 31'd0};
            end
            else if (PR12_a_is_zero) begin
                special_valid_calc  = 1'b1;
                special_result_calc = { b_effective_sign_calc,
                                        PR12_b_mantissa[23] ? (PR12_b_exponent[7:0] + 8'd127) : 8'd0,
                                        PR12_b_mantissa[22:0] };
            end
            else if (PR12_b_is_zero) begin
                special_valid_calc  = 1'b1;
                special_result_calc = { PR12_a_sign,
                                        PR12_a_mantissa[23] ? (PR12_a_exponent[7:0] + 8'd127) : 8'd0,
                                        PR12_a_mantissa[22:0] };
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            PR23_valid             <= 1'b0;
            PR23_a_sign            <= 1'b0; PR23_a_exponent <= 10'sd0; PR23_a_mantissa <= 24'd0;
            PR23_b_sign            <= 1'b0; PR23_b_exponent <= 10'sd0; PR23_b_mantissa <= 24'd0;
            PR23_effective_op_sub  <= 1'b0;
            PR23_special_valid     <= 1'b0;
            PR23_special_result    <= 32'd0;
            PR23_invalid_op        <= 1'b0;
        end
        else if (flush) begin
            PR23_valid         <= 1'b0;
            PR23_special_valid <= 1'b0;
        end
        else if (!stall) begin
            PR23_valid             <= PR12_valid;
            PR23_a_sign            <= stage_active ? PR12_a_sign     : 1'b0;
            PR23_a_exponent        <= stage_active ? PR12_a_exponent : 10'sd0;
            PR23_a_mantissa        <= stage_active ? PR12_a_mantissa : 24'd0;
            PR23_b_sign            <= b_effective_sign_calc;
            PR23_b_exponent        <= stage_active ? PR12_b_exponent : 10'sd0;
            PR23_b_mantissa        <= stage_active ? PR12_b_mantissa : 24'd0;
            PR23_effective_op_sub  <= effective_op_sub_calc;
            PR23_special_valid     <= special_valid_calc;
            PR23_special_result    <= special_result_calc;
            PR23_invalid_op        <= invalid_op_calc;
        end
    end

endmodule


// =============================================================================
// Stage 3: Operand Comparison & Swap
// =============================================================================
module fpu_stage3_compare (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    input  wire        PR23_valid,
    input  wire        PR23_a_sign,
    input  wire signed [9:0] PR23_a_exponent,
    input  wire [23:0] PR23_a_mantissa,
    input  wire        PR23_b_sign,
    input  wire signed [9:0] PR23_b_exponent,
    input  wire [23:0] PR23_b_mantissa,
    input  wire        PR23_effective_op_sub,
    input  wire        PR23_special_valid,
    input  wire [31:0] PR23_special_result,
    input  wire        PR23_invalid_op,

    output reg         PR34_valid,
    output reg         PR34_big_sign,
    output reg  signed [9:0] PR34_big_exponent,
    output reg  [23:0] PR34_big_mantissa,
    output reg         PR34_small_sign,
    output reg  signed [9:0] PR34_small_exponent,
    output reg  [23:0] PR34_small_mantissa,
    output reg  [9:0]  PR34_exponent_diff,
    output reg         PR34_result_sign,
    output reg         PR34_effective_op_sub,
    output reg         PR34_special_valid,
    output reg  [31:0] PR34_special_result,
    output reg         PR34_invalid_op
);

    wire stage_active = PR23_valid & ~PR23_special_valid;

    reg               big_sign_calc;
    reg  signed [9:0] big_exponent_calc;
    reg  [23:0]       big_mantissa_calc;
    reg               small_sign_calc;
    reg  signed [9:0] small_exponent_calc;
    reg  [23:0]       small_mantissa_calc;
    reg  [9:0]        exponent_diff_calc;
    reg               result_sign_calc;

    always @(*) begin
        big_sign_calc       = 1'b0; big_exponent_calc   = 10'sd0; big_mantissa_calc   = 24'd0;
        small_sign_calc     = 1'b0; small_exponent_calc = 10'sd0; small_mantissa_calc = 24'd0;
        exponent_diff_calc  = 10'd0;
        result_sign_calc    = 1'b0;

        if (stage_active) begin
            begin : compare_block
                reg exponents_equal, a_mantissa_ge_b, a_is_bigger, exact_cancellation;
                exponents_equal    = (PR23_a_exponent == PR23_b_exponent);
                a_mantissa_ge_b    = (PR23_a_mantissa >= PR23_b_mantissa);
                a_is_bigger        = exponents_equal ? a_mantissa_ge_b : (PR23_a_exponent > PR23_b_exponent);
                exact_cancellation = exponents_equal && (PR23_a_mantissa == PR23_b_mantissa) && PR23_effective_op_sub;

                big_sign_calc       = a_is_bigger ? PR23_a_sign     : PR23_b_sign;
                big_exponent_calc   = a_is_bigger ? PR23_a_exponent : PR23_b_exponent;
                big_mantissa_calc   = a_is_bigger ? PR23_a_mantissa : PR23_b_mantissa;

                small_sign_calc     = a_is_bigger ? PR23_b_sign     : PR23_a_sign;
                small_exponent_calc = a_is_bigger ? PR23_b_exponent : PR23_a_exponent;
                small_mantissa_calc = a_is_bigger ? PR23_b_mantissa : PR23_a_mantissa;

                exponent_diff_calc  = big_exponent_calc - small_exponent_calc;
                // Exact cancellation in RNE produces +0.0
                result_sign_calc    = exact_cancellation ? 1'b0 : big_sign_calc;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            PR34_valid            <= 1'b0;
            PR34_big_sign         <= 1'b0; PR34_big_exponent   <= 10'sd0; PR34_big_mantissa   <= 24'd0;
            PR34_small_sign       <= 1'b0; PR34_small_exponent <= 10'sd0; PR34_small_mantissa <= 24'd0;
            PR34_exponent_diff    <= 10'd0;
            PR34_result_sign      <= 1'b0;
            PR34_effective_op_sub <= 1'b0;
            PR34_special_valid    <= 1'b0;
            PR34_special_result   <= 32'd0;
            PR34_invalid_op       <= 1'b0;
        end
        else if (flush) begin
            PR34_valid         <= 1'b0;
            PR34_special_valid <= 1'b0;
        end
        else if (!stall) begin
            PR34_valid            <= PR23_valid;
            PR34_big_sign         <= big_sign_calc;
            PR34_big_exponent     <= big_exponent_calc;
            PR34_big_mantissa     <= big_mantissa_calc;
            PR34_small_sign       <= small_sign_calc;
            PR34_small_exponent   <= small_exponent_calc;
            PR34_small_mantissa   <= small_mantissa_calc;
            PR34_exponent_diff    <= exponent_diff_calc;
            PR34_result_sign      <= result_sign_calc;
            PR34_effective_op_sub <= PR23_valid ? PR23_effective_op_sub : 1'b0;
            PR34_special_valid    <= PR23_valid & PR23_special_valid;
            PR34_special_result   <= PR23_special_result;
            PR34_invalid_op       <= PR23_valid & PR23_invalid_op;
        end
    end

endmodule


// =============================================================================
// Stage 4: Mantissa Alignment & Sticky Bit Generation
// =============================================================================
module fpu_stage4_align (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    input  wire            PR34_valid,
    input  wire            PR34_big_sign,
    input  wire signed [9:0] PR34_big_exponent,
    input  wire [23:0]     PR34_big_mantissa,
    input  wire            PR34_small_sign,
    input  wire signed [9:0] PR34_small_exponent,
    input  wire [23:0]     PR34_small_mantissa,
    input  wire [9:0]      PR34_exponent_diff,
    input  wire            PR34_result_sign,
    input  wire            PR34_effective_op_sub,
    input  wire            PR34_special_valid,
    input  wire [31:0]     PR34_special_result,
    input  wire            PR34_invalid_op,

    output reg            PR45_valid,
    output reg            PR45_result_sign,
    output reg  signed [9:0] PR45_result_exponent,
    output reg  [26:0]    PR45_big_extended,
    output reg  [26:0]    PR45_small_extended_aligned,
    output reg            PR45_effective_op_sub,
    output reg            PR45_special_valid,
    output reg  [31:0]    PR45_special_result,
    output reg            PR45_invalid_op
);

    localparam ALIGN_WIDTH = 27;
    localparam [9:0] MAX_SHIFT = 10'd27;

    wire stage_active = PR34_valid & ~PR34_special_valid;

    reg [26:0] big_extended_calc;
    reg [26:0] small_extended_aligned_calc;

    always @(*) begin
        big_extended_calc           = 27'd0;
        small_extended_aligned_calc = 27'd0;

        if (stage_active) begin
            begin : align_block
                reg [26:0] small_extended_raw, small_shifted, dropped_bit_mask;
                reg        shift_is_overflow, sticky_from_dropped_bits, sticky_from_full_overflow, final_sticky_bit;
                reg [9:0]  shift_amt;

                big_extended_calc  = {PR34_big_mantissa, 3'b000};
                small_extended_raw = {PR34_small_mantissa, 3'b000};

                shift_is_overflow = (PR34_exponent_diff > MAX_SHIFT);
                shift_amt = shift_is_overflow ? MAX_SHIFT : PR34_exponent_diff;

                small_shifted = small_extended_raw >> shift_amt;

                dropped_bit_mask = (shift_amt == 10'd0) ? 27'd0
                                    : ({ALIGN_WIDTH{1'b1}} >> (ALIGN_WIDTH - shift_amt));
                sticky_from_dropped_bits  = |(small_extended_raw & dropped_bit_mask);
                sticky_from_full_overflow = shift_is_overflow & (|PR34_small_mantissa);

                final_sticky_bit = small_shifted[0] | sticky_from_dropped_bits | sticky_from_full_overflow;
                small_extended_aligned_calc = {small_shifted[26:1], final_sticky_bit};
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            PR45_valid                  <= 1'b0;
            PR45_result_sign            <= 1'b0;
            PR45_result_exponent        <= 10'sd0;
            PR45_big_extended           <= 27'd0;
            PR45_small_extended_aligned <= 27'd0;
            PR45_effective_op_sub       <= 1'b0;
            PR45_special_valid          <= 1'b0;
            PR45_special_result         <= 32'd0;
            PR45_invalid_op             <= 1'b0;
        end
        else if (flush) begin
            PR45_valid         <= 1'b0;
            PR45_special_valid <= 1'b0;
        end
        else if (!stall) begin
            PR45_valid                  <= PR34_valid;
            PR45_result_sign            <= stage_active ? PR34_result_sign  : 1'b0;
            PR45_result_exponent        <= stage_active ? PR34_big_exponent : 10'sd0;
            PR45_big_extended           <= big_extended_calc;
            PR45_small_extended_aligned <= small_extended_aligned_calc;
            PR45_effective_op_sub       <= PR34_valid ? PR34_effective_op_sub : 1'b0;
            PR45_special_valid          <= PR34_valid & PR34_special_valid;
            PR45_special_result         <= PR34_special_result;
            PR45_invalid_op             <= PR34_valid & PR34_invalid_op;
        end
    end

endmodule


// =============================================================================
// Stage 5: Mantissa Addition / Subtraction
// =============================================================================
module fpu_stage5_arith (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    input  wire            PR45_valid,
    input  wire            PR45_result_sign,
    input  wire signed [9:0] PR45_result_exponent,
    input  wire [26:0]     PR45_big_extended,
    input  wire [26:0]     PR45_small_extended_aligned,
    input  wire            PR45_effective_op_sub,
    input  wire            PR45_special_valid,
    input  wire [31:0]     PR45_special_result,
    input  wire            PR45_invalid_op,

    output reg            PR56_valid,
    output reg            PR56_result_sign,
    output reg  signed [9:0] PR56_result_exponent,
    output reg  [27:0]    PR56_mantissa_sum,
    output reg            PR56_special_valid,
    output reg  [31:0]    PR56_special_result,
    output reg            PR56_invalid_op
);

    wire stage_active = PR45_valid & ~PR45_special_valid;

    reg [27:0] mantissa_sum_calc;

    always @(*) begin
        mantissa_sum_calc = 28'd0;
        if (stage_active) begin
            mantissa_sum_calc = PR45_effective_op_sub
                                  ? ({1'b0, PR45_big_extended} - {1'b0, PR45_small_extended_aligned})
                                  : ({1'b0, PR45_big_extended} + {1'b0, PR45_small_extended_aligned});
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            PR56_valid           <= 1'b0;
            PR56_result_sign     <= 1'b0;
            PR56_result_exponent <= 10'sd0;
            PR56_mantissa_sum    <= 28'd0;
            PR56_special_valid   <= 1'b0;
            PR56_special_result  <= 32'd0;
            PR56_invalid_op      <= 1'b0;
        end
        else if (flush) begin
            PR56_valid         <= 1'b0;
            PR56_special_valid <= 1'b0;
        end
        else if (!stall) begin
            PR56_valid           <= PR45_valid;
            PR56_result_sign     <= stage_active ? PR45_result_sign     : 1'b0;
            PR56_result_exponent <= stage_active ? PR45_result_exponent : 10'sd0;
            PR56_mantissa_sum    <= mantissa_sum_calc;
            PR56_special_valid   <= PR45_valid & PR45_special_valid;
            PR56_special_result  <= PR45_special_result;
            PR56_invalid_op      <= PR45_valid & PR45_invalid_op;
        end
    end

endmodule


// =============================================================================
// Stage 6: Post-Arithmetic Normalization & LZC
// =============================================================================
module fpu_stage6_normalize (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    input  wire            PR56_valid,
    input  wire            PR56_result_sign,
    input  wire signed [9:0] PR56_result_exponent,
    input  wire [27:0]     PR56_mantissa_sum,
    input  wire            PR56_special_valid,
    input  wire [31:0]     PR56_special_result,
    input  wire            PR56_invalid_op,

    output reg            PR67_valid,
    output reg            PR67_result_sign,
    output reg  signed [9:0] PR67_result_exponent,
    output reg  [23:0]    PR67_result_mantissa,
    output reg  [2:0]     PR67_grs_bits,
    output reg            PR67_is_denormal_result,
    output reg            PR67_overflow_flag,
    output reg            PR67_result_is_zero,
    output reg            PR67_special_valid,
    output reg  [31:0]    PR67_special_result,
    output reg            PR67_invalid_op
);

    localparam signed [9:0] EXP_MIN_NORMAL = -10'sd126;
    localparam signed [9:0] EXP_MAX_NORMAL =  10'sd127;

    wire stage_active = PR56_valid & ~PR56_special_valid;

    function [4:0] leading_zero_count;
        input [26:0] bits;
        integer i;
        reg     found;
        begin
            leading_zero_count = 5'd27;
            found = 1'b0;
            for (i = 0; i < 27; i = i + 1) begin
                if (!found && bits[26 - i]) begin
                    leading_zero_count = i[4:0];
                    found = 1'b1;
                end
            end
        end
    endfunction

    reg  signed [9:0] normalized_exponent_calc;
    reg  [23:0]        result_mantissa_calc;
    reg  [2:0]         grs_bits_calc;
    reg                overflow_flag_calc;
    reg                denormal_flag_calc;
    reg                result_is_zero_calc;

    always @(*) begin
        normalized_exponent_calc = 10'sd0;
        result_mantissa_calc     = 24'd0;
        grs_bits_calc            = 3'd0;
        overflow_flag_calc       = 1'b0;
        denormal_flag_calc       = 1'b0;
        result_is_zero_calc      = 1'b0;

        if (stage_active) begin
            begin : normalize_block
                reg        carry_out_bit;
                reg [26:0] sum_no_carry;
                reg [26:0] normalized_field;
                reg        sticky_from_shift_right;

                reg signed [9:0] max_shift_signed;
                reg signed [9:0] exponent_after_left_shift;
                reg [4:0]        lzc;
                reg [4:0]        max_shift_allowed;
                reg [4:0]        actual_left_shift;
                reg              clamp_at_denormal_floor;

                carry_out_bit = PR56_mantissa_sum[27];
                sum_no_carry  = PR56_mantissa_sum[26:0];
                result_is_zero_calc = (sum_no_carry == 27'd0);

                // Case 1: Addition with Carry-out -> 1-bit right shift
                if (carry_out_bit) begin
                    normalized_field         = {1'b1, sum_no_carry[26:1]};
                    normalized_exponent_calc = PR56_result_exponent + 10'sd1;
                    sticky_from_shift_right  = sum_no_carry[0];

                    grs_bits_calc = {
                        normalized_field[2],
                        normalized_field[1],
                        normalized_field[0] | sticky_from_shift_right
                    };

                    result_mantissa_calc = normalized_field[26:3];
                    overflow_flag_calc   = (normalized_exponent_calc > EXP_MAX_NORMAL);
                    denormal_flag_calc   = 1'b0;
                end
                // Case 2: Subtraction / No Carry -> LZC left shift with subnormal floor clamp
                else begin
                    lzc = leading_zero_count(sum_no_carry);

                    max_shift_signed = PR56_result_exponent - EXP_MIN_NORMAL;
                    max_shift_allowed = (max_shift_signed < 0)          ? 5'd0 :
                                        (max_shift_signed > 10'sd27)    ? 5'd27 :
                                        max_shift_signed[4:0];

                    clamp_at_denormal_floor = ((PR56_result_exponent - $signed({5'b0, lzc})) < EXP_MIN_NORMAL);
                    actual_left_shift = clamp_at_denormal_floor ? max_shift_allowed : lzc;

                    normalized_field = sum_no_carry << actual_left_shift;
                    exponent_after_left_shift = clamp_at_denormal_floor ? EXP_MIN_NORMAL :
                                                (PR56_result_exponent - $signed({5'b0, actual_left_shift}));

                    normalized_exponent_calc = exponent_after_left_shift;
                    result_mantissa_calc     = normalized_field[26:3];
                    grs_bits_calc            = {normalized_field[2], normalized_field[1], normalized_field[0]};
                    overflow_flag_calc       = (normalized_exponent_calc > EXP_MAX_NORMAL);
                    denormal_flag_calc       = clamp_at_denormal_floor;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            PR67_valid              <= 1'b0;
            PR67_result_sign        <= 1'b0;
            PR67_result_exponent    <= 10'sd0;
            PR67_result_mantissa    <= 24'd0;
            PR67_grs_bits           <= 3'd0;
            PR67_is_denormal_result <= 1'b0;
            PR67_overflow_flag      <= 1'b0;
            PR67_result_is_zero     <= 1'b0;
            PR67_special_valid      <= 1'b0;
            PR67_special_result     <= 32'd0;
            PR67_invalid_op         <= 1'b0;
        end
        else if (flush) begin
            PR67_valid         <= 1'b0;
            PR67_special_valid <= 1'b0;
        end
        else if (!stall) begin
            PR67_valid              <= PR56_valid;
            PR67_result_sign        <= stage_active ? PR56_result_sign : 1'b0;
            PR67_result_exponent    <= normalized_exponent_calc;
            PR67_result_mantissa    <= result_mantissa_calc;
            PR67_grs_bits           <= grs_bits_calc;
            PR67_is_denormal_result <= denormal_flag_calc;
            PR67_overflow_flag      <= overflow_flag_calc;
            PR67_result_is_zero     <= result_is_zero_calc;
            PR67_special_valid      <= PR56_valid & PR56_special_valid;
            PR67_special_result     <= PR56_special_result;
            PR67_invalid_op         <= PR56_valid & PR56_invalid_op;
        end
    end

endmodule


// =============================================================================
// Stage 7: Round-to-Nearest-Even (RNE) & Exception Calculation
// =============================================================================
module fpu_stage7_round (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    input  wire            PR67_valid,
    input  wire            PR67_result_sign,
    input  wire signed [9:0] PR67_result_exponent,
    input  wire [23:0]     PR67_result_mantissa,
    input  wire [2:0]      PR67_grs_bits,
    input  wire            PR67_is_denormal_result,
    input  wire            PR67_overflow_flag,
    input  wire            PR67_result_is_zero,
    input  wire            PR67_special_valid,
    input  wire [31:0]     PR67_special_result,
    input  wire            PR67_invalid_op,

    output reg            PR78_valid,
    output reg            PR78_result_sign,
    output reg  signed [9:0] PR78_result_exponent,
    output reg  [23:0]    PR78_result_mantissa,
    output reg            PR78_result_is_zero,
    output reg            PR78_overflow_flag,
    output reg            PR78_underflow_flag,
    output reg            PR78_inexact_flag,
    output reg            PR78_special_valid,
    output reg  [31:0]    PR78_special_result,
    output reg            PR78_invalid_op
);

    localparam signed [9:0] EXP_MAX_NORMAL = 10'sd127;

    wire stage_active = PR67_valid & ~PR67_special_valid;

    reg  signed [9:0] final_exponent_calc;
    reg  [23:0]        final_mantissa_calc;
    reg                overflow_flag_calc;
    reg                underflow_flag_calc;
    reg                inexact_calc;
    reg                result_is_zero_calc;

    always @(*) begin
        final_exponent_calc = 10'sd0;
        final_mantissa_calc = 24'd0;
        overflow_flag_calc  = 1'b0;
        underflow_flag_calc = 1'b0;
        inexact_calc        = 1'b0;
        result_is_zero_calc = 1'b0;

        if (stage_active) begin
            begin : round_block
                reg guard_bit, round_bit, sticky_bit, round_up, round_carry_out, overflow_after_round;
                reg [24:0] mantissa_rounded;

                guard_bit  = PR67_grs_bits[2];
                round_bit  = PR67_grs_bits[1];
                sticky_bit = PR67_grs_bits[0];

                // RNE tie-to-even: round up if Guard and (Round | Sticky | LSB)
                round_up     = guard_bit & (round_bit | sticky_bit | PR67_result_mantissa[0]);
                inexact_calc = guard_bit | round_bit | sticky_bit;

                mantissa_rounded = {1'b0, PR67_result_mantissa} + (round_up ? 25'd1 : 25'd0);
                round_carry_out  = mantissa_rounded[24];

                final_mantissa_calc = round_carry_out ? mantissa_rounded[24:1] : mantissa_rounded[23:0];
                final_exponent_calc = round_carry_out ? (PR67_result_exponent + 10'sd1) : PR67_result_exponent;

                overflow_after_round = (final_exponent_calc > EXP_MAX_NORMAL);
                overflow_flag_calc   = PR67_overflow_flag | overflow_after_round;
                underflow_flag_calc  = PR67_is_denormal_result & inexact_calc;
                result_is_zero_calc  = PR67_result_is_zero;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            PR78_valid            <= 1'b0;
            PR78_result_sign      <= 1'b0;
            PR78_result_exponent  <= 10'sd0;
            PR78_result_mantissa  <= 24'd0;
            PR78_result_is_zero   <= 1'b0;
            PR78_overflow_flag    <= 1'b0;
            PR78_underflow_flag   <= 1'b0;
            PR78_inexact_flag     <= 1'b0;
            PR78_special_valid    <= 1'b0;
            PR78_special_result   <= 32'd0;
            PR78_invalid_op       <= 1'b0;
        end
        else if (flush) begin
            PR78_valid         <= 1'b0;
            PR78_special_valid <= 1'b0;
        end
        else if (!stall) begin
            PR78_valid            <= PR67_valid;
            PR78_result_sign      <= stage_active ? PR67_result_sign : 1'b0;
            PR78_result_exponent  <= final_exponent_calc;
            PR78_result_mantissa  <= final_mantissa_calc;
            PR78_result_is_zero   <= result_is_zero_calc;
            PR78_overflow_flag    <= overflow_flag_calc;
            PR78_underflow_flag   <= underflow_flag_calc;
            PR78_inexact_flag     <= inexact_calc;
            PR78_special_valid    <= PR67_valid & PR67_special_valid;
            PR78_special_result   <= PR67_special_result;
            PR78_invalid_op       <= PR67_valid & PR67_invalid_op;
        end
    end

endmodule


// =============================================================================
// Stage 8: Result Packing & Output Format
// =============================================================================
module fpu_stage8_pack (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    input  wire            PR78_valid,
    input  wire            PR78_result_sign,
    input  wire signed [9:0] PR78_result_exponent,
    input  wire [23:0]     PR78_result_mantissa,
    input  wire            PR78_result_is_zero,
    input  wire            PR78_overflow_flag,
    input  wire            PR78_underflow_flag,
    input  wire            PR78_inexact_flag,
    input  wire            PR78_special_valid,
    input  wire [31:0]     PR78_special_result,
    input  wire            PR78_invalid_op,

    output reg            OUT_valid,
    output reg  [31:0]    OUT_result,
    output reg            OUT_flag_invalid,
    output reg            OUT_flag_overflow,
    output reg            OUT_flag_underflow,
    output reg            OUT_flag_inexact
);

    localparam [31:0] INF_MAGNITUDE = 32'h7F80_0000;

    wire stage_active = PR78_valid;

    reg [31:0] final_result_calc;
    reg        flag_invalid_calc;
    reg        flag_overflow_calc;
    reg        flag_underflow_calc;
    reg        flag_inexact_calc;

    always @(*) begin
        final_result_calc   = 32'd0;
        flag_invalid_calc   = 1'b0;
        flag_overflow_calc  = 1'b0;
        flag_underflow_calc = 1'b0;
        flag_inexact_calc   = 1'b0;

        if (stage_active) begin
            begin : pack_block
                reg        hidden_bit_set;
                reg [7:0]  stored_exponent;
                reg [22:0] stored_fraction;
                reg [31:0] normal_packed, overflow_packed, computed_result;

                hidden_bit_set  = PR78_result_mantissa[23];
                stored_exponent = (~hidden_bit_set) ? 8'd0 : PR78_result_exponent[7:0] + 8'd127;
                stored_fraction = PR78_result_mantissa[22:0];

                normal_packed   = {PR78_result_sign, stored_exponent, stored_fraction};
                overflow_packed = {PR78_result_sign, INF_MAGNITUDE[30:0]};
                computed_result = PR78_overflow_flag ? overflow_packed : normal_packed;

                final_result_calc   = PR78_special_valid ? PR78_special_result : computed_result;
                flag_invalid_calc   = PR78_invalid_op;
                flag_overflow_calc  = ~PR78_special_valid & PR78_overflow_flag;
                flag_underflow_calc = ~PR78_special_valid & ~PR78_overflow_flag & PR78_underflow_flag;
                // In IEEE-754: overflow strictly signals the inexact exception
                flag_inexact_calc   = ~PR78_special_valid & (PR78_inexact_flag | PR78_overflow_flag);
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            OUT_valid          <= 1'b0;
            OUT_result         <= 32'd0;
            OUT_flag_invalid   <= 1'b0;
            OUT_flag_overflow  <= 1'b0;
            OUT_flag_underflow <= 1'b0;
            OUT_flag_inexact   <= 1'b0;
        end
        else if (flush) begin
            OUT_valid <= 1'b0;
        end
        else if (!stall) begin
            OUT_valid          <= PR78_valid;
            OUT_result         <= final_result_calc;
            OUT_flag_invalid   <= flag_invalid_calc;
            OUT_flag_overflow  <= flag_overflow_calc;
            OUT_flag_underflow <= flag_underflow_calc;
            OUT_flag_inexact   <= flag_inexact_calc;
        end
    end

endmodule
