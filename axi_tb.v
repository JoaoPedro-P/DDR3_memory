/*
 * module: axi_tb
 * -----------------
 * PT: Testbench do Sistema AXI-DDR3.
 *     Este módulo emula um processador (Mestre AXI-Lite) para validar o 
 *     comportamento do controlador de memória. Ele realiza uma sequência de 
 *     operações de escrita e leitura, verificando se os dados retornados 
 *     são idênticos aos enviados originalmente.
 * 
 *     Fluxo de Teste:
 *     1. Inicialização: Aguarda o controlador completar o boot JEDEC (init_done).
 *     2. Escrita (Stress Test): Realiza 250 escritas em endereços aleatórios, 
 *        garantindo que cada acesso respeite o alinhamento de 64 bits exigido 
 *        pelo core interno.
 *     3. Leitura e Verificação: Lê os mesmos 250 endereços e compara com um 
 *        "gabarito" (array test_data).
 *     4. Diagnóstico: Reporta o sucesso absoluto ou o número de falhas.
 *
 * EN: AXI-DDR3 System Testbench.
 *     This module emulates a processor (AXI-Lite Master) to validate the 
 *     memory controller's behavior. It performs a sequence of write and 
 *     read operations, verifying if the returned data matches the original data.
 * 
 *     Test Flow:
 *     1. Initialization: Waits for the controller to finish JEDEC boot (init_done).
 *     2. Write (Stress Test): Executes 250 writes to random addresses, 
 *        ensuring each access respects the 64-bit alignment required by 
 *        the internal core.
 *     3. Read and Verification: Reads the same 250 addresses and compares 
 *        them with a "golden" copy (test_data array).
 *     4. Diagnostics: Reports absolute success or the number of failures.
 */
module axi_tb;


    // =========================================================================
    // Parâmetros e Sinais
    // =========================================================================
    parameter FREQ = 100;
    
    // Clocks e Resets
    reg ACLK;
    reg ARESETn;
    reg clk;
    reg clk_90;
    reg rst_n;

    // Canal AW
    reg  [26:0] AWADDR;
    reg         AWVALID;
    wire        AWREADY;

    // Canal W
    reg  [15:0] WDATA;
	 reg  [1:0]  WSTRB;
    reg         WVALID;
    wire        WREADY;

    // Canal B
    wire [1:0]  BRESP;
    wire        BVALID;
    reg         BREADY;

    // Canal AR
    reg  [26:0] ARADDR;
    reg         ARVALID;
    wire        ARREADY;

    // Canal R
    wire [15:0] RDATA;
    wire [1:0]  RRESP;
    wire        RVALID;
    reg         RREADY;

    // =========================================================================
    // Instanciação do Módulo (Device Under Test)
    // =========================================================================
    subordinate_module #(.freq(FREQ)) dut (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .clk(clk),
        .clk_90(clk_90),
        .rst_n(rst_n),
        
        .AWADDR(AWADDR),
        .AWVALID(AWVALID),
        .AWREADY(AWREADY),
        
        .WDATA(WDATA),
		  .WSTRB(WSTRB),
        .WVALID(WVALID),
        .WREADY(WREADY),
        
        .BRESP(BRESP),
        .BVALID(BVALID),
        .BREADY(BREADY),
        
        .ARADDR(ARADDR),
        .ARVALID(ARVALID),
        .ARREADY(ARREADY),
        
        .RDATA(RDATA),
        .RRESP(RRESP),
        .RVALID(RVALID),
        .RREADY(RREADY)
    );

    // =========================================================================
    // Geração de Clocks
    // =========================================================================
    // ACLK (AXI Clock) - Ex: 50 MHz (Período 20ns)
    initial begin ACLK = 0; forever #5 ACLK = ~ACLK; end
    
    // clk (Memory Clock) - Ex: 100 MHz (Período 10ns)
    initial begin clk = 0; forever #5 clk = ~clk; end
    
    // clk_90 (Memory Clock defasado 90 graus)
    // clk_90 (Memory Clock defasado 90 graus)
    initial begin clk_90 = 0; #2.5; forever #5 clk_90 = ~clk_90; end

    // =========================================================================
    // Tasks de Transação AXI
    // =========================================================================
    task axi_write(input [26:0] addr, input [15:0] data);
    begin
        // Alinha com a borda do clock
        @(posedge ACLK);
        
        // Dispara Endereço e Dado em paralelo (Regra do AXI)
        fork
            begin
                AWADDR = addr;
                AWVALID = 1'b1;
                wait(AWREADY);
                @(posedge ACLK);
                AWVALID = 1'b0;
            end
				begin
                WDATA = data;
                WSTRB = 2'b11;   // <--- Avisa a memória para gravar os dois bytes
                WVALID = 1'b1;
                wait(WREADY);
                @(posedge ACLK);
                WVALID = 1'b0;
                WSTRB = 2'b00;   // (Opcional) Limpa o barramento
            end
        join

        // Aguarda a resposta (BRESP)
        BREADY = 1'b1;
        wait(BVALID);
        @(posedge ACLK);
        BREADY = 1'b0;
    end
    endtask

    task axi_read(input [26:0] addr, output [15:0] data);
    begin
        @(posedge ACLK);
        
        // Envia o Endereço
        ARADDR = addr;
        ARVALID = 1'b1;
        wait(ARREADY);
        @(posedge ACLK);
        ARVALID = 1'b0;

        // Aguarda e captura o Dado
        RREADY = 1'b1;
        wait(RVALID);
        data = RDATA;
        @(posedge ACLK);
        RREADY = 1'b0;
    end
    endtask

    // =========================================================================
    // Fluxo de Teste Autoverificável
    // =========================================================================
    integer i;
    integer errors;
    reg [15:0] read_data;
    
    // Arrays para guardar o gabarito do teste
    reg [26:0] test_addr [0:249];
    reg [15:0] test_data [0:249];

    initial begin
        // Configuração inicial para salvar waveforms (Opcional)
        $dumpfile("axi_test.vcd");
        $dumpvars(0, axi_tb);

        // Inicializa os sinais
        AWVALID = 0; WVALID = 0; BREADY = 0;
        ARVALID = 0; RREADY = 0;
        AWADDR = 0; WDATA = 0; ARADDR = 0;
        errors = 0;

        // Aplica o Reset
        ARESETn = 0; rst_n = 0;
        #100;
        @(posedge ACLK);
        ARESETn = 1; rst_n = 1;

        $display("--------------------------------------------------");
        $display("Iniciando simulacao... Aguardando FSM sair de IDLE e INIT_DONE da memoria.");
        
        // Damos um pequeno tempo. Como fizemos a FSM segurar tudo ate o init_done ser 1,
        // o AXI ja vai fazer o trabalho duro pra gente.
        #500;

        // 1. Fase de Escrita
        $display("--------------------------------------------------");
        $display("[FASE 1] Iniciando 250 escritas aleatorias no AXI...");
		  for (i = 0; i < 250; i = i + 1) begin
            // Multiplicando por 8 garantimos que cada teste use um bloco 64-bits único
            test_addr[i] = i * 8; 
            test_data[i] = $urandom_range(0, 16'hFFFF);
            
            axi_write(test_addr[i], test_data[i]);
        end
        $display("[FASE 1] Escritas concluidas.");

        // 2. Fase de Leitura e Verificação
        $display("--------------------------------------------------");
        $display("[FASE 2] Lendo os 250 enderecos e validando dados...");
        for (i = 0; i < 250; i = i + 1) begin
            axi_read(test_addr[i], read_data);
            
            if (read_data !== test_data[i]) begin
                $display("ERRO no ind %0d | End: %h | Esperado: %h | Lido: %h", i, test_addr[i], test_data[i], read_data);
                errors = errors + 1;
            end
        end

        // 3. Resultado Final
        $display("--------------------------------------------------");
        if (errors == 0) begin
            $display(">>> SUCESSO ABSOLUTO! <<<");
            $display("Todas as 500 transacoes (250 WR / 250 RD) passaram sem erros.");
        end else begin
            $display(">>> FALHA NO TESTE! <<<");
            $display("Encontrados %0d erros de corrupcao ou perda de dados.", errors);
        end
        $display("--------------------------------------------------");

        $finish;
    end

endmodule