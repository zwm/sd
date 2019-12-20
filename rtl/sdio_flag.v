module sdio_flag #(
    parameter REG_ADDR_IRQ = 32,
    parameter REG_ADDR_ERR = 33 
)(
    // global
    input rstn,
    input sd_clk,
    input cmd_sd_rst,
    input dat_sd_rst,
    input all_sd_rst,
    input cmd_start,
    // reg
    input reg_data_wr,
    input [7:0] reg_addr,
    input [7:0] reg_wdata,
    // event
    input card_irq_event, // block gap can trigger irq
    input blk_gap_event, // block gap can trigger irq
    input dat_done_event, // dat complete flag
    input cmd_done_event, // cmd complete flag
    input dat_end_err_event,
    input dat_crc_err_event,
    input dat_timeout_err_event,
    input cmd_index_err_event,
    input cmd_end_err_event,
    input cmd_crc_err_event,
    input cmd_timeout_err_event,
    // flag
    output reg card_irq,
    output reg blk_gap_irq,
    output reg dat_complete_irq,
    output reg cmd_complete_irq,
    output reg dat_end_err,
    output reg dat_crc_err,
    output reg dat_timeout_err,
    output reg cmd_index_err,
    output reg cmd_end_err,
    output reg cmd_crc_err,
    output reg cmd_timeout_err
);

// flag
always @(posedge sd_clk or negedge rstn)
    if (~rstn) begin
        card_irq            <= 0;
        blk_gap_irq         <= 0;
        dat_complete_irq    <= 0;
        cmd_complete_irq    <= 0;
        dat_end_err         <= 0;
        dat_crc_err         <= 0;
        dat_timeout_err     <= 0;
        cmd_index_err       <= 0;
        cmd_end_err         <= 0;
        cmd_crc_err         <= 0;
        cmd_timeout_err     <= 0;
    end
    else begin
        // card_irq, bit[3]
        if (all_sd_rst | cmd_start)
            card_irq <= 0;
        else if (card_irq_event)
            card_irq <= 1;
        else if ((reg_data_wr == 1) && (reg_addr == REG_ADDR_IRQ) && (reg_wdata[3] == 1))
            card_irq <= 0;
        // blk_gap_irq, bit[2]
        if (dat_sd_rst | all_sd_rst | cmd_start)
            blk_gap_irq <= 0;
        else if (blk_gap_event)
            blk_gap_irq <= 1;
        else if ((reg_data_wr == 1) && (reg_addr == REG_ADDR_IRQ) && (reg_wdata[2] == 1))
            blk_gap_irq <= 0;
        // dat_complete_irq, bit[1]
        if (dat_sd_rst | all_sd_rst | cmd_start)
            dat_complete_irq <= 0;
        else if (dat_done_event)
            dat_complete_irq <= 1;
        else if ((reg_data_wr == 1) && (reg_addr == REG_ADDR_IRQ) && (reg_wdata[1] == 1))
            dat_complete_irq <= 0;
        // cmd_complete_irq, bit[1]
        if (cmd_sd_rst | all_sd_rst | cmd_start)
            cmd_complete_irq <= 0;
        else if (cmd_done_event)
            cmd_complete_irq <= 1;
        else if ((reg_data_wr == 1) && (reg_addr == REG_ADDR_IRQ) && (reg_wdata[0] == 1))
            cmd_complete_irq <= 0;
        // dat_end_err, bit[6]
        if (dat_sd_rst | all_sd_rst | cmd_start)
            dat_end_err <= 0;
        else if (dat_end_err_event)
            dat_end_err <= 1;
        else if ((reg_data_wr == 1) && (reg_addr == REG_ADDR_ERR) && (reg_wdata[6] == 1))
            dat_end_err <= 0;
        // dat_crc_err, bit[5]
        if (dat_sd_rst | all_sd_rst | cmd_start)
            dat_crc_err <= 0;
        else if (dat_crc_err_event)
            dat_crc_err <= 1;
        else if ((reg_data_wr == 1) && (reg_addr == REG_ADDR_ERR) && (reg_wdata[5] == 1))
            dat_crc_err <= 0;
        // dat_timeout_err, bit[4]
        if (dat_sd_rst | all_sd_rst | cmd_start)
            dat_timeout_err <= 0;
        else if (dat_timeout_err_event)
            dat_timeout_err <= 1;
        else if ((reg_data_wr == 1) && (reg_addr == REG_ADDR_ERR) && (reg_wdata[4] == 1))
            dat_timeout_err <= 0;
        // cmd_index_err, bit[3]
        if (cmd_sd_rst | all_sd_rst | cmd_start)
            cmd_index_err <= 0;
        else if (cmd_index_err_event)
            cmd_index_err <= 1;
        else if ((reg_data_wr == 1) && (reg_addr == REG_ADDR_ERR) && (reg_wdata[3] == 1))
            cmd_index_err <= 0;
        // cmd_end_err, bit[2]
        if (cmd_sd_rst | all_sd_rst | cmd_start)
            cmd_end_err <= 0;
        else if (cmd_end_err_event)
            cmd_end_err <= 1;
        else if ((reg_data_wr == 1) && (reg_addr == REG_ADDR_ERR) && (reg_wdata[2] == 1))
            cmd_end_err <= 0;
        // cmd_crc_err, bit[1]
        if (cmd_sd_rst | all_sd_rst | cmd_start)
            cmd_crc_err <= 0;
        else if (cmd_crc_err_event)
            cmd_crc_err <= 1;
        else if ((reg_data_wr == 1) && (reg_addr == REG_ADDR_ERR) && (reg_wdata[1] == 1))
            cmd_crc_err <= 0;
        // cmd_timeout_err, bit[0]
        if (cmd_sd_rst | all_sd_rst | cmd_start)
            cmd_timeout_err <= 0;
        else if (cmd_timeout_err_event)
            cmd_timeout_err <= 1;
        else if ((reg_data_wr == 1) && (reg_addr == REG_ADDR_ERR) && (reg_wdata[0] == 1))
            cmd_timeout_err <= 0;
    end

endmodule
