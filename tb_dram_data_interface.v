`timescale 1ns / 1ps

module tb_dram_data_interface();

    // Sinais do DUT
    reg         clk, rst_n;
    reg         rd_cmd, wr_cmd;
    reg  [63:0] data_from_core;
    wire [63:0] data_to_core;
    wire [7:0]  dm_to_core;
    reg         DM;
    
    // Pinos Bidirecionais
    wire [7:0]  DQ;
    wire        DQS, DQS_n;

    // Sinais Mock do Controlador (Para forçar no barramento inout)
    reg [7:0]   tb_dq_out;
    reg         tb_dqs_out;
    reg         tb_drive_bus; // 1 = TB dirige o barramento, 0 = TB em alta impedância

    assign DQ    = tb_drive_bus ? tb_dq_out  : 8'bz;
    assign DQS   = tb_drive_bus ? tb_dqs_out : 1'bz;
    assign DQS_n = tb_drive_bus ? ~tb_dqs_out: 1'bz;

    // Instanciação
    dram_data_interface dut (
        .clk(clk), .rst_n(rst_n), 
        .rd_cmd(rd_cmd), .wr_cmd(wr_cmd),
        .data_from_core(data_from_core), .data_to_core(data_to_core), .dm_to_core(dm_to_core),
        .DQ(DQ), .DQS(DQS), .DQS_n(DQS_n), .DM(DM)
    );

    // Clock Principal
    initial begin clk = 0; forever #5 clk = ~clk; end

    integer i, e, errors;
    reg [63:0] expected_64;
    reg [63:0] captured_64;

    // Task para emular o Controlador enviando um Burst de Escrita (DDR)
    task send_ddr_write_burst(input [63:0] data);
        integer j;
        begin
            @(posedge clk);
            wr_cmd = 1; // Avisa a Interface que vamos começar
            @(posedge clk);
            wr_cmd = 0;
            
            // Toma controle do barramento
            tb_drive_bus = 1;
            tb_dqs_out = 0;
            #2.5; // Alinhamento de fase em 90 graus
            
            // Bate 8 bordas de DQS (4 ciclos completos) enviando byte a byte
            for (j = 0; j < 4; j = j + 1) begin
                // Borda de Subida
                tb_dq_out = data[j*16 +: 8]; 
                DM = 0;
                tb_dqs_out = 1;
                #5;
                
                // Borda de Descida
                tb_dq_out = data[j*16+8 +: 8]; 
                DM = 0;
                tb_dqs_out = 0;
                #5;
            end
            
            tb_drive_bus = 0; // Libera o barramento
            tb_dq_out = 8'bz;
            tb_dqs_out = 1'bz;
        end
    endtask

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

        // FASE 1: TESTANDO A RECEPÇÃO DA MEMÓRIA (DDR -> SDR)
        $display(">> Iniciando Fase 1: Emulando Controlador enviando (Escrita)");
        for (i = 0; i < 250; i = i + 1) begin
            expected_64 = {$random, $random};
            
            send_ddr_write_burst(expected_64);
            
            // Aguarda o contador interno reconstruir a palavra (6 ciclos)
            repeat(8) @(posedge clk);
            
            if (data_to_core !== expected_64) begin
                $display("[ERRO RX] Iteracao %0d. Esp: %h | Construido: %h", i, expected_64, data_to_core);
                errors = errors + 1;
            end
        end

        // FASE 2: TESTANDO A TRANSMISSÃO DA MEMÓRIA (SDR -> DDR)
        $display(">> Iniciando Fase 2: Emulando Memoria enviando (Leitura)");
        for (i = 0; i < 250; i = i + 1) begin
            expected_64 = {$random, $random};
            data_from_core = expected_64;
            
            @(posedge clk);
            rd_cmd = 1;
            @(posedge clk);
            rd_cmd = 0;
            
            // O DUT agora deve assumir o barramento DQ/DQS.
            // Precisamos capturar os 8 bytes baseado nas bordas do DQS gerado por ele.
            captured_64 = 64'd0;
            
            for (e = 0; e < 4; e = e + 1) begin
                @(posedge DQS); // Captura na subida
                captured_64[e*16 +: 8] = DQ;
                
                @(negedge DQS); // Captura na descida
                captured_64[e*16+8 +: 8] = DQ;
            end
            
            if (captured_64 !== expected_64) begin
                $display("[ERRO TX] Iteracao %0d. Esp: %h | Transmitido: %h", i, expected_64, captured_64);
                errors = errors + 1;
            end
            
            // Aguarda a interface liberar o barramento
            repeat(3) @(posedge clk);
        end

        if (errors == 0) $display(">> [DATA PHY] SUCESSO! 500 conversoes DDR/SDR bidirecionais sem erros.");
        else $display(">> [DATA PHY] FALHOU com %0d erros.", errors);
        $stop;
    end
endmodule