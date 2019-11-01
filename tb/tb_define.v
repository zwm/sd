`define SINGLE_BIT_DAT0
//`define SINGLE_BIT_DAT0
//`define SINGLE_BIT_DAT1
//`define SINGLE_BIT_DAT2
//`define SINGLE_BIT_DAT3
`define FILE_SIM                "case_example.dat"
//`define FILE_SIM                "case_1_bit.dat"
// fsdb
`define DUMP_FSDB               1
// case_dir
`define FILE_CASE_DIR           "./case_dir"
// delay
`define COMPLETE_POLL_GAP       10
`define TASK_SIM_GAP            100
// rsp type
`define RSP_NONE                0
`define RSP_136                 1
`define RSP_48                  2
`define RSP_48_BUSY             3
// bus width
`define BUS_WIDTH_1_BIT         0
`define BUS_WIDTH_4_BIT         1
// dat present
`define DAT_PRESENT_OFF         0
`define DAT_PRESENT_ON          1
// trans dir
`define TRANS_DIR_WR            0
`define TRANS_DIR_RD            1
// inst
`define TB_TOP                  tb_top
`define TOP_RSTN                tb_top.rstn
`define TOP_CASE_DIR            tb_top.case_dir
`define TOP_SIM_END             tb_top.sim_end
`define SDIO_TOP                tb_top.u0_sdio
`define SDCARD_TOP              tb_top.u1_sdcard
`define SDDMA_TOP               tb_top.u2_dma


