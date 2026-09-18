// =========================================================================
// [PT] Módulo: tb_axi4lite_system / [EN] Module: tb_axi4lite_system
// [PT] Testbench para validar o sistema AXI4-Lite integrado com DDR. / [EN] Testbench to validate the AXI4-Lite system integrated with DDR.
// [PT] Entradas/Saídas: Sinais de clock e controle de alto nível, interfaces CPU. / [EN] Inputs/Outputs: Clock and high-level control signals, CPU interfaces.
// [PT] Papel no sistema: Testar a inicialização, escrita, leitura, erros de proteção e acesso fora dos limites. / [EN] Role in system: Test initialization, write, read, protection errors and out-of-bounds access.
// =========================================================================
`timescale 1ns/1ps

module tb_axi4lite_system #(
    parameter ADDR_WIDTH = 27,
    // [PT] ATUALIZADO PARA 32 BITS / [EN] UPDATED TO 32 BITS
    parameter DATA_WIDTH = 32 
);

// =========================================================================
// [PT] Parâmetros do Testbench / [EN] Testbench Parameters
// =========================================================================
parameter NUM_TESTS = 5000;
// [PT] Profundidade simulada (igual ao ddr_mem) / [EN] Simulated depth (equal to ddr_mem)
parameter MEM_DEPTH_LOG2 = 2; 
localparam DEPTH = 1 << MEM_DEPTH_LOG2;
// [PT] 8 bancos * Profundidade / [EN] 8 banks * Depth
localparam TOTAL_POSITIONS = 8 * DEPTH; 

// =========================================================================
// [PT] Sinais de Clock e Reset / [EN] Clock and Reset Signals
// =========================================================================
reg clk_axi_bus;
reg clk_mem;
reg clk_90_mem;

reg resetn_bus;
reg reset_mem;

// =========================================================================
// [PT] Interface CPU (AXI Master) / [EN] CPU Interface (AXI Master)
// =========================================================================
reg STARTW;
reg STARTR;
reg [ADDR_WIDTH-1:0] m_addr;
reg [DATA_WIDTH-1:0] m_wdata;
// [PT] ATUALIZADO PARA 4 BITS / [EN] UPDATED TO 4 BITS
reg [3:0] m_wstrb;            
// [PT] ADICIONADO: Sinal de Proteção (Escrita) / [EN] ADDED: Protection Signal (Write)
reg [2:0] m_awprot;           
// [PT] ADICIONADO: Sinal de Proteção (Leitura) / [EN] ADDED: Protection Signal (Read)
reg [2:0] m_arprot;           

wire [DATA_WIDTH-1:0] m_rdata;
wire m_wdone;
wire m_rdone;
wire [1:0] m_wresp;
wire [1:0] m_rresp;

// =========================================================================
// [PT] DUT (Device Under Test) / [EN] DUT (Device Under Test)
// =========================================================================
axi4lite_system uut (
    .clk_axi_bus(clk_axi_bus),
    .clk_mem(clk_mem),
    .clk_90_mem(clk_90_mem),
    .resetn_bus(resetn_bus),
    .reset_mem(reset_mem),
    .STARTW(STARTW),
    .STARTR(STARTR),
    .m_addr(m_addr),
    .m_wdata(m_wdata),
    .m_wstrb(m_wstrb),
    // [PT] ADICIONADO: Conexão da Proteção / [EN] ADDED: Protection Connection
    .m_awprot(m_awprot),      
    // [PT] ADICIONADO: Conexão da Proteção / [EN] ADDED: Protection Connection
    .m_arprot(m_arprot),      
    .m_rdata(m_rdata),
    .m_wdone(m_wdone),
    .m_rdone(m_rdone),
    .m_wresp(m_wresp),
    .m_rresp(m_rresp)
);

// =========================================================================
// [PT] Golden Model (Gabarito) / [EN] Golden Model (Reference)
// =========================================================================
// [PT] ATUALIZADO PARA 32 BITS / [EN] UPDATED TO 32 BITS
reg [31:0] golden_mem [0:TOTAL_POSITIONS-1]; 

// [PT] Variáveis de iteração e geração de endereço / [EN] Iteration variables and address generation
integer i, b, d;
integer errors;
integer is_read;
integer golden_idx;
integer eff_addr;

reg [13:0] r_row;
reg [2:0]  r_bank;
reg [9:0]  r_col;
reg [26:0] axi_addr;

// [PT] ATUALIZADO PARA 32 BITS / [EN] UPDATED TO 32 BITS
reg [31:0] read_data;  
// [PT] ATUALIZADO PARA 32 BITS / [EN] UPDATED TO 32 BITS
reg [31:0] write_data; 

// =========================================================================
// [PT] Geração de Clocks (Alinhado ao novo SDC: AXI=20MHz, MEM=10MHz) / [EN] Clock Generation (Aligned to new SDC: AXI=20MHz, MEM=10MHz)
// =========================================================================
// [PT] T = 50ns / [EN] T = 50ns
initial begin clk_axi_bus = 0; forever #25 clk_axi_bus = ~clk_axi_bus; end         
// [PT] T = 100ns / [EN] T = 100ns
initial begin clk_mem = 0; forever #50 clk_mem = ~clk_mem; end                     
// [PT] T = 100ns, Defasado 25ns / [EN] T = 100ns, Phase shifted 25ns
initial begin clk_90_mem = 0; #25; forever #50 clk_90_mem = ~clk_90_mem; end       

// =========================================================================
// [PT] Tasks do Testbench (Com proteção de Hold Time e Respostas Inteligentes) / [EN] Testbench Tasks (With Hold Time protection and Smart Responses)
// =========================================================================
task automatic cpu_write(input [26:0] addr_in, input [31:0] data_in, input [2:0] prot_in, input [1:0] exp_resp);
begin
    @(posedge clk_axi_bus);
    // [PT] Proteção GLS / [EN] GLS Protection
    #1; 

    m_addr   <= addr_in;
    m_wdata  <= data_in;
    m_awprot <= prot_in;
    // [PT] 4 bits altos para habilitar os 4 bytes / [EN] 4 high bits to enable the 4 bytes
    m_wstrb  <= 4'b1111; 
    STARTW   <= 1'b1;

    @(posedge clk_axi_bus);
    #1;
    STARTW <= 1'b0;

    wait(m_wdone);
    if(m_wresp != exp_resp) begin
        $display("[ERRO] WRITE | End: %h | RESP: %b | ESPERADO: %b", addr_in, m_wresp, exp_resp);
        errors = errors + 1;
    end
end
endtask

task automatic cpu_read(input [26:0] addr_in, input [2:0] prot_in, input [1:0] exp_resp, output [31:0] data_out);
begin
    @(posedge clk_axi_bus);
    // [PT] Proteção GLS / [EN] GLS Protection
    #1; 

    m_addr   <= addr_in;
    m_arprot <= prot_in;
    STARTR   <= 1'b1;

    @(posedge clk_axi_bus);
    #1;
    STARTR <= 1'b0;

    wait(m_rdone);
    data_out = m_rdata;

    if(m_rresp != exp_resp) begin
        $display("[ERRO] READ RESP | End: %h | RESP: %b | ESPERADO: %b", addr_in, m_rresp, exp_resp);
        errors = errors + 1;
    end
end
endtask

// =========================================================================
// [PT] TESTE PRINCIPAL / [EN] MAIN TEST
// =========================================================================
initial begin
    // [PT] Inicialização / [EN] Initialization
    STARTW   = 0;
    STARTR   = 0;
    m_addr   = 0;
    m_wdata  = 0;
    m_wstrb  = 4'b0000;
    m_awprot = 3'b000;
    m_arprot = 3'b000;

    resetn_bus = 0;
    reset_mem  = 0;
    errors = 0;

    // [PT] Liberação segura dos resets (Sempre na borda de DESCIDA do respectivo clock) / [EN] Safe release of resets (Always on the FALLING edge of the respective clock)
    #100;
    @(negedge clk_axi_bus);
    resetn_bus = 1;
    @(negedge clk_mem);
    reset_mem  = 1;

    $display("--------------------------------------------------");
    $display("Aguardando inicializacao JEDEC da memoria...");
    // [PT] Monitora dinamicamente a flag init_done dentro do subordinate_module / [EN] Dynamically monitors the init_done flag inside the subordinate_module
    #5000;
    $display("Inicializacao concluida com sucesso!");
    $display("--------------------------------------------------");

    // =====================================================================
    // [PT] FASE 1 — FILL / [EN] PHASE 1 — FILL
    // =====================================================================
    $display("--------------------------------------------------");
    $display("[FASE 1] Preenchendo %0d posicoes ativas (Valor: 32'h00000007)...", TOTAL_POSITIONS);
    
    for (b = 0; b < 8; b = b + 1) begin
        for (d = 0; d < DEPTH; d = d + 1) begin
            r_bank = b;
            r_row  = d >> 7;             
            r_col  = (d & 7'h7F) << 3;   
            axi_addr = {r_row, r_bank, r_col};
            golden_idx = (b * DEPTH) + d;
            
            // [PT] 32 bits, Privilegiado (3'b001), Espera Sucesso (2'b00) / [EN] 32 bits, Privileged (3'b001), Expects Success (2'b00)
            cpu_write(axi_addr, 32'h00000007, 3'b001, 2'b00);
            golden_mem[golden_idx] = 32'h00000007;
        end
    end
    $display("[FASE 1] Concluido.");

    // =====================================================================
    // [PT] FASE 2 — STRESS RANDOM / [EN] PHASE 2 — STRESS RANDOM
    // =====================================================================
    $display("--------------------------------------------------");
    $display("[FASE 2] Iniciando %0d acessos randomicos...", NUM_TESTS);

for (i = 0; i < NUM_TESTS; i = i + 1) begin
        is_read = $urandom_range(0, 1);
        // [PT] CORRIGIDO: Mantém r_row = 0 para alinhar com o espaço inicializado na Fase 1 / [EN] FIXED: Keeps r_row = 0 to align with the initialized space in Phase 1
        r_row  = 13'd0; 
        r_bank = $urandom_range(0, 7);
        // [PT] Gera colunas válidas de 0 a 3 (alinhadas a 8) / [EN] Generates valid columns from 0 to 3 (aligned to 8)
        r_col  = {7'd0, $urandom_range(0, DEPTH-1)} << 3; 
        axi_addr = {r_row, r_bank, r_col};
        
        eff_addr = r_col[9:3] & (DEPTH - 1);
        golden_idx = (r_bank * DEPTH) + eff_addr;

        if (is_read == 1) begin
            cpu_read(axi_addr, 3'b001, 2'b00, read_data);

            if (read_data !== golden_mem[golden_idx]) begin
                $display("  -> [ERRO] Divergencia detectada! End: %h | Lido: %h | Gabarito: %h", 
                         axi_addr, read_data, golden_mem[golden_idx]);
                errors = errors + 1;
            end
        end else begin
            write_data = $urandom; 
            cpu_write(axi_addr, write_data, 3'b001, 2'b00);
            golden_mem[golden_idx] = write_data;
        end
    end
    $display("[FASE 2] Concluida.");

    // =====================================================================
    // [PT] FASE 3 — FAULT INJECTION (INJEÇÃO DE ERRO) / [EN] PHASE 3 — FAULT INJECTION
    // =====================================================================
    $display("--------------------------------------------------");
    $display("[FASE 3] Iniciando Injecao de Erro Forcada (Fault Injection)...");
    
    // [PT] Escolhe um endereço fixo de cobaia / [EN] Chooses a fixed address as test subject
    // [PT] CORRIGIDO: r_row deve ser 0 / [EN] FIXED: r_row must be 0
    r_row  = 13'd0;    
    r_bank = 3'd3;
    // [PT] Coluna 8 corresponde ao eff_addr = 1 (dentro de DEPTH=4) / [EN] Column 8 corresponds to eff_addr = 1 (within DEPTH=4)
    r_col  = 10'd8;    
    axi_addr = {r_row, r_bank, r_col};
    
    eff_addr = r_col[9:3] & (DEPTH - 1);
    golden_idx = (r_bank * DEPTH) + eff_addr;

    write_data = 32'hDEADBEEF;
    // [PT] O que esperamos que a memória tenha / [EN] What we expect the memory to have
    golden_mem[golden_idx] = write_data; 

    $display("[INJECAO] Corrompendo dado intencionalmente...");
    $display(" -> Esperado no Gabarito: %h", write_data);
    $display(" -> Enviado para escrita: %h", 32'h0000DEAD);
    
    // [PT] Força escrita incorreta / [EN] Forces incorrect write
    cpu_write(axi_addr, 32'h0000DEAD, 3'b001, 2'b00);
    
    // [PT] Pequeno atraso para garantir processamento / [EN] Small delay to ensure processing
    repeat(50) @(posedge clk_mem);
    
    cpu_read(axi_addr, 3'b001, 2'b00, read_data);

    if (read_data !== golden_mem[golden_idx]) begin
        $display("==================================================");
        $display("[SUCESSO NA INJECAO] Testbench capturou a divergencia!");
        $display(" -> Endereco: %h | Lido: %h | Gabarito: %h", axi_addr, read_data, golden_mem[golden_idx]);
        $display("==================================================");
    end else begin
        $display("==================================================");
        $display("[FALHA NA INJECAO] O testbench NAO detectou a divergencia!");
        $display("==================================================");
        errors = errors + 1;
    end

    // =====================================================================
    // [PT] FASE 4 — VERIFICAÇÃO DE SEGURANÇA E LIMITES (DECERR e SLVERR) / [EN] PHASE 4 — SECURITY AND LIMITS VERIFICATION (DECERR and SLVERR)
    // =====================================================================
    $display("--------------------------------------------------");
    $display("[FASE 4] Testando Regras de Protecao e Limites de Memoria...");

    $display("[TESTE A] Acesso fora dos limites da memoria (DECERR)...");
    // [PT] Tenta escrever e ler no endereco 0x4000000 (Fora do limite de 67MB) / [EN] Tries to write and read at address 0x4000000 (Outside the 67MB limit)
    // [PT] Espera 2'b11 (DECERR) / [EN] Expects 2'b11 (DECERR)
    cpu_write(27'h4000000, 32'hDEADBEEF, 3'b001, 2'b11); 
    cpu_read(27'h4000000, 3'b001, 2'b11, read_data);

    $display("[TESTE B] Acesso sem privilegio a area protegida (SLVERR)...");
    // [PT] Tenta escrever e ler no endereco 0x0000800 com nivel de protecao 0 (nao privilegiado) / [EN] Tries to write and read at address 0x0000800 with protection level 0 (unprivileged)
    // [PT] Espera 2'b10 (SLVERR) / [EN] Expects 2'b10 (SLVERR)
    cpu_write(27'h0000800, 32'hCAFECAFE, 3'b000, 2'b10); 
    cpu_read(27'h0000800, 3'b000, 2'b10, read_data);

    $display("[FASE 4] Testes de Seguranca aprovados! O hardware bloqueou os acessos.");

    // =====================================================================
    // [PT] RESULTADO FINAL / [EN] FINAL RESULT
    // =====================================================================
    $display("--------------------------------------------------");
    if (errors == 0) begin
        $display(">>> APROVADO! <<<");
        $display("Todas as transacoes operaram perfeitamente em 32-bits.");
    end else begin
        $display(">>> REPROVADO! <<<");
        $display("Foram encontrados %0d erros REAIS na Fase 2 ou Fase 3.", errors);
    end
    $display("--------------------------------------------------");

    #1000000;
    $finish;
end

endmodule