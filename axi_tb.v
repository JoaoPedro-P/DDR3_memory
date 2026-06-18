/*
 * module: axi_tb
 * -----------------
 * PT: Testbench do Sistema AXI-DDR3 (Golden Model / Scoreboard com Injeção de Falha).
 * Este módulo realiza um teste de estresse avançado e valida a própria infraestrutura de teste.
 * * Fluxo de Teste:
 * 1. Inicialização: Aguarda o controlador completar o boot JEDEC (init_done).
 * 2. Preenchimento (Fill): Escreve o valor 7 em TODAS as posições emuladas da memória.
 * 3. Estresse Intercalado: Realiza transações randômicas de Leitura/Escrita (Fase 2).
 * 4. Injeção de Erro (Fault Injection): Força uma gravação corrompida para garantir
 * que a lógica de comparação do testbench está operando e pegando falhas (Fase 3).
 */
`timescale 1ns/1ps

module axi_tb;
    // =========================================================================
    // Parâmetros do Testbench
    // =========================================================================
    parameter FREQ = 100;
    parameter NUM_TESTS = 1000; // Reduzido um pouco para o log ficar mais limpo. Pode voltar para 10000.
    
    // PT: Controle da profundidade da memória simulada (Deve ser igual ao ddr_mem.v)
    parameter MEM_DEPTH_LOG2 = 8; 
    localparam DEPTH = 1 << MEM_DEPTH_LOG2;
    localparam TOTAL_POSITIONS = 8 * DEPTH; // 8 bancos * Profundidade

    // =========================================================================
    // Sinais AXI e Clocks
    // =========================================================================
    reg ACLK, ARESETn, clk, clk_90, rst_n;
    
    // Canais AXI
    reg  [26:0] AWADDR;  reg         AWVALID; wire        AWREADY;
    reg  [15:0] WDATA;   reg  [1:0]  WSTRB;   reg         WVALID;  wire        WREADY;
    wire [1:0]  BRESP;   wire        BVALID;  reg         BREADY;
    reg  [26:0] ARADDR;  reg         ARVALID; wire        ARREADY;
    wire [15:0] RDATA;   wire [1:0]  RRESP;   wire        RVALID;  reg         RREADY;

    // =========================================================================
    // Instanciação do Módulo (Device Under Test)
    // =========================================================================
    subordinate_module #(.freq(FREQ)) dut (
        .ACLK(ACLK), .ARESETn(ARESETn), .clk(clk), .clk_90(clk_90), .rst_n(rst_n),
        .AWADDR(AWADDR), .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA(WDATA), .WSTRB(WSTRB), .WVALID(WVALID), .WREADY(WREADY),
        .BRESP(BRESP), .BVALID(BVALID), .BREADY(BREADY),
        .ARADDR(ARADDR), .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA(RDATA), .RRESP(RRESP), .RVALID(RVALID), .RREADY(RREADY)
    );

    // =========================================================================
    // Geração de Clocks
    // =========================================================================
    initial begin ACLK = 0; forever #5 ACLK = ~ACLK; end
    initial begin clk = 0; forever #5 clk = ~clk; end
    initial begin clk_90 = 0; #2.5; forever #5 clk_90 = ~clk_90; end

    // =========================================================================
    // Tasks de Transação AXI
    // =========================================================================
    task axi_write(input [26:0] addr, input [15:0] data);
    begin
        @(posedge ACLK);
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
        ARADDR = addr; ARVALID = 1'b1;
        wait(ARREADY); @(posedge ACLK); ARVALID = 1'b0;
        
        RREADY = 1'b1; wait(RVALID); data = RDATA;
        @(posedge ACLK); RREADY = 1'b0;
    end
    endtask

    // =========================================================================
    // Fluxo de Teste Principal
    // =========================================================================
    reg [15:0] golden_mem [0:TOTAL_POSITIONS-1]; // Gabarito
    
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
        // FASE 1: PREENCHIMENTO
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
        // FASE 2: ACESSOS RANDÔMICOS
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
        // FASE 3: INJEÇÃO DE ERRO FORÇADA (FAULT INJECTION)
        // ---------------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("[FASE 3] Iniciando Injecao de Erro Forcada (Fault Injection)...");
        
        // Escolhe um endereço específico para ser a cobaia
        r_row  = 13'd42;
        r_bank = 3'd3;
        r_col  = 10'd8; 
        axi_addr = {r_row, r_bank, r_col};
        eff_addr = {r_row, r_col[9:3]} & (DEPTH - 1);
        golden_idx = (r_bank * DEPTH) + eff_addr;

        // O valor correto que "deveria" ir para a memória
        write_data = 16'hBEEF; 
        
        // Escreve o dado correto no Gabarito
        golden_mem[golden_idx] = write_data;

        // MAS mandamos um LIXO para a memória real através do AXI
        $display("[INJECAO] Corrompendo dado AXI intencionalmente...");
        $display(" -> Esperado no Gabarito: %h", write_data);
        $display(" -> Enviado para o AXI:   %h", 16'hDEAD);
        axi_write(axi_addr, 16'hDEAD); 
		  repeat(50) @(posedge clk);
        // Lê a memória para ver se o testbench percebe
        axi_read(axi_addr, read_data);

        // Lógica de verificação invertida: queremos que ele ache o erro!
        if (read_data !== golden_mem[golden_idx]) begin
            $display("==================================================");
            $display("[SUCESSO NA INJECAO] Testbench capturou a divergencia!");
            $display(" -> Endereco: %h | Lido: %h | Gabarito: %h", axi_addr, read_data, golden_mem[golden_idx]);
            $display("==================================================");
            // NOTA: Como esse erro era esperado, NÃO incrementamos a variável 'errors'
        end else begin
            $display("==================================================");
            $display("[FALHA NA INJECAO] O testbench NAO detectou a divergencia!");
            $display("Isso significa que a sua logica de checagem do testbench ou o modelo estao com problemas.");
            $display("==================================================");
            errors = errors + 1; // Incrementamos, pois o testbench falhou em achar a falha
        end

        // ---------------------------------------------------------------------
        // RESULTADO FINAL
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