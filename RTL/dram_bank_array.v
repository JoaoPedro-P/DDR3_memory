// [PT] Modelo funcional do array de armazenamento da DRAM. Este módulo emula o comportamento interno de um chip DDR3 real, simplificando os processos analógicos para uma representação digital comportamental eficiente para simulação. / [EN] Functional model of the DRAM storage array. This module emulates the internal behavior of a real DDR3 chip, simplifying analog processes into a digital behavioral representation efficient for simulation.
// [PT] Simplificações Analógicas Emuladas: / [EN] Emulated Analog Simplifications:
// [PT] 1. Bancos de Memória: Emulados como matrizes (arrays) de 64 bits. Cada banco possui seu próprio espaço de endereçamento independente. / [EN] 1. Memory Banks: Emulated as 64-bit arrays. Each bank has its own independent address space.
// [PT] 2. Amplificadores de Detecção (Sense Amplifiers): Representados pela lógica de ativação de linha (active_row). Quando uma linha é ativada (ACT), o conteúdo dela é "carregado" nos amplificadores (emulados aqui pelo registro da linha ativa). / [EN] 2. Sense Amplifiers: Represented by the row activation logic (active_row). When a row is activated (ACT), its content is "loaded" into the sense amplifiers (emulated here by registering the active row).
// [PT] 3. Data Mask (DM): Implementado como uma máscara de bits que impede a escrita em bytes específicos dentro de um bloco de 64 bits, simulando o pino DM analógico. / [EN] 3. Data Mask (DM): Implemented as a bit mask that prevents writing to specific bytes within a 64-bit block, simulating the analog DM pin.
// [PT] 4. Pipeline de Escrita: Simula a latência interna do core da memória entre o comando de escrita e a gravação física nas células. / [EN] 4. Write Pipeline: Simulates the internal memory core latency between the write command and the physical recording in the cells.
// [PT] Parâmetros: freq - Frequência de operação (MHz). MEM_DEPTH_LOG2 - Log2 da profundidade da memória (p/ simulação). / [EN] Parameters: freq - Operating frequency (MHz). MEM_DEPTH_LOG2 - Log2 of memory depth.
module dram_bank_array #(
    parameter freq = 100,
    parameter MEM_DEPTH_LOG2 = 8 
)(
    input  wire        clk,          // [PT] Clock do array / [EN] Array clock
    input  wire        rst_n,        // [PT] Reset ativo baixo / [EN] Active-low reset
    input  wire        act_cmd,      // [PT] Comando de ativação / [EN] Activation command
    input  wire        pre_cmd,      // [PT] Comando de pré-carga / [EN] Precharge command
    input  wire        rd_cmd,       // [PT] Comando de leitura / [EN] Read command
    input  wire        wr_cmd,       // [PT] Comando de escrita / [EN] Write command
    input  wire [2:0]  bank_addr,    // [PT] Endereço do banco / [EN] Bank address
    input  wire [9:0]  col_addr,     // [PT] Endereço da coluna / [EN] Column address
    input  wire [13:0] row_addr,     // [PT] Endereço da linha / [EN] Row address
    
    input  wire [63:0] data_in,      // [PT] Dados de entrada / [EN] Input data
    input  wire [7:0]  dm_in,        // [PT] Máscara de dados de entrada / [EN] Input data mask
    output reg  [63:0] data_out,     // [PT] Dados de saída / [EN] Output data
    
    output wire [7:0]  bank_active,  // [PT] Sinalização de banco ativo / [EN] Active bank signaling
    output wire        timing_error  // [PT] Erro de temporização / [EN] Timing error
);

    localparam DEPTH = 1 << MEM_DEPTH_LOG2; // [PT] Profundidade local calculada / [EN] Calculated local depth
    
    // [PT] Definição das matrizes de memória por banco / [EN] Definition of memory matrices per bank
    reg [63:0] bank0 [0:DEPTH-1];
    reg [63:0] bank1 [0:DEPTH-1];
    reg [63:0] bank2 [0:DEPTH-1];
    reg [63:0] bank3 [0:DEPTH-1];
    reg [63:0] bank4 [0:DEPTH-1];
    reg [63:0] bank5 [0:DEPTH-1];
    reg [63:0] bank6 [0:DEPTH-1];
    reg [63:0] bank7 [0:DEPTH-1];

    // [PT] Inicialização explícita para o Vivado XSim / [EN] Explicit initialization for Vivado XSim
    integer init_i;
    initial begin
        // [PT] Loop de inicialização / [EN] Initialization loop
        for (init_i = 0; init_i < DEPTH; init_i = init_i + 1) begin
            bank0[init_i] = 64'd0;
            bank1[init_i] = 64'd0;
            bank2[init_i] = 64'd0;
            bank3[init_i] = 64'd7;
            bank4[init_i] = 64'd0;
            bank5[init_i] = 64'd0;
            bank6[init_i] = 64'd0;
            bank7[init_i] = 64'd0;
        end
    end

    reg [MEM_DEPTH_LOG2-1:0] eff_addr; // [PT] Endereço efetivo / [EN] Effective address
    reg [13:0] active_row [0:7];       // [PT] Registros das linhas ativas por banco / [EN] Registers for active rows per bank
    
    // [PT] CORREÇÃO: Pipeline de Escrita Expandido para 9 estágios (0 a 8) / [EN] FIX: Write Pipeline Expanded to 9 stages (0 to 8)
    reg [8:0] write_pipeline;
    reg [2:0] write_bank_pipe [0:8];
    reg [9:0] write_col_pipe  [0:8];

    integer i, b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // [PT] Reset das linhas ativas / [EN] Active rows reset
            for(i = 0; i < 8; i = i + 1) begin
                active_row[i] <= 14'd0;
            end
            // [PT] Reset dos pipelines de escrita / [EN] Write pipelines reset
            for(i = 0; i < 9; i = i + 1) begin
                write_bank_pipe[i] <= 3'd0;
                write_col_pipe[i]  <= 10'd0;
            end
            data_out <= 64'd0;
            write_pipeline <= 9'd0;
        end else begin
            // [PT] 1. Lógica de Ativação (ACT) / [EN] 1. Activation Logic (ACT)
            if (act_cmd) begin
                active_row[bank_addr] <= row_addr;
            end
            
            // [PT] 2. Agendamento de Escrita (Pipeline com 1 ciclo extra para estabilidade) / [EN] 2. Write Scheduling (Pipeline with 1 extra cycle for stability)
            write_pipeline <= {write_pipeline[7:0], 1'b0};
            for (i = 8; i > 0; i = i - 1) begin
                write_bank_pipe[i] <= write_bank_pipe[i-1];
                write_col_pipe[i]  <= write_col_pipe[i-1];
            end

            // [PT] Se comando de escrita, banco ativo e sem erro / [EN] If write cmd, bank active and no error
            if (wr_cmd && bank_active[bank_addr] && !timing_error) begin
                write_pipeline[0]  <= 1'b1;
                write_bank_pipe[0] <= bank_addr;
                write_col_pipe[0]  <= col_addr;
            end

            // [PT] 3. Execução da Escrita Diferida (Agora lido com segurança no estágio 8) / [EN] 3. Deferred Write Execution (Now safely read at stage 8)
            if (write_pipeline[8]) begin
                eff_addr = {active_row[write_bank_pipe[8]], write_col_pipe[8][9:3]} & (DEPTH - 8'd1);
                for (b = 0; b < 8; b = b + 1) begin
                    if (!dm_in[b]) begin
                        case (write_bank_pipe[8])
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

            // [PT] 4. Execução de Leitura (Síncrona) / [EN] 4. Read Execution (Synchronous)
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

    // [PT] Instanciação do controle do banco DRAM / [EN] Instantiation of DRAM bank control
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