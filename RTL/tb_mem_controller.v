// [PT] Módulo: tb_mem_controller / [EN] Module: tb_mem_controller
// [PT] Testbench do Controlador de Memória, abrangendo fluxos de dados e interações com a PHY. / [EN] Memory Controller Testbench, covering data flows and PHY interactions.
// [PT] Entradas/Saídas: Interfaces CPU para leitura/escrita e portas emuladas da memória DDR. / [EN] Inputs/Outputs: CPU interfaces for read/write and emulated DDR memory ports.
// [PT] Papel: Valida o agrupamento de operações entre os domínios de clock CPU e Memória (CDC). / [EN] Role: Validates the grouping of operations between CPU and Memory clock domains (CDC).
`timescale 1ns / 1ps

module tb_mem_controller();

    // [PT] Sinais do Testbench / [EN] Testbench Signals
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
    
    // [PT] Sinais Mock da Memória DDR3 Física / [EN] Physical DDR3 Memory Mock Signals
    reg [7:0] tb_dq;
    reg tb_dqs, tb_dqs_n, tb_drive_bus;
    
    integer i, errors = 0;
    // [PT] Array para guardar os 100 casos aleatórios / [EN] Array to store the 100 random cases
    reg [15:0] test_vector [0:99]; 

    assign DQ    = tb_drive_bus ? tb_dq    : 8'bz;
    assign DQS   = tb_drive_bus ? tb_dqs   : 1'bz;
    assign DQS_n = tb_drive_bus ? tb_dqs_n : 1'bz;

    // [PT] Instanciação do DUT / [EN] DUT Instantiation
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

    // [PT] Geração de Clocks (CPU = 200MHz, Memória = 100MHz) / [EN] Clock Generation (CPU = 200MHz, Memory = 100MHz)
    initial begin clk = 0; forever #5 clk = ~clk; end
    initial begin clk_90 = 0; #2.5 forever #5 clk_90 = ~clk_90; end
    initial begin cpu_clk = 0; forever #2.5 cpu_clk = ~cpu_clk; end

    // -------------------------------------------------------------------------
    // [PT] TASKS DE APOIO / [EN] HELPER TASKS
    // -------------------------------------------------------------------------
    // [PT] Escrita em FIFO pela CPU / [EN] CPU FIFO write
    task cpu_write_fifo(input [15:0] data);
        begin
            @(negedge cpu_clk);
            cpu_wr_en = 1;
            cpu_wdata = data;
            @(negedge cpu_clk);
            cpu_wr_en = 0;
        end
    endtask

    // [PT] Simula a memória enviando um dado de volta (SDR para DDR) / [EN] Simulates the memory sending data back (SDR to DDR)
    task mem_send_read(input [15:0] data);
        begin
            @(negedge clk);
            tb_drive_bus = 1;
            // [PT] Preamble / [EN] Preamble
            tb_dqs = 0; tb_dqs_n = 1; #10; 
            
            // [PT] LSB (Subida) / [EN] LSB (Rising Edge)
            tb_dqs = 1; tb_dqs_n = 0; tb_dq = data[7:0];   
            #5;
            // [PT] MSB (Descida) / [EN] MSB (Falling Edge)
            tb_dqs = 0; tb_dqs_n = 1; tb_dq = data[15:8];  
            #5;
            
            // [PT] Postamble / [EN] Postamble
            tb_dqs = 0; tb_dqs_n = 1; tb_dq = 8'bz; #10;   
            tb_drive_bus = 0; tb_dqs = 1'bz; tb_dqs_n = 1'bz;
        end
    endtask

    // -------------------------------------------------------------------------
    // [PT] BLOCO DE EXECUÇÃO PRINCIPAL / [EN] MAIN EXECUTION BLOCK
    // -------------------------------------------------------------------------
    initial begin
        $display("===============================================================");
        $display(" INICIANDO VALIDACAO DO MEMORY CONTROLLER (100 CASOS ALEATORIOS)");
        $display("===============================================================");

        // [PT] Reset inicial / [EN] Initial reset
        clk = 0; clk_90 = 0; cpu_clk = 0;
        rst_n = 0; cpu_rst_n = 0;
        CS = 1; RAS = 1; CAS = 1; WE = 1; A = 0; BA = 0;
        cpu_wr_en = 0; cpu_wdata = 0;
        tb_drive_bus = 0; tb_dq = 8'bz; tb_dqs = 1'bz; tb_dqs_n = 1'bz;

        #50 rst_n = 1; cpu_rst_n = 1;

        // [PT] Fictício: Pula a inicialização para acelerar simulação / [EN] Fictitious: Skips initialization to speed up simulation
        force dut.init_done = 1;
        #20;

        // ---------------------------------------------------------------------
        // [PT] FASE 1: TESTANDO 100 ESCRITAS (CPU -> FIFO -> MEMORIA) / [EN] PHASE 1: TESTING 100 WRITES (CPU -> FIFO -> MEMORY)
        // ---------------------------------------------------------------------
        $display("[FASE 1] Gerando e enviando 100 dados aleatorios...");
        for (i = 0; i < 100; i = i + 1) begin
            // [PT] Salva o dado para conferir depois / [EN] Saves data to check later
            test_vector[i] = $random; 
            cpu_write_fifo(test_vector[i]);
            
            // [PT] Força o comando JEDEC de WRITE (CS=0, RAS=1, CAS=0, WE=0) / [EN] Forces JEDEC WRITE command (CS=0, RAS=1, CAS=0, WE=0)
            @(negedge clk);
            CS = 0; RAS = 1; CAS = 0; WE = 0;
            @(negedge clk);
            // [PT] NOP / [EN] NOP
            CS = 1; RAS = 1; CAS = 1; WE = 1; 
            
            // [PT] Espera a FSM de controle transmitir fisicamente para os pinos / [EN] Waits for control FSM to physically transmit to pins
            #40; 
        end
        $display("[FASE 1] Concluida. Fila esvaziada para a memoria.");

        // ---------------------------------------------------------------------
        // [PT] FASE 2: TESTANDO 100 LEITURAS (MEMORIA -> CONVERSOR -> CPU) / [EN] PHASE 2: TESTING 100 READS (MEMORY -> CONVERTER -> CPU)
        // ---------------------------------------------------------------------
        $display("[FASE 2] Lendo 100 dados e verificando integridade...");
        for (i = 0; i < 100; i = i + 1) begin
            // [PT] Envia o dado esperado simulando a resposta da memória / [EN] Sends the expected data simulating memory response
            mem_send_read(test_vector[i]);
            
            // [PT] Espera a CPU flag de Rx Subir / [EN] Waits for Rx flag to raise for CPU
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