/*
 * module: mem_controller
 * -----------------
 * PT: Controlador de Memória DDR3. Orquestra a Unidade de Controle e o Datapath Físico (PHY).
 *     Faz a ponte entre os comandos do Scheduler e a interface física com o chip DRAM.
 * 
 * EN: DDR3 Memory Controller. Orchestrates the Control Unit and the Physical Datapath (PHY).
 *     Bridges Scheduler commands to the physical interface with the DRAM chip.
 */
module mem_controller #(parameter freq = 100) (
    // -------------------------------------------------------------------------
    // PT: Clocks e Resets Globais | EN: Global Clocks and Resets
    // -------------------------------------------------------------------------
    input  wire        clk,        // PT: Clock principal (0°) | EN: Main system clock (0 degrees)
    input  wire        clk_90,     // PT: Clock defasado para DQS (90°) | EN: Phase-shifted clock for DQS (90 degrees)
    input  wire        rst_n,      // PT: Reset principal | EN: Main reset
    input  wire        cpu_clk,    // PT: Clock do processador | EN: CPU clock
    input  wire        cpu_rst_n,  // PT: Reset do processador | EN: CPU reset
	input  wire        frontend_idle_safe, // PT: Sinal de segurança para Refresh | EN: Safety signal for Refresh

    // -------------------------------------------------------------------------
    // PT: Interface com o Scheduler | EN: Scheduler Interface (Control FSM)
    // -------------------------------------------------------------------------
    input  wire        CS, RAS, CAS, WE,
    input  wire [12:0] A,
    input  wire [2:0]  BA,
    
    // PT: Flags de Status para o Scheduler | EN: Status Flags for the Scheduler
    output wire        init_done,            // PT: Inicialização OK | EN: Init done
    output wire        enable_read_fifo,     // PT: Habilita leitura | EN: Enable read FIFO
    output wire        enable_write_drivers, // PT: Habilita escrita | EN: Enable write drivers
    output wire        enable_row_decoder,   // PT: Habilita decod. de linha | EN: Enable row decoder
    output wire        refresh_mem_flag,     // PT: Indica refresh em curso | EN: Indicates refresh in progress
    output wire [7:0]  BC4_flag, AP_flag, bank_active_flag, bank_idle_flag,
    output wire [12:0] MR0, MR1, MR2, MR3,   // PT: Registradores de Modo | EN: Mode Registers

    // -------------------------------------------------------------------------
    // PT: Interface de Dados com a CPU | EN: Data Interface with CPU / AXI Master
    // -------------------------------------------------------------------------
    input  wire        cpu_wr_en,    // PT: Escrita da CPU | EN: CPU write enable
    input  wire [15:0] cpu_wdata,    // PT: Dados de escrita | EN: CPU write data
    output wire        tx_full,      // PT: FIFO TX cheia | EN: TX FIFO full
    output wire        tx_empty,     // PT: FIFO TX vazia | EN: TX FIFO empty
    output wire [15:0] cpu_rdata,    // PT: Dados de leitura | EN: Read data to CPU
    output wire        rx_valid,     // PT: Leitura válida | EN: Read data valid

    // -------------------------------------------------------------------------
    // PT: Saídas Físicas (Pad Ring) | EN: Physical Outputs (Pad Ring)
    // -------------------------------------------------------------------------
    output wire        CKE, RESET_n,
    output wire        CS_out, RAS_out, CAS_out, WE_out,
    output wire [12:0] A_out,
    output wire [2:0]  BA_out,
    output wire        odt_out,      // PT: Terminação On-Die | EN: On-Die Termination
    inout  wire [7:0]  DQ,           // PT: Barramento de Dados | EN: Data Bus
    inout  wire        DQS,          // PT: Strobe de Dados | EN: Data Strobe
    inout  wire        DQS_n         // PT: Strobe Diferencial | EN: Differential Data Strobe
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
        .CKE(CKE), .RESET_n(RESET_n),
        .CS_out(CS_out), .RAS_out(RAS_out), .CAS_out(CAS_out), .WE_out(WE_out),
        .A_out(A_out), .BA_out(BA_out),
        
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
        .DQS_n(DQS_n)
    );

endmodule
