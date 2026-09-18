// [PT] Módulo: tb_dram_data_interface / [EN] Module: tb_dram_data_interface
// [PT] Testbench da Interface de Dados DRAM (PHY), responsável por validar a conversão SDR-DDR. / [EN] Testbench for the DRAM Data Interface (PHY), responsible for validating SDR-DDR conversion.
// [PT] Entradas/Saídas: Comandos read/write, barramento inout DQ/DQS, dados core-to-phy e phy-to-core. / [EN] Inputs/Outputs: Read/write commands, inout DQ/DQS bus, core-to-phy and phy-to-core data.
// [PT] Papel: Verificar a emulação de transferências double data rate e serialização/desserialização. / [EN] Role: Verify the emulation of double data rate transfers and serialization/deserialization.
`timescale 1ns / 1ps

module tb_dram_data_interface();

    // [PT] Sinais do DUT / [EN] DUT Signals
    reg         clk, rst_n;
    reg         rd_cmd, wr_cmd;
    reg  [63:0] data_from_core;
    wire [63:0] data_to_core;
    wire [7:0]  dm_to_core;
    reg         DM;
    
    // [PT] Pinos Bidirecionais / [EN] Bidirectional Pins
    wire [7:0]  DQ;
    wire        DQS, DQS_n;

    // [PT] Sinais Mock do Controlador (Para forçar no barramento inout) / [EN] Controller Mock Signals (To drive the inout bus)
    reg [7:0]   tb_dq_out;
    reg         tb_dqs_out;
    // [PT] 1 = TB dirige o barramento, 0 = TB em alta impedância / [EN] 1 = TB drives bus, 0 = TB in high impedance
    reg         tb_drive_bus; 

    assign DQ    = tb_drive_bus ? tb_dq_out  : 8'bz;
    assign DQS   = tb_drive_bus ? tb_dqs_out : 1'bz;
    assign DQS_n = tb_drive_bus ? ~tb_dqs_out: 1'bz;

    // [PT] Instanciação do módulo / [EN] Module Instantiation
    dram_data_interface dut (
        .clk(clk), .rst_n(rst_n), 
        .rd_cmd(rd_cmd), .wr_cmd(wr_cmd),
        .data_from_core(data_from_core), .data_to_core(data_to_core), .dm_to_core(dm_to_core),
        .DQ(DQ), .DQS(DQS), .DQS_n(DQS_n), .DM(DM)
    );

    // [PT] Clock Principal / [EN] Main Clock
    initial begin clk = 0; forever #5 clk = ~clk; end

    integer i, e, errors;
    reg [63:0] expected_64;
    reg [63:0] captured_64;

    // [PT] Task para emular o Controlador enviando um Burst de Escrita (DDR) / [EN] Task to emulate the Controller sending a Write Burst (DDR)
    task send_ddr_write_burst(input [63:0] data);
        integer j;
        begin
            @(posedge clk);
            // [PT] Avisa a Interface que vamos começar / [EN] Notifies the Interface that we are starting
            wr_cmd = 1; 
            @(posedge clk);
            wr_cmd = 0;
            
            // [PT] Toma controle do barramento / [EN] Takes control of the bus
            tb_drive_bus = 1;
            tb_dqs_out = 0;
            // [PT] Alinhamento de fase em 90 graus / [EN] 90-degree phase alignment
            #2.5; 
            
            // [PT] Bate 8 bordas de DQS (4 ciclos completos) enviando byte a byte / [EN] Triggers 8 DQS edges (4 full cycles) sending byte by byte
            for (j = 0; j < 4; j = j + 1) begin
                // [PT] Borda de Subida / [EN] Rising Edge
                tb_dq_out = data[j*16 +: 8]; 
                DM = 0;
                tb_dqs_out = 1;
                #5;
                
                // [PT] Borda de Descida / [EN] Falling Edge
                tb_dq_out = data[j*16+8 +: 8]; 
                DM = 0;
                tb_dqs_out = 0;
                #5;
            end
            
            // [PT] Libera o barramento / [EN] Releases the bus
            tb_drive_bus = 0; 
            tb_dq_out = 8'bz;
            tb_dqs_out = 1'bz;
        end
    endtask

    // [PT] Bloco de Inicialização e Execução do Teste / [EN] Test Initialization and Execution Block
    initial begin
        rst_n = 0;
        rd_cmd = 0; wr_cmd = 0;
        data_from_core = 0; DM = 0;
        tb_drive_bus = 0; tb_dq_out = 8'bz; tb_dqs_out = 1'bz;
        errors = 0;
        
        #50 rst_n = 1; #50;

        $display("==========================================================");
        $display("[TB DATA PHY] Testando Conversao SDR <-> DDR (250 Casos)");
        $display("==========================================================");

        // [PT] FASE 1: TESTANDO A RECEPÇÃO DA MEMÓRIA (DDR -> SDR) / [EN] PHASE 1: TESTING MEMORY RECEPTION (DDR -> SDR)
        $display(">> Iniciando Fase 1: Emulando Controlador enviando (Escrita)");
        for (i = 0; i < 250; i = i + 1) begin
            expected_64 = {$random, $random};
            
            send_ddr_write_burst(expected_64);
            
            // [PT] Aguarda o contador interno reconstruir a palavra (6 ciclos) / [EN] Wait for internal counter to rebuild the word (6 cycles)
            repeat(8) @(posedge clk);
            
            if (data_to_core !== expected_64) begin
                $display("[ERRO RX] Iteracao %0d. Esp: %h | Construido: %h", i, expected_64, data_to_core);
                errors = errors + 1;
            end
        end

        // [PT] FASE 2: TESTANDO A TRANSMISSÃO DA MEMÓRIA (SDR -> DDR) / [EN] PHASE 2: TESTING MEMORY TRANSMISSION (SDR -> DDR)
        $display(">> Iniciando Fase 2: Emulando Memoria enviando (Leitura)");
        for (i = 0; i < 250; i = i + 1) begin
            expected_64 = {$random, $random};
            data_from_core = expected_64;
            
            @(posedge clk);
            rd_cmd = 1;
            @(posedge clk);
            rd_cmd = 0;
            
            // [PT] O DUT agora deve assumir o barramento DQ/DQS. / [EN] The DUT must now assume the DQ/DQS bus.
            // [PT] Precisamos capturar os 8 bytes baseado nas bordas do DQS gerado por ele. / [EN] We need to capture the 8 bytes based on the DQS edges it generates.
            captured_64 = 64'd0;
            
            for (e = 0; e < 4; e = e + 1) begin
                // [PT] Captura na subida / [EN] Capture on rising edge
                @(posedge DQS); 
                captured_64[e*16 +: 8] = DQ;
                
                // [PT] Captura na descida / [EN] Capture on falling edge
                @(negedge DQS); 
                captured_64[e*16+8 +: 8] = DQ;
            end
            
            if (captured_64 !== expected_64) begin
                $display("[ERRO TX] Iteracao %0d. Esp: %h | Transmitido: %h", i, expected_64, captured_64);
                errors = errors + 1;
            end
            
            // [PT] Aguarda a interface liberar o barramento / [EN] Wait for the interface to release the bus
            repeat(3) @(posedge clk);
        end

        if (errors == 0) $display(">> [DATA PHY] SUCESSO! 500 conversoes DDR/SDR bidirecionais sem erros.");
        else $display(">> [DATA PHY] FALHOU com %0d erros.", errors);
        $stop;
    end
endmodule