module parallel_rx (
    input wire clk,
    input wire rst_n,
    input wire [3:0] data_in,
    input wire strobe,
    output reg [11:0] full_adc_code,
    output reg data_ready
);

    reg strobe_sync_0;
    reg strobe_sync_1;
    reg [3:0] low_bits_hold;
    reg [3:0] mid_bits_hold;
    reg [1:0] strobe_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            strobe_sync_0 <= 1'b0;
            strobe_sync_1 <= 1'b0;
        end else begin
            strobe_sync_0 <= strobe;
            strobe_sync_1 <= strobe_sync_0;
        end
    end

    wire strobe_changed = (strobe_sync_0 ^ strobe_sync_1);
    reg [12:0] timeout_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            low_bits_hold <= 4'b0;
            mid_bits_hold <= 4'b0;
            full_adc_code <= 12'b0;
            data_ready    <= 1'b0;
            strobe_count  <= 2'd0;
            timeout_cnt   <= 13'd0;
        end else begin
            if (strobe_changed) begin
                timeout_cnt <= 13'd0;
                if (strobe_count == 2'd0) begin
                    low_bits_hold <= data_in;
                    strobe_count  <= 2'd1;
                    data_ready    <= 1'b0;
                end else if (strobe_count == 2'd1) begin
                    mid_bits_hold <= data_in;
                    strobe_count  <= 2'd2;
                    data_ready    <= 1'b0;
                end else begin
                    full_adc_code <= {data_in, mid_bits_hold, low_bits_hold};
                    strobe_count  <= 2'd0;
                    data_ready    <= 1'b1;
                end
            end else begin
                data_ready <= 1'b0;
                if (timeout_cnt == 13'd5000) begin
                    strobe_count <= 2'd0;
                end else begin
                    timeout_cnt <= timeout_cnt + 13'd1;
                end
            end
        end
    end
endmodule