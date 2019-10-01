// pingpang buffer for sdio read
module sdio_buf (
    input rstn,
    input sd_rst,
    input sd_clk,
    input buf_wr,
    input [7:0] buf_wdata,
    input buf_free,
    output buf_wr_rdy,
    output buf0_rd_rdy,
    output buf1_rd_rdy,
    output [7:0] buf0_rdata,
    output [7:0] buf1_rdata
);
// var
reg [7:0] buf0;
reg [7:0] buf1;
reg rptr;
reg wptr;
reg buf0_wr_rdy;
reg buf1_wr_rdy;
//---------------------------------------------------------------------------
// SD_CLK DOMAIN
//---------------------------------------------------------------------------
// buf flags
always @(posedge sd_clk or negedge rstn) begin
    if (rstn == 1'b0) begin
        rptr <= 0;
        wptr <= 0;
        buf0_wr_rdy <= 1;
        buf1_wr_rdy <= 1;
    end
    else if (sd_rst == 1'b1) begin
        rptr <= 0;
        wptr <= 0;
        buf0_wr_rdy <= 1;
        buf1_wr_rdy <= 1;
    end
    else begin
        // wptr
        if (wptr == 1'b0 && buf0_wr_rdy == 1'b1 && buf_wr == 1'b1) begin
            wptr <= 1'b1;
        end
        else if (wptr == 1'b1 && buf1_wr_rdy == 1'b1 && buf_wr == 1'b1) begin
            wptr <= 1'b0;
        end
        // rptr
        if (rptr == 1'b0 && buf0_wr_rdy == 1'b0 && buf_free == 1'b1) begin // using buf_reged???
            rptr <= 1'b1;
        end
        else if (rptr == 1'b1 && buf1_wr_rdy == 1'b0 && buf_free == 1'b1) begin
            rptr <= 1'b0;
        end
        // buf0_wr_rdy
        if (wptr == 1'b0 && buf0_wr_rdy == 1'b1 && buf_wr == 1'b1) begin // write
            buf0_wr_rdy <= 1'b0;
        end
        else if (rptr == 1'b0 && buf0_wr_rdy == 1'b0 && buf_free == 1'b1) begin // read
            buf0_wr_rdy <= 1'b1;
        end
        // buf1_wr_rdy
        if (wptr == 1'b1 && buf1_wr_rdy == 1'b1 && buf_wr == 1'b1) begin // write
            buf1_wr_rdy <= 1'b0;
        end
        else if (rptr == 1'b1 && buf1_wr_rdy == 1'b0 && buf_free == 1'b1) begin // read
            buf1_wr_rdy <= 1'b1;
        end
    end
end
// buf
always @(posedge sd_clk) begin
    // buf0
    if (wptr == 1'b0 && buf0_wr_rdy == 1'b1 && buf_wr == 1'b1) begin
        buf0 <= buf_wdata;
    end
    // buf1
    if (wptr == 1'b1 && buf1_wr_rdy == 1'b1 && buf_wr == 1'b1) begin
        buf1 <= buf_wdata;
    end
end
// buf_wr_rdy
assign buf_wr_rdy = buf0_wr_rdy | buf1_wr_rdy;

//---------------------------------------------------------------------------
// SYS_CLK DOMAIN
//---------------------------------------------------------------------------
// rd_rdy sync
assign buf0_rd_rdy = ~buf0_wr_rdy;
assign buf1_rd_rdy = ~buf1_wr_rdy;
// buf_rdata
assign buf0_rdata = buf0;
assign buf1_rdata = buf1;

endmodule
