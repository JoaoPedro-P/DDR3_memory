/*
 * module: dram_bank_array
 * -----------------
 * PT: Modelo funcional do array de armazenamento da DRAM. Este módulo emula o comportamento 
 *     interno de um chip DDR3 real, simplificando os processos analógicos para uma 
 *     representação digital comportamental eficiente para simulação.
 * 
 *     Simplificações Analógicas Emuladas:
 *     1. Bancos de Memória: Emulados como matrizes (arrays) de 64 bits. Cada banco possui 
 *        seu próprio espaço de endereçamento independente.
 *     2. Amplificadores de Detecção (Sense Amplifiers): Representados pela lógica de 
 *        ativação de linha (active_row). Quando uma linha é ativada (ACT), o conteúdo 
 *        dela é "carregado" nos amplificadores (emulados aqui pelo registro da linha ativa).
 *     3. Data Mask (DM): Implementado como uma máscara de bits que impede a escrita em 
 *        bytes específicos dentro de um bloco de 64 bits, simulando o pino DM analógico.
 *     4. Pipeline de Escrita: Simula a latência interna do core da memória entre o 
 *        comando de escrita e a gravação física nas células.
 *
 * EN: Functional model of the DRAM storage array. This module emulates the internal 
 *     behavior of a real DDR3 chip, simplifying analog processes into a digital 
 *     behavioral representation efficient for simulation.
 * 
 *     Emulated Analog Simplifications:
 *     1. Memory Banks: Emulated as 64-bit arrays. Each bank has its own independent 
 *        address space.
 *     2. Sense Amplifiers: Represented by the row activation logic (active_row). 
 *        When a row is activated (ACT), its content is "loaded" into the sense 
 *        amplifiers (emulated here by registering the active row).
 *     3. Data Mask (DM): Implemented as a bit mask that prevents writing to specific 
 *        bytes within a 64-bit block, simulating the analog DM pin.
 *     4. Write Pipeline: Simulates the internal memory core latency between the 
 *        write command and the physical recording in the cells.
 *
 * Parameters | Parâmetros:
 *     - freq: PT: Frequência de operação (MHz). | EN: Operating frequency (MHz).
 *     - MEM_DEPTH_LOG2: PT: Log2 da profundidade da memória (p/ simulação). | EN: Log2 of memory depth.
 */
module dram_bank_array #(
    parameter freq = 100,
    parameter MEM_DEPTH_LOG2 = 8 
)(
    // =========================================================================
    // Sinais de Controle | Control Signals
    // =========================================================================
    input  wire        clk,          // PT: Clock principal. | EN: System clock.
    input  wire        rst_n,        // PT: Reset (Ativo Baixo). | EN: Reset (Active Low).
    input  wire        act_cmd,      // PT: Ativa uma linha no banco selecionado. | EN: Activates a row.
    input  wire        pre_cmd,      // PT: Fecha (precharge) a linha aberta. | EN: Closes (precharges) row.
    input  wire        rd_cmd,       // PT: Comando de leitura. | EN: Read command.
    input  wire        wr_cmd,       // PT: Comando de escrita. | EN: Write command.
    input  wire [2:0]  bank_addr,    // PT: Endereço do banco (BA0-BA2). | EN: Bank address (BA0-BA2).
    input  wire [9:0]  col_addr,     // PT: Endereço de coluna (A0-A9). | EN: Column address (A0-A9).
    input  wire [13:0] row_addr,     // PT: Endereço de linha (A0-A13). | EN: Row address (A0-A13).
    
    // ================= ========================================================
    // Barramento de Dados | Data Bus
    // =========================================================================
    input  wire [63:0] data_in,      // PT: Dados de escrita (SDR, 64-bits). | EN: Write data (SDR).
    input  wire [7:0]  dm_in,        // PT: Máscara de dados (Data Mask). 0=Escreve, 1=Mascarado.
                                     // EN: Data mask (DM). 0=Write, 1=Masked.
    output reg  [63:0] data_out,     // PT: Dados de leitura (SDR, 64-bits). | EN: Read data (SDR).
    
    // =========================================================================
    // Status e Diagnóstico | Status and Diagnostics
    // =========================================================================
    output wire [7:0]  bank_active,  // PT: Flag indicando bancos com página aberta. | EN: Bank active flags.
    output wire        timing_error  // PT: Indica violação de tempo JEDEC. | EN: JEDEC timing violation.
);


    localparam DEPTH = 1 << MEM_DEPTH_LOG2;
    
    // PT: Arrays de memória (Modelagem comportamental)
    // EN: Memory arrays (Behavioral modeling)
    reg [63:0] bank0 [0:DEPTH-1];
    reg [63:0] bank1 [0:DEPTH-1];
    reg [63:0] bank2 [0:DEPTH-1];
    reg [63:0] bank3 [0:DEPTH-1];
    reg [63:0] bank4 [0:DEPTH-1];
    reg [63:0] bank5 [0:DEPTH-1];
    reg [63:0] bank6 [0:DEPTH-1];
    reg [63:0] bank7 [0:DEPTH-1];

    reg [13:0] active_row [0:7];
	reg [MEM_DEPTH_LOG2-1:0] eff_addr;
	 
    // PT: Pipeline de Escrita (DDR Latency) | EN: Write Pipeline (DDR Latency)
	 reg [7:0] write_pipeline;
    reg [2:0] write_bank_pipe [0:7];
    reg [9:0] write_col_pipe  [0:7];

    integer i, b;

 always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(i = 0; i < 8; i = i + 1) begin
                active_row[i] <= 14'd0;
                write_bank_pipe[i] <= 3'd0;
                write_col_pipe[i]  <= 10'd0;
            end
            data_out <= 64'd0;
            write_pipeline <= 8'd0;
        end else begin
            // 1. PT: Lógica de Ativação (ACT) | EN: Activation Logic (ACT)
            if (act_cmd) begin
                active_row[bank_addr] <= row_addr;
            end
            
            // 2. PT: Agendamento de Escrita (Pipeline) | EN: Pipelined Write Scheduling
            write_pipeline <= {write_pipeline[6:0], 1'b0};
            for (i = 7; i > 0; i = i - 1) begin
                write_bank_pipe[i] <= write_bank_pipe[i-1];
                write_col_pipe[i]  <= write_col_pipe[i-1];
            end

            if (wr_cmd && bank_active[bank_addr] && !timing_error) begin
                write_pipeline[0]  <= 1'b1;
                write_bank_pipe[0] <= bank_addr;
                write_col_pipe[0]  <= col_addr;
            end

            // 3. PT: Execução da Escrita Diferida | EN: Deferred Write Execution
            if (write_pipeline[7]) begin
                eff_addr = {active_row[write_bank_pipe[7]], write_col_pipe[7][9:3]} & (DEPTH - 8'd1);
                for (b = 0; b < 8; b = b + 1) begin
                    if (!dm_in[b]) begin
                        case (write_bank_pipe[7])
                            3'd0: bank0[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                            3'd1: bank1[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                            3'd2: bank2[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                            3'd3: bank3[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                            3'd4: bank4[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                            3'd5: bank5[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                            3'd6: bank6[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                            3'd7: bank7[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                        endcase
                    end
                end
            end

            // 4. PT: Execução de Leitura (Síncrona) | EN: Synchronous Read Execution
            if (rd_cmd && bank_active[bank_addr] && !timing_error) begin
                eff_addr = {active_row[bank_addr], col_addr[9:3]} & (DEPTH - 8'd1);
                case (bank_addr)
                    3'd0: data_out <= bank0[eff_addr];
                    3'd1: data_out <= bank1[eff_addr];
                    3'd2: data_out <= bank2[eff_addr];
                    3'd3: data_out <= bank3[eff_addr];
                    3'd4: data_out <= bank4[eff_addr];
                    3'd5: data_out <= bank5[eff_addr];
                    3'd6: data_out <= bank6[eff_addr];
                    3'd7: data_out <= bank7[eff_addr];
                endcase
            end
        end
    end

    // PT: Instanciação do controlador de bancos | EN: Bank control instantiation
    dram_bank_control #(
        .freq(freq),
        .T_RCD_CYCLES((freq / 67) + 1),
        .T_RP_CYCLES((freq / 67) + 1)
    ) bank_inst (
        .clk(clk), 
        .rst_n(rst_n), 
        .act_cmd(act_cmd), 
        .pre_cmd(pre_cmd), 
        .rd_cmd(rd_cmd), 
        .wr_cmd(wr_cmd),
        .bank_addr(bank_addr),
        .bank_active(bank_active),
        .timing_error(timing_error)
    );

endmodule
