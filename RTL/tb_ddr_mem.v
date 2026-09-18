// [PT] Módulo: tb_ddr_mem / [EN] Module: tb_ddr_mem
// [PT] Testbench do Sistema de Memória DDR3 com Clocks Independentes. / [EN] DDR3 Memory System Testbench with Independent Clocks.
// [PT] Simula uma CPU realizando operações massivas de escrita e leitura aleatória. / [EN] Simulates a CPU performing massive random write and read operations.
// [PT] Inclui cálculo automático de períodos e suporte a domínios de clock diferentes (CDC). / [EN] Includes automatic period calculation and support for different clock domains (CDC).
`timescale 1ns/1ps

module tb_ddr_mem;

    // =========================================================================
    // [PT] Parâmetros e Clocks Independentes / [EN] Independent Parameters and Clocks
    // =========================================================================
    // [PT] Frequência da Memória (MHz) / [EN] Memory frequency (MHz)
    parameter FREQ_MEM = 100; 
    // [PT] Frequência da CPU (MHz) / [EN] CPU frequency (MHz)
    parameter FREQ_CPU = 200; 
    
    // [PT] Cálculo automático dos períodos (ns) / [EN] Automatic period calculation (ns)
    real T_MEM = 1000.0 / FREQ_MEM;
    real T_CPU = 1000.0 / FREQ_CPU;

    reg         clk;
    reg         clk_90;
    reg         rst_n;
    reg         cpu_clk;
    reg         cpu_rst_n;
    
    // [PT] Interface de Alto Nível / [EN] High-Level Interface
    reg         cpu_req;
    reg         cpu_rnw;
    reg  [26:0] cpu_addr;
    wire        cpu_ready;
    
    // [PT] Interface de Dados CPU -> PHY / [EN] CPU -> PHY Data Interface
    reg         cpu_wr_en;
    reg  [15:0] cpu_wdata;
    wire [15:0] cpu_rdata;
	reg  [1:0]  cpu_wstrb;
	reg         cpu_rd_en;
    
    // [PT] Sinais de Status Internos / [EN] Internal Status Signals
    wire        init_done;
    wire        tx_full;
    wire        tx_empty;
    wire        rx_valid;

    // [PT] Variáveis de Verificação / [EN] Verification Variables
    integer         erros = 0;
    reg  [63:0] test_data;
    reg  [63:0] read_data;
    reg  [13:0] test_row;
    reg  [2:0]  test_bank;
    reg  [9:0]  test_col;
    reg  [26:0] test_full_addr;

    // =========================================================================
    // [PT] Instanciação do Sistema Completo / [EN] Full System Instantiation
    // =========================================================================
    ddr_mem #(.freq(FREQ_MEM)) dut (
        .clk        (clk),
        .clk_90     (clk_90),
        .rst_n      (rst_n),
        .cpu_clk    (cpu_clk),
        .cpu_rst_n  (cpu_rst_n),
        
        .cpu_req    (cpu_req),
        .cpu_rnw    (cpu_rnw),
        .cpu_addr   (cpu_addr),
        .cpu_ready  (cpu_ready),
        .cpu_wstrb  (cpu_wstrb),
		  
        .init_done  (init_done),
        .tx_full    (tx_full),
        .tx_empty   (tx_empty),
        .rx_valid   (rx_valid),
        
        .cpu_wr_en  (cpu_wr_en),
        .cpu_wdata  (cpu_wdata),
        .cpu_rdata  (cpu_rdata)
    );

    // =========================================================================
    // [PT] Geração de Clocks Automatizada / [EN] Automated Clock Generation
    // =========================================================================
    
    // [PT] 1. Clock da Memória / [EN] 1. Memory Clock
    initial begin
        clk = 0;
        forever #(T_MEM / 2.0) clk = ~clk; 
    end

    // [PT] 2. Clock DQS Defasado (90°) / [EN] 2. Phase-shifted DQS Clock (90°)
    initial begin
        clk_90 = 0;
        // [PT] 90° é 1/4 do período / [EN] 90 degrees is 1/4 of the period
        #(T_MEM / 4.0); 
        forever #(T_MEM / 2.0) clk_90 = ~clk_90;
    end

    // [PT] 3. Clock do Processador/AXI / [EN] 3. Processor/AXI Clock
    initial begin
        cpu_clk = 0;
        forever #(T_CPU / 2.0) cpu_clk = ~cpu_clk;
    end

    // =========================================================================
    // [PT] Tasks de Operação (Handshake Seguro) / [EN] Operation Tasks (Safe Handshake)
    // =========================================================================
    
    // [PT] Escrita em Burst (BL8) / [EN] Burst Write (BL8)
    task write_burst(input [26:0] addr, input [63:0] data_in);
        begin
            // [PT] 1. Solicita comando / [EN] 1. Request command
            cpu_req   = 1'b1;
            // [PT] WRITE / [EN] WRITE
            cpu_rnw   = 1'b0; 
            cpu_addr  = addr;
            cpu_wr_en = 1'b0; 
            
            // [PT] 2. Aguarda handshake do controlador / [EN] 2. Wait for controller handshake
            @(posedge cpu_clk);
            while (cpu_ready !== 1'b1) begin
                @(posedge cpu_clk);
            end
            
			// [PT] 3. Envia dados para a TX FIFO / [EN] 3. Push data to TX FIFO
            cpu_req   = 1'b0;
            // [PT] Strobe em ALTO / [EN] Strobe HIGH
            cpu_wr_en = 1'b1; cpu_wdata = data_in[63:48]; cpu_wstrb = 2'b11; 
            @(posedge cpu_clk);
            
            // [PT] Strobe em ALTO / [EN] Strobe HIGH
            cpu_wr_en = 1'b1; cpu_wdata = data_in[47:32]; cpu_wstrb = 2'b11; 
            @(posedge cpu_clk);
            
            // [PT] Strobe em ALTO / [EN] Strobe HIGH
            cpu_wr_en = 1'b1; cpu_wdata = data_in[31:16]; cpu_wstrb = 2'b11; 
            @(posedge cpu_clk);
            
            // [PT] Strobe em ALTO / [EN] Strobe HIGH
            cpu_wr_en = 1'b1; cpu_wdata = data_in[15:0];  cpu_wstrb = 2'b11; 
            @(posedge cpu_clk);
            
            // [PT] Limpa o strobe ao terminar / [EN] Clear strobe upon finish
            cpu_wr_en = 1'b0; cpu_wstrb = 2'b00; 
            
            // [PT] Atraso tWTR para estabilização / [EN] tWTR delay for stability
            repeat(40) @(posedge clk);
        end
    endtask

    // [PT] Leitura em Burst (BL8) / [EN] Burst Read (BL8)
    task read_burst(input [26:0] addr, output [63:0] data_out);
        integer j;
        integer timer;
        begin
            data_out = 64'd0;
            j = 0;

            // [PT] 1. Solicita leitura / [EN] 1. Request read
            cpu_req  = 1'b1;
            // [PT] READ / [EN] READ
            cpu_rnw  = 1'b1; 
            cpu_addr = addr;

            // [PT] 2. Aguarda aceitação / [EN] 2. Wait for acceptance
            @(posedge cpu_clk);
            while (cpu_ready !== 1'b1) begin
                @(posedge cpu_clk);
            end

            cpu_req = 1'b0;

            // [PT] 3. Aguarda dados na RX FIFO / [EN] 3. Wait for data in RX FIFO
            for (timer = 0; timer < 100000; timer = timer + 1) begin
                @(posedge cpu_clk);
                if (rx_valid === 1'b1) begin
                    if (j == 0) data_out[63:48] = cpu_rdata;
                    if (j == 1) data_out[47:32] = cpu_rdata;
                    if (j == 2) data_out[31:16] = cpu_rdata;
                    if (j == 3) data_out[15:0]  = cpu_rdata;
                    
                    j = j + 1;
                    if (j == 4) timer = 100000; 
                end
            end
            
            repeat(40) @(posedge clk);
        end
    endtask

    // =========================================================================
    // [PT] Fluxo de Validação Massiva / [EN] Massive Validation Flow
    // =========================================================================
    integer i;
    initial begin
        rst_n     = 0;
        cpu_rst_n = 0;
        cpu_req   = 0; 
        cpu_rnw   = 0;
        cpu_addr  = 0;
        cpu_wr_en = 0; 
        cpu_wdata = 0;
		cpu_rd_en = 0;
	    cpu_wstrb = 0;
        #100;
        rst_n     = 1;
        cpu_rst_n = 1;
        
        $display("=========================================================");
        $display(" PT: Aguardando Inicializacao JEDEC... | EN: Waiting for JEDEC Init...");
        $display("=========================================================");
        
        wait(init_done == 1'b1);
        $display("PT: Inicializacao Concluida em %0t ns!", $time);
        repeat(20) @(posedge clk);
        
        $display("PT: Iniciando varredura (100.000 Testes)... | EN: Starting stress test...");
        for (i = 0; i < 100000; i = i + 1) begin
            
            // [PT] Geração de Endereço Aleatório / [EN] Random Address Generation
            test_row  = $urandom_range(0, 8191);
            test_bank = $urandom_range(0, 7);
            // [PT] Alinhado a BL8 / [EN] BL8 Aligned
            test_col  = $urandom_range(0, 1023) & 10'h3F8; 
            test_full_addr = {test_row[13:0], test_bank[2:0], test_col[9:0]};
            
            test_data = {$urandom, $urandom};
            read_data = 64'd0;

            write_burst(test_full_addr, test_data);
            read_burst(test_full_addr, read_data);
            
            if (read_data !== test_data) begin
                $display("[FALHA/FAIL] Teste/Test %0d | END: %h | EXP: %h | OBT: %h", 
                         i, test_full_addr, test_data, read_data);
                erros = erros + 1;
            end else if (i % 1000 == 0) begin
                $display("[PROGRESSO/PROGRESS] %0d testes concluidos/completed tests...", i);
            end
        end

        $display("=========================================================");
        if (erros == 0)
            $display(" PT: SUCESSO ABSOLUTO! 0 Erros. | EN: ABSOLUTE SUCCESS! 0 Errors.");
        else
            $display(" PT: FALHA: %0d erros encontrados. | EN: FAILURE: %0d errors found.", erros, erros);
        $display("=========================================================");
        
        $finish;
    end

endmodule
