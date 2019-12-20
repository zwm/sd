module sdio_sync (
    // global
    input rstn,
    input sys_rst,
    input sys_clk,
    input sd_rst,
    input sd_clk,
    // sys_clk -> sd_clk
    input buf_free_sys, // pulse
    output buf_free_sd,
    input dma_byte_en_sys,
    output dma_byte_en_sd,
    input reg_data_wr_sys,
    output reg_data_wr_sd,
    input reg_addr_wr_sys,
    output reg_addr_wr_sd,
    input dma_buf_empty_sys, // level
    output dma_buf_empty_sd,
    // sd_clk -> sys_clk
    input buf0_rd_rdy_sd, // level
    input buf1_rd_rdy_sd,
    output buf0_rd_rdy_sys,
    output buf1_rd_rdy_sys,
    input sdio_byte_done_sd,
    output sdio_byte_done_sys,
    input dma_auto_start_sd,
    output dma_auto_start_sys,
    input dat_done_sd,
    output dat_done_sys
);

//---------------------------------------------------------------------------
// SYS_CLK -> SD_CLK (12M -> 48M)
//---------------------------------------------------------------------------
// buf_free_sys, pulse
sdio_psync u_psync00 (
    .rstn(rstn),
    .sclk(sys_clk),
    .srst(sys_rst),
    .ssig(buf_free_sys),
    .dclk(sd_clk),
    .drst(sd_rst),
    .dsig(buf_free_sd)
);
// dma_byte_en_sys, pulse
sdio_psync u_psync01 (
    .rstn(rstn),
    .sclk(sys_clk),
    .srst(sys_rst),
    .ssig(dma_byte_en_sys),
    .dclk(sd_clk),
    .drst(sd_rst),
    .dsig(dma_byte_en_sd)
);
// reg_data_wr_sys, pulse
sdio_psync u_psync02 (
    .rstn(rstn),
    .sclk(sys_clk),
    .srst(sys_rst),
    .ssig(reg_data_wr_sys),
    .dclk(sd_clk),
    .drst(sd_rst),
    .dsig(reg_data_wr_sd)
);
// reg_addr_wr_sys, pulse
sdio_psync u_psync03 (
    .rstn(rstn),
    .sclk(sys_clk),
    .srst(sys_rst),
    .ssig(reg_addr_wr_sys),
    .dclk(sd_clk),
    .drst(sd_rst),
    .dsig(reg_addr_wr_sd)
);
// dma_buf_empty_sys, level
sdio_lsync u_lsync00 (
    .rstn(rstn),
    .ssig(dma_buf_empty_sys),
    .dclk(sd_clk),
    .drst(sd_rst),
    .dsig(dma_buf_empty_sd)
);

//---------------------------------------------------------------------------
// SD_CLK -> SYS_CLK (48M -> 12M)
//---------------------------------------------------------------------------
// buf0_rd_rdy_sd, level
sdio_lsync u_lsync10 (
    .rstn(rstn),
    .ssig(buf0_rd_rdy_sd),
    .dclk(sys_clk),
    .drst(sys_rst),
    .dsig(buf0_rd_rdy_sys)
);
// buf1_rd_rdy_sd, level
sdio_lsync u_lsync11 (
    .rstn(rstn),
    .ssig(buf1_rd_rdy_sd),
    .dclk(sys_clk),
    .drst(sys_rst),
    .dsig(buf1_rd_rdy_sys)
);
// sdio_byte_done_sd, pulse
sdio_psync u_psync10 (
    .rstn(rstn),
    .sclk(sd_clk),
    .srst(sd_rst),
    .ssig(sdio_byte_done_sd),
    .dclk(sys_clk),
    .drst(sys_rst),
    .dsig(sdio_byte_done_sys)
);
// dma_auto_start_sd, pulse
sdio_psync u_psync11 (
    .rstn(rstn),
    .sclk(sd_clk),
    .srst(sd_rst),
    .ssig(dma_auto_start_sd),
    .dclk(sys_clk),
    .drst(sys_rst),
    .dsig(dma_auto_start_sys)
);
// dat_done_sd, pulse
sdio_psync u_psync12 (
    .rstn(rstn),
    .sclk(sd_clk),
    .srst(sd_rst),
    .ssig(dat_done_sd),
    .dclk(sys_clk),
    .drst(sys_rst),
    .dsig(dat_done_sys)
);

endmodule

// pulse sync
module sdio_psync (
    input rstn,
    input sclk,
    input srst,
    input ssig,
    input dclk,
    input drst,
    output dsig
);
// var
reg ssig_tog;
reg [2:0] ssig_tog_sync;
// tog
always @(posedge sclk or negedge rstn)
    if (~rstn)
        ssig_tog <= 0;
    else
        if (srst)
            ssig_tog <= 0;
        else if (ssig)
            ssig_tog <= ~ssig_tog;
// sync
always @(posedge dclk or negedge rstn)
    if (~rstn)
        ssig_tog_sync <= 0;
    else
        if (drst)
            ssig_tog_sync <= 0;
        else
            ssig_tog_sync <= {ssig_tog_sync[1:0], ssig_tog};
// output
assign dsig = ssig_tog_sync[2] ^ ssig_tog_sync[1];
endmodule

// level sync
module sdio_lsync(
    input rstn,
    input ssig,
    input dclk,
    input drst,
    output dsig
);
// var
reg [1:0] ssig_sync;
// sync
always @(posedge dclk or negedge rstn)
    if (rstn == 0)
        ssig_sync <= 0;
    else
        if (drst == 1)
            ssig_sync <= 0;
        else
            ssig_sync <= {ssig_sync[0], ssig};
// output
assign dsig = ssig_sync[1];
endmodule

