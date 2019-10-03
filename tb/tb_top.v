`timescale 1ns/1ps

module tb_top();

//
reg sim_end;
reg [8*64-1:0] case_dir;
// global
reg rstn, sd_clk, bus_clk, reg_data_wr;
reg [7:0] reg_addr, reg_wdata; wire [16:0] bus_addr;
wire [7:0] reg_rdata, bus_rdata, bus_wdata;
wire bus_ready, bus_rdata_ready, bus_rd, bus_wr;
wire pad_clk_i, pad_clk_o, pad_clk_oe;
wire pad_cmd_i, pad_cmd_o, pad_cmd_oe;
wire [3:0] pad_dat_i, pad_dat_o, pad_dat_oe;
wire sdio_irq, sdio_pad_clk, sdio_pad_cmd;
wire [3:0] sdio_pad_dat;
// tri-state connection
assign sdio_pad_clk = pad_clk_oe ? pad_clk_o : 1'bz;
assign sdio_pad_cmd = pad_cmd_oe ? pad_cmd_o : 1'bz;
assign sdio_pad_dat[0] = pad_dat_oe[0] ? pad_dat_o[0] : 1'bz;
assign sdio_pad_dat[1] = pad_dat_oe[1] ? pad_dat_o[1] : 1'bz;
assign sdio_pad_dat[2] = pad_dat_oe[2] ? pad_dat_o[2] : 1'bz;
assign sdio_pad_dat[3] = pad_dat_oe[3] ? pad_dat_o[3] : 1'bz;
assign pad_clk_i = sdio_pad_clk;
assign pad_cmd_i = sdio_pad_cmd;
assign pad_dat_i = sdio_pad_dat;
// pull-up
pullup(sdio_pad_clk);
pullup(sdio_pad_cmd);
pullup(sdio_pad_dat[0]);
pullup(sdio_pad_dat[1]);
pullup(sdio_pad_dat[2]);
pullup(sdio_pad_dat[3]);
// inc
`include "tb_define.v"
`include "tb_lib.v"
// main
initial begin
    sys_init;
    #50_000;
    wr_reg(28, 8'h01); // set SdClkEn 1
    //wr_reg(8, 8'h0e); // set resp type, 48-bit
    //set_cmd_idx(6'h00);
    //wr_blk_1b(512, 2);
    //wr_blk_4b(512, 2);
    //wr_blk(0, 512, 2); // 1-bit
    //wr_blk(1, 512, 2); // 4-bit
    //wr_rd_blk(0, 512, 2); // 1-bit
    wr_rd_blk(0, 512, 2); // 4-bit
    #100_000;
    sim_end = 1;
    #100_000;
    $finish;
end
// file read
initial begin: CASE_INFO_INIT
    integer i, fp, ret;
    $display("---> %t, file_case_dir: %s", $time, `FILE_CASE_DIR);
    fp = $fopen(`FILE_CASE_DIR, "r");
    if (fp == 0) begin
        $display("---> %t, error while openning file_case_dir", $time);
        $fclose(fp);
        $finish;
    end
    ret = $fscanf(fp, "%s", case_dir);
    $display("---> %t, case_dir: %s", $time, case_dir);
    $fclose(fp);
end
// inst sdio
sdio_top u0_sdio (
    .rstn                   ( rstn                  ),
    .sd_clk                 ( sd_clk                ),
    .bus_clk                ( bus_clk               ),
    .reg_data_wr            ( reg_data_wr           ),
    .reg_addr               ( reg_addr              ),
    .reg_wdata              ( reg_wdata             ),
    .reg_rdata              ( reg_rdata             ),
    .bus_ready              ( bus_ready             ),
    .bus_rdata_ready        ( bus_rdata_ready       ),
    .bus_rdata              ( bus_rdata             ),
    .bus_addr               ( bus_addr              ),
    .bus_wdata              ( bus_wdata             ),
    .bus_rd                 ( bus_rd                ),
    .bus_wr                 ( bus_wr                ),
    .sdio_irq               ( sdio_irq              ),
    .pad_clk_o              ( pad_clk_o             ),
    .pad_clk_oe             ( pad_clk_oe            ),
    .pad_cmd_i              ( pad_cmd_i             ),
    .pad_cmd_o              ( pad_cmd_o             ),
    .pad_cmd_oe             ( pad_cmd_oe            ),
    .pad_dat_i              ( pad_dat_i             ),
    .pad_dat_o              ( pad_dat_o             ),
    .pad_dat_oe             ( pad_dat_oe            )
);
// inst sd_card
sd_card u1_sdcard (
    .rstn                   ( rstn                  ),
    .pad_clk                ( sdio_pad_clk          ),
    .pad_cmd                ( sdio_pad_cmd          ),
    .pad_dat                ( sdio_pad_dat          )
);
// inst dma
dma_serv u2_dma (
    .rstn                   ( rstn                  ),
    .bus_clk                ( bus_clk               ),
    .bus_ready              ( bus_ready             ),
    .bus_rdata_ready        ( bus_rdata_ready       ),
    .bus_rdata              ( bus_rdata             ),
    .bus_addr               ( bus_addr              ),
    .bus_wdata              ( bus_wdata             ),
    .bus_rd                 ( bus_rd                ),
    .bus_wr                 ( bus_wr                )
);
// fsdb
`ifdef DUMP_FSDB
initial begin
    $fsdbDumpfile("tb_top.fsdb");
    $fsdbDumpvars(0, tb_top);
end
`endif

endmodule
