module qspi (
input spi_clk,
input rstn, scan_mode,

// spi interface
input [3:0] spd_in,
output reg ncs,
output sck,
output reg [3:0] spd_out, spd_en,

// mram
input mcu_clk,
input [7:0] mram_rdata,
output mram_rd, mram_wr,
output [15:0] mram_addr,
output [7:0] mram_wdata,

// system bus for dma
input start, bus_clk,
input [15:0] ctrl,
input [15:0] tx_addr, rx_addr, tx_len, rx_len,
input [7:0] bus_rdata,
input [7:0] xorkey,
output load_key, shift_key,
output reg [15:0] remain,
output [15:0] bus_addr,
output [7:0] bus_wdata,
output bus_wr, bus_rd, crcok, done,
output reg read, cont_mode,

// xip
input [7:0] flash_read_cmd,
input [23:0] flash_offset,
input code_rd,
input [21:0] code_addr,
input [63:0] tea_xor,
output code_valid, tea_next,
output reg tea_start,
output [31:0] code_data

);

localparam IDLE = 0;
localparam DMA_READ = 1;
localparam START = 2;
localparam WRITE = 3;
localparam DELAY = 4;
localparam READ = 5;
localparam WAIT_XIP = 6;
localparam ASYNC_DELAY = 7;

localparam DUAL = 1;
localparam QUAD = 2;

reg clken, clken_n, enable, xip_mode,
reg cs, rd, wr, wr_dly, bus_rd_dly;
reg spi_done, pre_wr, mram_rdly;
reg [15:0] timeout;
reg [15:0] bytecnt, dma_addr, wr_addr, lfsr;
reg [3:0] bitcnt, keycnt, spd_in_dly;
reg [7:0] odat, odatn, idat, bus_rdata_sync;
reg [7:0] mram_wdata_async, mram_rdata_async;
reg [2:0] state;
reg [21:0] last_code_addr;
reg [31:0] rx_data, code_data_async;
reg [1:0] mode;
wire [7:0] fifo_out;
wire data_ready, xip_en, dma_en, mram_rd_done, mram_wr_done;
wire code_rd_async, code_valid0, code_valid_async, mram_rd0, mram_wr0;
wire wdata_empty, done_sync, read_sync, mram_rd_async, mram_wr_async;

reg code_rd_async_d;
wire code_rd_async_pos;
wire code_rd_t0;
wire code_rd_t1;


wire [1:0] mode_set = ctrl[1:0];
wire auto_inc = ctrl[2];
wire xip = ctrl[3];
wire mbyte = ctrl[4];
wire mbyte_cont_mode = ctrl[5];
wire mram = ctrl[6];
wire clkp = ctrl[7];
wire [3:0] delay = ctrl[11:8];
wire [2:0] wslen = ctrl[14:12];
wire async = ctrl[15];

wire qmode = mode == QUAD;
wire dmode = mode == DUAL;
wire spi_nclk = scan_mode ? bus_clk : ~spi_clk;
wire [3:0] bitinc = qmode ? 4 : dmode ? 2 : 1;
wire [3:0] bitmax = qmode ? 4 : dmode ? 6 : 7;
wire [15:0] byte_dec = bytecnt - 1;
wire [23:0] flash_addr = flash_offset + {code_addr, 2'b0};
wire [7:0] shift_in = qmode ? {idat, spd_in_dly} : dmode ? {idat, spi_in_dly[1:0]} : {idat, spd_in_dly[1]};
wire [7:0] tx_data = mram ? async ? mram_rdata_async : mram_rdata : bus_rdata_sync;
wire [31:0] code_data_enc = {rx_data, idat};
wire [31:0] code_data_dec = code_data_enc ^ tea_xor[63:32];
assign sck = scan_mode ? clken_n : clkp ? ~clken_n | spi_clk : clken_n & spi_clk;
assign code_valid0 = xip_mode & wr & bytecnt[1:0] == 0;
assign mram_rd0 = rd & mram;
assign mram_wr0 = wr & mram & ~xip_mode;
assign code_valid = async ? code_valid_async : code_valid0;
assign code_data = async ? code_data_async : code_data_dec; // code_data_enc ^ tea_xor[63:32]
assign mram_rd = async ? mram_rd_async : mram_rd0;
assign mram_wr = async ? mram_wr_async : mram_wr0;
assign mram_wdata = async ? mram_wdata_async : idat;
assign mram_addr = dma_addr;
assign bus_wr = wr_dly;
assign bus_addr = bus_wr ? wr_addr : dma_addr;
assign bus_wdata = fifo_out ^ xorkey;
assign crcok = lfsr == 0;
assign done = done_sync & wdata_empty;
assign shift_key = bus_wr;
assign load_key = start | bus_wr & keycnt == 15;
assign tea_next = state == READ & bitcnt[1:0] == 0 | state == WAIT_XIP & bytecnt == 32;

assign code_rd_async_pos = code_rd_async & ~code_rd_async_d;
assign code_rd_t0 = async ? code_rd_async : code_rd;
assign code_rd_t1 = async ? code_rd_async_pos : code_rd;

always @(posedge spi_clk or negedge rstn)
if (~rstn) begin
    cs <= 1;
    clken <= 0;
    bitcnt <= 0;
    bytecnt <= 0;
    odat <= 0;
    state <= IDLE;
    cont_mode <= 0;
    xip_mode <= 0;
    mode <= 0;
    idat <= 0;
    rx_data <= 0;
    rd <= 0;
    wr <= 0;
    pre_wr <= 0;
    spi_done <= 0;
    tea_start <= 0;
    dma_addr <= 0;
    last_code_addr <= 0;
    timeout <= 0;
    code_rd_async_d <= 0;
end
else begin
    code_rd_async_d <= code_rd_async;
    rd <= 0;
    pre_wr <= 0;
    spi_done <= 0;
    idat <= shift_in;
    wr <= pre_wr;
    tea_start <= 0;
    if (~xip_mode & mram ? mram_wr_done : wr) begin
        rd_data <= code_data_enc;
        dma_addr <= dma_addr + 1;
    end
    case (state)
        IDLE: begin
            xip_mode <= 0;
            if (~cont_mode) mode <= 0;
            if (dma_en) begin
                rd <= 1;
                bitcnt <= 0;
                dma_addr <= tx_addr;
                bytecnt <= tx_len;
                state <= DMA_READ;
            end
            else if (xip_en & code_rd_t0) begin
                odat <= cont_mode ? flash_addr[23:16] : flash_read_cmd;
                bytecnt <= cont_mode ? 2 : 3;
                state <= START;
                xip_mode <= 1;
            end
        end

        DMA_READ: begin
            bitcnt <= bitcnt + 1;
            if (mram & bitcnt == (async ? 5 : 1) | ~mram & bitcnt == 15) begin
                odat <= tx_data;
                state <= START;
            end
        end

        START: begin
            cs <= 0;
            clken <= 1;
            state <= WRITE;
            bitcnt <= 0;
        end

        WRITE: begin
            odat <= qmode ? {odat, 4'd0} : dmode ? {odat, 2'd0} : {odat, 1'd0};
            bitcnt <= bitcnt + bitinc;
            if (bitcnt == bitmax) begin
                bitcnt <= 0;
                bytecnt <= byte_dec;
                if (bytecnt <= wslen) mode <= mode_set;
                if (xip_mode) begin
                    if (bytecnt == 0 & mbyte) begin
                        odat <= mbyte_cont_mode ? 8'ha0 : 0;
                        cont_mode <= mbyte_cont_mode;
                    end
                    else if (bytecnt == 0 & ~mbyte | bytecnt[4:0] == 5'h1f)
                        write_end;
                    else
                        odat <= flash_addr[byte_dec[1:0]*8+:8];
                end
                else if (bytecnt == 1) begin
                    write_end;
                    cont_mode <= mbyte_cont_mode;
                    if (rx_len == 0 & delay == 0) spi_end;
                end
                else begin
                    clken <= 0;
                    rd <= 1;
                    dma_addr <= dma_addr + 1;
                    state <= DMA_READ;
                end
            end
        end

        DELAY: begin
            if (bitcnt == 0)
                if (~xip_mode & rx_len == 0)
                    spi_end;
                else begin
                    state <= READ;
                    tea_start <= 1;
                end
            else
                bitcnt <= bitcnt - 1;
        end

        READ: begin
            bitcnt <= bitcnt + bitinc;
            if (bitcnt == bitmax) begin
                bitcnt <= 0;
                pre_wr <= 1;
                bytecnt <= bytecnt + 1;
                if (xip_mode) begin
                    if (bytecnt[4:0] == 31) begin
                        clken <= 0;
                        state <= WAIT_XIP;
                        last_code_addr <= code_addr;
                        timeout <= 0;
                    end
                end
                else if (bytecnt == rx_len - 1) spi_end;
            end
        end

        WAIT_XIP: begin
            bytecnt <= 0;
            //if (code_rd & bytecnt == 0 & ~wr) begin
            if (code_rd_t1 & bytecnt == 0 & ~wr) begin
                timeout <= 0;
                if (last_code_addr + 1 == code_addr) begin
                    state <= READ;
                    tea_start <= 1;
                    clken <= 1;
                end
                else
                    spi_end;
            end
            else if (~timeout[8])
                timeout <= timeout + 1;
            else
                spi_end;

            if (dma_en) begin
                spi_end;
                spi_done <= 0;
            end
        end
    endcase
end

always @(posedge spi_clk or negedge rstn)
if (~rstn) begin
    code_data_async <= 0;
    mram_wdata_async <= 0;
end
else begin
    if (code_valid0)
        code_data_async <= code_data_dec;
    if (mram_wr0)
        mram_wdata_async <= idat;

end

always @(posedge spi_clk or negedge rstn)
if (~rstn) begin
    mram_rdly <= 0;
    mram_rdata_async <= 0;
end
else begin
    mram_rdly <= mram_rd_async;
    if (mram_rdly)
        mram_rdata_async <= mram_rdata;
end

always @(posedge spi_clk or negedge rstn)
if (~rstn) begin
    ncs <= 1;
    spd_out <= 0;
    spd_en <= 0;
    clken_n <= 0;
    spd_in_dly <= 0;
end
else begin
    spd_in_dly <= spi_in;
    spd_out <= qmode ? odat[7:4] : dmode ? odat[7:6] : odat[7];
    spd_en <= state != WRITE ? 0 : qmode ? 4'b1111 : dmode ? 4'b0011 : 4'b0001;
    ncs <= cs;
    clken_n <= clken;
end

always @(posedge spi_clk or negedge rstn)
if (~rstn) begin
    wr_addr <= 0;
    lfsr <= 16'hffff;
    bus_rdata_sync <= 0;
    read <= 0;
    wr_dly <= 0;
    keycnt <= 0;
    remain <= 0;
    bus_rd_dly <= 0;
end
else begin
    bus_rd_dly <= bus_rd;
    wr_dly <= ~wdata_empty;
    if (bus_rd_dly) bus_rdata_sync <= bus_rdata;
    if (start) begin
        read <= 1;
        wr_addr <= rx_addr;
        lfsr <= 16'hffff;
        keycnt <= 0;
        remain <= tx_len;
    end
    else if (bus_rd) begin
        remain <= remain - 1;
        if (remain == 1) remain <= rx_len;
    end
    else if (bus_wr) begin
        keycnt <= keycnt + 1;
        remain <= remain - 1;
        if (auto_inc)
            wr_addr <= wr_addr + 1;
        lfsr <= crc16_ccitt(bus_wdata, lfsr);
    end
    if (read_sync) read <= 0;
end

/* ====== spi_clk to m0 ====== */

sync coderd(rstn, spi_clk, code_rd, code_rd_async);
psync codevld(rstn, spi_clk, code_valid0, mcu_clk, code_valid_async);
psync mramrd(rstn, spi_clk, mram_rd0, mcu_clk, mram_rd_async);
psync mramwr(rstn, spi_clk, mram_wr0, mcu_clk, mram_wr_async);
psync mramwrdone(rstn, mcu_clk, mram_wr_async, spi_clk, mram_wr_done);


/* ====== control signals from spi_clk to system ====== */

sync xipsync(rstn, spi_clk, xip, xip_en);
psync rdsync(rstn, spi_clk, rd & ~mram, bus_clk, bus_rd);
psync readsync(rstn, spi_clk, spi_done | state >= DELAY, bus_clk, read_sync);
acksync donesync(rstn, spi_clk, spi_done, bus_clk, start, done_sync);

/* ====== control signals from system to spi_clk ====== */

acksync mstsync(rstn, bus_clk, start, spi_clk, rd, dma_en);


async_fifo_qspi #(2, 8) qspi2sys (
    .din(idat),
    .wr_en(wr & ~mram & ~xip_mode),
    .wr_clk(spi_clk),
    .rd_en(1'b1),
    .rd_clk(bus_clk),
    .rstn(rstn),
    .dout(fifo_out),
    .items(),
    .empty(wdata_empty),
    .full(),
    .nearfull(),
    .scan_mode(1'b0),
    .bist_ctrl(4'b0),
    .bist_out()
);


task spi_end;
begin
    state <= IDLE;
    cs <= 1;
    clken <= 0;
    spi_done <= 1;
end
endtask

task write_end;
begin
    state <= delay == 0 ? READ : DELAY;
    tea_start <= delay == 0;
    bitcnt <= delay == 0 ? 0 : delay - 1;
    mode <= mode_set;
    bytecnt <= 0;
    dma_addr <= rx_addr;
end
endtask

function [15:0] crc16_ccitt;
input [7:0] DataByte;
input [15:0] PrevCrc;

reg [15:0] TempPrevCrc;
integer i;
begin
    TempPrevCrc = {PrevCrc[7:0], PrevCrc[15:8] ^ DataByte};
    TempPrevCrc = TempPrevCrc ^ TempPrevCrc[7:4];
    TempPrevCrc = TempPrevCrc ^ {TempPrevCrc, 12'd0};
    TempPrevCrc = TempPrevCrc ^ {TempPrevCrc[7:0], 5'd0};
    crc16_ccitt = TempPrevCrc;
end

endfunction

endmodule

