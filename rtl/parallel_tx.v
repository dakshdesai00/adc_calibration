module parallel_tx (
    input wire clk,
    input wire rst_n,
    input wire [11:0] calibrated_adc,
    input wire output_valid,
    output reg [3:0] data_out,
    output reg [3:0] data_oe,
    output reg valid
);

    reg [2:0] tx_state;
    localparam TX_IDLE   = 3'd0;
    localparam TX_LOW    = 3'd1;
    localparam TX_MID    = 3'd2;
    localparam TX_HIGH   = 3'd3;
    localparam TX_FINISH = 3'd4;

    reg [11:0] data_hold;
    reg [12:0] delay_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state  <= TX_IDLE;
            data_out  <= 4'b0;
            data_oe   <= 4'b0;
            valid     <= 1'b0;
            data_hold <= 12'b0;
            delay_cnt <= 13'd0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    valid     <= 1'b0;
                    data_oe   <= 4'b0;
                    delay_cnt <= 13'd0;
                    if (output_valid) begin
                        data_hold <= calibrated_adc;
                        tx_state  <= TX_LOW;
                    end
                end

                TX_LOW: begin
                    data_out <= data_hold[3:0];
                    data_oe  <= 4'hF;
                    valid    <= 1'b1;
                    if (delay_cnt == 13'd2500) begin
                        delay_cnt <= 13'd0;
                        tx_state  <= TX_MID;
                    end else begin
                        delay_cnt <= delay_cnt + 13'd1;
                    end
                end

                TX_MID: begin
                    data_out <= data_hold[7:4];
                    valid    <= 1'b0;
                    if (delay_cnt == 13'd2500) begin
                        delay_cnt <= 13'd0;
                        tx_state  <= TX_HIGH;
                    end else begin
                        delay_cnt <= delay_cnt + 13'd1;
                    end
                end

                TX_HIGH: begin
                    data_out <= data_hold[11:8];
                    valid    <= 1'b1;
                    if (delay_cnt == 13'd2500) begin
                        delay_cnt <= 13'd0;
                        tx_state  <= TX_FINISH;
                    end else begin
                        delay_cnt <= delay_cnt + 13'd1;
                    end
                end

                TX_FINISH: begin
                    valid    <= 1'b0;
                    data_oe  <= 4'b0;
                    if (delay_cnt == 13'd2500) begin
                        delay_cnt <= 13'd0;
                        tx_state  <= TX_IDLE;
                    end else begin
                        delay_cnt <= delay_cnt + 13'd1;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end
endmodule
