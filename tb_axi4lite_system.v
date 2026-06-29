`timescale 1ns/1ps

module tb_axi4lite_system #(
    parameter ADDR_WIDTH = 27,
    parameter DATA_WIDTH = 16
);

// =========================================================================
// Parâmetros do Testbench (Padronizado com axi_tb)
// =========================================================================
parameter NUM_TESTS = 1000;
parameter MEM_DEPTH_LOG2 = 2; // Profundidade simulada (igual ao ddr_mem)
localparam DEPTH = 1 << MEM_DEPTH_LOG2;
localparam TOTAL_POSITIONS = 8 * DEPTH; // 8 bancos * Profundidade

// =========================================================================
// Sinais de Clock e Reset
// =========================================================================
reg clk_axi_bus;
reg clk_mem;
reg clk_90_mem;

reg resetn_bus;
reg reset_mem;

// =========================================================================
// Interface CPU (AXI Master)
// =========================================================================
reg STARTW;
reg STARTR;
reg [ADDR_WIDTH-1:0] m_addr;
reg [DATA_WIDTH-1:0] m_wdata;
reg [1:0] m_wstrb;

wire [DATA_WIDTH-1:0] m_rdata;
wire m_wdone;
wire m_rdone;
wire [1:0] m_wresp;
wire [1:0] m_rresp;

// =========================================================================
// DUT (Device Under Test)
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
    .m_rdata(m_rdata),
    .m_wdone(m_wdone),
    .m_rdone(m_rdone),
    .m_wresp(m_wresp),
    .m_rresp(m_rresp)
);

// =========================================================================
// Golden Model (Gabarito)
// =========================================================================
reg [15:0] golden_mem [0:TOTAL_POSITIONS-1];

// Variáveis de iteração e geração de endereço
integer i, b, d;
integer errors;
integer is_read;
integer golden_idx;
integer eff_addr;

reg [13:0] r_row;
reg [2:0]  r_bank;
reg [9:0]  r_col;
reg [26:0] axi_addr;

reg [15:0] read_data;
reg [15:0] write_data;

// =========================================================================
// Geração de Clocks (Alinhado ao novo SDC: AXI=20MHz, MEM=10MHz)
// =========================================================================
initial begin clk_axi_bus = 0; forever #25 clk_axi_bus = ~clk_axi_bus; end         // T = 50ns
initial begin clk_mem = 0; forever #50 clk_mem = ~clk_mem; end                     // T = 100ns
initial begin clk_90_mem = 0; #25; forever #50 clk_90_mem = ~clk_90_mem; end       // T = 100ns, Defasado 25ns

// =========================================================================
// Tasks do Testbench (Com proteção de Hold Time para GLS)
// =========================================================================
task automatic cpu_write(input [26:0] addr_in, input [15:0] data_in);
begin
    @(posedge clk_axi_bus);
    #1; // Proteção GLS

    m_addr  <= addr_in;
    m_wdata <= data_in;
    m_wstrb <= 2'b11;
    STARTW  <= 1'b1;

    @(posedge clk_axi_bus);
    #1;
    STARTW <= 1'b0;

    wait(m_wdone);
    if(m_wresp != 2'b00) begin
        $display("[ERRO] WRITE | End: %h | RESP: %b", addr_in, m_wresp);
        errors = errors + 1;
    end
end
endtask

task automatic cpu_read(input [26:0] addr_in, output [15:0] data_out);
begin
    @(posedge clk_axi_bus);
    #1; // Proteção GLS

    m_addr <= addr_in;
    STARTR <= 1'b1;

    @(posedge clk_axi_bus);
    #1;
    STARTR <= 1'b0;

    wait(m_rdone);
    data_out = m_rdata;

    if(m_rresp != 2'b00) begin
        $display("[ERRO] READ RESP | End: %h | RESP: %b", addr_in, m_rresp);
        errors = errors + 1;
    end
end
endtask

// =========================================================================
// TESTE PRINCIPAL
// =========================================================================
initial begin
    // Inicialização
    STARTW = 0;
    STARTR = 0;
    m_addr = 0;
    m_wdata = 0;
    m_wstrb = 2'b00;

    resetn_bus = 0;
    reset_mem  = 0;
    errors = 0;

    // Liberação segura dos resets (Sempre na borda de DESCIDA do respectivo clock)
    #100;
    @(negedge clk_axi_bus);
    resetn_bus = 1;
    @(negedge clk_mem);
    reset_mem  = 1;

    $display("--------------------------------------------------");
    $display("Aguardando inicializacao JEDEC da memoria...");
    // Monitora dinamicamente a flag init_done dentro do subordinate_module
    #5000;
    $display("Inicializacao concluida com sucesso!");
    $display("--------------------------------------------------");

    // =====================================================================
    // FASE 1 — FILL
    // =====================================================================
    $display("--------------------------------------------------");
    $display("[FASE 1] Preenchendo %0d posicoes ativas (Valor: 16'h0007)...", TOTAL_POSITIONS);
    
    for (b = 0; b < 8; b = b + 1) begin
        for (d = 0; d < DEPTH; d = d + 1) begin
            r_bank = b;
            r_row  = d >> 7;             
            r_col  = (d & 7'h7F) << 3;   
            axi_addr = {r_row, r_bank, r_col};
            golden_idx = (b * DEPTH) + d;
            
            cpu_write(axi_addr, 16'h0007);
            golden_mem[golden_idx] = 16'h0007;
        end
    end
    $display("[FASE 1] Concluido.");

    // =====================================================================
    // FASE 2 — STRESS RANDOM
    // =====================================================================
    $display("--------------------------------------------------");
    $display("[FASE 2] Iniciando %0d acessos randomicos...", NUM_TESTS);

    for (i = 0; i < NUM_TESTS; i = i + 1) begin
        is_read = $urandom_range(0, 1);
        r_row  = $urandom_range(0, 8191);
        r_bank = $urandom_range(0, 7);
        r_col  = $urandom_range(0, 1023) & 10'h3F8; // Alinhado a BL8
        axi_addr = {r_row, r_bank, r_col};
        
        eff_addr = {r_row, r_col[9:3]} & (DEPTH - 1);
        golden_idx = (r_bank * DEPTH) + eff_addr;

        if (is_read == 1) begin
            cpu_read(axi_addr, read_data);
            $display("[DEBUG %0d] LEITURA | End: %h | Lido: %h | Gabarito: %h", 
                     i, axi_addr, read_data, golden_mem[golden_idx]);

            if (read_data !== golden_mem[golden_idx]) begin
                $display("  -> [ERRO] Divergencia detectada neste acesso!");
                errors = errors + 1;
            end
        end else begin
            write_data = $urandom_range(0, 16'hFFFF);
            $display("[DEBUG %0d] ESCRITA | End: %h | Escrito: %h", 
                     i, axi_addr, write_data);
                     
            cpu_write(axi_addr, write_data);
            golden_mem[golden_idx] = write_data;
        end
    end
    $display("[FASE 2] Concluida.");

    // =====================================================================
    // FASE 3 — FAULT INJECTION (INJEÇÃO DE ERRO)
    // =====================================================================
    $display("--------------------------------------------------");
    $display("[FASE 3] Iniciando Injecao de Erro Forcada (Fault Injection)...");
    
    // Escolhe um endereço fixo de cobaia
    r_row  = 13'd42;
    r_bank = 3'd3;
    r_col  = 10'd8; 
    axi_addr = {r_row, r_bank, r_col};
    eff_addr = {r_row, r_col[9:3]} & (DEPTH - 1);
    golden_idx = (r_bank * DEPTH) + eff_addr;

    write_data = 16'hBEEF;
    golden_mem[golden_idx] = write_data; // Esperado

    $display("[INJECAO] Corrompendo dado intencionalmente...");
    $display(" -> Esperado no Gabarito: %h", write_data);
    $display(" -> Enviado para escrita: %h", 16'hDEAD);
    
    cpu_write(axi_addr, 16'hDEAD);
    
    // Pequeno atraso para garantir processamento
    repeat(50) @(posedge clk_mem);
    
    cpu_read(axi_addr, read_data);

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
    // RESULTADO FINAL
    // =====================================================================
    $display("--------------------------------------------------");
    if (errors == 0) begin
        $display(">>> APROVADO! <<<");
        $display("Todas as transacoes operaram perfeitamente.");
    end else begin
        $display(">>> REPROVADO! <<<");
        $display("Foram encontrados %0d erros REAIS na Fase 2 ou Fase 3.", errors);
    end
    $display("--------------------------------------------------");

    #100;
    $finish;
end

endmodule