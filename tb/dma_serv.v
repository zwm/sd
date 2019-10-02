module dma_serv (
    input rstn,
    input bus_clk,
    output bus_ready, 
    output bus_rdata_ready,
    output reg [7:0] bus_rdata,
    input [16:0] bus_addr,
    input [7:0] bus_wdata,
    input bus_rd,
    input bus_wr
);
// macro
localparam RD_DLY_CYC       = 6; // 0~7
localparam WR_DLY_CYC       = 6; // 0~7
// var
//reg [7:0] mem [2^17 - 1: 0]; // error!!!
reg [7:0] mem [2**17 - 1: 0]; // ok
//reg [7:0] mem [65535: 0];
reg [7:0] bus_rd_dly;
reg [7:0] bus_wr_dly;
// delay
always @(posedge bus_clk or negedge rstn)
    if (~rstn) begin
        bus_rd_dly <= 0;
        bus_wr_dly <= 0;
    end
    else begin
        bus_rd_dly <= {bus_rd_dly, bus_rd};
        bus_wr_dly <= {bus_wr_dly, bus_wr};
    end
// output
assign bus_rdata_ready = bus_rd_dly[RD_DLY_CYC]; // delay 6 cycles
assign bus_ready = (~(|bus_rd_dly[RD_DLY_CYC - 1: 0])) & (~(|bus_wr_dly[WR_DLY_CYC - 1: 0]));
// mem rd
always @(posedge bus_clk)
    if (bus_rd_dly[RD_DLY_CYC - 1]) begin
        bus_rdata <= mem[bus_addr];
    end
// mem wr
always @(posedge bus_clk)
    if (bus_wr_dly[RD_DLY_CYC - 1]) begin
        mem[bus_addr] <= bus_wdata;
    end
wire new_tx_cmd = (tb_top.u0_sdio.cmd_start == 1) && (tb_top.u0_sdio.dat_present == 1) && (tb_top.u0_sdio.dat_trans_dir == 0);
wire tx_blk_end = (tb_top.u0_sdio.u5_dat.blk_gap_event == 1) && (tb_top.u0_sdio.dat_trans_dir == 0);
// mem init
initial begin: SIM_SD_DMA
    integer fp, ret, i, addr;
    reg [64*8-1:0] s;
    reg [15:0] dat_len, dma_start_addr, dma_len;
    @(posedge tb_top.rstn);
    fp = $fopen({tb_top.case_dir, "dma_dat.dat"}, "r");
    begin: LP_SIM
        while(1) begin
            @(negedge tb_top.sd_clk);
            // sim_end check
            if (tb_top.sim_end == 1) begin
                disable LP_SIM;
            end
            // new command
            if (new_tx_cmd | tx_blk_end) begin
                ret = $fgets(s, fp); // skip comment
                $display("%t, File: dma_dat, Comment: %s", $time, s);
                ret = $fscanf(fp, "%h %h %h", dat_len, dma_start_addr, dma_len);
                $display("%t, File: dma_dat, dat_len: %h, dma_start_addr: %h, dma_len: %h", $time, dat_len, dma_start_addr, dma_len);
                addr = 0;
                for (i = 0; i < dat_len[15:0]; i = i + 1) begin
                    ret = $fscanf(fp, "%h", s[7:0]);
                    mem[dma_start_addr[15:0] + addr[15:0]] = s[7:0];
                    //$display("addr: %h, dat: %h, mem: %h", addr, s[7:0], mem[dma_start_addr[15:0] + addr[15:0]]);
                    if (addr[15:0] == dma_len[15:0] - 1) addr = 0;
                    else addr = addr + 1;
                end
                ret = $fgets(s, fp); // must add here to skip "\n"
            end
        end
    end
// close file
$fclose(fp);
end

endmodule

