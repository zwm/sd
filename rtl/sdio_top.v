// sdio lite
module sdio_top (
    // global
    input rstn, // async reset
    input sd_clk, // pll 48M
    input bus_clk, // dsp core bus clk, 12/24M
    // clock domain: bus_clk
    // reg
    input reg_data_wr, // assert one cycle ahead wdata, 20190925
    input [7:0] reg_addr,
    input [7:0] reg_wdata,
    output [7:0] reg_rdata,
    // dma
    input bus_ready,
    input bus_rdata_ready,
    input [7:0] bus_rdata,
    output [16:0] bus_addr,
    output [7:0] bus_wdata,
    output bus_rd,
    output bus_wr,
    // clock domain: sd_clk
    // irq
    output sdio_irq,
    // gpio
    //input pad_clk_i,  // never used
    output pad_clk_o, pad_clk_oe,
    input pad_cmd_i,
    output pad_cmd_o, pad_cmd_oe,
    input [3:0] pad_dat_i,
    output [3:0] pad_dat_o, pad_dat_oe
);
// sync
wire sync_sys_rst, sync_sd_rst;
wire buf_free_sys, buf_free_sd;
wire buf0_rd_rdy_sd, buf0_rd_rdy_sys;
wire buf1_rd_rdy_sd, buf1_rd_rdy_sys;
wire dma_byte_en_sys, dma_byte_en_sd;
wire sdio_byte_done_sd, sdio_byte_done_sys;
wire reg_wr_sys, reg_wr_sd;
wire dat_done_sd, dat_done_sys;
wire dma_buf_empty_sys, dma_buf_empty_sd;
// misc
wire tx_en, rx_en;
wire cmd_start, dat_start;
wire cmd_tx_end, resp_rx_end;
wire rx_buf_wr, rx_buf_rdy;
wire [7:0] dma_tx_byte;
wire [7:0] buf0_rdata, buf1_rdata, rx_buf;
wire timeout_cnt_en, dat_timeout_err_event;
wire tmout_cmd_busy_en, tmout_wait_rx_start_en;
wire tmout_wait_tx_crc_start_en, tmout_wait_tx_crc_busy_en;
wire inst_cmd_sd_rst, inst_dat_sd_rst, inst_buf_sd_rst;
wire dma_auto_start_sd, dma_auto_start_sys, dma_start_mux, dma_rst_mux;
// reg
wire [15:0] block_size; // 0~65535 bytes
wire [15:0] block_count; // 0: infinite, 1: single, others: multiple
wire [31:0] cmd_argument;
wire dat_trans_width; // 0: 1-bit, 1: 4-bit
wire dat_trans_dir; // 1: read, 0: write
wire dat_present;
wire cmd_index_check;
wire cmd_crc_check;
wire [1:0] resp_type; // 00: no resp, 01: resp 136, 10: resp 48, 11: resp 48 with busy
wire [5:0] cmd_index;
wire [119:0] resp;
wire [5:0] resp_index;
wire [6:0] resp_crc;
wire irq_at_block_gap; // not implemented
wire blk_gap_read_wait_en; // 1: drive DAT[2] low to stop card data output during block gap
wire blk_gap_clk_en; // 1: stop SdClk to stop card data output during block gap
wire blk_gap_stop; // 1: stop at block gap, 0: continue
wire tx_pos;
wire rx_neg;
wire sd_clk_pause;
wire sd_clk_en;
wire [7:0] sd_clk_div; // sd_clk = 48m/((sd_clk_div + 1)*2), even freq div only
wire [7:0] dat_timeout_sel;
wire [2:0] tx_crc_status;
wire dat_timeout_cnt_running;
wire dat_timeout_cnt_sw_en; // software enable
wire dat_sd_rst, cmd_sd_rst, all_sd_rst, all_sys_rst; // software reset
wire err_irq, card_irq, blk_gap_irq, dat_complete_irq, cmd_complete_irq;
wire dat_end_err, dat_crc_err, dat_timeout_err, cmd_index_err;
wire cmd_end_err, cmd_crc_err, cmd_timeout_err;
wire err_irq_en, card_irq_en, blk_gap_irq_en, dat_complete_irq_en, cmd_complete_irq_en;
wire dat_end_err_en, dat_crc_err_en, dat_timeout_err_en;
wire cmd_index_err_en, cmd_end_err_en, cmd_crc_err_en, cmd_timeout_err_en;
wire cmd_busy; // indicate cmd machine state
wire [3:0] cmd_fsm;
wire dat_busy; // indicate dat machine state
wire [4:0] dat_fsm;
wire [1:0] pad_sel;
// dma
wire dma_sw_start, dma_mram_sel, dma_rst, dma_hw_start_disable;
wire [15:0] dma_start_addr, dma_len, dma_addr;
wire dma_slavemode; wire [3:0] dma_state;
// event
wire resp_crc_err_event, resp_end_err_event;
wire cmd_timeout_err_event, resp_index_err_event;
wire dat_crc_err_event, dat_end_err_event;
wire card_irq_event, blk_gap_event;
wire dat_done, cmd_done;
// start!
assign cmd_start = (reg_wr_sd == 1) && (reg_addr == 9) && (cmd_busy == 1'b0);
//assign dat_start = dat_present ? (dat_trans_dir ? cmd_tx_end : resp_rx_end) : 1'b0;
assign dat_start = dat_present ? (dat_trans_dir ? cmd_tx_end : (resp_type == 2'b00 ? cmd_tx_end : resp_rx_end)) : 1'b0; // 20190924
assign dma_rst_mux = dma_rst | all_sys_rst;
assign dma_auto_start_sd = (~dma_hw_start_disable) & cmd_start & dat_present;
assign dma_start_mux = dma_sw_start | dma_auto_start_sys;
// rst
assign inst_cmd_sd_rst = cmd_sd_rst | all_sd_rst;
assign inst_dat_sd_rst = dat_sd_rst | all_sd_rst;
//assign inst_buf_sd_rst = dat_sd_rst | all_sd_rst | dat_done; // tx end should reset buf
assign inst_buf_sd_rst = dat_sd_rst | all_sd_rst | cmd_start; // rx may lose data, so rst and cmd_start!
// bus_addr
assign bus_addr[16:0] = {dma_mram_sel, dma_addr[15:0]};
// sync
assign sync_sys_rst = 1'b0;
assign sync_sd_rst = 1'b0; // sync no need to reset
assign reg_wr_sys = reg_data_wr;
assign dat_done_sd = dat_done;
// timeout timer
assign timeout_cnt_en = tmout_cmd_busy_en | 
                        tmout_wait_rx_start_en | 
                        tmout_wait_tx_crc_start_en | 
                        tmout_wait_tx_crc_busy_en |
                        dat_timeout_cnt_sw_en;
assign dat_timeout_cnt_running = timeout_cnt_en;
// card_irq
// SDIO2.0, 8.1.1, 1-bit mode, Pin 8, dedicated to interrupt function, signals irq by assert Pin 8 low
// SDIO2.0, 8.1.2, 4-bit mode, Pin 8, shared between IRQ and DAT[1], signals irq by assert Pin 8 low
assign card_irq_event = (~dat_trans_width) ? ((pad_sel == 2'b01) ? (~pad_dat_i[0]) : (~pad_dat_i[1])) : (dat_busy ? 1'b0 : (~pad_dat_i[1]));
// err_irq
assign err_irq = (dat_end_err_en & dat_end_err) |
                 (dat_crc_err_en & dat_crc_err) |
                 (dat_timeout_err_en & dat_timeout_err) |
                 (cmd_index_err_en & cmd_index_err) |
                 (cmd_end_err_en & cmd_end_err) |
                 (cmd_crc_err_en & cmd_crc_err) |
                 (cmd_timeout_err_en & cmd_timeout_err);
// sdio_irq
assign sdio_irq = (err_irq & err_irq_en) |
                  (card_irq & card_irq_en) |
                  (blk_gap_irq & blk_gap_irq_en) |
                  (dat_complete_irq & dat_complete_irq_en) |
                  (cmd_complete_irq & cmd_complete_irq_en);
//---------------------------------------------------------------------------
// Clock Domain: BUS_CLK
//---------------------------------------------------------------------------
// inst dma
sdio_dma u0_dma (
    .rstn                       ( rstn                          ),
    .dma_rst                    ( dma_rst_mux                   ),
    .start                      ( dma_start_mux                 ),
    .slavemode                  ( dma_slavemode                 ),
    .start_addr                 ( dma_start_addr                ),
    .len                        ( dma_len                       ),
    .dma_end                    ( dat_done_sys                  ), // from sd, sd -> sys
    .buf0_rd_rdy                ( buf0_rd_rdy_sys               ), // from sd, sd -> sys
    .buf1_rd_rdy                ( buf1_rd_rdy_sys               ), // from sd, sd -> sys
    .buf0                       ( buf0_rdata                    ),
    .buf1                       ( buf1_rdata                    ),
    .buf_free                   ( buf_free_sys                  ), // to sd, sys -> sd
    .dma_buf_empty              ( dma_buf_empty_sys             ), // to sd, sys -> sd
    .dma_byte_en                ( dma_byte_en_sys               ), // to sd, sys -> sd
    .sdio_byte_done             ( sdio_byte_done_sys            ), // from sd, sd -> sys
    .dma_byte                   ( dma_tx_byte                   ), 
    .bus_clk                    ( bus_clk                       ),
    .bus_ready                  ( bus_ready                     ),
    .bus_rdata_ready            ( bus_rdata_ready               ),
    .bus_rdata                  ( bus_rdata                     ),
    .bus_addr                   ( dma_addr                      ),
    .bus_wdata                  ( bus_wdata                     ),
    .bus_rd                     ( bus_rd                        ),
    .bus_wr                     ( bus_wr                        ),
    .dma_state                  ( dma_state                     )
);
//---------------------------------------------------------------------------
// Clock Domain Cross: Sync
//---------------------------------------------------------------------------
// inst sync
sdio_sync u1_sync (
    .rstn                       ( rstn                          ),
    .sys_rst                    ( sync_sys_rst                  ), // ???
    .sys_clk                    ( bus_clk                       ),
    .sd_rst                     ( sync_sd_rst                   ), // ???
    .sd_clk                     ( sd_clk                        ),
    .buf_free_sys               ( buf_free_sys                  ), // sys_clk -> sd_clk
    .buf_free_sd                ( buf_free_sd                   ),
    .dma_buf_empty_sys          ( dma_buf_empty_sys             ), // to sd, sys -> sd
    .dma_buf_empty_sd           ( dma_buf_empty_sd              ),
    .dma_byte_en_sys            ( dma_byte_en_sys               ),
    .dma_byte_en_sd             ( dma_byte_en_sd                ),
    .reg_wr_sys                 ( reg_wr_sys                    ),
    .reg_wr_sd                  ( reg_wr_sd                     ),
    .buf0_rd_rdy_sd             ( buf0_rd_rdy_sd                ), // sd_clk -> sys_clk
    .buf1_rd_rdy_sd             ( buf1_rd_rdy_sd                ),
    .buf0_rd_rdy_sys            ( buf0_rd_rdy_sys               ),
    .buf1_rd_rdy_sys            ( buf1_rd_rdy_sys               ),
    .sdio_byte_done_sd          ( sdio_byte_done_sd             ),
    .sdio_byte_done_sys         ( sdio_byte_done_sys            ),
    .dma_auto_start_sd          ( dma_auto_start_sd             ),
    .dma_auto_start_sys         ( dma_auto_start_sys            ),
    .dat_done_sd                ( dat_done_sd                   ),
    .dat_done_sys               ( dat_done_sys                  )
);
//---------------------------------------------------------------------------
// Clock Domain: SD_CLK
//---------------------------------------------------------------------------
// inst reg
sdio_reg u2_reg (
    .rstn                       ( rstn                          ),
    .sys_clk                    ( bus_clk                       ),
    .sd_clk                     ( sd_clk                        ),
    .reg_wr_sys                 ( reg_wr_sys                    ),
    .reg_wr_sd                  ( reg_wr_sd                     ),
    .reg_addr                   ( reg_addr                      ),
    .reg_wdata                  ( reg_wdata                     ),
    .reg_rdata                  ( reg_rdata                     ),
    .block_size                 ( block_size                    ),
    .block_count                ( block_count                   ),
    .cmd_argument               ( cmd_argument                  ),
    .dat_trans_width            ( dat_trans_width               ),
    .dat_trans_dir              ( dat_trans_dir                 ),
    .dat_present                ( dat_present                   ),
    .cmd_index_check            ( cmd_index_check               ),
    .cmd_crc_check              ( cmd_crc_check                 ),
    .resp_type                  ( resp_type                     ),
    .cmd_index                  ( cmd_index                     ),
    .resp                       ( resp                          ),
    .resp_index                 ( resp_index                    ),
    .resp_crc                   ( resp_crc                      ),
    .irq_at_block_gap           ( irq_at_block_gap              ),
    .blk_gap_read_wait_en       ( blk_gap_read_wait_en          ),
    .blk_gap_clk_en             ( blk_gap_clk_en                ),
    .blk_gap_stop               ( blk_gap_stop                  ),
    .tx_pos                     ( tx_pos                        ),
    .rx_neg                     ( rx_neg                        ),
    .sd_clk_pause               ( sd_clk_pause                  ),
    .sd_clk_en                  ( sd_clk_en                     ),
    .sd_clk_div                 ( sd_clk_div                    ),
    .dat_timeout_sel            ( dat_timeout_sel               ),
    .tx_crc_status              ( tx_crc_status                 ),
    .dat_timeout_cnt_running    ( dat_timeout_cnt_running       ),
    .dat_timeout_cnt_sw_en      ( dat_timeout_cnt_sw_en         ),
    .dat_sd_rst                 ( dat_sd_rst                    ),
    .cmd_sd_rst                 ( cmd_sd_rst                    ),
    .all_sd_rst                 ( all_sd_rst                    ),
    .all_sys_rst                ( all_sys_rst                   ),
    .err_irq                    ( err_irq                       ),
    .card_irq                   ( card_irq                      ),
    .blk_gap_irq                ( blk_gap_irq                   ),
    .dat_complete_irq           ( dat_complete_irq              ),
    .cmd_complete_irq           ( cmd_complete_irq              ),
    .dat_end_err                ( dat_end_err                   ),
    .dat_crc_err                ( dat_crc_err                   ),
    .dat_timeout_err            ( dat_timeout_err               ),
    .cmd_index_err              ( cmd_index_err                 ),
    .cmd_end_err                ( cmd_end_err                   ),
    .cmd_crc_err                ( cmd_crc_err                   ),
    .cmd_timeout_err            ( cmd_timeout_err               ),
    .err_irq_en                 ( err_irq_en                    ),
    .card_irq_en                ( card_irq_en                   ),
    .blk_gap_irq_en             ( blk_gap_irq_en                ),
    .dat_complete_irq_en        ( dat_complete_irq_en           ),
    .cmd_complete_irq_en        ( cmd_complete_irq_en           ),
    .dat_end_err_en             ( dat_end_err_en                ),
    .dat_crc_err_en             ( dat_crc_err_en                ),
    .dat_timeout_err_en         ( dat_timeout_err_en            ),
    .cmd_index_err_en           ( cmd_index_err_en              ),
    .cmd_end_err_en             ( cmd_end_err_en                ),
    .cmd_crc_err_en             ( cmd_crc_err_en                ),
    .cmd_timeout_err_en         ( cmd_timeout_err_en            ),
    .cmd_busy                   ( cmd_busy                      ),
    .cmd_fsm                    ( cmd_fsm                       ),
    .dat_busy                   ( dat_busy                      ),
    .dat_fsm                    ( dat_fsm                       ),
    .pad_clk_o                  ( pad_clk_o                     ),
    .pad_cmd_oe                 ( pad_cmd_oe                    ),
    .pad_cmd_o                  ( pad_cmd_o                     ),
    .pad_cmd_i                  ( pad_cmd_i                     ),
    .pad_dat_i                  ( pad_dat_i                     ),
    .pad_dat_oe                 ( pad_dat_oe                    ),
    .pad_dat_o                  ( pad_dat_o                     ),
    .pad_sel                    ( pad_sel                       ),
    .dma_sw_start               ( dma_sw_start                  ), // dma
    .dma_mram_sel               ( dma_mram_sel                  ),
    .dma_rst                    ( dma_rst                       ),
    .dma_hw_start_disable       ( dma_hw_start_disable          ),
    .dma_start_addr             ( dma_start_addr                ),
    .dma_len                    ( dma_len                       ),
    .dma_addr                   ( dma_addr                      ),
    .dma_slavemode              ( dma_slavemode                 ),
    .dma_state                  ( dma_state                     )
);
// inst clk
sdio_clk u3_clk (
    .rstn                       ( rstn                          ),
    .sd_clk                     ( sd_clk                        ),
    .sd_clk_en                  ( sd_clk_en                     ),
    .sd_clk_div                 ( sd_clk_div                    ),
    .tx_pos                     ( tx_pos                        ),
    .rx_neg                     ( rx_neg                        ),
    .sd_clk_pause               ( sd_clk_pause                  ),
    .clk_o                      ( pad_clk_o                     ), // gpio
    .clk_oe                     ( pad_clk_oe                    ),
    .tx_en                      ( tx_en                         ),
    .rx_en                      ( rx_en                         )
);
// inst cmd
sdio_cmd u4_cmd (
    .rstn                       ( rstn                          ),
    .sd_rst                     ( inst_cmd_sd_rst               ),
    .sd_clk                     ( sd_clk                        ),
    .cmd_index                  ( cmd_index                     ),
    .cmd_argument               ( cmd_argument                  ),
    .resp_type                  ( resp_type                     ),
    .cmd_crc_check              ( cmd_crc_check                 ),
    .cmd_index_check            ( cmd_index_check               ),
    .resp_index                 ( resp_index                    ),
    .resp                       ( resp                          ),
    .resp_crc                   ( resp_crc                      ),
    .cmd_timeout_err_event      ( cmd_timeout_err_event         ),
    .resp_index_err_event       ( resp_index_err_event          ),
    .resp_crc_err_event         ( resp_crc_err_event            ),
    .resp_end_err_event         ( resp_end_err_event            ),
    .cmd_busy                   ( cmd_busy                      ),
    .cmd_done                   ( cmd_done                      ),
    .cmd_fsm                    ( cmd_fsm                       ),
    .tx_en                      ( tx_en                         ),
    .rx_en                      ( rx_en                         ),
    .cmd_start                  ( cmd_start                     ),
    .cmd_tx_end                 ( cmd_tx_end                    ),
    .resp_rx_end                ( resp_rx_end                   ),
    .tmout_cmd_busy_en          ( tmout_cmd_busy_en             ),
    .dat_0_i                    ( pad_dat_i[0]                  ),
    .cmd_i                      ( pad_cmd_i                     ),
    .cmd_o                      ( pad_cmd_o                     ),
    .cmd_oe                     ( pad_cmd_oe                    )
);
// rst
sdio_dat u5_dat (
    .rstn                       ( rstn                          ),
    .sd_rst                     ( inst_dat_sd_rst               ),
    .sd_clk                     ( sd_clk                        ),
    .block_size                 ( block_size                    ),
    .block_count                ( block_count                   ),
    .dat_trans_dir              ( dat_trans_dir                 ),
    .dat_trans_width            ( dat_trans_width               ),
    .blk_gap_stop               ( blk_gap_stop                  ),
    .blk_gap_clk_en             ( blk_gap_clk_en                ),
    .blk_gap_read_wait_en       ( blk_gap_read_wait_en          ),
    .pad_sel                    ( pad_sel                       ),
    .dat_crc_err_event          ( dat_crc_err_event             ),
    .dat_end_err_event          ( dat_end_err_event             ),
    .blk_gap_event              ( blk_gap_event                 ),
    .tx_crc_status              ( tx_crc_status                 ),
    .dat_busy                   ( dat_busy                      ),
    .dat_done                   ( dat_done                      ),
    .dat_fsm                    ( dat_fsm                       ),
    .tx_en                      ( tx_en                         ),
    .rx_en                      ( rx_en                         ),
    .dat_start                  ( dat_start                     ),
    .sd_clk_pause               ( sd_clk_pause                  ),
    .tmout_wait_rx_start_en     ( tmout_wait_rx_start_en        ),
    .tmout_wait_tx_crc_start_en ( tmout_wait_tx_crc_start_en    ),
    .tmout_wait_tx_crc_busy_en  ( tmout_wait_tx_crc_busy_en     ),
    .dma_rx_buf_rdy             ( rx_buf_rdy                    ),
    .dma_rx_buf_empty           ( dma_buf_empty_sd              ),
    .dma_rx_buf                 ( rx_buf                        ),
    .dma_rx_buf_wr              ( rx_buf_wr                     ),
    .dma_tx_byte_rdy            ( dma_byte_en_sd                ), // from dma, sys -> sd
    .dma_tx_byte                ( dma_tx_byte                   ), // from dma
    .dma_tx_byte_end            ( sdio_byte_done_sd             ), // to dma, sd -> sys
    .dat_0_i                    ( pad_dat_i[0]                  ),
    .dat_1_i                    ( pad_dat_i[1]                  ),
    .dat_2_i                    ( pad_dat_i[2]                  ),
    .dat_3_i                    ( pad_dat_i[3]                  ),
    .dat_0_o                    ( pad_dat_o[0]                  ),
    .dat_1_o                    ( pad_dat_o[1]                  ),
    .dat_2_o                    ( pad_dat_o[2]                  ),
    .dat_3_o                    ( pad_dat_o[3]                  ),
    .dat_0_oe                   ( pad_dat_oe[0]                 ),
    .dat_1_oe                   ( pad_dat_oe[1]                 ),
    .dat_2_oe                   ( pad_dat_oe[2]                 ),
    .dat_3_oe                   ( pad_dat_oe[3]                 )
);
// inst, pingpang buffer
sdio_buf u6_buf (
    .rstn                       ( rstn                          ),
    .sd_rst                     ( inst_buf_sd_rst               ),
    .sd_clk                     ( sd_clk                        ),
    .buf_wr                     ( rx_buf_wr                     ),
    .buf_wdata                  ( rx_buf                        ),
    .buf_free                   ( buf_free_sd                   ), // from dma, sys -> sd
    .buf_wr_rdy                 ( rx_buf_rdy                    ),
    .buf0_rd_rdy                ( buf0_rd_rdy_sd                ), // to dma, sd -> sys
    .buf1_rd_rdy                ( buf1_rd_rdy_sd                ),
    .buf0_rdata                 ( buf0_rdata                    ),
    .buf1_rdata                 ( buf1_rdata                    )
);
// inst timer
sdio_timer u7_timer (
    .rstn                       ( rstn                          ),
    .sd_clk                     ( sd_clk                        ),
    .timeout_cnt_en             ( timeout_cnt_en                ),
    .timeout_cnt_sel            ( dat_timeout_sel               ),
    .timeout_event              ( dat_timeout_err_event         )
);
// inst flag
sdio_flag #(32, 33) u8_flag (
    .rstn                       ( rstn                          ),
    .sd_clk                     ( sd_clk                        ),
    .cmd_sd_rst                 ( cmd_sd_rst                    ),
    .dat_sd_rst                 ( dat_sd_rst                    ),
    .all_sd_rst                 ( all_sd_rst                    ),
    .cmd_start                  ( cmd_start                     ),
    .reg_wr                     ( reg_wr_sd                     ),
    .reg_addr                   ( reg_addr                      ),
    .reg_wdata                  ( reg_wdata                     ),
    .card_irq_event             ( card_irq_event                ),
    .blk_gap_event              ( blk_gap_event                 ),
    .dat_done_event             ( dat_done                      ),
    .cmd_done_event             ( cmd_done                      ),
    .dat_end_err_event          ( dat_end_err_event             ),
    .dat_crc_err_event          ( dat_crc_err_event             ),
    .dat_timeout_err_event      ( dat_timeout_err_event         ),
    .cmd_index_err_event        ( resp_index_err_event          ),
    .cmd_end_err_event          ( resp_end_err_event            ),
    .cmd_crc_err_event          ( resp_crc_err_event            ),
    .cmd_timeout_err_event      ( cmd_timeout_err_event         ),
    .card_irq                   ( card_irq                      ),
    .blk_gap_irq                ( blk_gap_irq                   ),
    .dat_complete_irq           ( dat_complete_irq              ),
    .cmd_complete_irq           ( cmd_complete_irq              ),
    .dat_end_err                ( dat_end_err                   ),
    .dat_crc_err                ( dat_crc_err                   ),
    .dat_timeout_err            ( dat_timeout_err               ),
    .cmd_index_err              ( cmd_index_err                 ),
    .cmd_end_err                ( cmd_end_err                   ),
    .cmd_crc_err                ( cmd_crc_err                   ),
    .cmd_timeout_err            ( cmd_timeout_err               )
);

endmodule
