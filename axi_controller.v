/*
 * module: axi_controller
 * -----------------
 * PT: Este módulo implementa a lógica de interface AXI-Lite. Ele é composto por duas sub-unidades:
 *     1. axi_lite_fsm: Gerencia o protocolo de handshake AXI e os estados de operação (Leitura/Escrita).
 *     2. axi_lite_datapath: Registra endereços, dados e gerencia o multiplexador de barramento.
 *     
 *     O controlador abstrai a complexidade do barramento DDR3 (que opera com blocos de 64 bits) 
 *     para um mestre AXI-Lite de 16 bits, garantindo que as transações sejam entregues corretamente.
 *
 * EN: This module implements the AXI-Lite interface logic. It consists of two sub-units:
 *     1. axi_lite_fsm: Manages the AXI handshake protocol and operation states (Read/Write).
 *     2. axi_lite_datapath: Registers addresses and data, and manages the bus multiplexer.
 *     
 *     The controller abstracts the DDR3 bus complexity (which operates with 64-bit blocks) 
 *     for a 16-bit AXI-Lite master, ensuring transactions are delivered correctly.
 */
module axi_controller (
    // =========================================================================
    // Clocks e Resets | Clocks and Resets
    // =========================================================================
    input  wire        ACLK,       // PT: Clock AXI (Síncrono com o Mestre).
                                   // EN: AXI Clock (Synchronous with Master).
    input  wire        ARESETn,    // PT: Reset AXI (Ativo Baixo).
                                   // EN: AXI Reset (Active Low).

    // =========================================================================
    // Interface AXI-Lite (Lado Mestre/CPU) | AXI-Lite Interface (Master/CPU Side)
    // =========================================================================
    
    // Canal de Endereço de Escrita (AW) | Write Address Channel (AW)
    input  wire [26:0] AWADDR,     // PT: Endereço de escrita capturado no handshake.
                                   // EN: Write address captured during handshake.
    input  wire        AWVALID,    // PT: Sinal de validade do endereço vindo do Mestre.
                                   // EN: Address validity signal from Master.
    output wire        AWREADY,    // PT: Indica que o controlador aceitou o endereço.
                                   // EN: Indicates the controller accepted the address.

    // Canal de Dados de Escrita (W) | Write Data Channel (W)
    input  wire [15:0] WDATA,      // PT: Dado de escrita (16 bits).
                                   // EN: Write data (16 bits).
    input  wire        WVALID,     // PT: Sinal de validade do dado vindo do Mestre.
                                   // EN: Data validity signal from Master.
	 input wire  [1:0]  WSTRB,      // PT: Máscara de bytes (Strobes).
	                               // EN: Byte mask (Strobes).
    output wire        WREADY,     // PT: Indica que o controlador aceitou o dado.
                                   // EN: Indicates the controller accepted the data.

    // Canal de Resposta de Escrita (B) | Write Response Channel (B)
    output wire [1:0]  BRESP,      // PT: Resposta de escrita (Sempre OKAY nesta implementação).
                                   // EN: Write response (Always OKAY in this implementation).
    output wire        BVALID,     // PT: Resposta de escrita válida.
                                   // EN: Write response valid.
    input  wire        BREADY,     // PT: Mestre pronto para receber resposta.
                                   // EN: Master ready to receive response.

    // Canal de Endereço de Leitura (AR) | Read Address Channel (AR)
    input  wire [26:0] ARADDR,     // PT: Endereço de leitura.
                                   // EN: Read address.
    input  wire        ARVALID,    // PT: Sinal de validade do endereço de leitura.
                                   // EN: Read address validity signal.
    output wire        ARREADY,    // PT: Indica prontidão para receber endereço de leitura.
                                   // EN: Indicates readiness to receive read address.

    // Canal de Dados de Leitura (R) | Read Data Channel (R)
    output wire [15:0] RDATA,      // PT: Dado de leitura retornado para o mestre.
                                   // EN: Read data returned to master.
    output wire [1:0]  RRESP,      // PT: Resposta de leitura (Sempre OKAY).
                                   // EN: Read response (Always OKAY).
    output wire        RVALID,     // PT: Dado de leitura disponível e válido.
                                   // EN: Read data available and valid.
    input  wire        RREADY,     // PT: Mestre pronto para ler o dado.
                                   // EN: Master ready to read the data.

    // =========================================================================
    // Interface Customizada (Lado Escravo/Memória DDR3) | Custom Interface (Slave/DDR3 Side)
    // =========================================================================
    output wire        cpu_req,    // PT: Solicitação de comando para a memória.
                                   // EN: Command request to memory.
    output wire        cpu_rnw,    // PT: Seletor Read/Write_n.
                                   // EN: Read/Write_n selector.
    output wire [26:0] cpu_addr,   // PT: Endereço traduzido para a memória.
                                   // EN: Translated address for memory.
    output wire        cpu_wr_en,  // PT: Habilita escrita nos buffers internos da memória.
                                   // EN: Enables write to memory internal buffers.
    output wire [15:0] cpu_wdata,  // PT: Dado a ser escrito.
                                   // EN: Data to be written.
	 output wire [1:0]  cpu_wstrb,  // PT: Máscara de bytes.
	                               // EN: Byte strobe mask.
    input  wire [15:0] cpu_rdata,  // PT: Dado lido vindo da memória.
                                   // EN: Read data coming from memory.
    input  wire        cpu_ready,  // PT: Indica que a memória está pronta para aceitar requisições.
                                   // EN: Indicates memory is ready to accept requests.
    input  wire        rx_valid,   // PT: Indica que o dado lido da memória é válido.
                                   // EN: Indicates read data from memory is valid.
    input  wire        tx_full,    // PT: Indica que a fila de escrita está cheia.
                                   // EN: Indicates write queue is full.
	 input  wire        init_done   // PT: Sinaliza que a sequência de calibração JEDEC terminou.
	                               // EN: Signals JEDEC calibration sequence has finished.
);


    // =========================================================================
    // Sinais Internos de Interconexão (FSM <-> Datapath)
    // =========================================================================
    wire latch_aw;
    wire latch_w;
    wire latch_ar;
	 wire latch_r;
    wire sel_read;

    // =========================================================================
    // Instanciação: Máquina de Estados (Controle)
    // =========================================================================
    axi_lite_fsm u_fsm (
        .ACLK       (ACLK),
        .ARESETn    (ARESETn),
        
        // Entradas/Saídas AXI
        .AWVALID    (AWVALID),
        .WVALID     (WVALID),
        .BREADY     (BREADY),
        .ARVALID    (ARVALID),
        .RREADY     (RREADY),
        .AWREADY    (AWREADY),
        .WREADY     (WREADY),
        .BVALID     (BVALID),
        .ARREADY    (ARREADY),
        .RVALID     (RVALID),
        
        // Entradas/Saídas da Memória
        .cpu_ready  (cpu_ready),
        .rx_valid   (rx_valid),
        .tx_full    (tx_full),
        .cpu_req    (cpu_req),
        .cpu_rnw    (cpu_rnw),
        .cpu_wr_en  (cpu_wr_en),
        .init_done  (init_done),
        // Sinais de controle para o Datapath
        .latch_aw   (latch_aw),
        .latch_w    (latch_w),
        .latch_ar   (latch_ar),
        .sel_read   (sel_read),
		  .latch_r	  (latch_r)
    );

    // =========================================================================
    // Instanciação: Caminho de Dados (Datapath)
    // =========================================================================
    axi_lite_datapath u_datapath (
        .ACLK       (ACLK),
        .ARESETn    (ARESETn),
        
        // Sinais de controle vindos da FSM
        .latch_aw   (latch_aw),
        .latch_w    (latch_w),
        .latch_ar   (latch_ar),
        .sel_read   (sel_read),
		  .latch_r    (latch_r),
        
        // Entradas/Saídas AXI
        .AWADDR     (AWADDR),
        .WDATA      (WDATA),
        .ARADDR     (ARADDR),
        .RDATA      (RDATA),
        .BRESP      (BRESP),
        .RRESP      (RRESP),
        .WSTRB      (WSTRB),
		  
        // Entradas/Saídas da Memória
        .cpu_rdata  (cpu_rdata),
        .cpu_addr   (cpu_addr),
        .cpu_wdata  (cpu_wdata),
		  .cpu_wstrb  (cpu_wstrb)
    );

endmodule