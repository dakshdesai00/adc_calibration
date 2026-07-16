(* top *)
module top (
    (* iopad_external_pin, clkbuf_inhibit *) input wire clk,
    (* iopad_external_pin *)                 output wire clk_en,
    (* iopad_external_pin *)                 input wire [3:0] data_in,
    (* iopad_external_pin *)                 output wire [3:0] data_out,
    (* iopad_external_pin *)                 output wire [3:0] data_oe,
    (* iopad_external_pin *)                 input wire strobe,
    (* iopad_external_pin *)                 output wire valid,
    (* iopad_external_pin *)                 output wire valid_oe
);

    assign clk_en = 1'b1;
    assign valid_oe = 1'b1;
    wire rst_n = 1'b1;

    wire [11:0] raw_adc_wire;
    wire data_ready_wire;
    wire [11:0] calibrated_adc;
    wire output_valid;

    parallel_rx rx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .strobe(strobe),
        .full_adc_code(raw_adc_wire),
        .data_ready(data_ready_wire)
    );

    adc_calibrator cal_inst (
        .clk(clk),
        .rst_n(rst_n),
        .raw_adc(raw_adc_wire),
        .input_valid(data_ready_wire),
        .calibrated_adc(calibrated_adc),
        .output_valid(output_valid)
    );

    parallel_tx tx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .calibrated_adc(calibrated_adc),
        .output_valid(output_valid),
        .data_out(data_out),
        .data_oe(data_oe),
        .valid(valid)
    );

endmodule