/*
 * module: ddr_mem
 * -----------------
 * PT: Módulo principal do sistema de memória DDR3. Atua como o "Top-Level" do core da memória, 
 *     instanciando o controlador JEDEC, a camada física (PHY) e o modelo de armazenamento.
 *     
 *     Principais Responsabilidades:
 *     1. Camada CDC (Clock Domain Crossing): Utiliza FIFOs assíncronas para transferir comandos 
 *        e dados entre o domínio de clock da CPU (cpu_clk) e o domínio da memória (clk).
 *     2. Interface de Controle: Instancia a interface_control_unit para decodificar requisições 
 *        e gerenciar a política de página aberta (Open-Page Policy).
 *     3. Back-end JEDEC: Instancia o mem_controller que gerencia inicialização, refresh e 
 *        estados dos bancos (FSMs de banco).
 *     4. Core de Armazenamento: Conecta-se ao dram_bank_array que emula as células de memória, 
 *        amplificadores de detecção e lógica de máscara.
 *
 * EN: Main module of the DDR3 memory system. Acts as the "Top-Level" of the memory core, 
 *     instantiating the JEDEC controller, the physical layer (PHY), and the storage model.
 *     
 *     Key Responsibilities:
 *     1. CDC (Clock Domain Crossing) Layer: Uses asynchronous FIFOs to transfer commands 
 *        and data between the CPU clock domain (cpu_clk) and the memory domain (clk).
 *     2. Control Interface: Instantiates the interface_control_unit to decode requests 
 *        and manage the Open-Page Policy.
 *     3. JEDEC Back-end: Instantiates the mem_controller which manages initialization, 
 *        refresh, and bank states (bank FSMs).
 *     4. Storage Core: Connects to the dram_bank_array which emulates memory cells, 
 *        sense amplifiers, and data mask logic.
 *
 * Parameters | Parâmetros:
 *     - freq: PT: Frequência de operação (MHz). Default 100MHz.
 *             EN: Operating frequency (MHz). Default 100MHz.
 */
module ddr_mem #(parameter freq = 100) (
    // -------------------------------------------------------------------------
    // PT: Clocks e Resets Globais | EN: Global Clocks and Resets
    // -------------------------------------------------------------------------
    input  wire        clk,        // PT: Clock principal do sistema (0°).
                                   // EN: Main system clock (0 degrees).
    input  wire        clk_90,     // PT: Clock defasado de 90°. Emula um DLL para centralizar o strobe DQS.
                                   // EN: 90-degree phase-shifted clock. Emulates a DLL to center the DQS strobe.
    input  wire        rst_n,      // PT: Reset global (Ativo Baixo). Reinicia todo o controlador e core.
                                   // EN: Global reset (Active Low). Resets the entire controller and core.
    input  wire        cpu_clk,    // PT: Clock da interface CPU (Ex: barramento AXI).
                                   // EN: CPU interface clock (e.g., AXI bus).
    input  wire        cpu_rst_n,  // PT: Reset da interface CPU.
                                   // EN: CPU interface reset.

    // -------------------------------------------------------------------------
    // PT: Interface de Controle CPU | EN: High-Level CPU Control Interface
    // -------------------------------------------------------------------------
    input  wire        cpu_req,      // PT: Solicitação de operação. Pulso indica novo comando.
                                     // EN: Operation request. Pulse indicates a new command.
    input  wire        cpu_rnw,      // PT: Direção: 1 = Leitura (Read), 0 = Escrita (Write).
                                     // EN: Direction: 1 = Read, 0 = Write.
    input  wire [26:0] cpu_addr,     // PT: Endereço completo (27 bits). Mapeado em {Banco, Linha, Coluna}.
                                     // EN: Full address (27 bits). Mapped as {Bank, Row, Column}.
    output wire        cpu_ready,    // PT: Handshake: Indica que a FIFO de comandos pode aceitar novas requisições.
                                     // EN: Handshake: Indicates command FIFO can accept new requests.
    
    // PT: Sinais de Status | EN: System Status Signals
    output wire        init_done,    // PT: Indica que a sequência de calibração JEDEC foi concluída com sucesso.
                                     // EN: Indicates JEDEC calibration sequence finished successfully.
    output wire        tx_full,      // PT: Indica que a FIFO de transmissão de dados de escrita está cheia.
                                     // EN: Indicates write data TX FIFO is full.
    output wire        tx_empty,     // PT: Indica que a FIFO de transmissão de dados de escrita está vazia.
                                     // EN: Indicates write data TX FIFO is empty.
    output wire        rx_valid,     // PT: Indica que há dados de leitura válidos na saída cpu_rdata.
                                     // EN: Indicates valid read data is available on cpu_rdata.

    // -------------------------------------------------------------------------
    // PT: Interface de Dados CPU | EN: CPU Data Interface (Write/Read Bus)
    // -------------------------------------------------------------------------
    input  wire        cpu_wr_en,    // PT: Habilita a escrita de um dado de 16 bits na FIFO TX.
                                     // EN: Enables writing 16-bit data into the TX FIFO.
    input  wire [15:0] cpu_wdata,    // PT: Barramento de dados de escrita vindo da CPU.
                                     // EN: Write data bus coming from CPU.
	 input  wire [1:0]  cpu_wstrb,   // PT: Máscara de bytes (Data Mask). Simplificação do modelo analógico.
	                                 // EN: Byte mask (Data Mask). Simplification of the analog model.
    output wire [15:0] cpu_rdata     // PT: Barramento de dados lidos entregues para a CPU.
                                     // EN: Read data bus delivered to CPU.
);


    // =========================================================================
    // PT: SINAIS INTERNOS DE ROTEAMENTO | EN: INTERNAL ROUTING SIGNALS
    // =========================================================================
    wire        int_CS, int_RAS, int_CAS, int_WE, RESET_n_pad, DM;
    wire [13:0] int_row_addr;
    wire [9:0]  int_col_addr;
    wire [2:0]  int_bank_addr;
    
    wire [7:0]  int_bank_active_flag;
    wire [7:0]  int_bank_idle_flag;
    wire        int_init_done;

    // PT: Repassa o init_done interno | EN: Forward internal init_done
    assign init_done = int_init_done; 

    /* 
     * PT: MUX DE ENDEREÇO JEDEC:
     * Converte os endereços paralelos da CPU no barramento multiplexado da DRAM.
     * EN: JEDEC ADDRESS MUX:
     * Converts parallel CPU addresses into the DRAM's multiplexed bus format.
     */
    wire [12:0] int_A;
    assign int_A = (int_RAS == 1'b0 && int_WE == 1'b1) ? int_row_addr[12:0] : // ACTIVATE (Row)
                   (int_RAS == 1'b0 && int_WE == 1'b0) ? 13'h000            : // PRECHARGE (A10=0)
                                                         {3'b000, int_col_addr}; // READ/WRITE (Col)

    // =========================================================================
    // PT: 0. CAMADA CDC (COMMAND FIFO) | EN: 0. CDC LAYER (COMMAND FIFO)
    // =========================================================================
    wire        cmd_fifo_empty;
    wire        cmd_fifo_full;
    wire [27:0] cmd_fifo_rdata;
    wire        cmd_ack;

    // PT: FIFO para transferir comandos do domínio da CPU para o domínio da DRAM
    // EN: FIFO to transfer commands from CPU domain to DRAM domain
    fifo_async #(.DATA_WIDTH(28), .ADDR_WIDTH(4)) cmd_fifo_inst (
        .wr_clk(cpu_clk),
        .wr_rst_n(cpu_rst_n),
        .wr_en(cpu_req && !cmd_fifo_full), 
        .wr_data({cpu_rnw, cpu_addr}),
        .full(cmd_fifo_full),

        .rd_clk(clk),
        .rd_rst_n(rst_n),
        .rd_en(cmd_ack), 
        .rd_data(cmd_fifo_rdata),
        .empty(cmd_fifo_empty)
    );

    // PT: CPU pode enviar comando se a FIFO não estiver cheia
    // EN: CPU can send a command if the FIFO is not full
    assign cpu_ready = !cmd_fifo_full; 

    // PT: Extração de sinais para o controlador | EN: Signal extraction for the controller
    wire        int_cpu_req  = !cmd_fifo_empty;
    wire        int_cpu_rnw  = cmd_fifo_rdata[27];
    wire [26:0] int_cpu_addr = cmd_fifo_rdata[26:0];
    wire        mem_fsm_ready;

    // PT: Segurança para o Refresh dinâmico | EN: Safety flag for dynamic refresh
    wire frontend_idle_safe = (mem_fsm_ready && !int_cpu_req);

    // =========================================================================
    // PT: 1. INTERFACE DE CONTROLE | EN: 1. CONTROL INTERFACE
    // =========================================================================
    interface_control_unit interface_inst (
        .clk             (clk), 
        .rst_n           (rst_n), 
        .cpu_req         (int_cpu_req),  
        .cpu_rnw         (int_cpu_rnw),  
        .init_done       (int_init_done),
        .cpu_address     (int_cpu_addr), 
        
        .cpu_active_flag (int_bank_active_flag), 
        .cpu_idle_flag   (int_bank_idle_flag),
        
        .row_addr        (int_row_addr),
        .col_addr        (int_col_addr),
        .bank_addr       (int_bank_addr),
        .cpu_ready       (mem_fsm_ready), 
        .cmd_ack         (cmd_ack),       
        .CS              (int_CS), 
        .RAS             (int_RAS), 
        .WE              (int_WE), 
        .CAS             (int_CAS)
    );

    // =========================================================================
    // PT: BARRAMENTOS FÍSICOS DA PLACA | EN: PHYSICAL BOARD BUSES (PHY PADS)
    // =========================================================================
    
    wire        CS_n_pad, RAS_n_pad, CAS_n_pad, WE_n_pad;
    wire [12:0] A_pad;
    wire [2:0]  BA_pad;
    wire        odt_pad;
    
    wire [7:0]  DQ_bus;
    wire        DQS_bus;
    wire        DQS_n_bus;
	 
    // =========================================================================
    // PT: 1. CONTROLADOR DE MEMÓRIA (BACK-END) | EN: 1. MEMORY CONTROLLER (BACK-END)
    // =========================================================================
    mem_controller #(.freq(freq)) controller_inst (
        .clk(clk),
        .clk_90(clk_90),
        .rst_n(rst_n),
        .cpu_clk(cpu_clk),
        .cpu_rst_n(cpu_rst_n),
        
        .CS(int_CS), 
        .RAS(int_RAS), 
        .CAS(int_CAS), 
        .WE(int_WE),
        .A(int_A), 
        .BA(int_bank_addr),
        
		  .frontend_idle_safe(frontend_idle_safe),
        .init_done(int_init_done),
        .enable_read_fifo(), 
        .enable_write_drivers(), 
        .enable_row_decoder(), 
        .refresh_mem_flag(),
        .BC4_flag(), .AP_flag(), 
        .bank_active_flag(int_bank_active_flag), 
        .bank_idle_flag(int_bank_idle_flag),     
        .MR0(), .MR1(), .MR2(), .MR3(),
        .cpu_wstrb(cpu_wstrb),
        .cpu_wr_en(cpu_wr_en),
        .cpu_wdata(cpu_wdata),
        .tx_full(tx_full),
        .tx_empty(tx_empty),
        .cpu_rdata(cpu_rdata),
        .rx_valid(rx_valid),
        .RESET_n(RESET_n_pad),

        .CS_out(CS_n_pad), 
        .RAS_out(RAS_n_pad), 
        .CAS_out(CAS_n_pad), 
        .WE_out(WE_n_pad),
        .A_out(A_pad), 
        .BA_out(BA_pad),
        .odt_out(odt_pad),
        
        .DQ(DQ_bus),
        .DQS(DQS_bus), 
        .DQS_n(DQS_n_bus),
		  .DM(DM)
    );

    // =========================================================================
    // PT: 2. DESCODIFICAÇÃO DE COMANDOS DRAM | EN: 2. DRAM COMMAND DECODING
    // =========================================================================
    wire dram_act_cmd = (!CS_n_pad && !RAS_n_pad &&  CAS_n_pad &&  WE_n_pad);
    wire dram_pre_cmd = (!CS_n_pad && !RAS_n_pad &&  CAS_n_pad && !WE_n_pad);
    wire dram_rd_cmd  = (!CS_n_pad &&  RAS_n_pad && !CAS_n_pad &&  WE_n_pad);
    wire dram_wr_cmd  = (!CS_n_pad &&  RAS_n_pad && !CAS_n_pad && !WE_n_pad);

    wire [63:0] sdr_data_to_core;
    wire [63:0] sdr_data_from_core;
    wire [7:0]  sdr_dm_to_core;
    
    wire [7:0]  dram_bank_active;
    wire        dram_timing_error;

    // =========================================================================
    // PT: 3. INTERFACE DE DADOS DDR3 | EN: 3. DDR3 DATA INTERFACE
    // =========================================================================
    dram_data_interface data_io_bridge_inst (
        .clk(clk),
        .rst_n(RESET_n_pad),
        .rd_cmd(dram_rd_cmd),
        .wr_cmd(dram_wr_cmd),
        
        .data_from_core(sdr_data_from_core),
        .data_to_core(sdr_data_to_core),
        .dm_to_core(sdr_dm_to_core),
        
        .DQ(DQ_bus),
        .DQS(DQS_bus),
        .DQS_n(DQS_n_bus),
        .DM(DM) 
    );

    // =========================================================================
    // PT: 4. CORE DE ARMAZENAMENTO (DRAM BANK ARRAY) | EN: 4. STORAGE CORE
    // =========================================================================
    dram_bank_array #(
        .freq(freq),
        .MEM_DEPTH_LOG2(2) 
    ) dram_core_inst (
        .clk(clk), 
        .rst_n(RESET_n_pad), 
        .act_cmd(dram_act_cmd), 
        .pre_cmd(dram_pre_cmd), 
        .rd_cmd(dram_rd_cmd), 
        .wr_cmd(dram_wr_cmd),
        .bank_addr(BA_pad),
        .col_addr(A_pad[9:0]),
        .row_addr({1'b0, A_pad}), 
        
        .data_in(sdr_data_to_core),
        .dm_in(sdr_dm_to_core),
        .data_out(sdr_data_from_core),
        
        .bank_active(dram_bank_active),
        .timing_error(dram_timing_error)
    );

endmodule
