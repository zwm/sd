module sdio_dat (
    input rstn,
    input sd_rst,
    input sd_clk,
    // reg
    input [15:0] block_size,
    input [15:0] block_count, // 0: infinite, 1: single, others: multiple
    input dat_trans_dir, // 1: read, 0: write
    input dat_trans_width, // 0: 1-bit, 1: 4-bit
    input blk_gap_stop, // 1: stop, 0: continue, no need continue reg???
    input blk_gap_clk_en, // 1: stop, 0: continue, no need continue reg???
    input blk_gap_read_wait_en, // 1: drive DAT[2] low to stop card output
    output reg dat_crc_err_event,
    output reg dat_end_err_event,
    output blk_gap_event, // block gap can trigger irq
    output reg [2:0] tx_crc_status,
    output dat_busy, // indicate dat machine state
    output dat_done, // complete flag
    output [4:0] dat_fsm,
    // ctrl
    input tx_en,
    input rx_en,
    input dat_start, // cmd_end or software trigger
    output sd_clk_pause,
    output tmout_wait_rx_start_en,
    output tmout_wait_tx_crc_start_en,
    output tmout_wait_tx_crc_busy_en,
    // dma
    input dma_rx_buf_rdy, // write dma rx buf
    output reg [7:0] dma_rx_buf,
    output reg dma_rx_buf_wr,
    input dma_tx_byte_rdy, // read dma tx byte
    input [7:0] dma_tx_byte,
    output dma_tx_byte_end,
    // status
    // gpio
    input dat_0_i,
    input dat_1_i,
    input dat_2_i,
    input dat_3_i,
    output reg dat_0_o,
    output reg dat_1_o,
    output reg dat_2_o,
    output reg dat_3_o,
    output reg dat_0_oe,
    output reg dat_1_oe,
    output reg dat_2_oe,
    output reg dat_3_oe
);
// macro
`define     CRC_LEN             16
// var
reg [4:0] st_curr;
reg [4:0] st_next;
localparam IDLE                 = 5'd0;
localparam RX_START_BIT         = 5'd1; // stop timeout cnt
localparam RX_DATA_BYTE         = 5'd2;
localparam DMA_RX_BYTE_WR       = 5'd3;
localparam RX_CRC               = 5'd4;
localparam RX_END_BIT           = 5'd5;
localparam RX_BLK_GAP_STOP      = 5'd6;
localparam TX_PRE_PBIT          = 5'd7;
localparam TX_START_BIT         = 5'd8;
localparam DMA_TX_BYTE_RD       = 5'd9;
localparam TX_DATA_BYTE         = 5'd10;
localparam TX_CRC               = 5'd11;
localparam TX_END_BIT           = 5'd12;
localparam TX_WAIT_NCRC         = 5'd13;
localparam TX_CRC_STS_START     = 5'd14;
localparam TX_CRC_STS_DATA      = 5'd15;
localparam TX_CRC_STS_END       = 5'd16;
localparam TX_CHECK_BUSY        = 5'd17;
localparam TX_WAIT_BUSY         = 5'd18;
localparam TX_BLOCK_END         = 5'd19;
localparam TX_BLK_GAP_STOP      = 5'd20;
localparam WAIT_EIGHT_CYC       = 5'd21;
// wire
reg [2:0] bit_cnt;
reg [15:0] byte_cnt;
reg [15:0] blk_cnt;
wire dat_i_1b;
wire [3:0] dat_i_4b;
reg rx_start_flag;
reg rx_end_flag;
wire [2:0] bit_cnt_max;
wire [2:0] ncrc_cnt_max;
wire [2:0] crc_sts_cnt_max;
wire rx_block_end;
wire last_bit, last_byte, last_blk;
wire last_crc, last_ncrc, last_crc_sts;
wire last_chk_busy, last_tx_pbit;
wire crc_rst;
wire crc0_din, crc1_din, crc2_din, crc3_din;
wire crc0_din_en, crc1_din_en, crc2_din_en, crc3_din_en;
wire [`CRC_LEN-1:0] crc0, crc1, crc2, crc3;
wire tx_lane_0, tx_lane_1, tx_lane_2, tx_lane_3;
reg rx_crc_err, dma_tx_byte_flag;
// max
assign bit_cnt_max = dat_trans_width ? 3'd1 : 3'd7; // 4-bit: 2 cycles, 1-bit: 8 cycles
assign ncrc_cnt_max = 3'd0; // smih: 3, jesd: 2
assign crc_sts_cnt_max = 3'd2; // smih: 3, jesd: 3
// last
assign last_bit = (bit_cnt == bit_cnt_max);
assign last_byte = (byte_cnt == block_size);
assign last_blk = (block_count != 0) && (blk_cnt == block_count); // non-infinite
assign last_crc = (byte_cnt[3:0] == (`CRC_LEN - 1));
assign last_ncrc = (bit_cnt[2:0] == ncrc_cnt_max[2:0]);
assign last_crc_sts = (bit_cnt[2:0] == crc_sts_cnt_max[2:0]);
assign last_chk_busy = (bit_cnt[2:0] == 3'd7);
assign last_tx_pbit = (bit_cnt[2:0] == 3'd2); // Nwr = 2
// dat_i bus alias
assign dat_i_1b = dat_0_i;
assign dat_i_4b = {dat_3_i, dat_2_i, dat_1_i, dat_0_i};
// tx_lane
assign tx_lane_0 = dat_trans_width ? (bit_cnt[0] ? dma_tx_byte[0] : dma_tx_byte[4]) : dma_tx_byte[7 - bit_cnt];
assign tx_lane_1 = dat_trans_width ? (bit_cnt[0] ? dma_tx_byte[1] : dma_tx_byte[5]) : 1'b1;
assign tx_lane_2 = dat_trans_width ? (bit_cnt[0] ? dma_tx_byte[2] : dma_tx_byte[6]) : 1'b1;
assign tx_lane_3 = dat_trans_width ? (bit_cnt[0] ? dma_tx_byte[3] : dma_tx_byte[7]) : 1'b1;
// rx_start_flag
always @(*)
    if (dat_trans_width == 0) // 1-bit
        if (dat_i_1b == 1'b0)
            rx_start_flag = 1;
        else
            rx_start_flag = 0;
    else
        if (dat_i_4b == 4'b0000)
            rx_start_flag = 1;
        else
            rx_start_flag = 0;
// rx_end_flag
always @(*)
    if (dat_trans_width == 0) // 1-bit
        if (dat_i_1b == 1'b1)
            rx_end_flag = 1;
        else
            rx_end_flag = 0;
    else
        if (dat_i_4b == 4'b1111)
            rx_end_flag = 1;
        else
            rx_end_flag = 0;
// fsm, sync
always @(posedge sd_clk or negedge rstn) begin
    if (rstn == 1'b0) begin
        st_curr <= IDLE;
    end
    else begin
        if (sd_rst) begin
            st_curr <= IDLE;
        end
        else begin
            st_curr <= st_next;
        end
    end
end
// fsm, comb
always @(*) begin
    // default
    st_next = st_curr;
    // state trans
    case (st_curr)
        IDLE: begin
            if (dat_start) begin
                if (dat_trans_dir) begin // 1: read
                    st_next = RX_START_BIT;
                end
                else begin // 0: write
                    st_next = TX_PRE_PBIT;
                end
            end
        end
        RX_START_BIT: begin
            if (rx_en & rx_start_flag) begin
                st_next = RX_DATA_BYTE;
            end
        end
        RX_DATA_BYTE: begin
            if (rx_en) begin
                if (last_bit)
                    st_next = DMA_RX_BYTE_WR;
            end
        end
        DMA_RX_BYTE_WR: begin
            if (dma_rx_buf_rdy) begin // sd_clk freezed
                if (last_byte)
                    st_next = RX_CRC;
                else
                    st_next = RX_DATA_BYTE;
            end
        end
        RX_CRC: begin
            if (rx_en) begin
                if (last_crc)
                    st_next = RX_END_BIT;
            end
        end
        RX_END_BIT: begin
            if (rx_en) begin
                st_next = RX_BLK_GAP_STOP;
            end
        end
        RX_BLK_GAP_STOP: begin
            if (last_blk)
                st_next = IDLE; // 8 ???
            else if (blk_gap_stop == 0) // need more wait ???
                st_next = RX_START_BIT;
        end
        TX_PRE_PBIT: begin
            if (tx_en) begin
                if (last_tx_pbit)
                    st_next = TX_START_BIT;
            end
        end
        TX_START_BIT: begin
            if (tx_en) begin
                st_next = DMA_TX_BYTE_RD;
            end
        end
        DMA_TX_BYTE_RD: begin // no need tx_en
            if (dma_tx_byte_flag) begin
                st_next = TX_DATA_BYTE;
            end
        end
        TX_DATA_BYTE: begin
            if (tx_en) begin
                if (last_bit) begin
                    if (last_byte)
                        st_next = TX_CRC;
                    else
                        st_next = DMA_TX_BYTE_RD;
                end
            end
        end
        TX_CRC: begin
            if (tx_en) begin
                if (last_crc)
                    st_next = TX_END_BIT;
            end
        end
        TX_END_BIT: begin
            if (tx_en) begin
                st_next = TX_WAIT_NCRC;
            end
        end
        TX_WAIT_NCRC: begin
            if (rx_en) begin
                if (last_ncrc)
                    st_next = TX_CRC_STS_START;
            end
        end
        TX_CRC_STS_START: begin
            if (rx_en) begin
                if (dat_0_i == 1'b0) // valid start
                    st_next = TX_CRC_STS_DATA;
            end
        end
        TX_CRC_STS_DATA: begin
            if (rx_en) begin
                if (last_crc_sts)
                    st_next = TX_CRC_STS_END;
            end
        end
        TX_CRC_STS_END: begin
            if (rx_en) begin
                st_next = TX_CHECK_BUSY;
            end
        end
        TX_CHECK_BUSY: begin // smih, check if busy comes in 8 cycles
            if (rx_en) begin
                if (dat_0_i == 1'b0)
                    st_next = TX_WAIT_BUSY;
                else if (last_chk_busy)
                    st_next = TX_BLOCK_END;
            end
        end
        TX_WAIT_BUSY: begin
            if (rx_en) begin
                if (dat_0_i == 1'b1)
                    st_next = TX_BLOCK_END;
            end
        end
        TX_BLOCK_END: begin
            st_next = TX_BLK_GAP_STOP;
        end
        TX_BLK_GAP_STOP: begin
            if (last_blk)
                st_next = IDLE;
            else if (blk_gap_stop == 0)
                st_next = TX_PRE_PBIT;
        end
        default: begin
            st_next = IDLE;
        end
    endcase
end
// output, cnt & gpio
always @(posedge sd_clk or negedge rstn) begin
    if (~rstn) begin
        bit_cnt <= 0; byte_cnt <= 0; blk_cnt <= 0;
        dat_0_o <= 1'b1; dat_0_oe <= 1'b0;
        dat_1_o <= 1'b1; dat_1_oe <= 1'b0;
        dat_2_o <= 1'b1; dat_2_oe <= 1'b0;
        dat_3_o <= 1'b1; dat_3_oe <= 1'b0;
    end
    else begin
        case (st_curr)
            IDLE: begin
                bit_cnt <= 0; byte_cnt <= 0; blk_cnt <= 0;
                dat_0_o <= 1'b1; dat_0_oe <= 1'b0;
                dat_1_o <= 1'b1; dat_1_oe <= 1'b0;
                dat_2_o <= 1'b1; dat_2_oe <= 1'b0;
                dat_3_o <= 1'b1; dat_3_oe <= 1'b0;
            end
            RX_START_BIT: begin
                if (rx_en & rx_start_flag) begin
                    bit_cnt <= 0; // reset cnt at each block start
                    byte_cnt <= 0;
                end
            end
            RX_DATA_BYTE: begin
                if (rx_en) begin
                    if (last_bit) begin
                        bit_cnt <= 0;
                        byte_cnt <= byte_cnt + 1; // inc here, block_size 1 represent 1 byte
                    end
                    else
                        bit_cnt <= bit_cnt + 1;
                end
            end
            DMA_RX_BYTE_WR: begin
                if (dma_rx_buf_rdy) begin
                    if (last_byte)
                        byte_cnt <= 0; // clear for crc bit counter, only use [3:0]
                    //else
                    //    byte_cnt <= byte_cnt + 1; // inc here, block_size 0 represent 1 byte
                end
            end
            RX_CRC: begin
                if (rx_en) begin
                    byte_cnt[3:0] <= byte_cnt[3:0] + 1;
                end
            end
            RX_END_BIT: begin
                if (rx_en) begin
                    blk_cnt <= blk_cnt + 1;
                end
            end
            RX_BLK_GAP_STOP: begin
                if (last_blk == 0 && blk_gap_stop == 1 && blk_gap_read_wait_en == 1) begin // read wait, drive DAT[2] low
                    dat_2_o <= 1'b0;
                    dat_2_oe <= 1'b1;
                end
                else begin // release DAT[2]
                    dat_2_o <= 1'b1;
                    dat_2_oe <= 1'b0;
                end
            end
            TX_PRE_PBIT: begin
                // data lane drive high
                dat_0_o <= 1'b1; dat_0_oe <= 1'b1;
                if (dat_trans_width) begin
                    dat_1_o <= 1'b1; dat_1_oe <= 1'b1;
                    dat_2_o <= 1'b1; dat_2_oe <= 1'b1;
                    dat_3_o <= 1'b1; dat_3_oe <= 1'b1;
                end
                if (tx_en) begin
                    bit_cnt <= bit_cnt + 1; // pbit cnt
                end
            end
            TX_START_BIT: begin
                if (tx_en) begin
                    // data lane drive low
                    dat_0_o <= 1'b0;
                    if (dat_trans_width) begin
                        dat_1_o <= 1'b0;
                        dat_2_o <= 1'b0;
                        dat_3_o <= 1'b0;
                    end
                    bit_cnt <= 0; // init cnt
                    byte_cnt <= 0;
                end
            end
            DMA_TX_BYTE_RD: begin // no need tx_en
                if (dma_tx_byte_flag) begin
                    byte_cnt <= byte_cnt + 1;
                end
            end
            TX_DATA_BYTE: begin
                if (tx_en) begin
                    // data lane drive
                    dat_0_o <= tx_lane_0; dat_1_o <= tx_lane_1;
                    dat_2_o <= tx_lane_2; dat_3_o <= tx_lane_3;
                    // bit_cnt
                    if (last_bit)
                        bit_cnt <= 0;
                    else
                        bit_cnt <= bit_cnt + 1;
                    // byte_cnt
                    if (last_bit) begin
                        if (last_byte)
                            byte_cnt <= 0; // init crc byte_cnt[3:0]
                        //else
                        //    byte_cnt <= byte_cnt + 1; // same as rx
                    end
                end
            end
            TX_CRC: begin
                if (tx_en) begin
                    // data lane drive
                    if (~dat_trans_width) begin // 1-bit
                        dat_0_o <= crc0[`CRC_LEN - 1 - byte_cnt[3:0]];
                    end
                    else begin // 4-bit
                        dat_0_o <= crc0[`CRC_LEN - 1 - byte_cnt[3:0]];
                        dat_1_o <= crc1[`CRC_LEN - 1 - byte_cnt[3:0]];
                        dat_2_o <= crc2[`CRC_LEN - 1 - byte_cnt[3:0]];
                        dat_3_o <= crc3[`CRC_LEN - 1 - byte_cnt[3:0]];
                    end
                    // cnt
                    byte_cnt[3:0] <= byte_cnt[3:0] + 1;
                end
            end
            TX_END_BIT: begin
                if (tx_en) begin
                    // data lane drive
                    if (~dat_trans_width) begin // 1-bit
                        dat_0_o <= 1'b1;
                    end
                    else begin // 4-bit
                        dat_0_o <= 1'b1; dat_1_o <= 1'b1;
                        dat_2_o <= 1'b1; dat_3_o <= 1'b1;
                    end
                    // cnt
                    bit_cnt <= 0; // init ncrc cnt
                end
            end
            TX_WAIT_NCRC: begin
                // release data lane
                if (~dat_trans_width) begin
                    dat_0_o <= 1'b1; dat_0_oe <= 1'b0;
                end
                else begin
                    dat_0_o <= 1'b1; dat_0_oe <= 1'b0;
                    dat_1_o <= 1'b1; dat_1_oe <= 1'b0;
                    dat_2_o <= 1'b1; dat_2_oe <= 1'b0;
                    dat_3_o <= 1'b1; dat_3_oe <= 1'b0;
                end
                // cnt
                if (rx_en) begin
                    if (last_ncrc)
                        bit_cnt <= 0;
                    else
                        bit_cnt <= bit_cnt + 1;
                end
            end
            TX_CRC_STS_START: begin
            end
            TX_CRC_STS_DATA: begin
                if (rx_en) begin
                    if (last_crc_sts)
                        bit_cnt <= 0;
                    else
                        bit_cnt <= bit_cnt + 1;
                end
            end
            TX_CRC_STS_END: begin
            end
            TX_CHECK_BUSY: begin // smih, check if busy comes in 8 cycles
                if (rx_en) begin
                    if (last_chk_busy)
                        bit_cnt <= 0;
                    else
                        bit_cnt <= bit_cnt + 1;
                end
            end
            TX_WAIT_BUSY: begin
            end
            TX_BLOCK_END: begin
                blk_cnt <= blk_cnt + 1;
                bit_cnt <= 0; // may be used by state TX_PRE_PBIT 
            end
            TX_BLK_GAP_STOP: begin
            end
            default: begin
            end
        endcase
    end
end
// dma_rx_buf
always @(posedge sd_clk)
    if (st_curr == RX_DATA_BYTE)
        if (rx_en)
            if (dat_trans_width == 0) // 1-bit
                dma_rx_buf[7 - bit_cnt] <= dat_i_1b;
            else
                if (bit_cnt == 0)
                    dma_rx_buf[7:4] <= dat_i_4b;
                else
                    dma_rx_buf[3:0] <= dat_i_4b;
// wr_en
always @(posedge sd_clk or negedge rstn)
    if (~rstn)
        dma_rx_buf_wr <= 0;
    else if ((st_curr == DMA_RX_BYTE_WR) && (dma_rx_buf_rdy == 1))
        dma_rx_buf_wr <= 1;
    else
        dma_rx_buf_wr <= 0;
// dma_tx_byte_flag, ???
always @(posedge sd_clk or negedge rstn)
    if (~rstn)
        dma_tx_byte_flag <= 0;
    else if (dma_tx_byte_rdy) // 1 pulse, need latch
        dma_tx_byte_flag <= 1;
    else if (dma_tx_byte_end)
        dma_tx_byte_flag <= 0;
// tx_crc_status
always @(posedge sd_clk or negedge rstn)
    if (~rstn)
        tx_crc_status <= 3'b000;
    else if ((st_curr == TX_CRC_STS_DATA) && (rx_en == 1'b1))
        tx_crc_status <= {tx_crc_status[1:0], dat_0_i};
// CLK pause logic
//always @(posedge sd_clk or negedge rstn)
//    if (~rstn)
//        sd_clk_pause <= 0;
//    else 
//        if ((st_curr == DMA_RX_BYTE_WR) || (st_curr == DMA_TX_BYTE_RD)) // dma
//            sd_clk_pause <= 1;
//        else if ((blk_gap_clk_en == 0) && ((st_curr == RX_BLK_GAP_STOP) || (st_curr == TX_BLK_GAP_STOP))) // gap
//            sd_clk_pause <= 1;
//        else // default
//            sd_clk_pause <= 0;
assign sd_clk_pause = ((st_curr == DMA_RX_BYTE_WR) || (st_curr == DMA_TX_BYTE_RD)) || 
                      ((blk_gap_clk_en == 0) && ((st_curr == RX_BLK_GAP_STOP) || (st_curr == TX_BLK_GAP_STOP)));
// rx_crc_err
always @(posedge sd_clk or negedge rstn)
    if (~rstn)
        rx_crc_err <= 0;
    else
        if (st_curr == RX_START_BIT)
            rx_crc_err <= 0;
        else if (st_curr == RX_CRC)
            if (rx_en)
                if (~dat_trans_width) begin // 1-bit
                    if (dat_0_i != crc0[byte_cnt[3:0]])
                        rx_crc_err <= 1;
                end
                else begin // 4-bit
                    if ((dat_0_i != crc0[byte_cnt[3:0]]) || (dat_1_i != crc1[byte_cnt[3:0]]) ||
                        (dat_2_i != crc2[byte_cnt[3:0]]) || (dat_3_i != crc3[byte_cnt[3:0]]))
                        rx_crc_err <= 1;
                end
// crc_rst
assign crc_rst  = (st_curr == RX_START_BIT) || (st_curr == TX_START_BIT); // reset at block start
assign crc0_din_en = (st_curr == RX_DATA_BYTE && rx_en == 1) || (st_curr == TX_DATA_BYTE && tx_en == 1);
assign crc1_din_en = dat_trans_width & crc0_din_en;
assign crc2_din_en = crc1_din_en;
assign crc3_din_en = crc1_din_en;
assign crc0_din = (st_curr == RX_DATA_BYTE) ? dat_0_i : tx_lane_0;
assign crc1_din = (st_curr == RX_DATA_BYTE) ? dat_1_i : tx_lane_1;
assign crc2_din = (st_curr == RX_DATA_BYTE) ? dat_2_i : tx_lane_2;
assign crc3_din = (st_curr == RX_DATA_BYTE) ? dat_3_i : tx_lane_3;
// crc dat lane 0
sdio_crc16 u_crc0 (
    .rstn(rstn),
    .sd_rst(sd_rst),
    .sd_clk(sd_clk),
    .crc_rst(crc_rst),
    .crc_din_en(crc0_din_en),
    .crc_din(crc0_din),
    .crc(crc0)
);
// crc dat lane 1
sdio_crc16 u_crc1 (
    .rstn(rstn),
    .sd_rst(sd_rst),
    .sd_clk(sd_clk),
    .crc_rst(crc_rst),
    .crc_din_en(crc1_din_en),
    .crc_din(crc1_din),
    .crc(crc1)
);
// crc dat lane 2
sdio_crc16 u_crc2 (
    .rstn(rstn),
    .sd_rst(sd_rst),
    .sd_clk(sd_clk),
    .crc_rst(crc_rst),
    .crc_din_en(crc2_din_en),
    .crc_din(crc2_din),
    .crc(crc2)
);
// crc dat lane 3
sdio_crc16 u_crc3 (
    .rstn(rstn),
    .sd_rst(sd_rst),
    .sd_clk(sd_clk),
    .crc_rst(crc_rst),
    .crc_din_en(crc3_din_en),
    .crc_din(crc3_din),
    .crc(crc3)
);
// crc err, rx_crc_err or tx crc status error
always @(posedge sd_clk or negedge rstn)
    if (~rstn)
        dat_crc_err_event <= 0;
    else if ((st_curr == RX_END_BIT) && (rx_en == 1)) // rx_crc
        dat_crc_err_event <= rx_crc_err;
    else if ((st_curr == TX_CRC_STS_END) && (rx_en == 1)) // tx_crc, "010": pass, "101": fail
        dat_crc_err_event <= (tx_crc_status != 3'b010);
// end_err, rx_data or tx_crc_status
always @(posedge sd_clk or negedge rstn)
    if (~rstn)
        dat_end_err_event <= 0;
    else if ((st_curr == RX_END_BIT) && (rx_en == 1)) // rx_end bit
        dat_end_err_event <= ~rx_end_flag;
    else if ((st_curr == TX_CRC_STS_END) && (rx_en == 1)) // tx_crc_status end bit
        dat_end_err_event <= ~rx_end_flag;
// block gap event
assign blk_gap_event = ((st_curr == RX_END_BIT) && (st_next == RX_BLK_GAP_STOP)) ||
                       ((st_curr == TX_BLOCK_END) && (st_next == TX_BLK_GAP_STOP));
// status
assign dat_busy = (st_curr != IDLE);
//assign dat_done = (st_curr != IDLE) && (st_next == IDLE);
assign dat_done = ((st_curr == RX_BLK_GAP_STOP) || (st_curr == TX_BLK_GAP_STOP)) && (st_next == IDLE);
assign dat_fsm = st_curr[4:0];
// timeout
assign tmout_wait_rx_start_en = (st_curr == RX_START_BIT);
assign tmout_wait_tx_crc_start_en = (st_curr == TX_CRC_STS_START);
assign tmout_wait_tx_crc_busy_en = (st_curr == TX_WAIT_BUSY);
// dma_tx_byte_end
assign dma_tx_byte_end = (st_curr == TX_DATA_BYTE) && tx_en && last_bit;

endmodule
