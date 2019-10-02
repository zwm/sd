// clk&rst
initial begin
    rstn = 0;
    sd_clk = 0;
    bus_clk = 0;
    #1000;
    rstn = 1;
    #10000;
    fork
        forever #42 bus_clk = ~bus_clk; // 12MHz
        forever #10 sd_clk = ~sd_clk; // 48M
    join
end
// sys_init
task sys_init;
    begin
        sim_end = 0;
    end
endtask
// wr_reg
task wr_reg;
    input [7:0] addr;
    input [7:0] wdata;
    begin
        // write addr
        @(posedge bus_clk);
        reg_data_wr = 0;
        reg_addr = addr;
        repeat(2) @(posedge bus_clk);
        reg_data_wr = 1;
        reg_wdata = wdata;
        // clear wr
        @(posedge bus_clk);
        reg_data_wr = 0;
    end
endtask
// rd_reg
task rd_reg;
    input [7:0] addr;
    output [7:0] rdata;
    begin
        // write addr
        @(posedge bus_clk);
        reg_data_wr = 0;
        reg_addr = addr;
        repeat(2) @(posedge bus_clk);
        // read data
        @(posedge bus_clk);
        rdata = reg_rdata;
    end
endtask
// set_dma_start_addr
task set_dma_start_addr;
    input [15:0] val;
    begin
        wr_reg(130, val[7:0]);
        wr_reg(131, val[15:8]);
    end
endtask
// set_dma_start_addr
task set_dma_len;
    input [15:0] val;
    begin
        wr_reg(132, val[7:0]);
        wr_reg(133, val[15:8]);
    end
endtask
// set_rsp_typ
task set_rsp_typ;
    input [1:0] val;
    reg [7:0] tmp;
    begin
        rd_reg(8, tmp);
        tmp = {tmp[7:2], val[1:0]};
        wr_reg(8, tmp);
    end
endtask
// set_bus_width
task set_bus_width;
    input val;
    reg [7:0] tmp;
    begin
        rd_reg(8, tmp);
        tmp = {tmp[7], val, tmp[5:0]};
        wr_reg(8, tmp);
    end
endtask
// set_trans_dir
task set_trans_dir;
    input val;
    reg [7:0] tmp;
    begin
        rd_reg(8, tmp);
        tmp = {tmp[7:6], val, tmp[4:0]};
        wr_reg(8, tmp);
    end
endtask
// set_dat_pres
task set_dat_pres;
    input val;
    reg [7:0] tmp;
    begin
        rd_reg(8, tmp);
        tmp = {tmp[7:5], val, tmp[3:0]};
        wr_reg(8, tmp);
    end
endtask
// set_cmd_idx
task set_cmd_idx;
    input [5:0] val;
    begin
        wr_reg(9, val);
    end
endtask
// set_blk_size
task set_blk_size;
    input [15:0] val;
    begin
        wr_reg(0, val[7:0]);
        wr_reg(1, val[15:8]);
    end
endtask
// set_blk_cnt
task set_blk_cnt;
    input [15:0] val;
    begin
        wr_reg(2, val[7:0]);
        wr_reg(3, val[15:8]);
    end
endtask
// set_cmd_arg
task set_cmd_arg;
    input [31:0] val;
    begin
        wr_reg(4, val[7:0]);
        wr_reg(5, val[15:8]);
        wr_reg(6, val[23:16]);
        wr_reg(7, val[31:24]);
    end
endtask
// get_irq_sts
task get_irq_sts;
    output [7:0] val;
    begin
        rd_reg(32, val);
    end
endtask
// cmd
task wait_cmd;
    reg [7:0] tmp;
    begin
        begin: LP_CHK
            while(1) begin
                // get sts
                get_irq_sts(tmp);
                if (tmp[0] == 1) disable LP_CHK;
                repeat(`COMPLETE_POLL_GAP) @(posedge tb_top.sdio_pad_clk);
            end
        end
    end
endtask
// dat
task wait_dat;
    reg [7:0] tmp;
    begin
        begin: LP_CHK
            while(1) begin
                // get sts
                get_irq_sts(tmp);
                if (tmp[1] == 1) disable LP_CHK;
                repeat(`COMPLETE_POLL_GAP) @(posedge tb_top.sdio_pad_clk);
            end
        end
    end
endtask
// set_sd_clk_div
task set_sd_clk_div;
    input [7:0] val;
    begin
        wr_reg(29, val);
    end
endtask
// set_sd_clk_en
task set_sd_clk_en;
    input val;
    begin
        wr_reg(28, val);
    end
endtask
// irq_flag_clr
task irq_flag_clr;
    begin
        wr_reg(32, 8'h1f);
    end
endtask
// set_card_blk_size
task set_card_blk_size;
    input [31:0] val;
    begin
        irq_flag_clr;
        set_cmd_arg(val);
        set_rsp_typ(`RSP_NONE);
        set_cmd_idx(16); // start command
        wait_cmd;
    end
endtask
// set_card_blk_cnt
task set_card_blk_cnt;
    input [31:0] val;
    begin
        irq_flag_clr;
        set_cmd_arg(val);
        set_rsp_typ(`RSP_NONE);
        set_cmd_idx(23); // start command
        wait_cmd;
    end
endtask
// set_card_bus_width
task set_card_bus_width;
    input val;
    begin
        irq_flag_clr;
        set_cmd_arg(val);
        set_rsp_typ(`RSP_NONE);
        set_cmd_idx(11); // start command
        wait_cmd;
    end
endtask
// set_card_abort
task set_card_abort;
    input val;
    begin
        irq_flag_clr;
        set_cmd_arg(val);
        set_rsp_typ(`RSP_NONE);
        set_cmd_idx(12); // start command
        wait_cmd;
    end
endtask
// set_card_rst
task set_card_rst;
    input val;
    begin
        irq_flag_clr;
        set_cmd_arg(val);
        set_rsp_typ(`RSP_NONE);
        set_cmd_idx(0); // start command
        wait_cmd;
    end
endtask
// cmd_single_rd
task cmd_single_rd;
    begin
        set_cmd_idx(17);
    end
endtask
// cmd_multiple_rd
task cmd_multiple_rd;
    begin
        set_cmd_idx(18);
    end
endtask
// cmd_single_wr
task cmd_single_wr;
    begin
        set_cmd_idx(24);
    end
endtask
// cmd_multiple_wr
task cmd_multiple_wr;
    begin
        set_cmd_idx(25);
    end
endtask
// wr_blk
task wr_blk;
    input bus_width;
    input [31:0] blk_size;
    input [31:0] blk_cnt;
    begin
        // dma
        set_dma_start_addr(16'd0);
        set_dma_len(16'd1023);
        // set card
        set_card_rst(1);
        set_card_blk_size(blk_size);
        set_card_blk_cnt(blk_cnt);
        if (~bus_width)
            set_card_bus_width(`BUS_WIDTH_1_BIT);
        else
            set_card_bus_width(`BUS_WIDTH_4_BIT);
        // set host
        set_blk_size(blk_size);
        set_blk_cnt(blk_cnt);
        set_dat_pres(`DAT_PRESENT_ON);
        if (~bus_width)
            set_bus_width(`BUS_WIDTH_1_BIT);
        else
            set_bus_width(`BUS_WIDTH_4_BIT);
        set_trans_dir(`TRANS_DIR_WR);
        // start
        cmd_multiple_wr;
    end
endtask
// wr_rd_blk
task wr_rd_blk;
    input bus_width;
    input [31:0] blk_size;
    input [31:0] blk_cnt;
    begin
        // dma
        set_dma_start_addr(16'd0);
        set_dma_len(16'd1023);
        // set card
        set_card_rst(1);
        set_card_blk_size(blk_size);
        set_card_blk_cnt(blk_cnt);
        if (~bus_width)
            set_card_bus_width(`BUS_WIDTH_1_BIT);
        else
            set_card_bus_width(`BUS_WIDTH_4_BIT);
        // set host
        set_blk_size(blk_size);
        set_blk_cnt(blk_cnt);
        set_dat_pres(`DAT_PRESENT_ON);
        if (~bus_width)
            set_bus_width(`BUS_WIDTH_1_BIT);
        else
            set_bus_width(`BUS_WIDTH_4_BIT);
        set_trans_dir(`TRANS_DIR_WR);
        // start
        cmd_multiple_wr;
        wait_dat; irq_flag_clr;
        // gap
        repeat (100) @(posedge sd_clk);
        // read
        set_blk_size(blk_size);
        set_blk_cnt(blk_cnt);
        set_dat_pres(`DAT_PRESENT_ON);
        if (~bus_width)
            set_bus_width(`BUS_WIDTH_1_BIT);
        else
            set_bus_width(`BUS_WIDTH_4_BIT);
        set_trans_dir(`TRANS_DIR_RD);
        // start
        cmd_multiple_rd;
        wait_dat; irq_flag_clr;
    end
endtask


