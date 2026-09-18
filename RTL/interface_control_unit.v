/*
 * module: interface_control_unit
 * -----------------
 * [PT] Unidade de Controle de Interface (Frontend). 
 *      Este módulo é a porta de entrada para os comandos da CPU/AXI. Ele traduz 
 *      endereços lógicos em endereços físicos de DRAM e decide quais comandos 
 *      JEDEC (ACT, RD, WR, PRE) devem ser enviados ao backend.
 * 
 *      Responsabilidades:
 *      1. Decodificação de Endereço: Mapeia o endereço de 27 bits da CPU em 
 *         Bank (3 bits), Row (14 bits) e Column (10 bits).
 *      2. Política de Página Aberta: Em conjunto com o row_tracker, determina 
 *         se o acesso é um Hit (mesma linha aberta), Miss (linha diferente 
 *         aberta) ou Empty (nenhuma linha aberta).
 *      3. Árbitro de Comandos: Coordena o handshake com a FIFO de comandos e 
 *         sinaliza para o mem_controller quando disparar operações.
 *
 * [EN] Interface Control Unit (Frontend).
 *      This module is the gateway for CPU/AXI commands. It translates logical 
 *      addresses into physical DRAM addresses and decides which JEDEC 
 *      commands (ACT, RD, WR, PRE) should be sent to the backend.
 * 
 *      Responsibilities:
 *      1. Address Decoding: Maps the 27-bit CPU address into Bank (3 bits), 
 *         Row (14 bits), and Column (10 bits).
 *      2. Open-Page Policy: Working with the row_tracker, it determines 
 *         if an access is a Hit (same row open), Miss (different row open), 
 *         or Empty (no row open).
 *      3. Command Arbiter: Coordinates the handshake with the command FIFO 
 *         and signals the mem_controller when to trigger operations.
 */
module interface_control_unit(
    // =========================================================================
    // [PT] Clocks e Controle / [EN] Clocks and Control
    // =========================================================================
    input  wire        clk,             // [PT] Clock da memória. / [EN] Memory clock.
    input  wire        rst_n,           // [PT] Reset (Ativo Baixo). / [EN] Reset (Active Low).
    input  wire        cpu_req,         // [PT] Requisição pendente na FIFO. / [EN] Pending request in FIFO.
    input  wire        cpu_rnw,         // [PT] 1=Leitura, 0=Escrita. / [EN] 1=Read, 0=Write.
    input  wire        init_done,       // [PT] Indica boot concluído. / [EN] Boot finished.
    input  wire [26:0] cpu_address,     // [PT] Endereço lógico (27-bits). / [EN] Logical address (27-bits).
    
    // [PT] Sinais de Status dos Bancos / [EN] Bank Status Signals
    input  wire [7:0]  cpu_active_flag, // [PT] Bancos com página aberta. / [EN] Active banks (open page).
    input  wire [7:0]  cpu_idle_flag,   // [PT] Bancos sem página aberta. / [EN] Idle banks (no open page).
    
    // [PT] Saídas de Endereço Traduzido / [EN] Translated Address Outputs
    output wire [13:0] row_addr,        // [PT] Endereço de linha (14 bits). / [EN] Row address (14 bits).
    output wire [9:0]  col_addr,        // [PT] Endereço de coluna (10 bits). / [EN] Column address (10 bits).
    output wire [2:0]  bank_addr,       // [PT] Endereço de banco (3 bits). / [EN] Bank address (3 bits).
    
    // [PT] Sinais p/ mem_controller / [EN] Signals for mem_controller
    output wire        cpu_ready,       // [PT] Frontend pronto p/ próximo comando. / [EN] Frontend ready for next command.
    output wire        CS, RAS, WE, CAS,// [PT] Comandos JEDEC SDR. / [EN] JEDEC SDR commands.
	 output wire        cmd_ack          // [PT] Reconhecimento p/ FIFO (CDC). / [EN] Ack for FIFO (CDC).
);

    wire page_empty, page_hit, page_miss, update_row_en;
    
    // [PT] Lógica de Comunicação (FSM JEDEC) / [EN] Communication Logic (JEDEC FSM)
    // [PT] Instanciação do módulo que controla a FSM de comandos / [EN] Instantiation of the command FSM module
    comunication_control_logic comu_inst(
        .clk(clk), .rst_n(rst_n), .init_done(init_done),
        .cpu_req(cpu_req), .cpu_rnw(cpu_rnw), .page_hit(page_hit),
        .page_empty(page_empty), .page_miss(page_miss), .cpu_idle_flag(cpu_idle_flag),
        .cpu_active_flag(cpu_active_flag), .cpu_bank_addr(bank_addr),
        .cpu_ready(cpu_ready), .update_row_en(update_row_en), .CS(CS),
        .RAS(RAS), .CAS(CAS), .WE(WE),
        .cmd_ack(cmd_ack) 
    );

    // [PT] Decodificador de Endereço / [EN] CPU Address Decoder
    // [PT] Instanciação do decodificador que mapeia o endereço / [EN] Instantiation of the decoder mapping the address
    cpu_addr_decoder decoder_inst (
        .cpu_addr(cpu_address),
        .row_addr(row_addr),
        .bank_addr(bank_addr),
        .col_addr(col_addr)
    );

    // [PT] Rastreador de Linhas (Page Policy) / [EN] Row Tracker (Page Policy)
    // [PT] Instanciação do módulo que monitora o status de linha / [EN] Instantiation of the row status tracker
    row_tracker tracker_inst(
        .clk(clk), .rst_n(rst_n), .update_row_en(update_row_en),
        .cpu_bank_addr(bank_addr), .cpu_row_addr(row_addr),
        .cpu_idle_flag(cpu_idle_flag), .cpu_active_flag(cpu_active_flag),
        .page_hit(page_hit), .page_miss(page_miss), .page_empty(page_empty)
    );
endmodule
