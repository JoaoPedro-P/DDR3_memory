module tb_axi4lite_system #(parameter ADDR_WIDTH = 27,
                            parameter DATA_WIDTH = 16);

reg clk_axi_bus;
reg clk_mem;
reg clk_90_mem;

reg resetn_bus;
reg reset_mem;

// Interface CPU
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

// DUT
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

// Golden model
reg [15:0] golden_mem [0:1023];

// Vars
integer i;
integer errors;
integer is_read;

reg [26:0] addr;
reg [15:0] data;
reg [15:0] read_data;

// Clocks
initial begin clk_axi_bus = 0; forever #5 clk_axi_bus = ~clk_axi_bus; end
initial begin clk_mem = 0; forever #5 clk_mem = ~clk_mem; end
initial begin clk_90_mem = 0; #2.5; forever #5 clk_90_mem = ~clk_90_mem; end

// WRITE
task automatic cpu_write(input [26:0] addr_in, input [15:0] data_in);
begin
    @(posedge clk_axi_bus);

    m_addr  <= addr_in;
    m_wdata <= data_in;
    m_wstrb <= 2'b11;
    STARTW  <= 1'b1;

    @(posedge clk_axi_bus);
    STARTW <= 1'b0;

    wait(m_wdone);

    if(m_wresp != 2'b00) begin
        $display("[ERRO] WRITE | End: %h | RESP: %b", addr_in, m_wresp);
        errors = errors + 1;
    end
end
endtask

// READ
task automatic cpu_read(input [26:0] addr_in, output [15:0] data_out);
begin
    @(posedge clk_axi_bus);

    m_addr <= addr_in;
    STARTR <= 1'b1;

    @(posedge clk_axi_bus);
    STARTR <= 1'b0;

    wait(m_rdone);

    data_out = m_rdata;

    if(m_rresp != 2'b00) begin
        $display("[ERRO] READ RESP | End: %h | RESP: %b", addr_in, m_rresp);
        errors = errors + 1;
    end
end
endtask

//=====================================================
// TESTE PRINCIPAL
//=====================================================

initial begin

    //--------------------------------------------------
    // Inicialização
    //--------------------------------------------------

    STARTW = 0;
    STARTR = 0;
    m_addr = 0;
    m_wdata = 0;
    m_wstrb = 2'b11;

    resetn_bus = 0;
    reset_mem  = 0;

    errors = 0;

    #100;
    resetn_bus = 1;
    reset_mem  = 1;

    $display("--------------------------------------------------");
    $display("Aguardando inicializacao da memoria...");
    $display("--------------------------------------------------");

    #5000;

    //==================================================
    // FASE 1 — FILL
    //==================================================

    $display("--------------------------------------------------");
    $display("[FASE 1] Preenchendo memoria (0x0007)...");
    $display("--------------------------------------------------");

    for(i = 0; i < 512; i = i + 1) begin

        addr = i * 8;
        data = 16'h0007;

        cpu_write(addr, data);

        golden_mem[i] = data;
    end

    $display("[FASE 1] Concluido.");
    $display("--------------------------------------------------");

    //==================================================
    // FASE 2 — STRESS RANDOM
    //==================================================

    $display("--------------------------------------------------");
    $display("[FASE 2] Iniciando acessos randomicos...");
    $display("--------------------------------------------------");

    for(i = 0; i < 1000; i = i + 1) begin

        is_read = $urandom_range(0,1);
        addr = $urandom_range(0,511) * 8;

        if(is_read) begin

            cpu_read(addr, read_data);

            $display("[DEBUG %0d] LEITURA | End: %h | Lido: %h | Esperado: %h",
                     i, addr, read_data, golden_mem[addr >> 3]);

            if(read_data !== golden_mem[addr >> 3]) begin
                $display("  -> [ERRO] Divergencia detectada!");
                errors = errors + 1;
            end

        end else begin

            data = $urandom_range(0,16'hFFFF);

            $display("[DEBUG %0d] ESCRITA | End: %h | Dado: %h",
                     i, addr, data);

            cpu_write(addr, data);

            golden_mem[addr >> 3] = data;
        end
    end

    $display("[FASE 2] Concluida.");
    $display("--------------------------------------------------");

    //==================================================
    // FASE 3 — FAULT INJECTION
    //==================================================

    $display("--------------------------------------------------");
    $display("[FASE 3] Injecao de erro forcada...");
    $display("--------------------------------------------------");

    addr = 27'h0000_00A0;
    data = 16'hBEEF;

    golden_mem[addr >> 3] = data;

    $display("[INJECAO] Escrevendo dado CORROMPIDO no AXI...");
    $display(" -> Esperado (golden): %h", data);
    $display(" -> Enviado (DUT):     %h", 16'hDEAD);

    cpu_write(addr, 16'hDEAD);

    cpu_read(addr, read_data);

    if(read_data !== golden_mem[addr >> 3]) begin

        $display("==================================================");
        $display("[SUCESSO NA INJECAO] Falha detectada corretamente!");
        $display(" -> End: %h | Lido: %h | Esperado: %h",
                 addr, read_data, golden_mem[addr >> 3]);
        $display("==================================================");

    end else begin

        $display("==================================================");
        $display("[FALHA NA INJECAO] Erro NAO detectado!");
        $display("==================================================");

        errors = errors + 1;
    end

    //==================================================
    // RESULTADO FINAL
    //==================================================

    $display("--------------------------------------------------");

    if(errors == 0) begin
        $display(">>> APROVADO! <<<");
        $display("Todas as transacoes passaram com sucesso.");
    end else begin
        $display(">>> REPROVADO! <<<");
        $display("Total de erros: %0d", errors);
    end

    $display("--------------------------------------------------");

    #100;
    $finish;

end


endmodule