// =========================================================================
// [PT] Módulo: tb_axi4lite_master / [EN] Module: tb_axi4lite_master
// [PT] Testbench simples para verificar a operação do mestre AXI4-Lite. / [EN] Simple testbench to verify the operation of the AXI4-Lite master.
// [PT] Entradas/Saídas: Interfaces AXI e sinais de controle da CPU. / [EN] Inputs/Outputs: AXI interfaces and CPU control signals.
// [PT] Papel no sistema: Testar a máquina de estados de escrita e leitura do mestre. / [EN] Role in system: Test the write and read state machine of the master.
// =========================================================================

module tb_axi4lite_master #(parameter ADDR_WIDTH = 32, parameter DATA_WIDTH = 32)();

reg ACLK;
reg ARESETn;

// [PT] Entradas do mestre provenientes da CPU / [EN] Master input from CPU

// [PT] Inicia uma transação de escrita (da CPU) / [EN] start a write transaction (from CPU)
reg STARTW; 
// [PT] Inicia uma transação de leitura (da CPU) / [EN] start a read transaction (from CPU)
reg STARTR; 
// [PT] Endereço para leitura/escrita da CPU / [EN] address for read/write from CPU
reg [ADDR_WIDTH-1:0] m_addr; 
// [PT] Dados de escrita da CPU / [EN] write data from CPU
reg [DATA_WIDTH-1:0] m_wdata; 
// [PT] Sinal de strobe (habilitação de bytes) da CPU / [EN] strobe from CPU
reg [3:0] m_wstrb; 
// [PT] DADO LIDO / [EN] READ DATA
wire[DATA_WIDTH-1:0] m_rdata; 
// [PT] Resposta de escrita - enviada pelo escravo / [EN] write response - send by the slave
wire [1:0] m_wresp; 
// [PT] Resposta de leitura - enviada pelo escravo / [EN] read response - send by the slave
wire [1:0] m_rresp; 
wire m_wdone;
wire m_rdone;

// [PT] Endereço de Escrita (AW) / [EN] Write Address (AW)
reg AWREADY;
wire AWVALID;
wire [ADDR_WIDTH-1:0] AWADDR;
wire [2:0] AWPROT;

// [PT] Dados de Escrita (W) / [EN] Write Data (W)
reg WREADY;
wire WVALID;
wire [DATA_WIDTH-1:0] WDATA;
wire [3:0] WSTRB;

// [PT] Resposta de Escrita (B) / [EN] Write Response (B)
reg BVALID;
reg [1:0] BRESP;
wire BREADY;

// [PT] Endereço de Leitura (AR) / [EN] Read Address (AR)
reg ARREADY;
wire ARVALID;
wire [ADDR_WIDTH-1:0] ARADDR;
wire [2:0] ARPROT;

// [PT] Dados de Leitura (R) / [EN] Read Data (R)
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

    // [PT] valores iniciais / [EN] initial values
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

    // [PT] espera reset / [EN] wait for reset
    @(posedge ARESETn);

    //-----------------------------------------
    // [PT] TESTE DE ESCRITA / [EN] WRITE TEST
    //-----------------------------------------

    $display("===== WRITE TEST =====");

    @(posedge ACLK);

    m_addr  <= 32'h0000_1000;
    m_wdata <= 32'hDEADBEEF;
    STARTW  <= 1'b1;

    @(posedge ACLK);
    STARTW <= 1'b0;

    // [PT] slave aceita endereço e dados / [EN] slave accepts address and data
    wait(AWVALID && WVALID);

    @(posedge ACLK);
    AWREADY <= 1'b1;
    WREADY  <= 1'b1;

    @(posedge ACLK);
    AWREADY <= 1'b0;
    WREADY  <= 1'b0;

    // [PT] resposta de escrita / [EN] write response
    repeat(2) @(posedge ACLK);

    // [PT] OKAY / [EN] OKAY
    BRESP  <= 2'b00; 
    BVALID <= 1'b1;

    wait(BREADY);

    @(posedge ACLK);
    BVALID <= 1'b0;

    wait(m_wdone);

    $display("[%0t] WRITE DONE", $time);
    $display("BRESP = %b", m_wresp);

    //-----------------------------------------
    // [PT] TESTE DE LEITURA / [EN] READ TEST
    //-----------------------------------------

    $display("===== READ TEST =====");

    @(posedge ACLK);

    m_addr <= 32'h0000_1000;
    STARTR <= 1'b1;

    @(posedge ACLK);
    STARTR <= 1'b0;

    // [PT] slave aceita endereço / [EN] slave accepts address
    wait(ARVALID);

    @(posedge ACLK);
    ARREADY <= 1'b1;

    @(posedge ACLK);
    ARREADY <= 1'b0;

    // [PT] slave devolve dado / [EN] slave returns data
    repeat(2) @(posedge ACLK);

    RDATA  <= 32'hCAFEBABE;
    // [PT] OKAY / [EN] OKAY
    RRESP  <= 2'b00; 
    RVALID <= 1'b1;

    wait(RREADY);

    @(posedge ACLK);
    RVALID <= 1'b0;

    wait(m_rdone);

    $display("[%0t] READ DONE", $time);
    $display("RDATA = %h", m_rdata);
    $display("RRESP = %b", m_rresp);

    //-----------------------------------------
    // [PT] fim / [EN] end
    //-----------------------------------------

    repeat(10) @(posedge ACLK);

    $display("===== END OF SIMULATION =====");
    $stop;

end

endmodule