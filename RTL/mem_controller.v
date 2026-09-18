// [PT] Orquestrador do Controlador de Memória DDR3. / [EN] DDR3 Memory Controller Orchestrator.
// [PT] Este módulo coordena a Unidade de Controle (control_unit) e a Camada Física (datapath/PHY). / [EN] This module coordinates the Control Unit (control_unit) and the Physical Layer (datapath/PHY).
// [PT] Ele serve como o ponto central onde as decisões lógicas de agendamento são convertidas em transações físicas e handshakes de dados com a CPU/AXI. / [EN] It serves as the central point where logical scheduling decisions are converted into physical transactions and data handshakes with the CPU/AXI.
// [PT] Responsabilidades: / [EN] Responsibilities:
// [PT] 1. Interface com o Scheduler: Recebe comandos JEDEC pré-processados. / [EN] 1. Scheduler Interface: Receives pre-processed JEDEC commands.
// [PT] 2. Interface de Dados: Gerencia a entrada/saída de dados entre o barramento da CPU e a PHY. / [EN] 2. Data Interface: Manages data I/O between the CPU bus and the PHY.
// [PT] 3. Controle da PHY: Ativa drivers de escrita, terminações ODT e gera sinais diferenciais. / [EN] 3. PHY Control: Activates write drivers, ODT terminations, and generates differential signals.
// [PT] 4. Sincronização de Domínios: Garante que os status de inicialização e erro cheguem ao sistema. / [EN] 4. Domain Synchronization: Ensures initialization and error status reach the system.
module mem_controller #(parameter freq = 100) (
    input  wire        clk,                 // [PT] Clock principal / [EN] Main clock
    input  wire        clk_90,              // [PT] Clock deslocado 90 graus / [EN] Clock shifted 90 degrees
    input  wire        rst_n,               // [PT] Reset ativo baixo / [EN] Active-low reset
    input  wire        cpu_clk,             // [PT] Clock da CPU / [EN] CPU clock
    input  wire        cpu_rst_n,           // [PT] Reset ativo baixo da CPU / [EN] Active-low CPU reset
	input  wire        frontend_idle_safe,  // [PT] Sinalização de ociosidade segura / [EN] Safe idle signaling
    input  wire        CS, RAS, CAS, WE,    // [PT] Sinais de controle JEDEC / [EN] JEDEC control signals
    input  wire [12:0] A,                   // [PT] Endereço / [EN] Address
    input  wire [2:0]  BA,                  // [PT] Endereço do banco / [EN] Bank address
    
    output wire        init_done, enable_read_fifo, enable_write_drivers, enable_row_decoder, refresh_mem_flag,
    output wire [7:0]  BC4_flag, AP_flag, bank_active_flag, bank_idle_flag,
    output wire [12:0] MR0, MR1, MR2, MR3,

    // [PT] Sinais de dados atualizados para 32 bits / [EN] Data signals updated to 32 bits
    input  wire        cpu_wr_en,           // [PT] Habilitação de escrita / [EN] Write enable
    input  wire [31:0] cpu_wdata,           // [PT] Dados de escrita / [EN] Write data
    output wire        tx_full,             // [PT] FIFO de transmissão cheia / [EN] TX FIFO full
    output wire        tx_empty,            // [PT] FIFO de transmissão vazia / [EN] TX FIFO empty
    output wire [31:0] cpu_rdata,           // [PT] Dados de leitura / [EN] Read data
    output wire        rx_valid,            // [PT] Dados de recepção válidos / [EN] RX valid
    input  wire [3:0]  cpu_wstrb,           // [PT] Strobe de escrita / [EN] Write strobe
	 
    output wire        CS_out, RAS_out, CAS_out, WE_out, RESET_n, // [PT] Saídas de controle para a PHY / [EN] Control outputs to PHY
    output wire [12:0] A_out,               // [PT] Saída de endereço / [EN] Address output
    output wire [2:0]  BA_out,              // [PT] Saída de banco / [EN] Bank output
    output wire        odt_out,             // [PT] On-Die Termination / [EN] On-Die Termination
	input  wire [7:0]  dq_in,               // [PT] Dados de entrada da PHY / [EN] Data input from PHY
    input  wire        dqs_in,              // [PT] Strobe de dados de entrada / [EN] Input data strobe
    input  wire        dqs_n_in,            // [PT] Strobe diferencial de entrada / [EN] Input differential strobe
    output wire [7:0]  dq_out,              // [PT] Dados de saída para a PHY / [EN] Data output to PHY
    output wire        dqs_out_pad,         // [PT] Strobe de dados de saída / [EN] Output data strobe
    output wire        dqs_n_out_pad,       // [PT] Strobe diferencial de saída / [EN] Output differential strobe
    output wire        dq_oe,               // [PT] Habilitação de saída de dados / [EN] Data output enable
    output wire        dqs_oe,              // [PT] Habilitação de saída de strobe / [EN] Strobe output enable
    output wire        DM                   // [PT] Máscara de dados / [EN] Data mask
);

    // [PT] Instanciação da unidade de controle / [EN] Instantiation of the control unit
    control_unit #(.freq(freq)) ctrl_inst (
        .clk(clk), .rst(rst_n), 
        .CS(CS), .RAS(RAS), .CAS(CAS), .WE(WE), .A(A), .BA(BA),
        .frontend_idle_safe(frontend_idle_safe),
        .CS_out(CS_out), .RAS_out(RAS_out), .CAS_out(CAS_out), .WE_out(WE_out),
        .A_out(A_out), .BA_out(BA_out), .RESET_n(RESET_n),
        .init_done(init_done), .enable_read_fifo(enable_read_fifo), 
        .enable_write_drivers(enable_write_drivers), .enable_row_decoder(enable_row_decoder), 
        .refresh_mem_flag(refresh_mem_flag),
        .BC4_flag(BC4_flag), .AP_flag(AP_flag), 
        .bank_active_flag(bank_active_flag), .bank_idle_flag(bank_idle_flag), 
        .MR0(MR0), .MR1(MR1), .MR2(MR2), .MR3(MR3)
    );

    // [PT] Instanciação do caminho de dados (PHY) / [EN] Instantiation of the datapath (PHY)
    datapath phy_inst (
        .clk(clk), .clk_90(clk_90), .rst_n(rst_n),
        .write_req(enable_write_drivers), 
        .cpu_wstrb(cpu_wstrb),
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .cpu_wr_en(cpu_wr_en), .cpu_wdata(cpu_wdata),
        .tx_full(tx_full), .tx_empty(tx_empty),
        .cpu_rdata(cpu_rdata), .rx_valid(rx_valid),
        .odt_out(odt_out), .dq_in(dq_in), .dqs_in(dqs_in), .dqs_n_in(dqs_n_in),
        .dq_out(dq_out), .dqs_out_pad(dqs_out_pad), .dqs_n_out_pad(dqs_n_out_pad),
        .phy_dq_oe(dq_oe), .phy_dqs_oe(dqs_oe), .DM(DM)
    );

endmodule