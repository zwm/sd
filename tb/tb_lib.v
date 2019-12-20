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
        reg_data_wr = 0;
        reg_addr_wr = 0;
        sim_end = 0;
    end
endtask
// wr_reg
task wr_reg;
    input [7:0] addr;
    input [7:0] wdata;
    begin
        // write addr
        repeat(1) @(posedge bus_clk); #1;
        reg_addr = addr;
        reg_addr_wr = 1;
        repeat(1) @(posedge bus_clk); #1;
        reg_addr_wr = 0;
        repeat(2) @(posedge bus_clk); #1;
        // write data
        reg_data_wr = 1;
        reg_wdata = wdata;
        repeat(1) @(posedge bus_clk); #1;
        reg_data_wr = 0;
        repeat(2) @(posedge bus_clk); #1;
    end
endtask
// rd_reg
task rd_reg;
    input [7:0] addr;
    output [7:0] rdata;
    begin
        // write addr
        repeat(1) @(posedge bus_clk); #1;
        reg_addr = addr;
        reg_addr_wr = 1;
        repeat(1) @(posedge bus_clk); #1;
        reg_addr_wr = 0;
        repeat(2) @(posedge bus_clk); #1;
        // read data
        repeat(1) @(posedge bus_clk); #1;
        rdata = reg_rdata;
    end
endtask
// set_resp_type
task set_resp_type;
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
// set_trans_mode
task set_trans_mode;
    input [7:0] val;
    begin
        wr_reg(8, val);
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
// set_sd_clk_en
task set_sd_clk_en;
    input val;
    begin
        wr_reg(28, val);
    end
endtask
// set_sd_clk_div
task set_sd_clk_div;
    input [7:0] val;
    begin
        wr_reg(29, val);
    end
endtask
// norm_irq_clr
task norm_irq_clr;
    begin
        wr_reg(32, 8'h1f);
    end
endtask
// err_flag_clr
task err_irq_clr;
    begin
        wr_reg(33, 8'h7f);
    end
endtask
// set_norm_irq_en
task set_norm_irq_en;
    input [7:0] val;
    begin
        wr_reg(34, val);
    end
endtask
// set_err_irq_en
task set_err_irq_en;
    input [7:0] val;
    begin
        wr_reg(35, val);
    end
endtask
// set_timeout_cnt
task set_timeout_cnt;
    input [7:0] val;
    begin
        wr_reg(30, val[7:0]);
    end
endtask
// set_rst_all
task set_rst_all;
    begin
        wr_reg(31, 8'h01);
        wr_reg(31, 8'h00);
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
// get_norm_irq
task get_norm_irq;
    output [7:0] val;
    begin
        rd_reg(32, val);
    end
endtask
// get_err_irq
task get_err_irq;
    output [7:0] val;
    begin
        rd_reg(33, val);
    end
endtask
// cmd
task wait_cmd;
    reg [7:0] tmp;
    begin
        begin: LP_CHK
            while(1) begin
                // cmd_complete
                get_norm_irq(tmp);
                if (tmp[0] == 1) begin
                    $display("%t, cmd_complete irq detected!", $time);
                    disable LP_CHK;
                end
                // cmd_timeout
                get_err_irq(tmp);
                if (tmp[0] == 1) begin
                    $display("%t, cmd_timeout irq detected!", $time);
                    disable LP_CHK;
                end
                // delay
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
                // dat_complete
                get_norm_irq(tmp);
                if (tmp[1] == 1) begin
                    $display("%t, dat_complete irq detected!", $time);
                    disable LP_CHK;
                end
                // dat_timeout
                get_err_irq(tmp);
                if (tmp[4] == 1) begin
                    $display("%t, dat_timeout irq detected!", $time);
                    disable LP_CHK;
                end
                // delay
                repeat(`COMPLETE_POLL_GAP) @(posedge tb_top.sdio_pad_clk);
            end
        end
    end
endtask
// mram
task set_mram_sel;
    input val;
    reg [7:0] tmp;
    begin
        rd_reg(129, tmp);
        tmp[4] = val;
        wr_reg(129, tmp);
    end
endtask
// dma_saddr
task set_dma_saddr;
    input [15:0] val;
    begin
        wr_reg(130, val[7:0]);
        wr_reg(131, val[15:8]);
    end
endtask
// dma_len
task set_dma_len;
    input [15:0] val;
    begin
        wr_reg(132, val[7:0]);
        wr_reg(133, val[15:8]);
    end
endtask
// blk_gap
task set_blk_gap;
    input [7:0] val;
    begin
        wr_reg(27, val[7:0]);
    end
endtask
// 
// set_card_blk_size
task set_card_blk_size;
    input [31:0] val;
    begin
        norm_irq_clr;
        set_cmd_arg(val);
        set_resp_type(`RSP_NONE);
        set_cmd_idx(16); // start command
        wait_cmd;
    end
endtask
// set_card_blk_cnt
task set_card_blk_cnt;
    input [31:0] val;
    begin
        norm_irq_clr;
        set_cmd_arg(val);
        set_resp_type(`RSP_NONE);
        set_cmd_idx(23); // start command
        wait_cmd;
    end
endtask
// set_card_bus_width
task set_card_bus_width;
    input val;
    begin
        norm_irq_clr;
        set_cmd_arg(val);
        set_resp_type(`RSP_NONE);
        set_cmd_idx(11); // start command
        wait_cmd;
    end
endtask
// set_card_abort
task set_card_abort;
    input val;
    begin
        norm_irq_clr;
        set_cmd_arg(val);
        set_resp_type(`RSP_NONE);
        set_cmd_idx(12); // start command
        wait_cmd;
    end
endtask
// set_card_rst
task set_card_rst;
    input val;
    begin
        norm_irq_clr;
        set_cmd_arg(val);
        set_resp_type(`RSP_NONE);
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
        set_dma_saddr(16'd0);
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
        wait_dat; norm_irq_clr;
    end
endtask
// wr_rd_blk
task wr_rd_blk;
    input bus_width;
    input [31:0] blk_size;
    input [31:0] blk_cnt;
    begin
        // dma
        set_dma_saddr(16'd0);
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
        wait_dat; norm_irq_clr;
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
        wait_dat; norm_irq_clr;
    end
endtask


