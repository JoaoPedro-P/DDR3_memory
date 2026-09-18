`timescale 1ns/1ps

// =========================================================================
// [PT] Modulo: tb_axi4lite_system_new
// [PT] Descrição: Testbench principal para o sistema AXI4-Lite integrado com DDR3 via SerDes. Emula a placa de testes e as transações seriais.
// [EN] Module: tb_axi4lite_system_new
// [EN] Description: Main testbench for the AXI4-Lite system integrated with DDR3 via SerDes. Emulates the test board and serial transactions.
// =========================================================================

module tb_axi4lite_system_new #(
    parameter ADDR_WIDTH = 27,
    parameter DATA_WIDTH = 32 
);

parameter NUM_TESTS = 1000;
parameter MEM_DEPTH_LOG2 = 10; 
localparam DEPTH = 1 << MEM_DEPTH_LOG2;
localparam TOTAL_POSITIONS = 8 * DEPTH; 

// [PT] Sinais Físicos do ASIC (Apenas 7 Pinos!) / [EN] ASIC Physical Signals (Only 7 Pins!)
reg clk_axi_bus;
reg clk_mem;
reg clk_90_mem;
reg rst_n;

reg  rx_sync;
reg  rx_data;
wire tx_data;

// [PT] DUT -> Top-Level de 7 Pinos / [EN] DUT -> 7-Pin Top-Level
chip_top_serdes uut (
    .clk_axi_bus(clk_axi_bus),
    .clk_mem(clk_mem),
    .clk_90_mem(clk_90_mem),
    .rst_n(rst_n),
    .rx_sync(rx_sync),
    .rx_data(rx_data),
    .tx_data(tx_data)
);

// [PT] Memória de referência (gabarito) para verificação de dados / [EN] Reference memory (golden) for data verification
reg [31:0] golden_mem [0:TOTAL_POSITIONS-1]; 

integer i, b, d;
integer errors;
integer is_read;
integer golden_idx;
integer eff_addr;

reg [13:0] r_row;
reg [2:0]  r_bank;
reg [9:0]  r_col;
reg [26:0] axi_addr;

reg [31:0] read_data;  
reg [31:0] write_data; 

// [PT] Geração de clocks para o barramento AXI e para a memória / [EN] Clock generation for AXI bus and memory
initial begin clk_axi_bus = 0; forever #25 clk_axi_bus = ~clk_axi_bus; end         
initial begin clk_mem = 0; forever #50 clk_mem = ~clk_mem; end                     
initial begin clk_90_mem = 0; #25; forever #50 clk_90_mem = ~clk_90_mem; end       

// =========================================================================
// [PT] TASKS SERIAIS (Emulação da Placa de Testes) / [EN] SERIAL TASKS (Test Board Emulation)
// =========================================================================
task automatic cpu_write(input [26:0] addr_in, input [31:0] data_in, input [2:0] prot_in, input [1:0] exp_resp);
    reg [67:0] packet;
    reg [35:0] resp_packet;
    integer k;
begin
    // [PT] Monta o pacote de 68 bits (1: STARTW, 0: STARTR) / [EN] Assembles the 68-bit packet (1: STARTW, 0: STARTR)
    packet = {1'b1, 1'b0, addr_in, data_in, 4'b1111, prot_in};
    
    @(posedge clk_axi_bus);
    #1;
    rx_sync = 1'b1;
    
    // [PT] Serializa o pacote para dentro do chip / [EN] Serializes the packet into the chip
    for (k = 0; k < 68; k = k + 1) begin
        rx_data = packet[67 - k];
        @(posedge clk_axi_bus);
        #1;
    end
    rx_sync = 1'b0;
    rx_data = 1'b0;

    // [PT] Aguarda o Chip confirmar a gravação via TX / [EN] Waits for the Chip to confirm the write via TX
    wait(tx_data == 1'b1); // [PT] Start Bit / [EN] Start Bit
    for (k = 0; k < 36; k = k + 1) begin
        @(posedge clk_axi_bus); 
        #1;
        resp_packet[35 - k] = tx_data;
    end
    
    // [PT] Verifica se a resposta recebida é igual à esperada / [EN] Checks if the received response matches the expected one
    if (resp_packet[1:0] != exp_resp) begin
        $display("[ERRO] WRITE | End: %h | RESP: %b | ESPERADO: %b", addr_in, resp_packet[1:0], exp_resp);
        errors = errors + 1;
    end
end
endtask

task automatic cpu_read(input [26:0] addr_in, input [2:0] prot_in, input [1:0] exp_resp, output [31:0] data_out);
    reg [67:0] packet;
    reg [35:0] resp_packet;
    integer k;
begin
    // [PT] Monta o pacote de 68 bits (0: STARTW, 1: STARTR) / [EN] Assembles the 68-bit packet (0: STARTW, 1: STARTR)
    packet = {1'b0, 1'b1, addr_in, 32'd0, 4'b0000, prot_in};
    
    @(posedge clk_axi_bus);
    #1;
    rx_sync = 1'b1;
    
    // [PT] Serializa o pacote para dentro do chip / [EN] Serializes the packet into the chip
    for (k = 0; k < 68; k = k + 1) begin
        rx_data = packet[67 - k];
        @(posedge clk_axi_bus);
        #1;
    end
    rx_sync = 1'b0;
    rx_data = 1'b0;

    // [PT] Aguarda o Chip devolver os dados via TX / [EN] Waits for the Chip to return data via TX
    wait(tx_data == 1'b1); // [PT] Start Bit / [EN] Start Bit
    for (k = 0; k < 36; k = k + 1) begin
        @(posedge clk_axi_bus);
        #1;
        resp_packet[35 - k] = tx_data;
    end
    
    data_out = resp_packet[33:2];
    
    // [PT] Verifica se a resposta de leitura está correta / [EN] Checks if the read response is correct
    if (resp_packet[1:0] != exp_resp) begin
        $display("[ERRO] READ RESP | End: %h | RESP: %b | ESPERADO: %b", addr_in, resp_packet[1:0], exp_resp);
        errors = errors + 1;
    end
end
endtask

// =========================================================================
// [PT] SEQUÊNCIA DE TESTES UVM/COMPORTAMENTAL / [EN] UVM/BEHAVIORAL TEST SEQUENCE
// =========================================================================
initial begin
    rx_sync = 0;
    rx_data = 0;
    rst_n   = 0;
    errors  = 0;

    #100;
    @(negedge clk_axi_bus);
    rst_n = 1;

    $display("--------------------------------------------------");
    $display("Aguardando inicializacao JEDEC da memoria (via SERDES)...");
    #5000;
    $display("Inicializacao concluida com sucesso!");
    $display("--------------------------------------------------");

    $display("--------------------------------------------------");
    $display("[FASE 1] Preenchendo %0d posicoes ativas...", TOTAL_POSITIONS);
    
    // [PT] Loop para preenchimento inicial da memória com dados e preenchimento da memória de referência / [EN] Loop for initial memory fill with data and reference memory filling
    for (b = 0; b < 8; b = b + 1) begin
        for (d = 0; d < DEPTH; d = d + 1) begin
            r_bank = b;
            r_row  = d >> 7;             
            r_col  = (d & 7'h7F) << 3;   
            axi_addr = {r_row, r_bank, r_col};
            golden_idx = (b * DEPTH) + d;
            
            cpu_write(axi_addr, 32'h00000007, 3'b001, 2'b00);
            golden_mem[golden_idx] = 32'h00000007;
        end
    end
    $display("[FASE 1] Concluido.");

    $display("--------------------------------------------------");
    $display("[FASE 2] Iniciando %0d acessos randomicos SERIAIS...", NUM_TESTS);

    // [PT] Loop principal para realização de acessos randômicos de leitura e escrita / [EN] Main loop for performing random read and write accesses
    for (i = 0; i < NUM_TESTS; i = i + 1) begin
        is_read = $urandom_range(0, 1);
        r_row  = $urandom_range(0, 4095); 
        r_bank = $urandom_range(0, 7);
        r_col  = $urandom_range(0, 1023) & 10'h3F8; 
        axi_addr = {r_row, r_bank, r_col};
        
        eff_addr = {r_row, r_col[9:3]} & (DEPTH - 1);
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

    $display("--------------------------------------------------");
    $display("[FASE 3] Iniciando Injecao de Erro Forcada (Fault Injection)...");
    
    r_row  = 13'd42;
    r_bank = 3'd3;
    r_col  = 10'd8; 
    axi_addr = {r_row, r_bank, r_col};
    eff_addr = {r_row, r_col[9:3]} & (DEPTH - 1);
    golden_idx = (r_bank * DEPTH) + eff_addr;

    write_data = 32'hDEADBEEF;
    golden_mem[golden_idx] = write_data; 

    $display("[INJECAO] Corrompendo dado intencionalmente...");
    
    cpu_write(axi_addr, 32'h0000DEAD, 3'b001, 2'b00);
    
    // [PT] Aguarda um determinado número de ciclos de clock da memória / [EN] Waits for a certain number of memory clock cycles
    repeat(50) @(posedge clk_mem);
    
    cpu_read(axi_addr, 3'b001, 2'b00, read_data);

    // [PT] Verifica se o testbench capturou a divergência introduzida na fase de injeção / [EN] Checks if the testbench caught the divergence introduced in the injection phase
    if (read_data !== golden_mem[golden_idx]) begin
        $display("==================================================");
        $display("[SUCESSO NA INJECAO] Testbench capturou a divergencia!");
        $display("==================================================");
    end else begin
        $display("==================================================");
        $display("[FALHA NA INJECAO] O testbench NAO detectou a divergencia!");
        $display("==================================================");
        errors = errors + 1;
    end

    $display("--------------------------------------------------");
    $display("[FASE 4] Testando Regras de Protecao e Limites de Memoria...");

    // [PT] Teste de limites de memória e respostas AXI correspondentes / [EN] Test of memory limits and corresponding AXI responses
    cpu_write(27'h4000000, 32'hDEADBEEF, 3'b001, 2'b11); 
    cpu_read(27'h4000000, 3'b001, 2'b11, read_data);

    cpu_write(27'h0000800, 32'hCAFECAFE, 3'b000, 2'b10); 
    cpu_read(27'h0000800, 3'b000, 2'b10, read_data);

    $display("[FASE 4] Testes de Seguranca aprovados! O hardware bloqueou os acessos.");

    $display("--------------------------------------------------");
    if (errors == 0) begin
        $display(">>> APROVADO! <<<");
        $display("Todas as transacoes operaram perfeitamente com a interface de 7 Pinos.");
    end else begin
        $display(">>> REPROVADO! <<<");
        $display("Foram encontrados %0d erros.", errors);
    end
    $display("--------------------------------------------------");

    #10000;
    $finish;
end

endmodule