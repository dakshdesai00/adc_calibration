module adc_calibrator (
    input wire clk,
    input wire rst_n,
    input wire [11:0] raw_adc,
    input wire input_valid,
    output reg [11:0] calibrated_adc,
    output reg output_valid
);

    localparam signed [15:0] COEFF_C0 = 16'shFF88;
    localparam signed [15:0] COEFF_C1 = 16'sh1338;
    localparam signed [15:0] COEFF_C2 = 16'shFD8A;
    localparam signed [15:0] COEFF_C3 = 16'sh00D2;

    reg [3:0] state;
    localparam STATE_IDLE     = 4'd0;
    localparam STATE_START_X2 = 4'd1;
    localparam STATE_WAIT_X2  = 4'd2;
    localparam STATE_START_X3 = 4'd3;
    localparam STATE_WAIT_X3  = 4'd4;
    localparam STATE_START_C1 = 4'd5;
    localparam STATE_WAIT_C1  = 4'd6;
    localparam STATE_START_C2 = 4'd7;
    localparam STATE_WAIT_C2  = 4'd8;
    localparam STATE_START_C3 = 4'd9;
    localparam STATE_WAIT_C3  = 4'd10;
    localparam STATE_ACCUM    = 4'd11;


    reg signed [12:0] x_reg;
    reg signed [12:0] x2_reg;
    reg signed [12:0] x3_reg;

    reg signed [28:0] p1;
    reg signed [28:0] p2;
    reg signed [28:0] p3;


    reg signed [15:0] mult_a;
    reg signed [12:0] mult_b;
    reg mult_start;
    reg mult_busy;
    reg mult_done;
    reg [3:0] mult_cycle;
    reg signed [28:0] accum;
    reg signed [28:0] shift_a;
    reg [12:0] shift_b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum      <= 29'sd0;
            shift_a    <= 29'sd0;
            shift_b    <= 13'd0;
            mult_cycle <= 4'd0;
            mult_busy  <= 1'b0;
            mult_done  <= 1'b0;
        end else if (mult_start) begin
            accum      <= 29'sd0;
            shift_a    <= $signed({{13{mult_a[15]}}, mult_a});
            shift_b    <= mult_b;
            mult_cycle <= 4'd0;
            mult_busy  <= 1'b1;
            mult_done  <= 1'b0;
        end else if (mult_busy) begin
            if (mult_cycle == 4'd12) begin
                if (shift_b[0]) begin
                    accum <= accum - shift_a;
                end
                mult_busy <= 1'b0;
                mult_done <= 1'b1;
            end else begin
                if (shift_b[0]) begin
                    accum <= accum + shift_a;
                end
                shift_a    <= shift_a << 1;
                shift_b    <= shift_b >> 1;
                mult_cycle <= mult_cycle + 4'd1;
            end
        end else begin
            mult_done <= 1'b0;
        end
    end

    wire signed [31:0] y_scaled_comb = COEFF_C0 +
                                      (p1 >>> 12) +
                                      (p2 >>> 12) +
                                      (p3 >>> 12) + 32'sd2048;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= STATE_IDLE;
            x_reg          <= 13'sd0;
            x2_reg         <= 13'sd0;
            x3_reg         <= 13'sd0;
            p1             <= 29'sd0;
            p2             <= 29'sd0;
            p3             <= 29'sd0;
            mult_a         <= 16'sd0;
            mult_b         <= 13'sd0;
            mult_start     <= 1'b0;
            calibrated_adc <= 12'd0;
            output_valid   <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    output_valid <= 1'b0;
                    if (input_valid) begin
                        x_reg <= $signed({1'b0, raw_adc}) - 13'sd2048;
                        state <= STATE_START_X2;
                    end
                end

                STATE_START_X2: begin
                    mult_a     <= $signed({{3{x_reg[12]}}, x_reg});
                    mult_b     <= x_reg;
                    mult_start <= 1'b1;
                    state      <= STATE_WAIT_X2;
                end

                STATE_WAIT_X2: begin
                    mult_start <= 1'b0;
                    if (mult_done) begin
                        x2_reg <= accum[24:12];
                        state  <= STATE_START_X3;
                    end
                end

                STATE_START_X3: begin
                    mult_a     <= $signed({{3{x2_reg[12]}}, x2_reg});
                    mult_b     <= x_reg;
                    mult_start <= 1'b1;
                    state      <= STATE_WAIT_X3;
                end

                STATE_WAIT_X3: begin
                    mult_start <= 1'b0;
                    if (mult_done) begin
                        x3_reg <= accum[24:12];
                        state  <= STATE_START_C1;
                    end
                end

                STATE_START_C1: begin
                    mult_a     <= COEFF_C1;
                    mult_b     <= x_reg;
                    mult_start <= 1'b1;
                    state      <= STATE_WAIT_C1;
                end

                STATE_WAIT_C1: begin
                    mult_start <= 1'b0;
                    if (mult_done) begin
                        p1    <= accum;
                        state <= STATE_START_C2;
                    end
                end

                STATE_START_C2: begin
                    mult_a     <= COEFF_C2;
                    mult_b     <= x2_reg;
                    mult_start <= 1'b1;
                    state      <= STATE_WAIT_C2;
                end

                STATE_WAIT_C2: begin
                    mult_start <= 1'b0;
                    if (mult_done) begin
                        p2    <= accum;
                        state <= STATE_START_C3;
                    end
                end

                STATE_START_C3: begin
                    mult_a     <= COEFF_C3;
                    mult_b     <= x3_reg;
                    mult_start <= 1'b1;
                    state      <= STATE_WAIT_C3;
                end

                STATE_WAIT_C3: begin
                    mult_start <= 1'b0;
                    if (mult_done) begin
                        p3    <= accum;
                        state <= STATE_ACCUM;
                    end
                end

                STATE_ACCUM: begin
                    if (y_scaled_comb > 32'sd4095) begin
                        calibrated_adc <= 12'd4095;
                    end else if (y_scaled_comb < 32'sd0) begin
                        calibrated_adc <= 12'd0;
                    end else begin
                        calibrated_adc <= y_scaled_comb[11:0];
                    end
                    output_valid <= 1'b1;
                    state        <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule