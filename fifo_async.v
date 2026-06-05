/*
 * module: fifo_async
 * -----------------
 * PT: FIFO Assíncrona. Utilizada para transferir dados entre domínios de clock diferentes.
 *     Usa ponteiros Gray para evitar problemas de metaestabilidade.
 * 
 * EN: Asynchronous FIFO. Used to transfer data between different clock domains.
 *     Uses Gray pointers to prevent metastability issues.
 */
module fifo_async #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 4 // 2^4 = 16 posições
)(
    // PT: Interface de Escrita | EN: Write Interface (wr_clk Domain)
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  full,

    // PT: Interface de Leitura | EN: Read Interface (rd_clk Domain)
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  empty
);

    // -------------------------------------------------------------------------
    // PT: 1. Memória de Porta Dupla | EN: 1. Dual-Port RAM
    // -------------------------------------------------------------------------
    localparam MEM_DEPTH = (1 << ADDR_WIDTH);
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

	integer i;
    initial begin
        for (i=0; i<MEM_DEPTH; i=i+1) mem[i] = 0;
    end
	 
    wire [ADDR_WIDTH-1:0] wr_addr;
    wire [ADDR_WIDTH-1:0] rd_addr;

    // PT: Escrita Síncrona | EN: Synchronous Write
    always @(posedge wr_clk) begin
        if (wr_en && !full) begin
            mem[wr_addr] <= wr_data;
        end
    end

    // PT: Leitura Direta | EN: Direct Read
    assign rd_data = mem[rd_addr];

    // -------------------------------------------------------------------------
    // PT: 2. Ponteiros e Conversores Gray | EN: 2. Pointers and Gray Converters
    // -------------------------------------------------------------------------
    reg  [ADDR_WIDTH:0] wr_ptr_bin,  wr_ptr_gray;
    reg  [ADDR_WIDTH:0] rd_ptr_bin,  rd_ptr_gray;
    wire [ADDR_WIDTH:0] wr_ptr_bin_next, wr_ptr_gray_next;
    wire [ADDR_WIDTH:0] rd_ptr_bin_next, rd_ptr_gray_next;

    assign wr_ptr_bin_next = wr_ptr_bin + (wr_en & ~full);
    assign rd_ptr_bin_next = rd_ptr_bin + (rd_en & ~empty);

    // PT: gray = bin ^ (bin >> 1) | EN: Binary to Gray conversion
    assign wr_ptr_gray_next = wr_ptr_bin_next ^ (wr_ptr_bin_next >> 1);
    assign rd_ptr_gray_next = rd_ptr_bin_next ^ (rd_ptr_bin_next >> 1);

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin  <= 0;
            wr_ptr_gray <= 0;
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin  <= 0;
            rd_ptr_gray <= 0;
        end else begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
        end
    end

    assign wr_addr = wr_ptr_bin[ADDR_WIDTH-1:0];
    assign rd_addr = rd_ptr_bin[ADDR_WIDTH-1:0];

    // -------------------------------------------------------------------------
    // PT: 3. Sincronizadores (Cross Domain) | EN: 3. Synchronizers
    // -------------------------------------------------------------------------
    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    // -------------------------------------------------------------------------
    // PT: 4. Lógica de Flags (Full / Empty) | EN: 4. Flag Logic
    // -------------------------------------------------------------------------
    reg full_reg, empty_reg;

    wire full_condition = (wr_ptr_gray_next == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], 
                                                 rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) full_reg <= 1'b0;
        else           full_reg <= full_condition;
    end

    wire empty_condition = (rd_ptr_gray_next == wr_ptr_gray_sync2);

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) empty_reg <= 1'b1;
        else           empty_reg <= empty_condition;
    end

    assign full  = full_reg;
    assign empty = empty_reg;

endmodule
