/*
 * module: ddr_mem
 * -----------------
 * PT: Módulo principal do sistema de memória DDR3. 
 *     Atua como o Top-Level, instanciando o controlador de memória e o core da DRAM.
 *     Inclui uma camada de sincronização (FIFO Assíncrona) para comunicação com a CPU.
 * 
 * EN: Top-level module of the DDR3 memory system.
 *     It instantiates the memory controller and the DRAM core model.
 *     Includes a Clock Domain Crossing (CDC) layer using an Asynchronous FIFO for CPU communication.
 */
module ddr_mem #(parameter freq = 100) (
    // -------------------------------------------------------------------------
    // PT: Clocks e Resets Globais | EN: Global Clocks and Resets
    // -------------------------------------------------------------------------
    input  wire        clk,        // PT: Clock do sistema (0°) | EN: System clock (0 degrees)
    input  wire        clk_90,     // PT: Clock defasado para DQS (90°) | EN: Phase-shifted clock for DQS (90 degrees)
    input  wire        rst_n,      // PT: Reset principal (Ativo Baixo) | EN: Main reset (Active Low)
    input  wire        cpu_clk,    // PT: Clock do processador (Domínio externo) | EN: CPU clock (External domain)
    input  wire        cpu_rst_n,  // PT: Reset do processador | EN: CPU reset

    // -------------------------------------------------------------------------
    // PT: Interface de Controle CPU | EN: High-Level CPU Control Interface
    // -------------------------------------------------------------------------
    input  wire        cpu_req,      // PT: CPU solicita operação | EN: CPU requests an operation
    input  wire        cpu_rnw,      // PT: 1 = Leitura, 0 = Escrita | EN: 1 = Read, 0 = Write
    input  wire [26:0] cpu_addr,     // PT: Endereço completo (27 bits) | EN: Full address sent by CPU
    output wire        cpu_ready,    // PT: Handshake: Controlador pronto | EN: Handshake: Controller is ready
    
    // PT: Sinais de Status | EN: System Status Signals
    output wire        init_done,    // PT: Inicialização concluída | EN: Initialization finished
    output wire        tx_full,      // PT: Fila de transmissão cheia | EN: TX FIFO is full
    output wire        tx_empty,     // PT: Fila de transmissão vazia | EN: TX FIFO is empty
    output wire        rx_valid,     // PT: Dados de leitura válidos | EN: Valid read data available

    // -------------------------------------------------------------------------
    // PT: Interface de Dados CPU | EN: CPU Data Interface (Write/Read Bus)
    // -------------------------------------------------------------------------
    input  wire        cpu_wr_en,    // PT: Habilita escrita na FIFO | EN: Enable write to TX FIFO
    input  wire [15:0] cpu_wdata,    // PT: Dados de escrita da CPU | EN: Write data from CPU
    output wire [15:0] cpu_rdata     // PT: Dados lidos para a CPU | EN: Read data to CPU
);

    // =========================================================================
    // PT: SINAIS INTERNOS DE ROTEAMENTO | EN: INTERNAL ROUTING SIGNALS
    // =========================================================================
    wire        int_CS, int_RAS, int_CAS, int_WE;
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
    wire        CKE_pad, RESET_n_pad;
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
        
        .cpu_wr_en(cpu_wr_en),
        .cpu_wdata(cpu_wdata),
        .tx_full(tx_full),
        .tx_empty(tx_empty),
        .cpu_rdata(cpu_rdata),
        .rx_valid(rx_valid),
        
        .CKE(CKE_pad), 
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
        .DQS_n(DQS_n_bus)
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
        .DM(1'b0) 
    );

    // =========================================================================
    // PT: 4. CORE DE ARMAZENAMENTO (DRAM BANK ARRAY) | EN: 4. STORAGE CORE
    // =========================================================================
    dram_bank_array #(
        .freq(freq),
        .MEM_DEPTH_LOG2(8) 
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
