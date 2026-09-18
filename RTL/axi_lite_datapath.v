// [PT] Módulo de datapath do AXI-Lite. Responsável por armazenar endereços, dados e sinais de controle. / [EN] AXI-Lite datapath module. Responsible for storing addresses, data, and control signals.
// [PT] Entradas e saídas de interface com o AXI-Lite e FSM, além da interface com a memória. / [EN] Inputs and outputs for AXI-Lite and FSM interface, as well as the memory interface.
module axi_lite_datapath (
    input          ACLK,
    input          ARESETn,

    // [PT] Sinais de Controle (da FSM) / [EN] Control Signals (from FSM)
    input          latch_aw,
    input          latch_w,
    input          latch_ar,
    input          latch_r,
    input          sel_read,
    
    // [PT] Interface AXI-Lite (Sinais de Dado e Proteção) / [EN] AXI-Lite Interface (Data and Protection Signals)
    input  [26:0]  AWADDR,
    input  [2:0]   AWPROT,
    input  [31:0]  WDATA,
    input  [26:0]  ARADDR,
    input  [2:0]   ARPROT,
    input  [3:0]   WSTRB,
    
    output [31:0]  RDATA,
    output reg [1:0] BRESP,
    output reg [1:0] RRESP,
    
    // [PT] Sinais de Erro para a FSM / [EN] Error Signals for the FSM
    output         error_write,
    output         error_read,
    
    // [PT] Interface com a Memória / [EN] Memory Interface
    input  [31:0]  cpu_rdata,
    output [26:0]  cpu_addr,
    output [31:0]  cpu_wdata,
    output [3:0]   cpu_wstrb
);

    // [PT] Registradores para armazenar endereços e dados / [EN] Registers for storing addresses and data
    reg [26:0] reg_awaddr, reg_araddr;
    reg [31:0] reg_wdata;
    reg [31:0] reg_rdata;
    reg [3:0]  reg_wstrb;

    // [PT] <-- CORREÇÃO: Limite ampliado para permitir o teste de estresse / [EN] <-- CORRECTION: Increased limit to allow stress testing
    localparam ADDR_MAX = 27'h3FFFFFF;          // [PT] Fim da memória emulada (67 MB) / [EN] End of emulated memory (67 MB)
    localparam PRIV_REGION_START = 27'h0000800; // [PT] Início da região protegida / [EN] Start of protected region

    // [PT] Sinaliza para a FSM se ocorreu algum erro na transação latcheada / [EN] Signals the FSM if an error occurred in the latched transaction
    assign error_write = (BRESP != 2'b00);
    assign error_read  = (RRESP != 2'b00);

    // [PT] Bloco procedural principal para latch de sinais e respostas / [EN] Main procedural block for latching signals and responses
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            // [PT] Reset síncrono negativo / [EN] Active-low synchronous reset
            reg_araddr <= 0;
            reg_awaddr <= 0;
            reg_wdata  <= 0;
            reg_rdata  <= 32'd0;
            reg_wstrb  <= 4'b0;
            BRESP      <= 2'b00;
            RRESP      <= 2'b00;
        end else begin
            if (latch_aw) begin
                reg_awaddr <= AWADDR;
                // [PT] Lógica de Proteção e Limite (Escrita) / [EN] Protection and Boundary Logic (Write)
                if (AWADDR > ADDR_MAX)
                    BRESP <= 2'b11; // [PT] DECERR (Fora da memória) / [EN] DECERR (Out of memory bounds)
                else if (AWADDR >= PRIV_REGION_START && AWPROT[0] == 1'b0)
                    BRESP <= 2'b10; // [PT] SLVERR (Violação de Privilégio) / [EN] SLVERR (Privilege Violation)
                else
                    BRESP <= 2'b00; // [PT] OKAY / [EN] OKAY
            end
            
            if (latch_ar) begin
                reg_araddr <= ARADDR;
                // [PT] Lógica de Proteção e Limite (Leitura) / [EN] Protection and Boundary Logic (Read)
                if (ARADDR > ADDR_MAX)
                    RRESP <= 2'b11; // [PT] DECERR (Fora da memória) / [EN] DECERR (Out of memory bounds)
                else if (ARADDR >= PRIV_REGION_START && ARPROT[0] == 1'b0)
                    RRESP <= 2'b10; // [PT] SLVERR (Violação de Privilégio) / [EN] SLVERR (Privilege Violation)
                else
                    RRESP <= 2'b00; // [PT] OKAY / [EN] OKAY
            end
            
            if (latch_w) begin
                reg_wdata <= WDATA;
                reg_wstrb <= WSTRB;
            end
            
            if (latch_r) reg_rdata <= cpu_rdata;
        end
    end

    // [PT] Atribuições contínuas das saídas baseadas nos registradores latcheados / [EN] Continuous assignments for outputs based on latched registers
    assign RDATA = reg_rdata;
    assign cpu_addr  = (sel_read) ? reg_araddr : reg_awaddr;
    assign cpu_wdata = reg_wdata;
    assign cpu_wstrb = reg_wstrb;
endmodule