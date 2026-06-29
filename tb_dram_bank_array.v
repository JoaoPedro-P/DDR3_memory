`timescale 1ns / 1ps

module tb_dram_bank_array();

    // Sinais do DUT
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

    // Instanciação
    dram_bank_array #(
        .freq(100),
        .MEM_DEPTH_LOG2(10) // 1024 posições para os 250 testes não colidirem
    ) dut (
        .clk(clk), .rst_n(rst_n), 
        .act_cmd(act_cmd), .pre_cmd(pre_cmd), .rd_cmd(rd_cmd), .wr_cmd(wr_cmd),
        .bank_addr(bank_addr), .col_addr(col_addr), .row_addr(row_addr),
        .data_in(data_in), .dm_in(dm_in),
        .data_out(data_out), .bank_active(bank_active), .timing_error(timing_error)
    );

    // Clock
    initial begin clk = 0; forever #5 clk = ~clk; end

    // Variáveis de Validação
    integer i, errors;
    reg [63:0] golden_data [0:249];
    
    // Tarefa para limpar os barramentos
    task clear_cmds;
        begin
            act_cmd = 0; pre_cmd = 0; rd_cmd = 0; wr_cmd = 0;
        end
    endtask

    // Monitoramento Assíncrono de Violação de JEDEC
    always @(posedge timing_error) begin
        if (rst_n) begin
            $display("[ERRO HARDWARE] timing_error disparou no tempo %0t!", $time);
            errors = errors + 1;
        end
    end

    initial begin
        rst_n = 0; clear_cmds;
        bank_addr = 0; col_addr = 0; row_addr = 0;
        data_in = 0; dm_in = 0; errors = 0;
        
        #50 rst_n = 1; #50;

        $display("==========================================================");
        $display("[TB ARRAY] Testando 250 escritas e leituras consecutivas...");
        $display("==========================================================");

        // FASE 1: ESCRITA
        for (i = 0; i < 250; i = i + 1) begin
            golden_data[i] = {$random, $random}; 
            
            // 1. Abre a linha (Avança a linha a cada 128 iterações)
            @(posedge clk);
            act_cmd = 1; bank_addr = 3'd1; row_addr = (i / 128); 
            @(posedge clk); clear_cmds;
            
            // Loop de espera dinâmico
            while (bank_active[3'd1] == 1'b0) @(posedge clk);
            
            // 2. Grava o dado (A coluna zera automaticamente ao atingir 128)
            wr_cmd = 1; col_addr = (i % 128) * 8; data_in = golden_data[i]; dm_in = 8'h00;
            @(posedge clk); clear_cmds;
            
            repeat(3) @(posedge clk);
            
            // 3. Fecha o banco (Precharge)
            pre_cmd = 1; bank_addr = 3'd1;
            @(posedge clk); clear_cmds;
            
            repeat(10) @(posedge clk);
        end

        // FASE 2: LEITURA
        for (i = 0; i < 250; i = i + 1) begin
            // 1. Abre a linha exata em que o dado foi gravado
            @(posedge clk);
            act_cmd = 1; bank_addr = 3'd1; row_addr = (i / 128);
            @(posedge clk); clear_cmds;
            
            while (bank_active[3'd1] == 1'b0) @(posedge clk);
            
            // 2. Comanda a leitura (CORRIGIDO: Agora é rd_cmd)
            rd_cmd = 1; col_addr = (i % 128) * 8;
            @(posedge clk); clear_cmds;
            
            // O dado fica estável na saída no ciclo seguinte
            @(posedge clk); 
            if (data_out !== golden_data[i]) begin
                $display("[ERRO] Leitura %0d falhou! Esp: %h | Lida: %h", i, golden_data[i], data_out);
                errors = errors + 1;
            end
            
            // 3. Fecha o banco
            pre_cmd = 1; bank_addr = 3'd1;
            @(posedge clk); clear_cmds;
            
            repeat(10) @(posedge clk);
        end

        if (errors == 0) $display(">> [ARRAY] SUCESSO! 250 operacoes efetuadas sem erros. FSM e Array alinhados.");
        else $display(">> [ARRAY] FALHOU com %0d erros.", errors);
        $stop;
    end
endmodule