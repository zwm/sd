module sdio_timer (
    input rstn,
    input sd_clk,
    input timeout_cnt_en,
    input [7:0] timeout_cnt_sel,
    output timeout_event
);

// var
reg [25:0] cnt; // max: 2^26*(1/48M) = 1.398s
wire [25:0] cnt_max;
// max
assign cnt_max      = {timeout_cnt_sel[7:0], 2'b11, 16'hffff};
// clk_cnt
always @(posedge sd_clk or negedge rstn)
    if (rstn == 1'b0) begin
        cnt <= 0;
    end
    else if (timeout_cnt_en) begin // enable
        if (cnt != cnt_max) begin
            cnt <= cnt + 1;
        end
    end
    else begin
        cnt <= 0;
    end
// timeout_event
assign timeout_event = (cnt[25:0] == {cnt_max[25:1], 1'b0});

endmodule
