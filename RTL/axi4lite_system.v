// =========================================================================
// [PT] Módulo Top-Level: AXI4-Lite + Controlador de Memória DDR3 (32 bits) / [EN] Top-Level Module: AXI4-Lite + DDR3 Memory Controller (32 bits)
// =========================================================================
module axi4lite_system #(parameter ADDR_WIDTH = 27, parameter DATA_WIDTH = 32)(
    input clk_axi_bus, 
    input clk_mem,         // [PT] Clock principal da Memória DDR / [EN] Main DDR Memory clock
    input clk_90_mem,      // [PT] Clock defasado 90º para o DQS / [EN] 90º phase-shifted clock for DQS
    input resetn_bus, 
    input reset_mem,
    
    // [PT] Sinais da CPU (Master) / [EN] CPU (Master) Signals
    input STARTW,
    input STARTR,
    input [ADDR_WIDTH-1:0] m_addr,
    input [DATA_WIDTH-1:0] m_wdata,
    input [3:0] m_wstrb,
    input [2:0] m_awprot,  // [PT] <-- PORTA RESTAURADA / [EN] <-- PORT RESTORED
    input [2:0] m_arprot,  // [PT] <-- PORTA RESTAURADA / [EN] <-- PORT RESTORED
    
    output [DATA_WIDTH-1:0] m_rdata,
    output m_wdone,
    output m_rdone,
    output [1:0] m_wresp,
    output [1:0] m_rresp
);

    // =========================================================================
    // [PT] Fios do Barramento AXI-Lite / [EN] AXI-Lite Bus Wires
    // =========================================================================
    wire AWREADY; wire AWVALID; wire [ADDR_WIDTH-1:0] AWADDR; wire [2:0] AWPROT;
    wire WREADY;  wire WVALID;  wire [DATA_WIDTH-1:0] WDATA;  wire [3:0] WSTRB;
    wire BVALID;  wire [1:0] BRESP; wire BREADY;
    wire ARREADY; wire ARVALID; wire [ADDR_WIDTH-1:0] ARADDR; wire [2:0] ARPROT;
    wire RVALID;  wire [DATA_WIDTH-1:0] RDATA; wire [1:0] RRESP; wire RREADY;

    // =========================================================================
    // [PT] Sinais Intermediários da Interface de Memória (Slave -> DDR_Mem) / [EN] Intermediate Signals of the Memory Interface (Slave -> DDR_Mem)
    // =========================================================================
    wire        cpu_req;
    wire        cpu_rnw;
    wire [26:0] cpu_addr;
    wire        cpu_wr_en;
    wire [31:0] cpu_wdata;
    wire [3:0]  cpu_wstrb;
    wire        cpu_ready;
    wire        rx_valid;
    wire        tx_full;
    wire        tx_empty;
    wire        init_done;
    wire [31:0] cpu_rdata;

    // =========================================================================
    // [PT] Instanciação: AXI Master / [EN] Instantiation: AXI Master
    // =========================================================================
    axi4lite_master master0 (
        .ACLK(clk_axi_bus),
        .ARESETn(resetn_bus),
        .STARTW(STARTW), .STARTR(STARTR), .m_addr(m_addr), .m_wdata(m_wdata), .m_wstrb(m_wstrb),
        .m_awprot(m_awprot), .m_arprot(m_arprot), // [PT] <-- CONEXÃO RESTAURADA / [EN] <-- CONNECTION RESTORED
        .m_rdata(m_rdata), .m_wdone(m_wdone), .m_rdone(m_rdone), .m_wresp(m_wresp), .m_rresp(m_rresp),
        
        .AWREADY(AWREADY), .AWVALID(AWVALID), .AWADDR(AWADDR), .AWPROT(AWPROT),
        .WREADY(WREADY), .WVALID(WVALID), .WDATA(WDATA), .WSTRB(WSTRB),
        .BVALID(BVALID), .BRESP(BRESP), .BREADY(BREADY),
        .ARREADY(ARREADY), .ARVALID(ARVALID), .ARADDR(ARADDR), .ARPROT(ARPROT),
        .RVALID(RVALID), .RDATA(RDATA), .RRESP(RRESP), .RREADY(RREADY)
    );

    // =========================================================================
    // [PT] Instanciação: AXI Slave (Wrapper do Controlador) / [EN] Instantiation: AXI Slave (Controller Wrapper)
    // =========================================================================
    subordinate_module slave0 (
        .ACLK(clk_axi_bus),
        .ARESETn(resetn_bus),
        
        .AWREADY(AWREADY), .AWVALID(AWVALID), .AWADDR(AWADDR), .AWPROT(AWPROT),
        .WREADY(WREADY), .WVALID(WVALID), .WDATA(WDATA), .WSTRB(WSTRB),
        .BVALID(BVALID), .BRESP(BRESP), .BREADY(BREADY),
        .ARREADY(ARREADY), .ARVALID(ARVALID), .ARADDR(ARADDR), .ARPROT(ARPROT),
        .RVALID(RVALID), .RDATA(RDATA), .RRESP(RRESP), .RREADY(RREADY),
        
        // [PT] Conexão com a Memória DDR3 / [EN] Connection to DDR3 Memory
        .cpu_req(cpu_req), .cpu_rnw(cpu_rnw), .cpu_addr(cpu_addr), .cpu_wr_en(cpu_wr_en),
        .cpu_wdata(cpu_wdata), .cpu_wstrb(cpu_wstrb), .cpu_ready(cpu_ready), .tx_empty(tx_empty),
        .rx_valid(rx_valid), .tx_full(tx_full), .init_done(init_done), .cpu_rdata(cpu_rdata)
    );

    // =========================================================================
    // [PT] Instanciação: Core da Memória DDR3 / [EN] Instantiation: DDR3 Memory Core
    // =========================================================================
    ddr_mem #(.freq(100)) memory_core (
        .clk(clk_mem),
        .clk_90(clk_90_mem),
        .rst_n(reset_mem),
        .cpu_clk(clk_axi_bus),
        .cpu_rst_n(resetn_bus),
        
        .cpu_req(cpu_req),
        .cpu_rnw(cpu_rnw),
        .cpu_addr(cpu_addr),
        .cpu_ready(cpu_ready),
        .init_done(init_done),
        .tx_full(tx_full),
        .tx_empty(tx_empty),
        .rx_valid(rx_valid),
        .cpu_wr_en(cpu_wr_en),
        .cpu_wdata(cpu_wdata),
        .cpu_wstrb(cpu_wstrb),
        .cpu_rdata(cpu_rdata)
    );

endmodule