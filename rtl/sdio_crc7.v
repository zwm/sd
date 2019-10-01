// Part1, 4.5
module sdio_crc7 (
    input rstn,
    input sd_rst,
    input sd_clk,
    // ctrl
    input crc_rst,
    input crc_din_en,
    input crc_din,
    output reg [6:0] crc
);
// var
wire [6:0] crc_next;
// calc, Part1, 4.5
assign crc_next = {  crc[5:3],
                    (crc[2] ^ crc[6] ^ crc_din),
                     crc[1:0],
                    (crc[6] ^ crc_din)
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
