// [PT] Módulo principal do sistema de memória DDR3. Atua como o "Top-Level" do core da memória, instanciando o controlador JEDEC, a camada física (PHY) e o modelo de armazenamento. / [EN] Main module of the DDR3 memory system. Acts as the "Top-Level" of the memory core, instantiating the JEDEC controller, the physical layer (PHY), and the storage model.
// [PT] Principais Responsabilidades: / [EN] Key Responsibilities:
// [PT] 1. Camada CDC (Clock Domain Crossing): Utiliza FIFOs assíncronas para transferir comandos e dados entre o domínio de clock da CPU (cpu_clk) e o domínio da memória (clk). / [EN] 1. CDC (Clock Domain Crossing) Layer: Uses asynchronous FIFOs to transfer commands and data between the CPU clock domain (cpu_clk) and the memory domain (clk).
// [PT] 2. Interface de Controle: Instancia a interface_control_unit para decodificar requisições e gerenciar a política de página aberta (Open-Page Policy). / [EN] 2. Control Interface: Instantiates the interface_control_unit to decode requests and manage the Open-Page Policy.
// [PT] 3. Back-end JEDEC: Instancia o mem_controller que gerencia inicialização, refresh e estados dos bancos (FSMs de banco). / [EN] 3. JEDEC Back-end: Instantiates the mem_controller which manages initialization, refresh, and bank states (bank FSMs).
// [PT] 4. Core de Armazenamento: Conecta-se ao dram_bank_array que emula as células de memória, amplificadores de detecção e lógica de máscara. / [EN] 4. Storage Core: Connects to the dram_bank_array which emulates memory cells, sense amplifiers, and data mask logic.
// [PT] Parâmetros: freq - Frequência de operação (MHz). Default 100MHz. / [EN] Parameters: freq - Operating frequency (MHz). Default 100MHz.
module ddr_mem #(parameter freq = 100) (
    input  wire        clk,        // [PT] Clock da memória / [EN] Memory clock
    input  wire        clk_90,     // [PT] Clock da memória deslocado em 90 graus / [EN] Memory clock shifted by 90 degrees
    input  wire        rst_n,      // [PT] Reset ativo baixo para o domínio da memória / [EN] Active-low reset for memory domain
    input  wire        cpu_clk,    // [PT] Clock da CPU / [EN] CPU clock
    input  wire        cpu_rst_n,  // [PT] Reset ativo baixo da CPU / [EN] Active-low CPU reset

    input  wire        cpu_req,      // [PT] Requisição de transação da CPU / [EN] CPU transaction request
    input  wire        cpu_rnw,      // [PT] CPU read/write (1=read, 0=write) / [EN] CPU read/write (1=read, 0=write)
    input  wire [26:0] cpu_addr,     // [PT] Endereço da CPU / [EN] CPU address
    output wire        cpu_ready,    // [PT] Indica que o sistema está pronto / [EN] Indicates system is ready
    
    output wire        init_done,    // [PT] Indica conclusão da inicialização / [EN] Indicates initialization is done
    output wire        tx_full,      // [PT] FIFO de transmissão cheia / [EN] TX FIFO full
    output wire        tx_empty,     // [PT] FIFO de transmissão vazia / [EN] TX FIFO empty
    output wire        rx_valid,     // [PT] Dados de recepção válidos / [EN] RX data valid

    // [PT] Sinais atualizados para 32 bits / [EN] Signals updated to 32 bits
    input  wire        cpu_wr_en,    // [PT] Habilitação de escrita da CPU / [EN] CPU write enable
    input  wire [31:0] cpu_wdata,    // [PT] Dados de escrita da CPU / [EN] CPU write data
    input  wire [3:0]  cpu_wstrb,    // [PT] Strobe de escrita da CPU / [EN] CPU write strobe
    output wire [31:0] cpu_rdata     // [PT] Dados de leitura da CPU / [EN] CPU read data
);

    // [PT] Fios internos para comandos JEDEC / [EN] Internal wires for JEDEC commands
    wire        int_CS, int_RAS, int_CAS, int_WE, RESET_n_pad, DM;
    wire [13:0] int_row_addr;
    wire [9:0]  int_col_addr;
    wire [2:0]  int_bank_addr;
    
    wire [7:0]  int_bank_active_flag;
    wire [7:0]  int_bank_idle_flag;
    wire        int_init_done;

    // [PT] Atribuição do sinal de inicialização concluída / [EN] Assignment of init done signal
    assign init_done = int_init_done; 

    // [PT] Multiplexação do barramento de endereço / [EN] Address bus multiplexing
    wire [12:0] int_A;
    assign int_A = (int_RAS == 1'b0 && int_WE == 1'b1) ? int_row_addr[12:0] : 
                   (int_RAS == 1'b0 && int_WE == 1'b0) ? 13'h000            : 
                                                         {3'b000, int_col_addr}; 

    // [PT] Sinais da FIFO de comandos / [EN] Command FIFO signals
    wire        cmd_fifo_empty;
    wire        cmd_fifo_full;
    wire [27:0] cmd_fifo_rdata;
    wire        cmd_ack;

    // [PT] Instanciação da FIFO assíncrona para CDC / [EN] Instantiation of asynchronous FIFO for CDC
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

    // [PT] CPU pronta quando a FIFO não estiver cheia / [EN] CPU ready when FIFO is not full
    assign cpu_ready = !cmd_fifo_full; 

    // [PT] Sinais internos decodificados da FIFO / [EN] Internal signals decoded from FIFO
    wire        int_cpu_req  = !cmd_fifo_empty;
    wire        int_cpu_rnw  = cmd_fifo_rdata[27];
    wire [26:0] int_cpu_addr = cmd_fifo_rdata[26:0];
    wire        mem_fsm_ready;
    wire frontend_idle_safe = (mem_fsm_ready && !int_cpu_req);

    // [PT] Unidade de controle de interface / [EN] Interface control unit
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

    // [PT] Sinais dos pads físicos / [EN] Physical pad signals
    wire        CS_n_pad, RAS_n_pad, CAS_n_pad, WE_n_pad;
    wire [12:0] A_pad;
    wire [2:0]  BA_pad;
    wire        odt_pad;
    
    // [PT] Sinais de controle de datapath / [EN] Datapath control signals
    wire [7:0] ctrl_dq_out;
    wire       ctrl_dqs_out;
    wire       ctrl_dqs_n_out;
    wire       ctrl_dq_oe;
    wire       ctrl_dqs_oe;

    // [PT] Sinais de datapath da DRAM / [EN] DRAM datapath signals
    wire [7:0] dram_dq_out;
    wire       dram_dqs_out;
    wire       dram_dqs_n_out;
    wire       dram_out_en;

    // [PT] Roteamento bidirecional de dados / [EN] Bidirectional data routing
    wire [7:0] ctrl_dq_in    = dram_out_en ? dram_dq_out    : 8'd0;
    wire       ctrl_dqs_in   = dram_out_en ? dram_dqs_out   : 1'b0;
    wire       ctrl_dqs_n_in = dram_out_en ? dram_dqs_n_out : 1'b1;

    wire [7:0] dram_dq_in    = ctrl_dq_oe  ? ctrl_dq_out    : 8'd0;
    wire       dram_dqs_in   = ctrl_dqs_oe ? ctrl_dqs_out   : 1'b0;
    wire       dram_dqs_n_in = ctrl_dqs_oe ? ctrl_dqs_n_out : 1'b1;
	 
    // [PT] Controlador JEDEC da memória / [EN] JEDEC memory controller
    mem_controller #(.freq(freq)) controller_inst (
        .clk(clk),
        .clk_90(clk_90),
        .rst_n(rst_n),
        .cpu_clk(cpu_clk),
        .cpu_rst_n(cpu_rst_n),
        .CS(int_CS), .RAS(int_RAS), .CAS(int_CAS), .WE(int_WE),
        .A(int_A), .BA(int_bank_addr),
        .frontend_idle_safe(frontend_idle_safe),
        .init_done(int_init_done),
        .enable_read_fifo(), .enable_write_drivers(), .enable_row_decoder(), 
        .refresh_mem_flag(), .BC4_flag(), .AP_flag(), 
        .bank_active_flag(int_bank_active_flag), .bank_idle_flag(int_bank_idle_flag),     
        .MR0(), .MR1(), .MR2(), .MR3(),
        .cpu_wstrb(cpu_wstrb),
        .cpu_wr_en(cpu_wr_en),
        .cpu_wdata(cpu_wdata),
        .tx_full(tx_full),
        .tx_empty(tx_empty),
        .cpu_rdata(cpu_rdata),
        .rx_valid(rx_valid),
        .RESET_n(RESET_n_pad),
        .CS_out(CS_n_pad), .RAS_out(RAS_n_pad), .CAS_out(CAS_n_pad), .WE_out(WE_n_pad),
        .A_out(A_pad), .BA_out(BA_pad), .odt_out(odt_pad),
        .dq_in(ctrl_dq_in), .dqs_in(ctrl_dqs_in), .dqs_n_in(ctrl_dqs_n_in),
        .dq_out(ctrl_dq_out), .dqs_out_pad(ctrl_dqs_out), .dqs_n_out_pad(ctrl_dqs_n_out),
        .dq_oe(ctrl_dq_oe), .dqs_oe(ctrl_dqs_oe), .DM(DM)
    );

    // [PT] Decodificação de comandos JEDEC na DRAM / [EN] JEDEC command decoding at DRAM
    wire dram_act_cmd = (!CS_n_pad && !RAS_n_pad &&  CAS_n_pad &&  WE_n_pad);
    wire dram_pre_cmd = (!CS_n_pad && !RAS_n_pad &&  CAS_n_pad && !WE_n_pad);
    wire dram_rd_cmd  = (!CS_n_pad &&  RAS_n_pad && !CAS_n_pad &&  WE_n_pad);
    wire dram_wr_cmd  = (!CS_n_pad &&  RAS_n_pad && !CAS_n_pad && !WE_n_pad);

    // [PT] Barramentos de dados de e para o core / [EN] Data buses to and from core
    wire [63:0] sdr_data_to_core;
    wire [63:0] sdr_data_from_core;
    wire [7:0]  sdr_dm_to_core;
    
    wire [7:0]  dram_bank_active;
    wire        dram_timing_error;

    // [PT] Interface de dados da DRAM / [EN] DRAM data interface
    dram_data_interface data_io_bridge_inst (
        .clk(clk),
        .rst_n(RESET_n_pad),
        .rd_cmd(dram_rd_cmd),
        .wr_cmd(dram_wr_cmd),
        .data_from_core(sdr_data_from_core),
        .data_to_core(sdr_data_to_core),
        .dm_to_core(sdr_dm_to_core),
        .dq_in(dram_dq_in), .dqs_in(dram_dqs_in), .dqs_n_in(dram_dqs_n_in),
        .dq_out(dram_dq_out), .dqs_out_pad(dram_dqs_out), .dqs_n_out_pad(dram_dqs_n_out),
        .out_en(dram_out_en), .DM(DM)
    );

    // [PT] Array de bancos da DRAM core / [EN] DRAM core bank array
    dram_bank_array #(.freq(freq), .MEM_DEPTH_LOG2(10)) dram_core_inst (
        .clk(clk), .rst_n(RESET_n_pad), 
        .act_cmd(dram_act_cmd), .pre_cmd(dram_pre_cmd), 
        .rd_cmd(dram_rd_cmd), .wr_cmd(dram_wr_cmd),
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