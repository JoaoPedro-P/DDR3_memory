// [PT] Módulo: tb_dram_bank_array / [EN] Module: tb_dram_bank_array
// [PT] Este testbench valida a matriz de bancos DRAM simulando escritas e leituras consecutivas. / [EN] This testbench validates the DRAM bank array by simulating consecutive reads and writes.
// [PT] Inputs/Outputs: Injeta comandos (ACT, PRE, RD, WR) e monitora a saída e os erros de temporização. / [EN] Inputs/Outputs: Injects commands (ACT, PRE, RD, WR) and monitors output and timing errors.
// [PT] Papel no sistema: Garantir que as operações no nível do banco respeitem latências e persistam os dados corretamente. / [EN] Role in the system: Ensure bank-level operations respect latencies and persist data correctly.
`timescale 1ns / 1ps

module tb_dram_bank_array();

    // [PT] Sinais do DUT / [EN] DUT Signals
    reg         clk, rst_n;
    reg         act_cmd, pre_cmd, rd_cmd, wr_cmd;
    reg  [2:0]  bank_addr;
    reg  [9:0]  col_addr;
    reg  [13:0] row_addr;
    reg  [63:0] data_in;
    reg  [7:0]  dm_in;
    
    wire [63:0] data_out;
    wire [7:0]  bank_active;
    wire        timing_error;

    // [PT] Instanciação do módulo em teste (DUT) / [EN] Device Under Test (DUT) Instantiation
    dram_bank_array #(
        .freq(100),
        // [PT] 1024 posições para os 250 testes não colidirem / [EN] 1024 positions so the 250 tests don't collide
        .MEM_DEPTH_LOG2(10) 
    ) dut (
        .clk(clk), .rst_n(rst_n), 
        .act_cmd(act_cmd), .pre_cmd(pre_cmd), .rd_cmd(rd_cmd), .wr_cmd(wr_cmd),
        .bank_addr(bank_addr), .col_addr(col_addr), .row_addr(row_addr),
        .data_in(data_in), .dm_in(dm_in),
        .data_out(data_out), .bank_active(bank_active), .timing_error(timing_error)
    );

    // [PT] Geração de Clock / [EN] Clock Generation
    initial begin clk = 0; forever #5 clk = ~clk; end

    // [PT] Variáveis de Validação / [EN] Validation Variables
    integer i, errors;
    reg [63:0] golden_data [0:249];
    
    // [PT] Tarefa para limpar os barramentos / [EN] Task to clear the buses
    task clear_cmds;
        begin
            act_cmd = 0; pre_cmd = 0; rd_cmd = 0; wr_cmd = 0;
        end
    endtask

    // [PT] Monitoramento Assíncrono de Violação de JEDEC / [EN] Asynchronous JEDEC Violation Monitoring
    always @(posedge timing_error) begin
        if (rst_n) begin
            $display("[ERRO HARDWARE] timing_error disparou no tempo %0t!", $time);
            errors = errors + 1;
        end
    end

    // [PT] Bloco de Inicialização e Estímulos / [EN] Initialization and Stimulus Block
    initial begin
        rst_n = 0; clear_cmds;
        bank_addr = 0; col_addr = 0; row_addr = 0;
        data_in = 0; dm_in = 0; errors = 0;
        
        #50 rst_n = 1; #50;

        $display("==========================================================");
        $display("[TB ARRAY] Testando 250 escritas e leituras consecutivas...");
        $display("==========================================================");

        // [PT] FASE 1: ESCRITA / [EN] PHASE 1: WRITE
        for (i = 0; i < 250; i = i + 1) begin
            golden_data[i] = {$random, $random}; 
            
            // [PT] 1. Abre a linha (Avança a linha a cada 128 iterações) / [EN] 1. Opens the row (Advances the row every 128 iterations)
            @(posedge clk);
            act_cmd = 1; bank_addr = 3'd1; row_addr = (i / 128); 
            @(posedge clk); clear_cmds;
            
            // [PT] Loop de espera dinâmico / [EN] Dynamic wait loop
            while (bank_active[3'd1] == 1'b0) @(posedge clk);
            
            // [PT] 2. Grava o dado (A coluna zera automaticamente ao atingir 128) / [EN] 2. Writes the data (Column automatically resets at 128)
            wr_cmd = 1; col_addr = (i % 128) * 8; data_in = golden_data[i]; dm_in = 8'h00;
            @(posedge clk); clear_cmds;
            
            repeat(3) @(posedge clk);
            
            // [PT] 3. Fecha o banco (Precharge) / [EN] 3. Closes the bank (Precharge)
            pre_cmd = 1; bank_addr = 3'd1;
            @(posedge clk); clear_cmds;
            
            repeat(10) @(posedge clk);
        end

        // [PT] FASE 2: LEITURA / [EN] PHASE 2: READ
        for (i = 0; i < 250; i = i + 1) begin
            // [PT] 1. Abre a linha exata em que o dado foi gravado / [EN] 1. Opens the exact row where the data was written
            @(posedge clk);
            act_cmd = 1; bank_addr = 3'd1; row_addr = (i / 128);
            @(posedge clk); clear_cmds;
            
            // [PT] Aguarda ativação do banco / [EN] Wait for bank activation
            while (bank_active[3'd1] == 1'b0) @(posedge clk);
            
            // [PT] 2. Comanda a leitura / [EN] 2. Commands the read
            rd_cmd = 1; col_addr = (i % 128) * 8;
            @(posedge clk); clear_cmds;
            
            // [PT] O dado fica estável na saída no ciclo seguinte / [EN] Data is stable at the output in the next cycle
            @(posedge clk); 
            if (data_out !== golden_data[i]) begin
                $display("[ERRO] Leitura %0d falhou! Esp: %h | Lida: %h", i, golden_data[i], data_out);
                errors = errors + 1;
            end
            
            // [PT] 3. Fecha o banco / [EN] 3. Closes the bank
            pre_cmd = 1; bank_addr = 3'd1;
            @(posedge clk); clear_cmds;
            
            repeat(10) @(posedge clk);
        end

        if (errors == 0) $display(">> [ARRAY] SUCESSO! 250 operacoes efetuadas sem erros. FSM e Array alinhados.");
        else $display(">> [ARRAY] FALHOU com %0d erros.", errors);
        $stop;
    end
endmodule