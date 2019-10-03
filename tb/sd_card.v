module sd_card (
    input rstn,
    inout pad_clk,
    inout pad_cmd,
    inout [3:0] pad_dat
);
// reg [7:0] mem [2^16-1:0]; // using 2^16 memory
reg [7:0] mem [2**16-1:0]; // using 2^16 memory, must using "**" instead of "^"
wire sd_clk, cmd_i; reg cmd_o, cmd_oe;
wire [3:0] dat_i, dat_o, dat_oe;
reg [3:0] rd_dat_i, rd_dat_o, rd_dat_oe;
reg [3:0] wr_dat_i, wr_dat_o, wr_dat_oe;
reg [7:0] wr_data, rd_data;
reg [15:0] wr_crc0_tmp, wr_crc1_tmp, wr_crc2_tmp, wr_crc3_tmp; // debug only
reg [15:0] wr_crc0, wr_crc1, wr_crc2, wr_crc3; // debug only
// gpio
assign sd_clk = pad_clk;
assign cmd_i = pad_cmd;
assign dat_i = pad_dat;
assign pad_cmd = cmd_oe ? cmd_o : 1'bz;
assign dat_oe = rd_dat_oe | wr_dat_oe;
assign dat_o[0] = rd_dat_oe[0] ? rd_dat_o[0] : wr_dat_o[0];
assign dat_o[1] = rd_dat_oe[1] ? rd_dat_o[1] : wr_dat_o[1];
assign dat_o[2] = rd_dat_oe[2] ? rd_dat_o[2] : wr_dat_o[2];
assign dat_o[3] = rd_dat_oe[3] ? rd_dat_o[3] : wr_dat_o[3];
assign pad_dat[0] = dat_oe[0] ? dat_o[0] : 1'bz;
assign pad_dat[1] = dat_oe[1] ? dat_o[1] : 1'bz;
assign pad_dat[2] = dat_oe[2] ? dat_o[2] : 1'bz;
assign pad_dat[3] = dat_oe[3] ? dat_o[3] : 1'bz;
//---------------------------------------------------------------------------
// CMD
//---------------------------------------------------------------------------
localparam CMD_RX_IDLE          = 0; // RX
localparam CMD_RX_DATA          = 1;
localparam CMD_RX_END           = 2;
localparam CMD_TX_IDLE          = 0;
localparam CMD_TX_WAIT          = 1;
localparam CMD_TX_DATA          = 2;
localparam CMD_TX_BUSY          = 3;
localparam CMD_TX_END           = 4;
reg [3:0] cmd_rx_st, cmd_tx_st;
reg [31:0] cmd_rx_cnt, cmd_tx_cnt;
reg [46:0] cmd_dat;
wire rx_trans;
wire [5:0] rx_index;
wire [31:0] rx_arg;
wire [6:0] rx_crc;
wire rx_end;
reg [31:0] resp_len, resp_wait, resp_busy;
reg resp_trans;
reg [5:0] resp_index;
reg [119:0] resp_dat;
reg [6:0] resp_crc;
reg resp_end;
wire [135:0] resp;
wire cmd_trans;
wire [5:0] cmd_index;
wire [31:0] cmd_arg;
wire [6:0] cmd_crc;
wire cmd_end;
assign cmd_trans = cmd_dat[46];
assign cmd_index = cmd_dat[45:40];
assign cmd_arg = cmd_dat[39:8];
assign cmd_crc = cmd_dat[7:1];
assign cmd_end = cmd_dat[0];
reg [15:0] block_size, block_count;
reg bus_width;
// cmd
wire cmd_rx_end = (cmd_rx_st == CMD_RX_END);
wire cmd0  = cmd_rx_end == 1 && cmd_index == 0; // reset
wire cmd12 = cmd_rx_end == 1 && cmd_index == 12; // abort
wire cmd11 = cmd_rx_end == 1 && cmd_index == 11; // bus_width
wire cmd16 = cmd_rx_end == 1 && cmd_index == 16; // block_size
wire cmd17 = cmd_rx_end == 1 && cmd_index == 17;
wire cmd18 = cmd_rx_end == 1 && cmd_index == 18;
wire cmd23 = cmd_rx_end == 1 && cmd_index == 23; // block_count
wire cmd24 = cmd_rx_end == 1 && cmd_index == 24;
wire cmd25 = cmd_rx_end == 1 && cmd_index == 25;
// cmd parse
always @(posedge sd_clk or negedge rstn)
    if (~rstn) begin
        block_size <= 0;
        block_count <= 0;
        bus_width <= 0;
    end
    else begin
        // CMD16, block_size
        if (cmd16)
            block_size <= cmd_arg[15:0];
        // CMD23, block_count
        if (cmd23)
            block_count <= cmd_arg[15:0];
        // CMD11
        if (cmd11)
            bus_width <= cmd_arg[0];
    end
// resp
assign resp = (resp_len == 48) ? {1'b0, resp_trans, resp_index, resp_dat[ 31:0], resp_crc, resp_end, 88'h0} :
                                 {1'b0, resp_trans, resp_index, resp_dat[119:0], resp_crc, resp_end};
wire cmd_rx_start = (cmd_rx_st == CMD_RX_IDLE) && (cmd_i == 0);
// file 
initial begin: BLK_CMD_FILE
    // open file
    reg [64*8-1:0] s;
    integer fp, ret;
    @(posedge `TOP_RSTN);
    // init
    fp = $fopen({`TOP_CASE_DIR, "card_resp.dat"}, "r");
    begin: LP_SIM
        while(1) begin
            @(negedge sd_clk);
            // sim_end check
            if (`TOP_SIM_END == 1) begin
                disable LP_SIM;
            end
            // new command
            if (cmd_rx_start) begin
                ret = $fgets(s, fp); // skip comment
                $display("%t, File: card_resp, Comment: %s", $time, s);
                ret = $fscanf(fp, "%s %d", s, resp_len);
                if (resp_len == 0) begin
                    resp_wait = 0; resp_busy = 0; resp_trans = 0; // init
                    $display("%t, File: card_resp, no response command", $time);
                end
                else begin
                    ret = $fscanf(fp, "%s %d", s, resp_wait);
                    ret = $fscanf(fp, "%s %d", s, resp_busy);
                    ret = $fscanf(fp, "%s %h", s, resp_trans);
                    ret = $fscanf(fp, "%s %h", s, resp_index);
                    ret = $fscanf(fp, "%s %h", s, resp_dat);
                    ret = $fscanf(fp, "%s %h", s, resp_crc);
                    ret = $fscanf(fp, "%s %h", s, resp_end);
                end
            end
        end
    end
    // close file
    $fclose(fp);
end
// cmd rx, posedge
always @(posedge sd_clk or negedge rstn)
    if (~rstn) begin
        cmd_rx_st <= CMD_RX_IDLE;
        cmd_rx_cnt <= 0; cmd_dat <= 0;
    end
    else begin
        case (cmd_rx_st)
            CMD_RX_IDLE: begin
                cmd_rx_cnt <= 0;
                if (cmd_i == 0) begin
                    cmd_rx_st <= CMD_RX_DATA;
                    cmd_dat <= 0;
                end
            end
            CMD_RX_DATA: begin
                if (cmd_rx_cnt == 46) begin
                    cmd_rx_st <= CMD_RX_END;
                    cmd_rx_cnt <= 0;
                end
                else begin
                    cmd_rx_cnt <= cmd_rx_cnt + 1;
                    cmd_dat[46 - cmd_rx_cnt] = cmd_i;
                end
            end
            CMD_RX_END: begin
                cmd_rx_st <= CMD_RX_IDLE;
            end
        endcase
    end
wire cmd_tx_start = (cmd_rx_st == CMD_RX_END) && (resp_len != 0);
// cmd tx, negedge
always @(negedge sd_clk or negedge rstn)
    if (~rstn) begin
        cmd_tx_st <= CMD_TX_IDLE;
        cmd_tx_cnt <= 0;
        cmd_o <= 0; cmd_oe <= 0;
    end
    else begin
        case (cmd_tx_st)
            CMD_TX_IDLE: begin
                cmd_o <= 0; cmd_oe <= 0;
                cmd_tx_cnt <= 0;
                if (cmd_tx_start == 1) begin
                    cmd_tx_st <= CMD_TX_WAIT;
                end
            end
            CMD_TX_WAIT: begin
                if (cmd_tx_cnt == resp_busy) begin
                    cmd_tx_cnt <= 0;
                    cmd_tx_st <= CMD_TX_DATA;
                end
                else begin
                    cmd_tx_cnt <= cmd_tx_cnt + 1;
                end
            end
            CMD_TX_DATA: begin
                if (cmd_tx_cnt == (resp_len - 1)) begin
                    cmd_tx_cnt <= 0;
                    cmd_oe <= 0;
                    if (resp_busy != 0)
                        cmd_tx_st <= CMD_TX_BUSY;
                    else
                        cmd_tx_st <= CMD_TX_END;
                end
                else begin
                    cmd_o <= resp[135 - cmd_tx_cnt];
                    cmd_oe <= 1;
                    cmd_tx_cnt <= cmd_tx_cnt + 1;
                end
            end
            CMD_TX_BUSY: begin
                if (cmd_tx_cnt == resp_busy)
                    cmd_tx_st <= CMD_TX_END;
                else
                    cmd_tx_cnt <= cmd_tx_cnt + 1;
            end
            CMD_TX_END: begin
                cmd_tx_st <= CMD_TX_IDLE;
            end
        endcase
    end
//---------------------------------------------------------------------------
// DATA TASK
//---------------------------------------------------------------------------
// crc
wire sd_rst, crc_rst, rd_crc_rst, wr_crc_rst;
wire crc0_din_en, crc1_din_en, crc2_din_en, crc3_din_en;
wire crc0_din, crc1_din, crc2_din, crc3_din;
wire [15:0] crc0, crc1, crc2, crc3;
wire rd_crc_en, wr_crc_en;
wire [3:0] rd_crc_din, wr_crc_din;
wire dat_blk_req_rd, dat_blk_req_wr;
reg [31:0] rd_wait_max, crc_wait_max, busy_wait_max;
wire [2:0] bit_cnt_max;
assign bit_cnt_max = bus_width ? 3'd1 : 3'd7;
// file 
initial begin: BLK_DAT_FILE
    // open file
    reg [64*8-1:0] s;
    integer fp, ret;
    @(posedge `TOP_RSTN);
    fp = $fopen({`TOP_CASE_DIR, "card_dat.dat"}, "r");
    begin: LP_SIM
        while(1) begin
            @(posedge sd_clk);
            // sim_end check
            if (`TOP_SIM_END == 1) begin
                disable LP_SIM;
            end
            // new command
            if (dat_blk_req_rd | dat_blk_req_wr) begin
                ret = $fgets(s, fp); // skip comment
                $display("%t, File: card_dat, Comment: %s", $time, s);
                ret = $fscanf(fp, "%s %d", s, rd_wait_max);
                ret = $fscanf(fp, "%s %d", s, crc_wait_max);
                ret = $fscanf(fp, "%s %d", s, busy_wait_max);
                $display("%t, File: card_dat, rd_wait: %d, crc_wait: %d, busy_wait: %d", $time, rd_wait_max, crc_wait_max, busy_wait_max);
            end
        end
    end
    // close file
    $fclose(fp);
end
// crc
assign sd_rst = 1'b0;
assign crc_rst = rd_crc_rst | wr_crc_rst;
assign crc0_din_en = rd_crc_en | wr_crc_en;
assign crc1_din_en = crc0_din_en;
assign crc2_din_en = crc0_din_en;
assign crc3_din_en = crc0_din_en;
assign crc0_din = rd_crc_en ? rd_crc_din[0] : wr_crc_din[0];
assign crc1_din = rd_crc_en ? rd_crc_din[1] : wr_crc_din[1];
assign crc2_din = rd_crc_en ? rd_crc_din[2] : wr_crc_din[2];
assign crc3_din = rd_crc_en ? rd_crc_din[3] : wr_crc_din[3];
// crc
assign sd_rst = 1'b0;
assign crc_rst = rd_crc_rst | wr_crc_rst;
assign crc0_din_en = rd_crc_en | wr_crc_en;
assign crc1_din_en = crc0_din_en;
assign crc2_din_en = crc0_din_en;
assign crc3_din_en = crc0_din_en;
assign crc0_din = rd_crc_en ? rd_crc_din[0] : wr_crc_din[0];
assign crc1_din = rd_crc_en ? rd_crc_din[1] : wr_crc_din[1];
assign crc2_din = rd_crc_en ? rd_crc_din[2] : wr_crc_din[2];
assign crc3_din = rd_crc_en ? rd_crc_din[3] : wr_crc_din[3];
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
//---------------------------------------------------------------------------
// DATA RX
//---------------------------------------------------------------------------
wire rd_clk = ~sd_clk; // falling edge
reg [3:0] rd_st;
reg [2:0] rd_bit_cnt;
reg [15:0] rd_byte_cnt, rd_blk_cnt;
reg [31:0] rd_wait_cnt, rd_addr;
localparam RD_IDLE          = 0;
localparam RD_WAIT          = 1;
localparam RD_START         = 2;
localparam RD_DATA          = 3;
localparam RD_CRC           = 4;
localparam RD_END           = 5;
// main
always @(posedge rd_clk or negedge rstn)
    if (~rstn) begin
        rd_st <= RD_IDLE;
        rd_bit_cnt <= 0; rd_byte_cnt <= 0;
        rd_blk_cnt <= 0; rd_wait_cnt <= 0;
        rd_dat_o <= 0; rd_dat_oe <= 0;
        rd_addr <= 0;
    end
    else if (cmd0 | cmd12) begin
        rd_st <= RD_IDLE;
        rd_bit_cnt <= 0; rd_byte_cnt <= 0;
        rd_blk_cnt <= 0; rd_wait_cnt <= 0;
        rd_dat_o <= 0; rd_dat_oe <= 0;
        rd_addr <= 0;
    end
    else begin
        case (rd_st)
            RD_IDLE: begin
                rd_dat_o <= 0; rd_dat_oe <= 0;
                rd_bit_cnt <= 0; rd_byte_cnt <= 0; rd_wait_cnt <= 0;
                if (cmd17 || cmd18) begin // single block
                    rd_st <= RD_WAIT;
                    rd_addr <= cmd_arg;
                    if (cmd17) // single
                        rd_blk_cnt <= 1;
                    else if (cmd18) // multiple
                        rd_blk_cnt <= (block_count == 0) ? 32'hffff_ffff : block_count; // infinite or limited
                end
            end
            RD_WAIT: begin
                if (rd_wait_cnt == rd_wait_max) begin
                    rd_st <= RD_START;
                    rd_bit_cnt <= 0;
                    rd_byte_cnt <= 0;
                    rd_wait_cnt <= 0;
                end
                else begin
                    rd_wait_cnt <= rd_wait_cnt + 1;
                end
            end
            RD_START: begin
                rd_st <= RD_DATA;
                if (~bus_width) begin
                    rd_dat_o[0] <= 1'b0;
                    rd_dat_oe[0] <= 1'b1;
                end
                else begin
                    rd_dat_o <= 4'h0;
                    rd_dat_oe <= 4'hf;
                end
            end
            RD_DATA: begin
                // cnt
                if (rd_bit_cnt == bit_cnt_max) begin
                    rd_bit_cnt <= 0;
                    rd_addr <= rd_addr + 1;
                    if ((rd_byte_cnt + 1) == block_size) begin
                        rd_st <= RD_CRC;
                        rd_byte_cnt <= 0;
                    end
                    else begin
                        rd_byte_cnt <= rd_byte_cnt + 1;
                    end
                end
                else begin
                    rd_bit_cnt <= rd_bit_cnt + 1;
                end
                // output
                if (~bus_width) begin
                    rd_dat_o[0] <= mem[rd_addr][7 - rd_bit_cnt]; // reverse ???
                    rd_dat_oe[0] <= 1'b1;
                end
                else begin
                    if (~rd_bit_cnt[0]) begin
                        rd_dat_o <= mem[rd_addr[15:0]][7:4];
                        rd_dat_oe <= 4'hf;
                    end
                    else begin
                        rd_dat_o <= mem[rd_addr[15:0]][3:0];
                        rd_dat_oe <= 4'hf;
                    end
                end
                if (rd_bit_cnt == 0) rd_data <= mem[rd_addr];
            end
            RD_CRC: begin
                // cnt
                if (rd_byte_cnt == 15) begin
                    rd_blk_cnt <= rd_blk_cnt - 1;
                    rd_byte_cnt <= 0;
                    rd_st <= RD_END;
                end
                else begin
                    rd_byte_cnt <= rd_byte_cnt + 1;
                end
                // output
                if (~bus_width) begin
                    rd_dat_o[0] <= crc0[rd_byte_cnt];
                    rd_dat_oe[0] <= 1'b1;
                end
                else begin
                    rd_dat_o[0] <= crc0[rd_byte_cnt];
                    rd_dat_o[1] <= crc1[rd_byte_cnt];
                    rd_dat_o[2] <= crc2[rd_byte_cnt];
                    rd_dat_o[3] <= crc3[rd_byte_cnt];
                    rd_dat_oe <= 4'hf;
                end
            end
            RD_END: begin
                // state
                if (rd_blk_cnt == 0)
                    rd_st <= RD_IDLE;
                else
                    rd_st <= RD_WAIT;
                // output
                if (~bus_width) begin
                    rd_dat_o[0] <= 1'b1;
                    rd_dat_oe[0] <= 1'b1;
                end
                else begin
                    rd_dat_o <= 4'hf;
                    rd_dat_oe <= 4'hf;
                end
            end
            default: begin
                rd_st <= RD_IDLE;
            end
        endcase
    end
// crc
assign rd_crc_rst = (rd_st == RD_START); // each block start
assign rd_crc_en = (rd_st == RD_DATA) || (rd_st == RD_CRC && rd_byte_cnt == 0);
assign rd_crc_din = rd_dat_o;
assign dat_blk_req_rd = ((rd_st == RD_IDLE) && (cmd17 | cmd18)) || (rd_st == RD_END && rd_blk_cnt != 0);
//---------------------------------------------------------------------------
// DATA TX
//---------------------------------------------------------------------------
wire wr_clk = sd_clk; // rising edge
reg [3:0] wr_st;
reg [2:0] wr_bit_cnt;
reg [15:0] wr_byte_cnt, wr_blk_cnt;
reg [31:0] wr_wait_cnt, wr_addr;
reg [7:0] wr_byte;
reg wr_crc_err;
wire [2:0] wr_crc_sts;
localparam WR_IDLE          = 0;
localparam WR_START         = 1;
localparam WR_DATA          = 2;
localparam WR_CRC           = 3;
localparam WR_END           = 4;
localparam WR_CRC_WAIT      = 6;
localparam WR_CRC_START     = 7;
localparam WR_CRC_STS       = 8;
localparam WR_CRC_END       = 9;
localparam WR_CRC_BUSY      = 10;
// main
always @(posedge wr_clk or negedge rstn)
    if (~rstn) begin
        wr_st <= WR_IDLE; wr_data <= 0;
        wr_bit_cnt <= 0; wr_byte_cnt <= 0; 
        wr_blk_cnt <= 0; wr_wait_cnt <= 0;
        wr_dat_o <= 0; wr_dat_oe <= 0;
        wr_addr <= 0; wr_byte <= 0;
    end
    else if (cmd0 | cmd12) begin
        wr_st <= WR_IDLE; wr_data <= 0;
        wr_bit_cnt <= 0; wr_byte_cnt <= 0; 
        wr_blk_cnt <= 0; wr_wait_cnt <= 0;
        wr_dat_o <= 0; wr_dat_oe <= 0;
        wr_addr <= 0; wr_byte <= 0;
    end
    else begin
        case (wr_st)
            WR_IDLE: begin
                wr_dat_o <= 0; wr_dat_oe <= 0; wr_data <= 0;
                wr_bit_cnt <= 0; wr_byte_cnt <= 0; wr_wait_cnt <= 0;
                if (cmd24 | cmd25) begin
                    wr_st <= WR_START;
                    wr_addr <= cmd_arg;
                    if (cmd24)
                        wr_blk_cnt <= 1;
                    else if (cmd25)
                        wr_blk_cnt <= block_count == 0 ? 32'hffff_ffff : block_count;
                end
            end
            WR_START: begin
                if (~bus_width) begin
                    if (dat_i[0] == 0) begin
                        wr_bit_cnt <= 0; wr_byte_cnt <= 0; wr_wait_cnt <= 0;
                        wr_st <= WR_DATA;
                    end
                end
                else begin
                    if (dat_i[3:0] == 4'h0) begin
                        wr_bit_cnt <= 0; wr_byte_cnt <= 0; wr_wait_cnt <= 0;
                        wr_st <= WR_DATA;
                    end
                end
            end
            WR_DATA: begin
                // cnt
                if (wr_bit_cnt == bit_cnt_max) begin
                    wr_bit_cnt <= 0;
                    wr_addr <= wr_addr + 1;
                    if ((wr_byte_cnt + 1) == block_size) begin
                        wr_byte_cnt <= 0;
                        wr_st <= WR_CRC;
                    end
                    else begin
                        wr_byte_cnt <= wr_byte_cnt + 1;
                    end
                end
                else begin
                    wr_bit_cnt <= wr_bit_cnt + 1;
                end
                // dat
                if (~bus_width) begin
                    wr_byte[7 - wr_bit_cnt] <= dat_i[0];
                end
                else begin
                    if (~wr_bit_cnt[0])
                        wr_byte[7:4] <= dat_i[3:0];
                    else
                        wr_byte[3:0] <= dat_i[3:0];
                end
                // mem
                if (wr_bit_cnt == bit_cnt_max) begin
                    if (~bus_width) begin
                        mem[wr_addr[15:0]] <= {wr_byte[7:1], dat_i[0]};
                        wr_data <= {wr_byte[7:1], dat_i[0]}; // debug only
                    end
                    else begin
                        mem[wr_addr[15:0]] <= {wr_byte[7:4], dat_i[3:0]};
                        wr_data <= {wr_byte[7:4], dat_i[3:0]}; // debug only
                    end
                end
            end
            WR_CRC: begin
                if (wr_byte_cnt == 15) begin
                    wr_st <= WR_END;
                    wr_byte_cnt <= 0;
                end
                else begin
                    wr_byte_cnt <= wr_byte_cnt + 1;
                end
            end
            WR_END: begin
                wr_st <= WR_CRC_WAIT;
                wr_wait_cnt <= 0;
            end
            WR_CRC_WAIT: begin
                if (wr_wait_cnt == crc_wait_max) begin
                    wr_st <= WR_CRC_START;
                    wr_wait_cnt <= 0;
                end
                else begin
                    wr_wait_cnt <= wr_wait_cnt + 1;
                end
            end
            WR_CRC_START: begin
                wr_st <= WR_CRC_STS;
                wr_byte_cnt <= 0;
                wr_dat_o[0] <= 1'b0; wr_dat_oe[0] <= 1'b1;
            end
            WR_CRC_STS: begin
                // cnt
                if (wr_byte_cnt == 2) begin // total 3-bit
                    wr_byte_cnt <= 0;
                    wr_st <= WR_CRC_END;
                end
                else begin
                    wr_byte_cnt <= wr_byte_cnt + 1;
                end
                // output
                wr_dat_o[0] <= wr_crc_sts[2 - wr_byte_cnt[1:0]];
            end
            WR_CRC_END: begin
                wr_st <= WR_CRC_BUSY;
                wr_dat_o[0] <= 1'b1;
                wr_wait_cnt <= 0;
                wr_blk_cnt <= wr_blk_cnt - 1;
            end
            WR_CRC_BUSY: begin
                if (wr_wait_cnt == busy_wait_max) begin
                    wr_wait_cnt <= 0;
                    wr_dat_o[0] <= 1'b0; wr_dat_oe[0] <= 1'b0; // disable output
                    if (wr_blk_cnt == 0) wr_st <= WR_IDLE;
                    else wr_st <= WR_START;
                end
                else begin
                    wr_wait_cnt <= wr_wait_cnt + 1;
                    wr_dat_o[0] <= 1'b0; wr_dat_oe[0] <= 1'b1; // assert busy
                end
            end
        endcase
    end
// crc
assign wr_crc_rst = (wr_st == WR_START); // each block start
assign wr_crc_en = (wr_st == WR_DATA);
assign wr_crc_din = dat_i[3:0];
assign dat_blk_req_wr = (wr_st == WR_START) && (bus_width ? dat_i[3:0] == 4'h0 : dat_i[0] == 1'b0);
always @(posedge sd_clk)
    if (wr_st == WR_START) begin
        wr_crc_err <= 0;
    end
    else if (wr_st == WR_CRC) begin
        if (~bus_width) begin
            wr_crc0_tmp[15 - wr_byte_cnt[3:0]] <= dat_i[0];
            if (wr_byte_cnt[3:0] == 15) wr_crc0 <= {wr_crc0_tmp[15:1], dat_i[0]};
            if (dat_i[0] != crc0[15 - wr_byte_cnt[3:0]]) begin
                wr_crc_err <= 1;
            end
        end
        else begin
            wr_crc0_tmp[15 - wr_byte_cnt[3:0]] <= dat_i[0];
            wr_crc1_tmp[15 - wr_byte_cnt[3:0]] <= dat_i[1];
            wr_crc2_tmp[15 - wr_byte_cnt[3:0]] <= dat_i[2];
            wr_crc3_tmp[15 - wr_byte_cnt[3:0]] <= dat_i[3];
            if (wr_byte_cnt[3:0] == 15) wr_crc0 <= {wr_crc0_tmp[15:1], dat_i[0]};
            if (wr_byte_cnt[3:0] == 15) wr_crc1 <= {wr_crc1_tmp[15:1], dat_i[1]};
            if (wr_byte_cnt[3:0] == 15) wr_crc2 <= {wr_crc2_tmp[15:1], dat_i[2]};
            if (wr_byte_cnt[3:0] == 15) wr_crc3 <= {wr_crc3_tmp[15:1], dat_i[3]};
            if ((dat_i[0] != crc0[15 - wr_byte_cnt[3:0]]) ||
                (dat_i[1] != crc1[15 - wr_byte_cnt[3:0]]) ||
                (dat_i[2] != crc2[15 - wr_byte_cnt[3:0]]) ||
                (dat_i[3] != crc3[15 - wr_byte_cnt[3:0]])) begin
                wr_crc_err <= 1;
            end
        end
    end
assign wr_crc_sts = wr_crc_err ? 3'b101 : 3'b010;

endmodule

