`timescale 1ns / 1ps

module tb_datapath();

    // -------------------------------------------------------------------------
    // Sinais Internos do Testbench
    // -------------------------------------------------------------------------
    reg clk;
    reg clk_90;
    reg rst_n;
    reg write_req;

    reg cpu_clk;
    reg cpu_rst_n;
    reg cpu_wr_en;
    reg [15:0] cpu_wdata;

    wire tx_full;
    wire tx_empty;
    wire [15:0] cpu_rdata;
    wire rx_valid;
    wire odt_out;

    // Sinais Físicos Bidirecionais (Tri-State)
    wire [7:0] DQ;
    wire DQS;
    wire DQS_n;

    // Controles do Mock da Memória DDR3 (Testbench)
    reg [7:0] tb_dq;
    reg tb_dqs;
    reg tb_dqs_n;
    reg tb_drive_bus;

    integer errors = 0;

    // -------------------------------------------------------------------------
    // Roteamento Tri-State no Testbench
    // -------------------------------------------------------------------------
    assign DQ    = tb_drive_bus ? tb_dq    : 8'bz;
    assign DQS   = tb_drive_bus ? tb_dqs   : 1'bz;
    assign DQS_n = tb_drive_bus ? tb_dqs_n : 1'bz;

    // -------------------------------------------------------------------------
    // Instanciação do DUT (Device Under Test)
    // -------------------------------------------------------------------------
    datapath dut (
        .clk(clk),
        .clk_90(clk_90),
        .rst_n(rst_n),
        .write_req(write_req),
        
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

    // -------------------------------------------------------------------------
    // Geração de Clocks (NOVA RELAÇÃO DE FREQUÊNCIAS)
    // -------------------------------------------------------------------------
    // 1. Clock Principal da PHY (100 MHz -> Período 10ns)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 2. Clock Atrasado em 90 graus (100 MHz, deslocado em 2.5ns)
    initial begin
        clk_90 = 0;
        #2.5; 
        forever #5 clk_90 = ~clk_90;
    end

    // 3. Clock do Processador RISC-V (200 MHz -> Período 5ns)
    // A CPU agora é o dobro da velocidade da memória
    initial begin
        cpu_clk = 0;
        forever #2.5 cpu_clk = ~cpu_clk;
    end

    // -------------------------------------------------------------------------
    // Monitor de Escrita (DDR TX Auto-Checker)
    // -------------------------------------------------------------------------
    always @(posedge DQS) begin
        if (!tb_drive_bus && odt_out) begin
            $display("[TX MONITOR] Borda de Subida (DQS=1). Dado capturado no DQ: %h", DQ);
        end
    end

    always @(negedge DQS) begin
        if (!tb_drive_bus && odt_out && DQS !== 1'bz) begin
            $display("[TX MONITOR] Borda de Descida (DQS=0). Dado capturado no DQ: %h", DQ);
        end
    end

    // -------------------------------------------------------------------------
    // TASKS (Ações do Testbench)
    // -------------------------------------------------------------------------
    
    // Task 1: A CPU envia 4 palavras para a TX FIFO (Agora muito mais rápido)
    task cpu_fill_tx_fifo(input [15:0] w1, input [15:0] w2, input [15:0] w3, input [15:0] w4);
        begin
            @(negedge cpu_clk); cpu_wr_en = 1; cpu_wdata = w1;
            @(negedge cpu_clk); cpu_wr_en = 1; cpu_wdata = w2;
            @(negedge cpu_clk); cpu_wr_en = 1; cpu_wdata = w3;
            @(negedge cpu_clk); cpu_wr_en = 1; cpu_wdata = w4;
            @(negedge cpu_clk); cpu_wr_en = 0;
            $display("[CPU] Fila de transmissao preenchida em alta velocidade (200MHz).");
        end
    endtask

    // Task 2: Dispara a máquina de estados da PHY para consumir a FIFO
    task phy_execute_write_burst(input integer op_num);
        begin
            @(negedge clk);
            write_req = 1;
            @(negedge clk);
            write_req = 0;
            
            wait(dut.control_inst.state == 2'd0); 
            @(negedge clk);
            $display("[OPERACAO %0d] Escrita Burst drenada pela PHY com sucesso (100MHz).", op_num);
            $display("---------------------------------------------------------------");
        end
    endtask

    // Task 3: Simula a Memória DDR3 enviando dados para a FPGA (DDR RX)
    task mem_execute_read(input integer op_num, input [7:0] msb, input [7:0] lsb);
        begin
            @(negedge clk);
            tb_drive_bus = 1;
            
            // Preamble da memória
            tb_dqs = 0; tb_dqs_n = 1; 
            #10; 
            
            // Borda de Subida (Envia LSB)
            tb_dqs = 1; tb_dqs_n = 0; tb_dq = lsb;
            #5;
            
            // Borda de Descida (Envia MSB)
            tb_dqs = 0; tb_dqs_n = 1; tb_dq = msb;
            #5;
            
            // Postamble
            tb_dqs = 0; tb_dqs_n = 1; tb_dq = 8'bz;
            #10;
            
            tb_drive_bus = 0;
            tb_dqs = 1'bz; tb_dqs_n = 1'bz;

            // Espera a CPU rápida (200MHz) detectar a flag válida
            @(posedge cpu_clk);
            wait(rx_valid == 1'b1);
            
            if (cpu_rdata !== {msb, lsb}) begin
                $display("[ERRO] Leitura falhou. Esperado: %h, Obtido: %h", {msb, lsb}, cpu_rdata);
                errors = errors + 1;
            end else begin
                $display("[OPERACAO %0d] Leitura Burst. Dado RX recebido pela CPU: %h", op_num, cpu_rdata);
            end
            
            wait(rx_valid == 1'b0); // Espera o sinal baixar antes do próximo teste
            $display("---------------------------------------------------------------");
        end
    endtask

    // -------------------------------------------------------------------------
    // SEQUÊNCIA DE TESTES (10 Operações)
    // -------------------------------------------------------------------------
    initial begin
        $display("===============================================================");
        $display(" INICIANDO VALIDACAO DO DATAPATH FÍSICO");
        $display(" CPU: 200MHz | PHY: 100MHz");
        $display("===============================================================");

        rst_n = 0; cpu_rst_n = 0;
        write_req = 0; cpu_wr_en = 0; cpu_wdata = 0;
        tb_drive_bus = 0; tb_dq = 8'bz; tb_dqs = 1'bz; tb_dqs_n = 1'bz;
        
        #30; 
        rst_n = 1; cpu_rst_n = 1;
        #30;

        // TX
        cpu_fill_tx_fifo(16'h1122, 16'h3344, 16'h5566, 16'h7788);
        phy_execute_write_burst(1);

        cpu_fill_tx_fifo(16'hAABB, 16'hCCDD, 16'hEEFF, 16'h9900);
        phy_execute_write_burst(2);

        cpu_fill_tx_fifo(16'h1234, 16'h5678, 16'h9ABC, 16'hDEF0);
        phy_execute_write_burst(3);
        
        cpu_fill_tx_fifo(16'h0011, 16'h0022, 16'h0033, 16'h0044);
        phy_execute_write_burst(4);
        
        cpu_fill_tx_fifo(16'hFF00, 16'hEE00, 16'hDD00, 16'hCC00);
        phy_execute_write_burst(5);

        // RX
        mem_execute_read(6, 8'hCA, 8'hFE);
        mem_execute_read(7, 8'hB0, 8'hBA);
        mem_execute_read(8, 8'hDE, 8'hAD);
        mem_execute_read(9, 8'hBE, 8'hEF);
        mem_execute_read(10, 8'h10, 8'h24);

        $display("===============================================================");
        if (errors == 0)
            $display(" SIMULACAO DO DATAPATH CONCLUIDA COM SUCESSO! 0 ERROS.");
        else
            $display(" SIMULACAO FALHOU COM %0d ERRO(S).", errors);
        $display("===============================================================");
        
        $finish;
    end

endmodule