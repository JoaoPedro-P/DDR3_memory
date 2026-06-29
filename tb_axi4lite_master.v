// test module master

module tb_axi4lite_master #(parameter ADDR_WIDTH = 32, parameter DATA_WIDTH = 32)();

reg ACLK;
reg ARESETn;

// Master input from CPU

reg STARTW; // start a write transaction (from CPU)
reg STARTR; // start a read transaction (from CPU)
reg [ADDR_WIDTH-1:0] m_addr; // address for read/write from CPU
reg [DATA_WIDTH-1:0] m_wdata; // write data from CPU
reg [3:0] m_wstrb; //strobe from CPU
wire[DATA_WIDTH-1:0] m_rdata; //DADO LIDO
wire [1:0] m_wresp; // write response - send by the slave
wire [1:0] m_rresp; // read response - send by the slave
wire m_wdone;
wire m_rdone;
// Write Address (AW)

reg AWREADY;
wire AWVALID;
wire [ADDR_WIDTH-1:0] AWADDR;
wire [2:0] AWPROT;

// Write Data (W)

reg WREADY;
wire WVALID;
wire [DATA_WIDTH-1:0] WDATA;
wire [3:0] WSTRB;

// Write Response (B)

reg BVALID;
reg [1:0] BRESP;
wire BREADY;

// Read Address (AR)

reg ARREADY;
wire ARVALID;
wire [ADDR_WIDTH-1:0] ARADDR;
wire [2:0] ARPROT;

// Read Data (R)

reg RVALID;
reg [DATA_WIDTH-1:0] RDATA;
reg [1:0] RRESP;
wire RREADY;

axi4lite_master uut (
	.ACLK(ACLK),
	.ARESETn(ARESETn),
	.STARTW(STARTW),
	.STARTR(STARTR),
	.m_addr(m_addr),
	.m_wdata(m_wdata),
	.m_wstrb(m_wstrb),
	.m_rdata(m_rdata),
	.m_wresp(m_wresp),
	.m_rresp(m_rresp),
	.m_wdone(m_wdone),
   .m_rdone(m_rdone),
	.AWREADY(AWREADY),
	.AWVALID(AWVALID),
	.AWADDR(AWADDR),
	.AWPROT(AWPROT),
	.WREADY(WREADY),
	.WVALID(WVALID),
	.WDATA(WDATA),
	.WSTRB(WSTRB),
	.BVALID(BVALID),
	.BRESP(BRESP),
	.BREADY(BREADY),
	.ARREADY(ARREADY),
	.ARVALID(ARVALID),
	.ARADDR(ARADDR),
	.ARPROT(ARPROT),
	.RVALID(RVALID),
	.RDATA(RDATA),
	.RRESP(RRESP),
	.RREADY(RREADY)

);

always #5 ACLK = ~ACLK;

initial begin 

ACLK = 1'b0;
ARESETn = 1'b0;

end

initial #10 ARESETn = 1'b1;

initial begin

    // valores iniciais
    STARTW  = 0;
    STARTR  = 0;

    m_addr  = 0;
    m_wdata = 0;
    m_wstrb = 4'b1111;

    AWREADY = 0;
    WREADY  = 0;

    BVALID  = 0;
    BRESP   = 2'b00;

    ARREADY = 0;

    RVALID  = 0;
    RDATA   = 0;
    RRESP   = 2'b00;

    // espera reset
    @(posedge ARESETn);

    //-----------------------------------------
    // TESTE DE ESCRITA
    //-----------------------------------------

    $display("===== WRITE TEST =====");

    @(posedge ACLK);

    m_addr  <= 32'h0000_1000;
    m_wdata <= 32'hDEADBEEF;
    STARTW  <= 1'b1;

    @(posedge ACLK);
    STARTW <= 1'b0;

    // slave aceita endereço e dados
    wait(AWVALID && WVALID);

    @(posedge ACLK);
    AWREADY <= 1'b1;
    WREADY  <= 1'b1;

    @(posedge ACLK);
    AWREADY <= 1'b0;
    WREADY  <= 1'b0;

    // resposta de escrita
    repeat(2) @(posedge ACLK);

    BRESP  <= 2'b00; // OKAY
    BVALID <= 1'b1;

    wait(BREADY);

    @(posedge ACLK);
    BVALID <= 1'b0;

    wait(m_wdone);

    $display("[%0t] WRITE DONE", $time);
    $display("BRESP = %b", m_wresp);

    //-----------------------------------------
    // TESTE DE LEITURA
    //-----------------------------------------

    $display("===== READ TEST =====");

    @(posedge ACLK);

    m_addr <= 32'h0000_1000;
    STARTR <= 1'b1;

    @(posedge ACLK);
    STARTR <= 1'b0;

    // slave aceita endereço
    wait(ARVALID);

    @(posedge ACLK);
    ARREADY <= 1'b1;

    @(posedge ACLK);
    ARREADY <= 1'b0;

    // slave devolve dado
    repeat(2) @(posedge ACLK);

    RDATA  <= 32'hCAFEBABE;
    RRESP  <= 2'b00; // OKAY
    RVALID <= 1'b1;

    wait(RREADY);

    @(posedge ACLK);
    RVALID <= 1'b0;

    wait(m_rdone);

    $display("[%0t] READ DONE", $time);
    $display("RDATA = %h", m_rdata);
    $display("RRESP = %b", m_rresp);

    //-----------------------------------------
    // fim
    //-----------------------------------------

    repeat(10) @(posedge ACLK);

    $display("===== END OF SIMULATION =====");
    $stop;

end


endmodule