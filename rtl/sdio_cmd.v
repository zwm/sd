module sdio_cmd (
    input rstn,
    input sd_rst,
    input sd_clk,
    // reg
    input [5:0] cmd_index,
    input [31:0] cmd_argument,
    input [1:0] resp_type, // 00: no resp, 01: resp 136, 10: resp 48, 11: resp 48 with busy
    input cmd_crc_check,
    input cmd_index_check,
    output reg [5:0] resp_index,
    output reg [119:0] resp,
    output reg [6:0] resp_crc,
    output cmd_timeout_err_event,
    output resp_index_err_event,
    output resp_crc_err_event,
    output resp_end_err_event,
    output cmd_busy, // indicate cmd machine state
    output cmd_done, // complete flag
    output [3:0] cmd_fsm,
    // ctrl
    input tx_en,
    input rx_en,
    input cmd_start,
    output cmd_tx_end, // to start dat_rx
    output resp_rx_end, // to start dat_tx
    output tmout_cmd_busy_en,
    // gpio
    input dat_0_i,
    input cmd_i,
    output reg cmd_o,
    output reg cmd_oe
);
// macro
`define     CMD_INDEX_LEN       6
`define     CMD_ARG_LEN         32
`define     CMD_CRC_LEN         7
`define     RSP_INDEX_LEN       6
`define     RSP_CRC_LEN         7
`define     CMD_TO_RSP_DLY      2 // SMIH 2
// var
reg [3:0] st_curr;
reg [3:0] st_next;
localparam IDLE                 = 4'd0;
localparam TX_CMD_START         = 4'd1;
localparam TX_CMD_TRANS         = 4'd2;
localparam TX_CMD_INDEX         = 4'd3;
localparam TX_CMD_ARG           = 4'd4;
localparam TX_CMD_CRC           = 4'd5;
localparam TX_CMD_END           = 4'd6;
localparam RX_RSP_DLY           = 4'd7;
localparam RX_RSP_START         = 4'd8;
localparam RX_RSP_TRANS         = 4'd9;
localparam RX_RSP_INDEX         = 4'd10;
localparam RX_RSP_ARG           = 4'd11;
localparam RX_RSP_CRC           = 4'd12;
localparam RX_RSP_END           = 4'd13;
localparam RX_WAIT_BUSY         = 4'd14;
reg [7:0] cnt;
wire no_resp;
wire resp_wait_busy;
wire [7:0] resp_arg_len_max;
wire crc_rst;
reg crc_din_en;
reg crc_din;
wire [6:0] crc;
// resp decode
assign no_resp = (resp_type == 2'b00);
assign resp_wait_busy = (resp_type == 2'b11);
assign resp_arg_len_max = resp_type[1] ? 8'd31 : 8'd119; // 01: 136, 10&11: 48

// fsm syn
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
// fsm comb
always @(*) begin
    // set default
    st_next = st_curr;
    // state trans
    case (st_curr)
        IDLE: begin
            if (cmd_start) 
                st_next = TX_CMD_START;
        end
        TX_CMD_START: begin
            if (tx_en)
                st_next = TX_CMD_TRANS;
        end
        TX_CMD_TRANS: begin
            if (tx_en)
                st_next = TX_CMD_INDEX;
        end
        TX_CMD_INDEX: begin
            if (tx_en && (cnt == 0)) // dec
                st_next = TX_CMD_ARG;
        end
        TX_CMD_ARG: begin
            if (tx_en && (cnt == 0)) // dec
                st_next = TX_CMD_CRC;
        end
        TX_CMD_CRC: begin
            if (tx_en && (cnt == 0)) // dec
                st_next = TX_CMD_END;
        end
        TX_CMD_END: begin
            if (tx_en)
                if (no_resp)
                    st_next = IDLE;
                else
                    st_next = RX_RSP_DLY;
        end
        RX_RSP_DLY: begin
            if (rx_en && (cnt == 0)) // dec
                st_next = RX_RSP_START;
        end
        RX_RSP_START: begin
            if (rx_en && (cmd_i == 0)) // 2~64
                st_next = RX_RSP_TRANS;
        end
        RX_RSP_TRANS: begin
            if (rx_en)
                st_next = RX_RSP_INDEX;
            //// smih_cr
            //if (rx_en & (~cmd_i))
            //    st_next = RX_RSP_INDEX;
        end
        RX_RSP_INDEX: begin
            if (rx_en && (cnt == 0)) // dec
                st_next = RX_RSP_ARG;
        end
        RX_RSP_ARG: begin
            if (rx_en && (cnt == 0)) // dec
                st_next = RX_RSP_CRC;
        end
        RX_RSP_CRC: begin
            if (rx_en && (cnt == 0)) // dec
                st_next = RX_RSP_END;
        end
        RX_RSP_END: begin
            if (rx_en)
                if (resp_wait_busy)
                    st_next = RX_WAIT_BUSY;
                else
                    st_next = IDLE;
        end
        RX_WAIT_BUSY: begin
            if (dat_0_i == 1'b1) // busy end, no timeout???
                st_next = IDLE;
        end
        default: begin
            st_next = IDLE;
        end
    endcase
end
// cmd pad & cnt
always @(posedge sd_clk or negedge rstn) begin
    if (rstn == 1'b0) begin
        cnt <= 0;
        cmd_o <= 1;
        cmd_oe <= 0;
    end
    else begin
        case (st_curr)
            IDLE: begin
                cnt <= 0;
                cmd_o <= 1;
                cmd_oe <= 0;
            end
            TX_CMD_START: begin
                if (tx_en) begin
                    cmd_o <= 0;
                    cmd_oe <= 1;
                end
            end
            TX_CMD_TRANS: begin // Host '1', Device '0'
                if (tx_en) begin
                    cmd_o <= 1;
                    cmd_oe <= 1;
                    cnt <= `CMD_INDEX_LEN - 1;
                end
            end
            TX_CMD_INDEX: begin // [5] transfer first
                if (tx_en) begin
                    cmd_o <= cmd_index[cnt];
                    cmd_oe <= 1;
                    if (cnt == 0)
                        cnt <= `CMD_ARG_LEN - 1;
                    else
                        cnt <= cnt - 1;
                end
            end
            TX_CMD_ARG: begin
                if (tx_en) begin
                    cmd_o <= cmd_argument[cnt];
                    cmd_oe <= 1;
                    if (cnt == 0)
                        cnt <= `CMD_CRC_LEN - 1;
                    else
                        cnt <= cnt - 1;
                end
            end
            TX_CMD_CRC: begin
                if (tx_en) begin
                    cmd_o <= crc[cnt];
                    cmd_oe <= 1;
                    cnt <= cnt - 1;
                end
            end
            TX_CMD_END: begin
                if (tx_en) begin
                    cmd_o <= 1;
                    cmd_oe <= 1;
                    cnt <= `CMD_TO_RSP_DLY - 1;
                end
            end
            RX_RSP_DLY: begin
                if (tx_en) begin // disable output
                    cmd_oe <= 0;
                    if (cnt != 0)
                        cnt <= cnt - 1;
                end
            end
            RX_RSP_START: begin
                if (rx_en & cmd_i) begin
                    if (cnt != 8'hff)
                        cnt <= cnt + 1; // timeout
                end
            end
            RX_RSP_TRANS: begin
                cnt <= `RSP_INDEX_LEN - 1;
            end
            RX_RSP_INDEX: begin
                if (rx_en) begin
                    if (cnt == 0)
                        cnt <= resp_arg_len_max;
                    else
                        cnt <= cnt - 1;
                end
            end
            RX_RSP_ARG: begin
                if (rx_en) begin
                    if (cnt == 0)
                        cnt <= `RSP_CRC_LEN - 1;
                    else
                        cnt <= cnt - 1;
                end
            end
            RX_RSP_CRC: begin
                if (rx_en) begin
                    cnt <= cnt - 1;
                end
            end
            RX_RSP_END: begin
            end
            RX_WAIT_BUSY: begin // smih, no timeout ???
            end
            default: begin
            end
        endcase
    end
end
// resp_index, no need reset!!!
always @(posedge sd_clk)
    if (sd_rst) // 
        resp_index <= 0;
    else if ((st_curr == IDLE) && (cmd_start == 1)) // init
        resp_index <= 0;
    else if ((st_curr == RX_RSP_INDEX) && (rx_en == 1))
        // resp_index[cnt[2:0]] <= cmd_i; // mux
        resp_index <= {resp_index[5:0], cmd_i}; // shift
// resp
always @(posedge sd_clk)
    if (sd_rst)
        resp <= 0;
    else if ((st_curr == IDLE) && (cmd_start == 1))
        resp <= 0;
    else if ((st_curr == RX_RSP_ARG) && (rx_en == 1))
        // resp[cnt[6:0]] <= cmd_i; // mux
        resp[119:0] <= {resp[118:0], cmd_i}; // shift
// resp_crc
always @(posedge sd_clk)
    if (sd_rst)
        resp_crc <= 0;
    else if ((st_curr == IDLE) && (cmd_start == 1))
        resp_crc <= 0;
    else if ((st_curr == RX_RSP_CRC) && (rx_en == 1))
        // resp_crc[cnt[2:0]] <= cmd_i; // mux
        resp_crc[6:0] <= {resp_crc[5:0], cmd_i}; // shift
// crc proc
// init, when cmd begin and resp begin
assign crc_rst = (st_curr == TX_CMD_START) | (st_curr == TX_CMD_END);
// crc ctrl
always @(*) begin
    if (st_curr == TX_CMD_TRANS) begin
        crc_din = 1;
        crc_din_en = tx_en;
    end
    else if (st_curr == TX_CMD_INDEX) begin
        crc_din = cmd_index[cnt];
        crc_din_en = tx_en;
    end
    else if (st_curr == TX_CMD_ARG) begin
        crc_din = cmd_argument[cnt];
        crc_din_en = tx_en;
    end
    else if (st_curr == RX_RSP_INDEX) begin
        crc_din = cmd_i;
        crc_din_en = rx_en;
    end
    else if (st_curr == RX_RSP_ARG) begin
        crc_din = cmd_i;
        crc_din_en = rx_en;
    end
    else begin
        crc_din = 0;
        crc_din_en = 0;
    end
end
// inst crc7
sdio_crc7 u_crc7 (
    .rstn(rstn),
    .sd_rst(sd_rst),
    .sd_clk(sd_clk),
    .crc_rst(crc_rst),
    .crc_din_en(crc_din_en),
    .crc_din(crc_din),
    .crc(crc)
);
// flags
//wire err_clr;
//wire cmd_timeout_err_event;
//wire resp_index_err_event;
//wire resp_crc_err_event;
//wire resp_end_err_event;
// cmd_timeout_err_event
assign cmd_timeout_err_event = (st_curr == RX_RSP_START) && (rx_en & cmd_i) && (cnt == 8'd64);
// resp_index_err_event
assign resp_index_err_event = cmd_index_check ? ((st_curr == RX_RSP_INDEX) && (st_next == RX_RSP_ARG) && ({resp_index[4:0], cmd_i} != cmd_index[5:0])) : 1'b0;
// resp_crc_err_event
assign resp_crc_err_event = cmd_crc_check ? ((st_curr == RX_RSP_CRC) && (st_next == RX_RSP_END) && ({resp_crc[5:0], cmd_i} != crc[6:0])) : 1'b0;
// resp_end_err_event
assign resp_end_err_event = (st_curr == RX_RSP_END) && (rx_en && (~cmd_i));
//// err_clr
//assign err_clr = (st_curr == IDLE) && (cmd_start == 1);
//// err reg
//always @(posedge sd_clk or negedge rstn)
//    if (~rstn) begin
//        cmd_timeout_err <= 0;
//        resp_index_err <= 0;
//        resp_crc_err <= 0;
//        resp_end_err <= 0;
//    end
//    else if (sd_rst) begin
//        cmd_timeout_err <= 0;
//        resp_index_err <= 0;
//        resp_crc_err <= 0;
//        resp_end_err <= 0;
//    end
//    else if (err_clr) begin
//        cmd_timeout_err <= 0;
//        resp_index_err <= 0;
//        resp_crc_err <= 0;
//        resp_end_err <= 0;
//    end
//    else begin
//        if (cmd_timeout_err_event) cmd_timeout_err <= 1;
//        if (resp_index_err_event & cmd_index_check) resp_index_err <= 1;
//        if (resp_crc_err_event & cmd_crc_check) resp_crc_err <= 1;
//        if (resp_end_err_event) resp_end_err <= 1;
//    end
// timeout
assign tmout_cmd_busy_en = st_curr == RX_WAIT_BUSY;
// flag
assign cmd_tx_end = (st_curr == TX_CMD_END) && (tx_en == 1);
assign resp_rx_end = ((st_curr == RX_RSP_END) && (st_next == IDLE)) || ((st_curr == RX_WAIT_BUSY) && (st_next == IDLE));
assign cmd_busy = (st_curr != IDLE);
// assign cmd_done = (st_curr != IDLE) && (st_next == IDLE); // simplified version
assign cmd_done = (st_curr == TX_CMD_END || st_curr == RX_RSP_END || st_curr == RX_WAIT_BUSY) && (st_next == IDLE);
// cmd_status
assign cmd_fsm = st_curr[3:0];

endmodule
