module sdio_clk (
    input rstn,
    //input sd_rst, // clock is not influenced by software reset
    input sd_clk,
    input sd_clk_en,
    input [7:0] sd_clk_div,
    input sd_clk_pause,
    output reg clk_o,
    output reg clk_oe,
    output tx_en,
    output rx_en
);

// fsm
reg [7:0] clk_cnt;
// output
assign tx_en = ((sd_clk_en == 1) && (clk_cnt == sd_clk_div) && (sd_clk_pause == 0)) ?  clk_o : 1'b0;
assign rx_en = ((sd_clk_en == 1) && (clk_cnt == sd_clk_div) && (sd_clk_pause == 0)) ? ~clk_o : 1'b0;
// clk_cnt
always @(posedge sd_clk or negedge rstn) begin
    if (rstn == 1'b0) begin
        clk_cnt <= 0;
        clk_o <= 0;
        clk_oe <= 0;
    end
    else begin
        // clock active
        if (sd_clk_en) begin
            clk_oe <= 1;
            if (sd_clk_pause) begin
                clk_cnt <= clk_cnt; // keep
                clk_o <= clk_o; // keep
            end
            else if (clk_cnt == sd_clk_div) begin
                clk_cnt <= 0;
                clk_o <= ~clk_o;
                ////tx_en <= clk_o; // falling edge
                ////rx_en <= ~clk_o; // rising edge
                //tx_en <= ~clk_o; // falling edge
                //rx_en <= clk_o; // rising edge
            end
            else begin
                clk_cnt <= clk_cnt + 1;
            end
        end
        // clock disabled
        else begin
            // PartA2, 1.12, disable clk after high
            if ((clk_cnt == 0) && (clk_o == 0)) begin // disable
                clk_cnt <= 0;
                clk_o <= 0;
                clk_oe <= 0;
            end
            else if (clk_cnt == sd_clk_div) begin // continue
                clk_cnt <= 0;
                if (clk_o == 1) begin
                    clk_o <= 0;
                    clk_oe <= 0;
                end
                else begin
                    clk_o <= 1;
                end
            end
            else begin
                clk_cnt <= clk_cnt + 1;
            end
        end
    end
end

endmodule
