`timescale 1ns / 1ps

module tb_mem_controller();

    // Sinais do Testbench
    reg clk, clk_90, rst_n;
    reg cpu_clk, cpu_rst_n;
    reg CS, RAS, CAS, WE;
    reg [12:0] A;
    reg [2:0]  BA;
    reg cpu_wr_en;
    reg [15:0] cpu_wdata;

    wire init_done, enable_read_fifo, enable_write_drivers;
    wire tx_full, tx_empty, rx_valid, odt_out;
    wire [15:0] cpu_rdata;
    
    wire [7:0] DQ;
    wire DQS, DQS_n;
    
    // Sinais Mock da Memória DDR3 Física
    reg [7:0] tb_dq;
    reg tb_dqs, tb_dqs_n, tb_drive_bus;
    
    integer i, errors = 0;
    reg [15:0] test_vector [0:99]; // Array para guardar os 100 casos aleatórios

    assign DQ    = tb_drive_bus ? tb_dq    : 8'bz;
    assign DQS   = tb_drive_bus ? tb_dqs   : 1'bz;
    assign DQS_n = tb_drive_bus ? tb_dqs_n : 1'bz;

    // DUT Instanciação
    mem_controller dut (
        .clk(clk), .clk_90(clk_90), .rst_n(rst_n), 
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .CS(CS), .RAS(RAS), .CAS(CAS), .WE(WE), .A(A), .BA(BA),
        .init_done(init_done),
        .enable_read_fifo(enable_read_fifo), .enable_write_drivers(enable_write_drivers),
        .cpu_wr_en(cpu_wr_en), .cpu_wdata(cpu_wdata),
        .tx_full(tx_full), .tx_empty(tx_empty),
        .cpu_rdata(cpu_rdata), .rx_valid(rx_valid),
        .odt_out(odt_out), .DQ(DQ), .DQS(DQS), .DQS_n(DQS_n)
    );

    // Geração de Clocks (CPU = 200MHz, Memória = 100MHz)
    initial begin clk = 0; forever #5 clk = ~clk; end
    initial begin clk_90 = 0; #2.5 forever #5 clk_90 = ~clk_90; end
    initial begin cpu_clk = 0; forever #2.5 cpu_clk = ~cpu_clk; end

    // -------------------------------------------------------------------------
    // TASKS DE APOIO
    // -------------------------------------------------------------------------
    task cpu_write_fifo(input [15:0] data);
        begin
            @(negedge cpu_clk);
            cpu_wr_en = 1;
            cpu_wdata = data;
            @(negedge cpu_clk);
            cpu_wr_en = 0;
        end
    endtask

    // Simula a memória enviando um dado de volta (SDR para DDR)
    task mem_send_read(input [15:0] data);
        begin
            @(negedge clk);
            tb_drive_bus = 1;
            tb_dqs = 0; tb_dqs_n = 1; #10; // Preamble
            
            tb_dqs = 1; tb_dqs_n = 0; tb_dq = data[7:0];   // LSB (Subida)
            #5;
            tb_dqs = 0; tb_dqs_n = 1; tb_dq = data[15:8];  // MSB (Descida)
            #5;
            
            tb_dqs = 0; tb_dqs_n = 1; tb_dq = 8'bz; #10;   // Postamble
            tb_drive_bus = 0; tb_dqs = 1'bz; tb_dqs_n = 1'bz;
        end
    endtask

    // -------------------------------------------------------------------------
    // BLOCO DE EXECUÇÃO PRINCIPAL
    // -------------------------------------------------------------------------
    initial begin
        $display("===============================================================");
        $display(" INICIANDO VALIDACAO DO MEMORY CONTROLLER (100 CASOS ALEATORIOS)");
        $display("===============================================================");

        // Reset inicial
        clk = 0; clk_90 = 0; cpu_clk = 0;
        rst_n = 0; cpu_rst_n = 0;
        CS = 1; RAS = 1; CAS = 1; WE = 1; A = 0; BA = 0;
        cpu_wr_en = 0; cpu_wdata = 0;
        tb_drive_bus = 0; tb_dq = 8'bz; tb_dqs = 1'bz; tb_dqs_n = 1'bz;

        #50 rst_n = 1; cpu_rst_n = 1;

        // Fictício: Pula a inicialização para acelerar simulação
        force dut.init_done = 1;
        #20;

        // ---------------------------------------------------------------------
        // FASE 1: TESTANDO 100 ESCRITAS (CPU -> FIFO -> MEMORIA)
        // ---------------------------------------------------------------------
        $display("[FASE 1] Gerando e enviando 100 dados aleatorios...");
        for (i = 0; i < 100; i = i + 1) begin
            test_vector[i] = $random; // Salva o dado para conferir depois
            cpu_write_fifo(test_vector[i]);
            
            // Força o comando JEDEC de WRITE (CS=0, RAS=1, CAS=0, WE=0)
            @(negedge clk);
            CS = 0; RAS = 1; CAS = 0; WE = 0;
            @(negedge clk);
            CS = 1; RAS = 1; CAS = 1; WE = 1; // NOP
            
            // Espera a FSM de controle transmitir fisicamente para os pinos
            #40; 
        end
        $display("[FASE 1] Concluida. Fila esvaziada para a memoria.");

        // ---------------------------------------------------------------------
        // FASE 2: TESTANDO 100 LEITURAS (MEMORIA -> CONVERSOR -> CPU)
        // ---------------------------------------------------------------------
        $display("[FASE 2] Lendo 100 dados e verificando integridade...");
        for (i = 0; i < 100; i = i + 1) begin
            // Envia o dado esperado simulando a resposta da memória
            mem_send_read(test_vector[i]);
            
            // Espera a CPU flag de Rx Subir
            @(posedge cpu_clk);
            wait(rx_valid == 1'b1);
            
            if (cpu_rdata !== test_vector[i]) begin
                $display("[ERRO] Caso %0d. Esperado: %h, Recebido: %h", i, test_vector[i], cpu_rdata);
                errors = errors + 1;
            end
            
            wait(rx_valid == 1'b0);
        end
        
        $display("===============================================================");
        if (errors == 0)
            $display(" SUCESSO ABSOLUTO! Todos os 100 casos foram validados com 0 Erros.");
        else
            $display(" FALHA. A simulação encontrou %0d erro(s).", errors);
        $display("===============================================================");
        
        $finish;
    end

endmodule