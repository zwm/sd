module icache #(
parameter ADDRLEN = 24) (
input clk, rstn,
input [1:0] isogate, init,

// cpu
input fetch, invalidate,
input [ADDRLEN-1:0] fetch_addr,
output inst_ready,
output [31:0] inst_data,

//code interface
input code_valid,
input [31:0] code_data,
output reg code_rd,
output reg [ADDRLEN-3:0] code_addr,

// memory access mode
input [1:0] cache_ctrl,
input bus_clk, bus_access, bus_wr,
input [13:0] bus_addr,
input [7:0] bus_wdata,
output [7:0] bus_rdata,


// bist
input scan_mode,
input [3:0] bist_ctrl,
output bist_done, bist_fail
);

localparam SIZE = 7;
localparam HB = 3;
localparam AB = HB + 12;

localparam IDLE = 0;
localparam INIT = 1;
localparam MATCH = 2;
localparam FILL = 3;
localparam HIT = 4;
localparam FILLEND = 5;
localparam INITEND = 6;
integer j;

wire [1:0] bist_done0, bist_fail0;
wire [31:0] cache_ram_do;
wire [(HB+12)*4-1:0] tag_ram_data_out;
wire cache_ram_clk;
reg hit, hit_dly, mmode;
reg [HB*4-1:0] tag_high_hit, tag_high_update, tag_high_init;
reg [1:0] hitval, tag_ram_hi[0:3], tag_high_incr, hitway, replaceway;
reg [1:0] cache_ram_way;
reg [2:0] addr1, state;
reg [3:0] tag_ram_valid;
reg fetch_dly, invd_dly;
reg [19:0] tag_ram_we;
reg [SIZE-1:0] tag_init_addr;
reg [1:0] bus_addr_sync;

wire bus_mode = cache_ctrl[0];
wire mem_mode = cache_ctrl[1];
wire [ADDRLEN-1:0] inst_addr = state == HIT & fetch ? fetch_addr : {code_addr[ADDRLEN-3:3], addr1, 2'b0};
wire cache_inline = code_addr[ADDRLEN-3:3] == fetch_addr[ADDRLEN-1:5];
wire [3:0] cache_ram_we = bus_mode & bus_wr ? 1 << bus_addr[1:0] : {4{code_valid}};
wire [SIZE+4:0] cache_ram_addr = mem_mode ? fetch_addr[ADDRLEN-1:2] : bus_mode ? bus_addr[13:2] : cache_ram_we ? {cache_ram_way, code_addr[SIZE+2:0]} : {hitway, inst_addr[SIZE+4:2]};
wire [31:0] cache_ram_wdata = bus_mode ? {4{bus_wdata}} : code_data;
wire cache_ram_rd = bus_mode & bus_access | mmode & fetch | ~mmode & mem_mode | state == MATCH & hit | fetch & state == HIT & cache_inline;
wire [SIZE-1:0] tag_ram_addr = inst_addr[SIZE+4:5];
wire [HB*4-1:0] tag_high_wdata = state == INIT ? tag_high_init : hit ? tag_high_hit : tag_high_update;
wire [11:0] tag_low_wdata = inst_addr[ADDRLEN-1:12];
wire write_tag = state == MATCH;
wire [3:0] wr_tag_high = {4(state == INIT | write_tag)};
wire [3:0] wr_tag_low = write_tag & ~hit ? 1 << replaceway : 0;
wire tag_ram_rd = fetch & ~cache_inline | state == FILL & code_valid & code_addr[2:0] == 7;

assign inst_ready = mmode | state == HIT;
assign inst_data = cache_ram_do;

assign bist_done = &bist_done0;
assign bist_fail = |bist_fail0;

always @*
begin
    hit = 0;
    hitval = 0;
    hitway = 0;
    replaceway = 0;
    for (j = 0; j < 4; j = j + 1) begin
        tag_ram_hi[j] = tag_ram_data_out[j*AB+12+:2];
        tag_ram_valid[j] = tag_ram_data_out[j*AB+14];
        if (tag_ram_valid[j] & tag_ram_data_out[j*AB+:12] = tag_low_wdata) begin
            hitway = j;
            hit = 1;
            hitval = tag_ram_hi[j];
        end
        if (tag_ram_hi[j] == 3) replaceway = j;
        tag_ram_we[j*5+:5] = {wr_tag_high[j], {4(wr_tag_low[j])}};
    end
    for (j = 0; j < 4; j = j + 1) begin
        tag_high_incr = tag_ram_hi[j] + 1;
        tag_high_init[j*HB+:HB] = j;
        tag_high_hit[J*HB+:HB] = j == hitway ? 4 :
                                                    {tag_ram_valid[j], tag_ram_hi[j] < hitval ? tag_high_incr : tag_ram_hi[j]};
        tag_high_update[j*HB+:HB] = j == replaceway ? 4 : {tag_ram_valid[j], tag_high_incr};
    end
end


always @(posedge clk or negedge rstn)
if (~rstn) begin
    code_addr <= 0;
    code_rd <= 0;
    state <= IDLE;
    code_ram_way <= 0;
    fetch_dly <= 0;
    addr1 <= 0;
    invd_dly <= 0;
end
else begin
    invd_dly <= invalidate;
    case(state)
        IDLE: begin
            if (fetch & ~fetch_dly) fetch_dly <= 1;
            if (init[0]) begin
                code_addr <= 0;
                state <= INIT;
            end
            else if (init[1])
                state <= MATCH;
        end
        
        INIT: begin
            if (fetch & ~fetch_dly) fetch_dly <= 1;
            code_addr <= code_addr + 8;
            if (code_addr == {{SIZE{1'b1}}, 3'b0}) begin
                state <= INITEND;
            end
            else
                state <= state;
        end

        INITEND: begin
            match;
            fetch_dly <= 0;
        end

        MATCH:
            if (hit)
                state <= HIT;
            else begin
                state <= FILL;
                code_rd <= 1;
                cache_ram_way <= replaceway;
            end

         HIT:
             if (fetch & ~cache_inline) match;

         FILL: begin
             if (code_valid) begin
                 if (code_addr[2:0] == 7) begin
                     state <= MATCH;
                     code_rd <= 0;
                 end
                 else begin
                     code_addr <= code_addr + 1;
                 end
             end
         end

     endcase
 end





























assign bus_rdata = cache_ram_do[bus_addr_sync*8+:8];

always @(posedge cache_ram_clk or negedge rstn)
if (~rstn)
    mmode <= 0;
else
    mmode <= ~bus_mode & mem_mode;


always @(posedge cache_ram_clk or negedge rstn)
if (~rstn)
    bus_addr_sync <= 0;
else if (bus_access)
    bus_addr_sync <= bus_addr;

ckmux cacheclk (
    .scan_mode(scan_mode),
    .rstn(rstn),
    .clkin({bus_clk, clk}),
    .clken({bus_mode, ~bus_mode}),
    .clkout(cache_ram_clk)
);


wire cache_ram_clk_gated;
wire tag_ram_clk_gated;
wire cache_ram_we_t;
wire tag_ram_we_t;

assign cache_ram_we_t = | cache_ram_we;
assign tag_ram_we_t = | tag_ram_we;

gck_lvt u_cache_clkgate(
    .clk_in(cache_ram_clk),
    .clk_en(cache_ram_rd | cache_ram_we_t),
    .test_en(scan_mode | bist_ctrl[0]),
    .clk_out(cache_ram_clk_gated)
);
gck_lvt u_cache_clkgate(
    .clk_in(clk),
    .clk_en(tag_ram_rd | tag_ram_we_t),
    .test_en(scan_mode | bist_ctrl[0]),
    .clk_out(tag_ram_clk_gated)
);



// ramsphs
ramsp #(SIZE + 5, 32, 4) cache (
    .clk(cache_ram_clk_gated),
    .rd(cache_ram_rd),
    .do(cache_ram_do),
    //.isogate(isogate),
    .we(cache_ram_we),
    .a(cache_ram_addr),
    .di(cache_ram_wdata),

    .bist_ctrl(bist_ctrl),
    .bist_done(bist_done0[1]),
    .bist_fail(bist_fail0[1]),
    .scan_mode(scan_mode)
);


ramsp #(SIZE, 60, 20) tagram (
    .clk(tag_ram_clk_gated),
    .rd(tag_ram_rd),
    .do(tag_ram_data_out),
    //.isogate(isogate),
    .we(tag_ram_we),
    .a(tag_ram_addr),
    .di({tag_high_wdata[11:9], tag_low_wdata, tag_high_wdata[8:6], tag_low_wdata, tag_high_wdata[5:3], tag_low_wdata, tag_high_wdata[2:0], tag_low_wdata}),

    .bist_ctrl(bist_ctrl),
    .bist_done(bist_done0[0]),
    .bist_fail(bist_fail0[0]),
    .scan_mode(scan_mode)
);



task match;
begin
    if (fetch | fetch_dly) begin
        code_addr <= {fetch_addr[ADDRLEN-1:5], 3'b0};
        addr1 <= fetch_addr[4:2];
        state <= MATCH;
    end
end
endtask

endmodule

