// Part1, 4.5
module sdio_crc16 (
    input rstn,
    input sd_rst,
    input sd_clk,
    // ctrl
    input crc_rst,
    input crc_din_en,
    input crc_din,
    output reg [15:0] crc
);
// var
wire [15:0] crc_next;
// calc, Part1, 4.5
assign crc_next = { crc[14:12],
                    (crc[11] ^ crc[15] ^ crc_din),
                    crc[10:5],
                    (crc[4] ^ crc[15] ^ crc_din),
                    crc[3:0],
                    (crc[15] ^ crc_din)
                  };
// sync
always @(posedge sd_clk or negedge rstn)
    if (~rstn)
        crc <= 0;
    else
        if (sd_rst)
            crc <= 0;
        else if (crc_rst)
            crc <= 0;
        else if (crc_din_en)
            crc <= crc_next;

endmodule
