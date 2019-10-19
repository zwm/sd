





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
