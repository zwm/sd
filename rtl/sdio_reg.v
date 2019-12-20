module sdio_reg (
    // global
    input rstn,
    input sys_clk,
    input sd_clk,
    // bus
    input reg_data_wr_sys,
    input reg_data_wr_sd,
    input reg_addr_wr_sd,
    input [7:0] reg_addr,
    input [7:0] reg_wdata,
    output reg [7:0] reg_rdata,
    // reg
    output reg [15:0] block_size,
    output reg [15:0] block_count,
    output reg [31:0] cmd_argument,
    output reg dat_trans_width,
    output reg dat_trans_dir,
    output reg dat_present,
    output reg cmd_index_check,
    output reg cmd_crc_check,
    output reg [1:0] resp_type,
    output reg [5:0] cmd_index,
    input [119:0] resp,
    input [5:0] resp_index,
    input [6:0] resp_crc,
    output reg irq_at_block_gap,
    output reg blk_gap_read_wait_en,
    output reg blk_gap_clk_en,
    output reg blk_gap_stop,
    output reg tx_pos,
    output reg rx_neg,
    input sd_clk_pause,
    output reg sd_clk_en,
    output reg [7:0] sd_clk_div,
    output reg [7:0] dat_timeout_sel,
    input [2:0] tx_crc_status,
    input dat_timeout_cnt_running,
    output reg dat_timeout_cnt_sw_en,
    output reg dat_sd_rst, cmd_sd_rst, all_sd_rst, all_sys_rst,
    input err_irq, card_irq, blk_gap_irq, dat_complete_irq, cmd_complete_irq,
    input dat_end_err, dat_crc_err, dat_timeout_err, cmd_index_err,
    input cmd_end_err, cmd_crc_err, cmd_timeout_err,
    output reg err_irq_en, card_irq_en, blk_gap_irq_en, dat_complete_irq_en, cmd_complete_irq_en,
    output reg dat_end_err_en, dat_crc_err_en, dat_timeout_err_en, cmd_index_err_en,
    output reg cmd_end_err_en, cmd_crc_err_en, cmd_timeout_err_en,
    input cmd_busy,
    input [3:0] cmd_fsm,
    input dat_busy,
    input [4:0] dat_fsm,
    input pad_clk_o, pad_cmd_oe, pad_cmd_o, pad_cmd_i,
    input [3:0] pad_dat_i, pad_dat_oe, pad_dat_o,
    output reg [1:0] pad_sel,
    output reg dma_sw_start, dma_mram_sel, dma_rst, dma_hw_start_disable, dma_slavemode,
    output reg [15:0] dma_start_addr, dma_len,
    input [15:0] dma_addr,
    input [3:0] dma_state
);
// bugfix: sd_clk_pause_state
wire sd_clk_pause_state;
assign sd_clk_pause_state = sd_clk_pause | (~sd_clk_en);
// bugfix, addr[15:8] should be freezed, 20191012
reg [7:0] dma_addr_hi_frz;
always @(posedge sd_clk or negedge rstn)
    if (~rstn)
        dma_addr_hi_frz <= 0;
    else if (reg_addr_wr_sd == 1 && reg_addr == 134)
        dma_addr_hi_frz <= dma_addr[15:8];
//---------------------------------------------------------------------------
// SD Domain, SD Regs
//---------------------------------------------------------------------------
// reg write
always @(posedge sd_clk or negedge rstn)
    if (~rstn) begin
        block_size <= 0;
        block_count <= 0;
        cmd_argument <= 0;
        {dat_trans_width, dat_trans_dir, dat_present, cmd_index_check, cmd_crc_check, resp_type[1:0]} <= 0;
        cmd_index <= 0;
        {irq_at_block_gap, blk_gap_read_wait_en, blk_gap_clk_en, blk_gap_stop} <= 0;
        {tx_pos, rx_neg, sd_clk_en} <= 0;
        sd_clk_div <= 0;
        dat_timeout_sel <= 0;
        {dat_timeout_cnt_sw_en, dat_sd_rst, cmd_sd_rst, all_sd_rst} <= 0;
        {err_irq_en, card_irq_en, blk_gap_irq_en, dat_complete_irq_en, cmd_complete_irq_en} <= 0;
        {dat_end_err_en, dat_crc_err_en, dat_timeout_err_en, cmd_index_err_en, cmd_end_err_en, cmd_crc_err_en, cmd_timeout_err_en} <= 0;
        pad_sel <= 0;
    end
    else if (reg_data_wr_sd) begin
        case (reg_addr)
            8'd0 : block_size[7:0] <= reg_wdata;
            8'd1 : block_size[15:8] <= reg_wdata;
            8'd2 : block_count[7:0] <= reg_wdata;
            8'd3 : block_count[15:8] <= reg_wdata;
            8'd4 : cmd_argument[7:0] <= reg_wdata;
            8'd5 : cmd_argument[15:8] <= reg_wdata;
            8'd6 : cmd_argument[23:16] <= reg_wdata;
            8'd7 : cmd_argument[31:24] <= reg_wdata;
            8'd8 : {dat_trans_width, dat_trans_dir, dat_present, cmd_index_check, cmd_crc_check, resp_type[1:0]} <= reg_wdata[6:0];
            8'd9 : cmd_index <= reg_wdata[5:0];
            8'd27: {irq_at_block_gap, blk_gap_read_wait_en, blk_gap_clk_en, blk_gap_stop} <= reg_wdata[3:0];
            8'd28: {tx_pos, rx_neg, sd_clk_en} <= {reg_wdata[5], reg_wdata[4], reg_wdata[0]};
            8'd29: sd_clk_div <= reg_wdata;
            8'd30: dat_timeout_sel <= reg_wdata;
            8'd31: {dat_timeout_cnt_sw_en, dat_sd_rst, cmd_sd_rst, all_sd_rst} <= reg_wdata[3:0];
            8'd34: {err_irq_en, card_irq_en, blk_gap_irq_en, dat_complete_irq_en, cmd_complete_irq_en} <= reg_wdata[4:0];
            8'd35: {dat_end_err_en, dat_crc_err_en, dat_timeout_err_en, cmd_index_err_en, cmd_end_err_en, cmd_crc_err_en, cmd_timeout_err_en} <= reg_wdata[6:0];
            8'd40: pad_sel[1:0] <= reg_wdata[1:0];
        endcase
    end
//---------------------------------------------------------------------------
// Reg Read
//---------------------------------------------------------------------------
// reg read
always @(posedge sd_clk or negedge rstn)
    if (~rstn) begin
        reg_rdata <= 8'h00;
    end
    else if (reg_addr_wr_sd) begin
        case (reg_addr)
            8'd0 : reg_rdata <= block_size[7:0];
            8'd1 : reg_rdata <= block_size[15:8];
            8'd2 : reg_rdata <= block_count[7:0];
            8'd3 : reg_rdata <= block_count[15:8];
            8'd4 : reg_rdata <= cmd_argument[7:0];
            8'd5 : reg_rdata <= cmd_argument[15:8];
            8'd6 : reg_rdata <= cmd_argument[23:16];
            8'd7 : reg_rdata <= cmd_argument[31:24];
            8'd8 : reg_rdata <= {1'b0, dat_trans_width, dat_trans_dir, dat_present, cmd_index_check, cmd_crc_check, resp_type};
            8'd9 : reg_rdata <= {2'h0, cmd_index};
            8'd10: reg_rdata <= resp[7:0];
            8'd11: reg_rdata <= resp[15:8];
            8'd12: reg_rdata <= resp[23:16];
            8'd13: reg_rdata <= resp[31:24];
            8'd14: reg_rdata <= resp[39:32];
            8'd15: reg_rdata <= resp[47:40];
            8'd16: reg_rdata <= resp[55:48];
            8'd17: reg_rdata <= resp[63:56];
            8'd18: reg_rdata <= resp[71:64];
            8'd19: reg_rdata <= resp[79:72];
            8'd20: reg_rdata <= resp[87:80];
            8'd21: reg_rdata <= resp[95:88];
            8'd22: reg_rdata <= resp[103:96];
            8'd23: reg_rdata <= resp[111:104];
            8'd24: reg_rdata <= resp[119:112];
            8'd25: reg_rdata <= {2'h0, resp_index};
            8'd26: reg_rdata <= {1'h0, resp_crc};
            8'd27: reg_rdata <= {4'h0, irq_at_block_gap, blk_gap_read_wait_en, blk_gap_clk_en, blk_gap_stop};
            8'd28: reg_rdata <= {2'h0, tx_pos, rx_neg, 2'h0, sd_clk_pause_state, sd_clk_en};
            8'd29: reg_rdata <= sd_clk_div;
            8'd30: reg_rdata <= dat_timeout_sel;
            8'd31: reg_rdata <= {tx_crc_status, dat_timeout_cnt_running, dat_timeout_cnt_sw_en, dat_sd_rst, cmd_sd_rst, all_sd_rst};
            8'd32: reg_rdata <= {3'h0, err_irq, card_irq, blk_gap_irq, dat_complete_irq, cmd_complete_irq};
            8'd33: reg_rdata <= {1'h0, dat_end_err, dat_crc_err, dat_timeout_err, cmd_index_err, cmd_end_err, cmd_crc_err, cmd_timeout_err};
            8'd34: reg_rdata <= {3'h0, err_irq_en, card_irq_en, blk_gap_irq_en, dat_complete_irq_en, cmd_complete_irq_en};
            8'd35: reg_rdata <= {1'h0, dat_end_err_en, dat_crc_err_en, dat_timeout_err_en, cmd_index_err_en, cmd_end_err_en, cmd_crc_err_en, cmd_timeout_err_en};
            8'd36: reg_rdata <= {cmd_busy, 3'h0, cmd_fsm};
            8'd37: reg_rdata <= {dat_busy, 2'h0, dat_fsm};
            8'd38: reg_rdata <= {pad_clk_o, pad_cmd_oe, pad_cmd_o, pad_cmd_i, pad_dat_i};
            8'd39: reg_rdata <= {pad_dat_oe, pad_dat_o};
            8'd40: reg_rdata <= {6'd0, pad_sel[1:0]};
            // dma
            8'd128: reg_rdata <= 8'h00; // dma_sw_start, not readable
            8'd129: reg_rdata <= {3'h0, dma_mram_sel, 2'h0, dma_rst, dma_hw_start_disable};
            8'd130: reg_rdata <= dma_start_addr[7:0];
            8'd131: reg_rdata <= dma_start_addr[15:8];
            8'd132: reg_rdata <= dma_len[7:0];
            8'd133: reg_rdata <= dma_len[15:8];
            8'd134: reg_rdata <= dma_addr[7:0];
            8'd135: reg_rdata <= dma_addr_hi_frz[7:0];
            8'd136: reg_rdata <= {4'h0, dma_state[3:0]};
            default: reg_rdata <= 0;
        endcase
    end
//---------------------------------------------------------------------------
// SYS Domain, DMA Regs
//---------------------------------------------------------------------------
// must delay 1 cycle
reg reg_data_wr_sys_d1;
//always @(posedge sys_clk or negedge rstn)
//    if (~rstn)
//        reg_data_wr_sys_d1 <= 0;
//    else
//        reg_data_wr_sys_d1 <= reg_data_wr_sys;
// no need delay, 20191113
always @(*)
    reg_data_wr_sys_d1 = reg_data_wr_sys;
// reg_data_wr
always @(posedge sys_clk or negedge rstn)
    if (~rstn) begin
        {dma_mram_sel, dma_rst, dma_hw_start_disable} <= 0;
        dma_start_addr <= 0;
        dma_len <= 0;
    end
    else if (reg_data_wr_sys_d1) begin
        case (reg_addr)
            8'd129: {dma_mram_sel, dma_rst, dma_hw_start_disable} <= {reg_wdata[4], reg_wdata[1], reg_wdata[0]};
            8'd130: dma_start_addr[7:0] <= reg_wdata[7:0];
            8'd131: dma_start_addr[15:8] <= reg_wdata[7:0];
            8'd132: dma_len[7:0] <= reg_wdata[7:0];
            8'd133: dma_len[15:8] <= reg_wdata[7:0];
        endcase
    end
// dma_sw_start
always @(*) dma_sw_start = (reg_data_wr_sys_d1 == 1) && (reg_addr == 128) && (reg_wdata[0] == 1'b1);
// dma_slavemode
always @(posedge sys_clk or negedge rstn) // same as dat_trans_dir
    if (~rstn)
        dma_slavemode <= 0;
    else if (reg_data_wr_sys_d1 == 1 && reg_addr == 8)
        dma_slavemode <= reg_wdata[5];
// all_sys_rst
always @(posedge sys_clk or negedge rstn)
    if (~rstn)
        all_sys_rst <= 0;
    else if (reg_data_wr_sys_d1 == 1 && reg_addr == 31)
        all_sys_rst <= reg_wdata[0];

endmodule
