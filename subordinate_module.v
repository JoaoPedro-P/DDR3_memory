/*
 * module: subordinate_module
 * -----------------
 * PT: Este módulo atua como o Top-Level do subsistema AXI-DDR3. Ele integra o controlador AXI-Lite 
 *     com o controlador de memória DDR3, servindo como uma ponte (Subordinate) que traduz o protocolo 
 *     padrão da indústria AXI para os sinais específicos de controle da memória.
 *     
 *     O módulo é responsável por:
 *     1. Receber requisições AXI-Lite (Write Address, Write Data, Read Address).
 *     2. Gerenciar o handshake AXI com o mestre (CPU).
 *     3. Encaminhar os endereços e dados para o core ddr_mem.
 *     4. Sincronizar as respostas da memória de volta para o barramento AXI.
 *
 * EN: This module acts as the Top-Level of the AXI-DDR3 subsystem. It integrates the AXI-Lite controller 
 *     with the DDR3 memory controller, serving as a bridge (Subordinate) that translates the industry-standard 
 *     AXI protocol into memory-specific control signals.
 *     
 *     The module is responsible for:
 *     1. Receiving AXI-Lite requests (Write Address, Write Data, Read Address).
 *     2. Managing the AXI handshake with the master (CPU).
 *     3. Forwarding addresses and data to the ddr_mem core.
 *     4. Synchronizing memory responses back to the AXI bus.
 *
 * Parameters | Parâmetros:
 *     - freq: PT: Frequência de operação do clock da memória (MHz). Default 100MHz.
 *             EN: Memory clock operating frequency (MHz). Default 100MHz.
 */
module subordinate_module #(parameter freq = 100) (
    // =========================================================================
    // Clocks e Resets | Clocks and Resets
    // =========================================================================
    input  wire        ACLK,       // PT: Clock do barramento AXI (Domínio da CPU).
                                   // EN: AXI bus clock (CPU domain).
    input  wire        ARESETn,    // PT: Reset do AXI (Ativo Baixo). Reinicia a FSM do AXI.
                                   // EN: AXI reset (Active Low). Resets the AXI FSM.
	 input  wire		  clk,        // PT: Clock principal da memória (0°).
	                               // EN: Main memory clock (0 degrees).
	 input  wire 		  clk_90,     // PT: Clock da memória defasado de 90°. Emula a função de um DLL
	                               //     para alinhar o strobe DQS no centro do olho de dados (PHY).
	                               // EN: 90-degree phase-shifted memory clock. Emulates a DLL function
	                               //     to align the DQS strobe at the center of the data eye (PHY).
	 input  wire        rst_n,      // PT: Reset principal do controlador de memória.
	                               // EN: Main memory controller reset.

    // =========================================================================
    // Interface AXI-Lite (Lado Mestre/CPU) | AXI-Lite Interface (Master/CPU Side)
    // =========================================================================
    
    // Canal de Endereço de Escrita (AW) | Write Address Channel (AW)
    input  wire [26:0] AWADDR,     // PT: Endereço de destino da escrita.
                                   // EN: Write destination address.
    input  wire        AWVALID,    // PT: Sinal do mestre indicando endereço válido.
                                   // EN: Master signal indicating valid address.
    output wire        AWREADY,    // PT: Resposta do escravo indicando pronto para receber endereço.
                                   // EN: Subordinate response indicating ready to receive address.

    // Canal de Dados de Escrita (W) | Write Data Channel (W)
    input  wire [15:0] WDATA,      // PT: Dados de 16-bits a serem escritos.
                                   // EN: 16-bit data to be written.
    input  wire        WVALID,     // PT: Sinal do mestre indicando dado válido.
                                   // EN: Master signal indicating valid data.
	 input  wire [1:0]  WSTRB,      // PT: Byte strobes (Data Mask). Indica quais bytes do WDATA são válidos.
	                               // EN: Byte strobes (Data Mask). Indicates which WDATA bytes are valid.
    output wire        WREADY,     // PT: Resposta do escravo indicando pronto para receber dado.
                                   // EN: Subordinate response indicating ready to receive data.

    // Canal de Resposta de Escrita (B) | Write Response Channel (B)
    output wire [1:0]  BRESP,      // PT: Status da transação de escrita (OKAY, ERROR, etc).
                                   // EN: Write transaction status (OKAY, ERROR, etc).
    output wire        BVALID,     // PT: Resposta válida do escravo.
                                   // EN: Subordinate valid response.
    input  wire        BREADY,     // PT: Mestre pronto para receber a resposta.
                                   // EN: Master ready to receive response.

    // Canal de Endereço de Leitura (AR) | Read Address Channel (AR)
    input  wire [26:0] ARADDR,     // PT: Endereço de destino da leitura.
                                   // EN: Read source address.
    input  wire        ARVALID,    // PT: Sinal do mestre indicando endereço de leitura válido.
                                   // EN: Master signal indicating valid read address.
    output wire        ARREADY,    // PT: Resposta do escravo indicando pronto para receber endereço.
                                   // EN: Subordinate response indicating ready to receive address.

    // Canal de Dados de Leitura (R) | Read Data Channel (R)
    output wire [15:0] RDATA,      // PT: Dado de 16-bits lido da memória.
                                   // EN: 16-bit data read from memory.
    output wire [1:0]  RRESP,      // PT: Status da transação de leitura.
                                   // EN: Read transaction status.
    output wire        RVALID,     // PT: Dado lido válido disponível.
                                   // EN: Valid read data available.
    input  wire        RREADY      // PT: Mestre pronto para receber o dado de leitura.
                                   // EN: Master ready to receive read data.

);


 wire  cpu_req, cpu_rnw, cpu_wr_en, cpu_ready, rx_valid, tx_full, init_done;
 wire [26:0] cpu_addr;
 wire [15:0] cpu_wdata;
 wire [15:0] cpu_rdata;
 wire [1:0]  cpu_wstrb;

axi_controller axi_inst (
    // =========================================================================
    // Clocks e Resets
    // =========================================================================
    .ACLK(ACLK),
    .ARESETn(ARESETn),

    // =========================================================================
    // Interface AXI-Lite (Lado Mestre/CPU)
    // =========================================================================
    
    // Canal de Endereço de Escrita (AW)
    .AWADDR(AWADDR),
    .AWVALID(AWVALID),
    .AWREADY(AWREADY),

    // Canal de Dados de Escrita (W)
    .WDATA(WDATA),
	 .WSTRB(WSTRB),
    .WVALID(WVALID),
    .WREADY(WREADY),

    // Canal de Resposta de Escrita (B)
    .BRESP(BRESP),
    .BVALID(BVALID),
    .BREADY(BREADY),

    // Canal de Endereço de Leitura (AR)
    .ARADDR(ARADDR),
    .ARVALID(ARVALID),
    .ARREADY(ARREADY),

    // Canal de Dados de Leitura (R)
    .RDATA(RDATA),
    .RRESP(RRESP),
    .RVALID(RVALID),
    .RREADY(RREADY),

    // =========================================================================
    // Interface Customizada (Lado Escravo/Memória DDR3)
    // =========================================================================
    .cpu_req(cpu_req),
    .cpu_rnw(cpu_rnw),
    .cpu_addr(cpu_addr),
    .cpu_wr_en(cpu_wr_en),
	 .init_done(init_done),
    .cpu_wdata(cpu_wdata),
    .cpu_rdata(cpu_rdata),
    .cpu_ready(cpu_ready),
	 .cpu_wstrb(cpu_wstrb),
    .rx_valid(rx_valid),
    .tx_full(tx_full)
);


ddr_mem #(.freq(freq)) mem_inst (
    // -------------------------------------------------------------------------
    // PT: Clocks e Resets Globais | EN: Global Clocks and Resets
    // -------------------------------------------------------------------------
    .clk(clk),           			  // PT: Clock do sistema (0°) | EN: System clock (0 degrees)
    .clk_90(clk_90),     			  // PT: Clock defasado para DQS (90°) | EN: Phase-shifted clock for DQS (90 degrees)
    .rst_n(rst_n),      			  // PT: Reset principal (Ativo Baixo) | EN: Main reset (Active Low)
    .cpu_clk(ACLK),    			     // PT: Clock do processador (Domínio externo) | EN: CPU clock (External domain)
    .cpu_rst_n(ARESETn),  			  // PT: Reset do processador | EN: CPU reset

    // -------------------------------------------------------------------------
    // PT: Interface de Controle CPU | EN: High-Level CPU Control Interface
    // -------------------------------------------------------------------------
    .cpu_req(cpu_req),        // PT: CPU solicita operação | EN: CPU requests an operation
    .cpu_rnw(cpu_rnw),        // PT: 1 = Leitura, 0 = Escrita | EN: 1 = Read, 0 = Write
    .cpu_addr(cpu_addr),      // PT: Endereço completo (27 bits) | EN: Full address sent by CPU
    .cpu_ready(cpu_ready),    // PT: Handshake: Controlador pronto | EN: Handshake: Controller is ready
	 .cpu_wstrb(cpu_wstrb),
    
    // PT: Sinais de Status | EN: System Status Signals
    .init_done(init_done),    // PT: Inicialização concluída | EN: Initialization finished
    .tx_full(tx_full),        // PT: Fila de transmissão cheia | EN: TX FIFO is full
    .tx_empty(),	            // PT: Fila de transmissão vazia | EN: TX FIFO is empty
    .rx_valid(rx_valid),      // PT: Dados de leitura válidos | EN: Valid read data available

    // -------------------------------------------------------------------------
    // PT: Interface de Dados CPU | EN: CPU Data Interface (Write/Read Bus)
    // -------------------------------------------------------------------------
    .cpu_wr_en(cpu_wr_en),    // PT: Habilita escrita na FIFO | EN: Enable write to TX FIFO
    .cpu_wdata(cpu_wdata),    // PT: Dados de escrita da CPU | EN: Write data from CPU
    .cpu_rdata(cpu_rdata)     // PT: Dados lidos para a CP
);

endmodule