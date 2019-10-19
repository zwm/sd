// global var
reg [7:0] log_mem [2**16-1:0]; // 64KB
integer task_end, task_cnt, err_cnt, cmp_cnt;
reg [7:0] log_clk_div;
reg [5:0] log_cmd_idx;
reg [1:0] log_resp_type;
reg [31:0] log_cmd_arg;
reg log_cmd_idx_check_en;
reg log_cmd_crc_check_en;
reg [7:0] log_resp_len;
reg log_resp_trans;
reg [5:0] log_resp_idx;
reg [119:0] log_resp_dat;
reg [6:0] log_resp_crc; // 7-bit
reg log_resp_end;
reg log_bus_width;
reg log_dat_present;
reg log_dat_direction;
reg [15:0] log_blk_size;
reg [15:0] log_blk_cnt;
reg log_dma_mram_sel;
reg [15:0] log_dma_saddr;
reg [15:0] log_dma_len;
reg log_blk_gap_read_wait_en;
reg log_blk_gap_clk_en;
reg log_stop_at_blk_gap;
reg [7:0] log_dat_timeout_cnt;
reg [31:0] log_resp_wait;
reg [31:0] log_resp_busy;
reg [31:0] log_data_rd_wait;
reg [31:0] log_data_wr_crc_wait;
reg [31:0] log_data_wr_busy;
reg [31:0] log_dma_rd_dly;
reg [31:0] log_dma_wr_dly;
reg [4:0] log_norm_irq_en;
reg [6:0] log_err_irq_en;
reg log_err_irq;
reg log_card_irq;
reg log_blk_gap_event;
reg log_data_complete;
reg log_cmd_complete;
reg log_data_end_bit_err;
reg log_data_crc_err;
reg log_data_timeout_err;
reg log_cmd_idx_err;
reg log_cmd_end_bit_err;
reg log_cmd_crc_err;
reg log_cmd_timeout_err;

// main loop
task main_loop;
    integer fp, ret, i, addr;
    begin
        task_end = 0; task_cnt = 0; err_cnt = 0; cmp_cnt = 0;
        // File Open
        fp = $fopen({tb_top.case_dir, "case_example.dat"}, "r");
        // Task Loop
        begin: LP_TASK
            while(1) begin
                // delay
                repeat (`TASK_SIM_GAP) @(posedge `SDIO_TOP.sd_clk);
                // end check
                if (sim_end == 1) begin
                    $display("%t, sim_end detected!", $time);
                    disable LP_TASK;
                end
                // task, parse log -> set reg -> send command 
                //       ^                                |      
                //       |_ check result <- wait finish <- 
                task_proc(fp);
            end
        end
    end
endtask
// log parse
task log_parse;
    input integer fp;
    integer ret, i, j, k, tmp;
    reg [64*8-1:0] s;
    begin
        // read title
        ret = $fgets (s, fp); // task label
        if (ret < 7)  begin // error detect
            sim_end = 1;
            $display("%t, read log file end!", $time);
        end
        else begin
            $display("%t, task_cnt: %d, log label: %s", $time, task_cnt, s);
        end
        // read log
        if (sim_end == 0) begin
            // command
            ret = $fgets (s, fp); // command label
            ret = $fscanf(fp, "%s %h", s, log_clk_div); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_cmd_idx); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %b", s, log_resp_type); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h %h", s, log_cmd_arg[31:16], log_cmd_arg[15:0]); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_cmd_idx_check_en); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_cmd_crc_check_en); ret = $fgets(s, fp);
            // response
            ret = $fgets(s, fp); // get response label
            ret = $fscanf(fp, "%s %d", s, log_resp_len); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_resp_trans); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_resp_idx); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_resp_dat[119:112]); ret = $fscanf(fp, "%h", s, log_resp_dat[111:96]);
            ret = $fscanf(fp, "%h", s, log_resp_dat[95:80]); ret = $fscanf(fp, "%h", s, log_resp_dat[79:64]);
            ret = $fscanf(fp, "%h", s, log_resp_dat[63:48]); ret = $fscanf(fp, "%h", s, log_resp_dat[47:32]);
            ret = $fscanf(fp, "%h", s, log_resp_dat[31:16]); ret = $fscanf(fp, "%h", s, log_resp_dat[15:0]); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_resp_crc); // 7-bit ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_resp_end); ret = $fgets(s, fp);
            // data/dma
            ret = $fgets(s, fp); // get data/dma label
            ret = $fscanf(fp, "%s %h", s, log_bus_width); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_dat_present); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_dat_direction); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_blk_size); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_blk_cnt); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_dma_mram_sel); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_dma_saddr); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_dma_len); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_blk_gap_read_wait_en); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_blk_gap_clk_en); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_stop_at_blk_gap); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_dat_timeout_cnt); ret = $fgets(s, fp);
            // time
            ret = $fgets(s, fp); // get time label
            ret = $fscanf(fp, "%s %d", s, log_resp_wait); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %d", s, log_resp_busy); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %d", s, log_data_rd_wait); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %d", s, log_data_wr_crc_wait); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %d", s, log_data_wr_busy); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %d", s, log_dma_rd_dly); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %d", s, log_dma_wr_dly); ret = $fgets(s, fp);
            // check
            ret = $fgets(s, fp); // get check label
            ret = $fscanf(fp, "%s %h", s, log_norm_irq_en); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_err_irq_en); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_err_irq); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_card_irq); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_blk_gap_event); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_data_complete); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_cmd_complete); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_data_end_bit_err); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_data_crc_err); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_data_timeout_err); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_cmd_idx_err); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_cmd_end_bit_err); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_cmd_crc_err); ret = $fgets(s, fp);
            ret = $fscanf(fp, "%s %h", s, log_cmd_timeout_err); ret = $fgets(s, fp);
            // data
            ret = $fgets(s, fp); // get data label
            ret = log_dat_present ? (log_blk_size*log_blk_cnt) : 0;
            if (ret != 0) begin
                for (i=0; i<ret; i=i+1) begin
                    ret = $fscanf(fp, "%h", s, log_mem[i]);
                end
                ret = $fgets(s, fp);
            end
        end
    end
endtask
// start_task
task start_task;
    begin
    end
endtask
// wait_task
task wait_task;
    begin
    end
endtask
// check_cmd
task check_flag;
    begin
    end
endtask
// data_checker;
task data_checker;
    begin
    end
endtask
// task_proc
task task_proc;
    input integer fp;
    begin
        log_parse(fp);
        task_end = 0;
        if (sim_end == 0) begin
            fork
                // driver
                begin
                    start_task;
                    wait_task;
                    check_flag;
                end
                // checker
                data_checker;
            join
        end
    end
endtask

/*
// task paser
task task_paser;
    integer fp, ret, i, addr;
    begin
    end
endtask
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
*/
