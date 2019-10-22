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
wire new_tx_cmd = (`SDIO_TOP.cmd_start == 1) && (`SDIO_TOP.dat_present == 1) && (`SDIO_TOP.dat_trans_dir == 0);
wire tx_blk_end = (`SDIO_TOP.u5_dat.blk_gap_event == 1) && (`SDIO_TOP.dat_trans_dir == 0);
// dma
wire [15:0] dma_saddr = `TB_TOP.log_dma_saddr[15:0];
wire [15:0] dma_len = `TB_TOP.log_dma_len[15:0];
wire [15:0] blk_size = `TB_TOP.log_blk_size[15:0];
wire [15:0] blk_cnt = `TB_TOP.log_blk_cnt[15:0];
// mem filler
initial begin: SIM_DMA_FILLER
    // var
    integer i; reg[15:0] addr, log_addr;
    // main
    while(1) begin
        @(negedge `SDIO_TOP.sd_clk) begin
            // new_tx_cmd, fill dma_len
            if (new_tx_cmd) begin
                addr = dma_saddr; // init ptr
                log_addr = 0;
                for (i = 0; i < dma_len; i = i + 1) begin
                    // mem
                    mem[addr] = `TB_TOP.log_mem[log_addr];
                    // addr
                    if (addr == (dma_saddr + dma_len - 1)) addr = dma_saddr;
                    else addr = addr + 1;
                    log_addr = log_addr + 1;
                end
            end
            // tx_blk_end, fill one block
            if (tx_blk_end) begin
                for (i = 0; i < blk_size; i = i + 1) begin
                    // mem
                    mem[addr] = `TB_TOP.log_mem[log_addr];
                    // addr
                    if (addr == (dma_saddr + dma_len - 1)) addr = dma_saddr;
                    else addr = addr + 1;
                    log_addr = log_addr + 1;
                end
            end
        end
    end
end

endmodule

