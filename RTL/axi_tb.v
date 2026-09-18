// =========================================================================
// [PT] Módulo: axi_tb / [EN] Module: axi_tb
// [PT] Testbench do Sistema AXI-DDR3 (Golden Model / Scoreboard com Injeção de Falha). / [EN] AXI-DDR3 System Testbench (Golden Model / Scoreboard with Fault Injection).
// [PT] Este módulo realiza um teste de estresse avançado e valida a própria infraestrutura de teste. / [EN] This module performs an advanced stress test and validates the test infrastructure itself.
// [PT] Fluxo de Teste: / [EN] Test Flow:
// [PT] 1. Inicialização: Aguarda o controlador completar o boot JEDEC (init_done). / [EN] 1. Initialization: Waits for the controller to complete JEDEC boot (init_done).
// [PT] 2. Preenchimento (Fill): Escreve o valor 7 em TODAS as posições emuladas da memória. / [EN] 2. Fill: Writes the value 7 in ALL emulated memory positions.
// [PT] 3. Estresse Intercalado: Realiza transações randômicas de Leitura/Escrita (Fase 2). / [EN] 3. Interleaved Stress: Performs random Read/Write transactions (Phase 2).
// [PT] 4. Injeção de Erro (Fault Injection): Força uma gravação corrompida para garantir que a lógica de comparação do testbench está operando e pegando falhas (Fase 3). / [EN] 4. Fault Injection: Forces a corrupted write to ensure the testbench comparison logic is operating and catching faults (Phase 3).
// =========================================================================
`timescale 1ns/1ps

module axi_tb;
    // =========================================================================
    // [PT] Parâmetros do Testbench / [EN] Testbench Parameters
    // =========================================================================
    parameter FREQ = 100;
    // [PT] Reduzido um pouco para o log ficar mais limpo. Pode voltar para 10000. / [EN] Reduced a bit to keep the log cleaner. Can be reverted to 10000.
    parameter NUM_TESTS = 1000; 
    
    // [PT] Controle da profundidade da memória simulada (Deve ser igual ao ddr_mem.v) / [EN] Simulated memory depth control (Must be equal to ddr_mem.v)
    parameter MEM_DEPTH_LOG2 = 2; 
    localparam DEPTH = 1 << MEM_DEPTH_LOG2;
    // [PT] 8 bancos * Profundidade / [EN] 8 banks * Depth
    localparam TOTAL_POSITIONS = 8 * DEPTH; 

    // =========================================================================
    // [PT] Sinais AXI e Clocks / [EN] AXI Signals and Clocks
    // =========================================================================
    reg ACLK, ARESETn, clk, clk_90, rst_n;
    
    // [PT] Canais AXI / [EN] AXI Channels
    reg  [26:0] AWADDR;  reg         AWVALID; wire        AWREADY;
    reg  [15:0] WDATA;   reg  [1:0]  WSTRB;   reg         WVALID;  wire        WREADY;
    wire [1:0]  BRESP;   wire        BVALID;  reg         BREADY;
    reg  [26:0] ARADDR;  reg         ARVALID; wire        ARREADY;
    wire [15:0] RDATA;   wire [1:0]  RRESP;   wire        RVALID;  reg         RREADY;

    // =========================================================================
    // [PT] Instanciação do Módulo (Device Under Test) / [EN] Module Instantiation (Device Under Test)
    // =========================================================================
    subordinate_module dut (
        .ACLK(ACLK), .ARESETn(ARESETn), .clk(clk), .clk_90(clk_90), .rst_n(rst_n),
        .AWADDR(AWADDR), .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA(WDATA), .WSTRB(WSTRB), .WVALID(WVALID), .WREADY(WREADY),
        .BRESP(BRESP), .BVALID(BVALID), .BREADY(BREADY),
        .ARADDR(ARADDR), .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA(RDATA), .RRESP(RRESP), .RVALID(RVALID), .RREADY(RREADY)
    );

	// =========================================================================
	// [PT] Geração de Clocks (Alinhado ao SDC) / [EN] Clock Generation (Aligned to SDC)
	// =========================================================================
    // [PT] T = 10ns (100 MHz) / [EN] T = 10ns (100 MHz)
	initial begin ACLK = 0; forever #10 ACLK = ~ACLK; end
    // [PT] T = 20ns (50 MHz) / [EN] T = 20ns (50 MHz)
	initial begin clk = 0; forever #20 clk = ~clk; end
    // [PT] T = 20ns, Defasado 90° (5ns) / [EN] T = 20ns, Phase shifted 90° (5ns)
	initial begin clk_90 = 0; #10; forever #20 clk_90 = ~clk_90; end 

    // =========================================================================
    // [PT] Tasks de Transação AXI / [EN] AXI Transaction Tasks
    // =========================================================================
    task axi_write(input [26:0] addr, input [15:0] data);
    begin
        @(posedge ACLK);
		  #1;
        fork
            begin
                AWADDR = addr; AWVALID = 1'b1;
                wait(AWREADY); @(posedge ACLK); AWVALID = 1'b0;
            end
            begin
                WDATA = data; WSTRB = 2'b11; WVALID = 1'b1;
                wait(WREADY); @(posedge ACLK); WVALID = 1'b0; WSTRB = 2'b00;
            end
        join
        BREADY = 1'b1; wait(BVALID); @(posedge ACLK); BREADY = 1'b0;
    end
    endtask

    task axi_read(input [26:0] addr, output [15:0] data);
    begin
        @(posedge ACLK);
		  #1;
        ARADDR = addr; ARVALID = 1'b1;
        wait(ARREADY); @(posedge ACLK); ARVALID = 1'b0;
        
        RREADY = 1'b1; wait(RVALID); data = RDATA;
        @(posedge ACLK); #1; RREADY = 1'b0;
    end
    endtask

    // =========================================================================
    // [PT] Fluxo de Teste Principal / [EN] Main Test Flow
    // =========================================================================
    // [PT] Gabarito / [EN] Golden model reference
    reg [15:0] golden_mem [0:TOTAL_POSITIONS-1]; 
    
    integer i, b, d;
    integer errors;
    integer is_read;
    integer golden_idx;
    integer eff_addr;

    reg [15:0] read_data;
    reg [15:0] write_data;
    
    reg [13:0] r_row;
    reg [2:0]  r_bank;
    reg [9:0]  r_col;
    reg [26:0] axi_addr;

    initial begin
        AWVALID = 0; WVALID = 0; BREADY = 0;
        ARVALID = 0; RREADY = 0; AWADDR = 0; WDATA = 0; ARADDR = 0;
        errors = 0;

        ARESETn = 0; rst_n = 0;
        #100;
        @(posedge ACLK);
        ARESETn = 1; rst_n = 1;

        $display("--------------------------------------------------");
        $display("Aguardando INIT_DONE da memoria...");
        #500; 

        // ---------------------------------------------------------------------
        // [PT] FASE 1: PREENCHIMENTO / [EN] PHASE 1: FILL
        // ---------------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("[FASE 1] Preenchendo %0d posicoes ativas (Valor: 16'h0007)...", TOTAL_POSITIONS);
        
        for (b = 0; b < 8; b = b + 1) begin
            for (d = 0; d < DEPTH; d = d + 1) begin
                r_bank = b;
                r_row  = d >> 7;             
                r_col  = (d & 7'h7F) << 3;   
                axi_addr = {r_row, r_bank, r_col};
                golden_idx = (b * DEPTH) + d;
                
                axi_write(axi_addr, 16'h0007);
                golden_mem[golden_idx] = 16'h0007; 
            end
        end
        $display("[FASE 1] Preenchimento concluido.");

        // ---------------------------------------------------------------------
        // [PT] FASE 2: ACESSOS RANDÔMICOS / [EN] PHASE 2: RANDOM ACCESSES
        // ---------------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("[FASE 2] Iniciando %0d acessos randomicos...", NUM_TESTS);
        
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            is_read = $urandom_range(0, 1);
            
            r_row  = $urandom_range(0, 8191);
            r_bank = $urandom_range(0, 7);
            r_col  = $urandom_range(0, 1023) & 10'h3F8; 
            axi_addr = {r_row, r_bank, r_col};
            
            eff_addr = {r_row, r_col[9:3]} & (DEPTH - 1);
            golden_idx = (r_bank * DEPTH) + eff_addr;
            
            if (is_read == 1) begin
                axi_read(axi_addr, read_data);
                $display("[DEBUG %0d] LEITURA | End: %h | Lido: %h | Gabarito: %h", 
                         i, axi_addr, read_data, golden_mem[golden_idx]);
                
                if (read_data !== golden_mem[golden_idx]) begin
                    $display("  -> [ERRO] Ocorreu uma divergencia neste acesso!");
                    errors = errors + 1;
                end
            end else begin
                write_data = $urandom_range(0, 16'hFFFF);
                $display("[DEBUG %0d] ESCRITA | End: %h | Escrito: %h", 
                         i, axi_addr, write_data);
                
                axi_write(axi_addr, write_data);
                golden_mem[golden_idx] = write_data;
            end
        end

        // ---------------------------------------------------------------------
        // [PT] FASE 3: INJEÇÃO DE ERRO FORÇADA (FAULT INJECTION) / [EN] PHASE 3: FORCED FAULT INJECTION
        // ---------------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("[FASE 3] Iniciando Injecao de Erro Forcada (Fault Injection)...");
        
        // [PT] Escolhe um endereço específico para ser a cobaia / [EN] Chooses a specific address to be the test subject
        r_row  = 13'd42;
        r_bank = 3'd3;
        r_col  = 10'd8; 
        axi_addr = {r_row, r_bank, r_col};
        eff_addr = {r_row, r_col[9:3]} & (DEPTH - 1);
        golden_idx = (r_bank * DEPTH) + eff_addr;

        // [PT] O valor correto que "deveria" ir para a memória / [EN] The correct value that "should" go to the memory
        write_data = 16'hBEEF; 
        
        // [PT] Escreve o dado correto no Gabarito / [EN] Writes the correct data to the Golden Model
        golden_mem[golden_idx] = write_data;

        // [PT] MAS mandamos um LIXO para a memória real através do AXI / [EN] BUT we send GARBAGE to the real memory through AXI
        $display("[INJECAO] Corrompendo dado AXI intencionalmente...");
        $display(" -> Esperado no Gabarito: %h", write_data);
        $display(" -> Enviado para o AXI:   %h", 16'hDEAD);
        axi_write(axi_addr, 16'hDEAD); 
		  repeat(50) @(posedge clk);
        // [PT] Lê a memória para ver se o testbench percebe / [EN] Reads memory to see if testbench notices
        axi_read(axi_addr, read_data);

        // [PT] Lógica de verificação invertida: queremos que ele ache o erro! / [EN] Inverted verification logic: we want it to find the error!
        if (read_data !== golden_mem[golden_idx]) begin
            $display("==================================================");
            $display("[SUCESSO NA INJECAO] Testbench capturou a divergencia!");
            $display(" -> Endereco: %h | Lido: %h | Gabarito: %h", axi_addr, read_data, golden_mem[golden_idx]);
            $display("==================================================");
            // [PT] NOTA: Como esse erro era esperado, NÃO incrementamos a variável 'errors' / [EN] NOTE: Since this error was expected, we DO NOT increment the 'errors' variable
        end else begin
            $display("==================================================");
            $display("[FALHA NA INJECAO] O testbench NAO detectou a divergencia!");
            $display("Isso significa que a sua logica de checagem do testbench ou o modelo estao com problemas.");
            $display("==================================================");
            // [PT] Incrementamos, pois o testbench falhou em achar a falha / [EN] We increment because the testbench failed to find the fault
            errors = errors + 1; 
        end

        // ---------------------------------------------------------------------
        // [PT] RESULTADO FINAL / [EN] FINAL RESULT
        // ---------------------------------------------------------------------
        $display("--------------------------------------------------");
        if (errors == 0) begin
            $display(">>> APROVADO! <<<");
            $display("Transacoes normais OK. Injecao de Erro validada com sucesso.");
        end else begin
            $display(">>> REPROVADO! <<<");
            $display("Foram encontrados %0d erros REAIS na Fase 2 ou Fase 3.", errors);
        end
        $display("--------------------------------------------------");

        $finish;
    end
endmodule