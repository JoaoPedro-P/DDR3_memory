/*
 * module: mem_controller
 * -----------------
 * PT: Orquestrador do Controlador de Memória DDR3. 
 *     Este módulo coordena a Unidade de Controle (control_unit) e a Camada Física (datapath/PHY).
 *     Ele serve como o ponto central onde as decisões lógicas de agendamento são 
 *     convertidas em transações físicas e handshakes de dados com a CPU/AXI.
 * 
 *     Responsabilidades:
 *     1. Interface com o Scheduler: Recebe comandos JEDEC pré-processados.
 *     2. Interface de Dados: Gerencia a entrada/saída de dados entre o barramento da CPU e a PHY.
 *     3. Controle da PHY: Ativa drivers de escrita, terminações ODT e gera sinais diferenciais.
 *     4. Sincronização de Domínios: Garante que os status de inicialização e erro cheguem ao sistema.
 *
 * EN: DDR3 Memory Controller Orchestrator. 
 *     This module coordinates the Control Unit (control_unit) and the Physical Layer (datapath/PHY).
 *     It serves as the central point where logical scheduling decisions are 
 *     converted into physical transactions and data handshakes with the CPU/AXI.
 * 
 *     Responsibilities:
 *     1. Scheduler Interface: Receives pre-processed JEDEC commands.
 *     2. Data Interface: Manages data I/O between the CPU bus and the PHY.
 *     3. PHY Control: Activates write drivers, ODT terminations, and generates differential signals.
 *     4. Domain Synchronization: Ensures initialization and error status reach the system.
 */
module mem_controller #(parameter freq = 100) (
    // -------------------------------------------------------------------------
    // PT: Clocks e Resets Globais | EN: Global Clocks and Resets
    // -------------------------------------------------------------------------
    input  wire        clk,        // PT: Clock principal (0°). | EN: Main system clock (0°).
    input  wire        clk_90,     // PT: Clock p/ strobe DQS (90°). | EN: DQS strobe clock (90°).
    input  wire        rst_n,      // PT: Reset (Ativo Baixo). | EN: Reset (Active Low).
    input  wire        cpu_clk,    // PT: Clock do mestre (AXI). | EN: Master (AXI) clock.
    input  wire        cpu_rst_n,  // PT: Reset do mestre. | EN: Master reset.
	 input  wire        frontend_idle_safe, // PT: Segurança p/ Refresh. | EN: Refresh safety signal.

    // -------------------------------------------------------------------------
    // PT: Interface com o Scheduler (Controle) | EN: Scheduler Interface (Control)
    // -------------------------------------------------------------------------
    input  wire        CS, RAS, CAS, WE, // PT: Comandos JEDEC do agendador. | EN: JEDEC scheduler commands.
    input  wire [12:0] A,                // PT: Endereço JEDEC (Multiplexado). | EN: JEDEC address.
    input  wire [2:0]  BA,               // PT: Endereço de banco. | EN: Bank address.
    
    // PT: Status do Controlador | EN: Controller Status
    output wire        init_done,            // PT: Boot JEDEC concluído. | EN: JEDEC boot finished.
    output wire        enable_read_fifo,     // PT: Gatilho p/ captura de dados lidos. | EN: Read data capture trigger.
    output wire        enable_write_drivers, // PT: Gatilho p/ drivers de saída DQ. | EN: Write driver trigger.
    output wire        enable_row_decoder,   // PT: Gatilho p/ ativação de linha. | EN: Row decoder trigger.
    output wire        refresh_mem_flag,     // PT: Memória em ciclo de Refresh. | EN: Refresh in progress.
    output wire [7:0]  BC4_flag, AP_flag,    // PT: Configurações de Burst/Precharge. | EN: Burst/Precharge flags.
    output wire [7:0]  bank_active_flag,     // PT: Status de bancos abertos. | EN: Bank active status.
    output wire [7:0]  bank_idle_flag,       // PT: Status de bancos fechados. | EN: Bank idle status.
    output wire [12:0] MR0, MR1, MR2, MR3,   // PT: Valores dos Registradores de Modo. | EN: Mode Register values.

    // -------------------------------------------------------------------------
    // PT: Interface de Dados CPU/AXI | EN: CPU/AXI Data Interface
    // -------------------------------------------------------------------------
    input  wire        cpu_wr_en,    // PT: Habilita escrita na FIFO de saída. | EN: Enable TX FIFO write.
    input  wire [15:0] cpu_wdata,    // PT: Dado vindo da CPU/AXI. | EN: Data from CPU/AXI.
    output wire        tx_full,      // PT: FIFO de escrita cheia. | EN: TX FIFO full.
    output wire        tx_empty,     // PT: FIFO de escrita vazia. | EN: TX FIFO empty.
    output wire [15:0] cpu_rdata,    // PT: Dado entregue à CPU/AXI. | EN: Data to CPU/AXI.
    output wire        rx_valid,     // PT: Dado lido é válido. | EN: Read data is valid.
    input  wire [1:0]  cpu_wstrb,    // PT: Máscara de bytes p/ escrita. | EN: Byte mask for writes.
	 
    // -------------------------------------------------------------------------
    // PT: Sinais Físicos (Pad Ring) | EN: Physical Signals (Pad Ring)
    // -------------------------------------------------------------------------
    output wire        CS_out, RAS_out, CAS_out, WE_out, RESET_n,
    output wire [12:0] A_out,        // PT: Endereço p/ o chip DRAM. | EN: Address to DRAM chip.
    output wire [2:0]  BA_out,       // PT: Banco p/ o chip DRAM. | EN: Bank to DRAM chip.
    output wire        odt_out,      // PT: Controle de Terminação Físico. | EN: Physical ODT control.
    inout  wire [7:0]  DQ,           // PT: Barramento bidirecional de dados. | EN: Bidirectional data bus.
    inout  wire        DQS,          // PT: Strobe de dados positivo. | EN: Positive data strobe.
    inout  wire        DQS_n,        // PT: Strobe de dados negativo. | EN: Negative data strobe.
	 output wire        DM            // PT: Pino físico de Data Mask. | EN: Physical Data Mask pin.
);


    // =========================================================================
    // PT: Unidade de Controle Principal (Back-End) | EN: Main Control Unit
    // =========================================================================
    control_unit #(.freq(freq)) ctrl_inst (
        .clk(clk), 
        .rst(rst_n), 
        .CS(CS), .RAS(RAS), .CAS(CAS), .WE(WE), 
        .A(A), .BA(BA),
        .frontend_idle_safe(frontend_idle_safe),
        .CS_out(CS_out), .RAS_out(RAS_out), .CAS_out(CAS_out), .WE_out(WE_out),
        .A_out(A_out), .BA_out(BA_out),
        .RESET_n(RESET_n),
        .init_done(init_done), 
        .enable_read_fifo(enable_read_fifo), 
        .enable_write_drivers(enable_write_drivers), 
        .enable_row_decoder(enable_row_decoder), 
        .refresh_mem_flag(refresh_mem_flag),
        .BC4_flag(BC4_flag), .AP_flag(AP_flag), 
        .bank_active_flag(bank_active_flag), .bank_idle_flag(bank_idle_flag), 
        .MR0(MR0), .MR1(MR1), .MR2(MR2), .MR3(MR3)
    );

    // =========================================================================
    // PT: Datapath Físico (Front-End / PHY) | EN: Physical Datapath (PHY)
    // =========================================================================
    datapath phy_inst (
        .clk(clk),
        .clk_90(clk_90),
        .rst_n(rst_n),
        
        // PT: Aviso de escrita | EN: Write notification
        .write_req(enable_write_drivers), 
        .cpu_wstrb(cpu_wstrb),
        .cpu_clk(cpu_clk),
        .cpu_rst_n(cpu_rst_n),
        .cpu_wr_en(cpu_wr_en),
        .cpu_wdata(cpu_wdata),
        .tx_full(tx_full),
        .tx_empty(tx_empty),
        .cpu_rdata(cpu_rdata),
        .rx_valid(rx_valid),
        .odt_out(odt_out),
        .DQ(DQ),
        .DQS(DQS),
        .DQS_n(DQS_n),
		  .DM(DM)
    );

endmodule
