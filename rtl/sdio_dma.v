module sdio_dma #(
    parameter LEN = 16
)(
    // global
    input rstn,
    // reg
    input dma_rst,
    input start,
    input slavemode,
    input [LEN-1:0] start_addr,
    input [LEN-1:0] len,
    // rx
    input dma_end,
    input buf0_rd_rdy,
    input buf1_rd_rdy,
    input [7:0] buf0,
    input [7:0] buf1,
    output reg buf_free,
    output dma_buf_empty,
    // tx
    input sdio_byte_done,
    output reg dma_byte_en,
    output reg [7:0] dma_byte,
    // bus
    input bus_clk,
    input bus_ready,
    input bus_rdata_ready,
    input [7:0] bus_rdata,
    output reg [LEN-1:0] bus_addr,
    output reg [7:0] bus_wdata,
    output bus_rd,
    output bus_wr,
    // debug
    output [3:0] dma_state
);

// fsm
reg [2:0] st;
localparam IDLE                 = 0;
localparam WAIT_BUF_DATA        = 1;
localparam WAIT_BUS             = 2;
localparam WAIT_WR_DONE         = 3;
localparam WAIT_RD_DONE         = 4;
localparam WAIT_SDIO_DONE       = 5;
reg buf_ptr;
// bus
assign bus_rd = (st == WAIT_BUS) & bus_ready & (~slavemode);
assign bus_wr = (st == WAIT_BUS) & bus_ready & slavemode;
// debug
assign dma_state = {buf_ptr, st[2:0]};
// dma_buf_empty
assign dma_buf_empty = (st == WAIT_BUF_DATA) & (buf_ptr == 0 ? ~buf0_rd_rdy : ~buf1_rd_rdy);
// fsm
always @(posedge bus_clk or negedge rstn) begin
    if (rstn == 1'b0) begin
        st <= IDLE;
        buf_ptr <= 0;
        bus_addr <= 0;
        buf_free <= 0;
        dma_byte_en <= 0;
    end
    else if (dma_rst) begin // rst should force dma to IDLE state
        st <= IDLE;
    end
    else if (dma_end) begin // dma_end
        st <= IDLE;
    end
    else begin
        case (st)
            IDLE: begin
                buf_ptr <= 0;
                buf_free <= 0;
                bus_addr <= start_addr;
                dma_byte_en <= 0;
                if (start) begin // start
                    if (slavemode)
                        st <= WAIT_BUF_DATA;
                    else
                        st <= WAIT_BUS;
                end
            end
            WAIT_BUF_DATA: begin // Read: dma_end only during this state
                if (buf_ptr) begin
                    if (buf1_rd_rdy) begin
                        st <= WAIT_BUS;
                        buf_free <= 1;
                        bus_wdata <= buf1;
                        buf_ptr <= ~buf_ptr;
                    end
                end
                else begin
                    if (buf0_rd_rdy) begin
                        st <= WAIT_BUS;
                        buf_free <= 1;
                        bus_wdata <= buf0;
                        buf_ptr <= ~buf_ptr;
                    end
                end
            end
            WAIT_BUS: begin
                buf_free <= 0;
                if (bus_ready) begin
                    if (slavemode)
                        st <= WAIT_WR_DONE;
                    else
                        st <= WAIT_RD_DONE;
                end
            end
            WAIT_WR_DONE: begin
                if (bus_ready) begin
                    st <= WAIT_BUF_DATA;
                    if (bus_addr == (start_addr + len))
                        bus_addr <= start_addr;
                    else
                        bus_addr <= bus_addr + 1;
                end
            end
            WAIT_RD_DONE: begin
                if (bus_rdata_ready) begin
                    st <= WAIT_SDIO_DONE;
                    dma_byte_en <= 1;
                    dma_byte <= bus_rdata;
                    if (bus_addr == (start_addr + len))
                        bus_addr <= start_addr;
                    else
                        bus_addr <= bus_addr + 1;
                end
            end
            WAIT_SDIO_DONE: begin // Write: dma_end only this state!
                dma_byte_en <= 0;
                if (sdio_byte_done) begin
                    st <= WAIT_BUS;
                end
            end
        endcase
    end
end

endmodule
