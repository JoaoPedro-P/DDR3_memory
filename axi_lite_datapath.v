/*
 * module: axi_lite_datapath
 * -----------------
 * PT: Subsistema de dados do controlador AXI-Lite. 
 *     Este módulo é responsável por:
 *     1. Registrar endereços (AWADDR/ARADDR) e dados (WDATA) para garantir estabilidade.
 *     2. Multiplexar o endereço (cpu_addr) que será enviado ao core da memória,
 *        selecionando entre o canal de leitura ou escrita com base no controle da FSM.
 *     3. Capturar o dado lido da memória (cpu_rdata) no momento exato e mantê-lo
 *        estável para o barramento AXI (RDATA).
 *
 * EN: Data subsystem of the AXI-Lite controller. 
 *     This module is responsible for:
 *     1. Registering addresses (AWADDR/ARADDR) and data (WDATA) to ensure stability.
 *     2. Multiplexing the address (cpu_addr) to be sent to the memory core,
 *        selecting between the read or write channel based on FSM control.
 *     3. Capturing the read data from memory (cpu_rdata) at the exact moment and 
 *        keeping it stable for the AXI bus (RDATA).
 */
module axi_lite_datapath (
    // =========================================================================
    // Clocks e Resets | Clocks and Resets
    // =========================================================================
    input          ACLK,
    input          ARESETn,

    // =========================================================================
    // Sinais de Controle (da FSM) | Control Signals (from FSM)
    // =========================================================================
    input          latch_aw,   // PT: Habilita registro do AWADDR. | EN: Enable AWADDR register.
    input          latch_w,    // PT: Habilita registro do WDATA/WSTRB. | EN: Enable WDATA/WSTRB register.
    input          latch_ar,   // PT: Habilita registro do ARADDR. | EN: Enable ARADDR register.
	 input          latch_r,    // PT: Habilita captura do dado lido. | EN: Enable read data capture.
    input          sel_read,   // PT: 1=Usa ARADDR, 0=Usa AWADDR. | EN: 1=Use ARADDR, 0=Use AWADDR.
    
    // =========================================================================
    // Interface AXI-Lite (Sinais de Dado) | AXI-Lite Interface (Data Signals)
    // =========================================================================
    input  [26:0]  AWADDR,
    input  [15:0]  WDATA,
    input  [26:0]  ARADDR,
	 input  [1:0]   WSTRB,
    output [15:0]  RDATA,      // PT: Saída p/ barramento AXI. | EN: Output to AXI bus.
    output [1:0]   BRESP,      // PT: Resposta de escrita. | EN: Write response.
    output [1:0]   RRESP,      // PT: Resposta de leitura. | EN: Read response.
    
    // =========================================================================
    // Interface com a Memória (Lado Físico) | Memory Interface (Physical Side)
    // =========================================================================
    input  [15:0]  cpu_rdata,  // PT: Dado bruto vindo da memória. | EN: Raw data from memory.
    output [26:0]  cpu_addr,   // PT: Endereço p/ o core DDR3. | EN: Address to DDR3 core.
    output [15:0]  cpu_wdata,  // PT: Dado p/ o core DDR3. | EN: Data to DDR3 core.
	 output [1:0]   cpu_wstrb   // PT: Strobes p/ o core DDR3. | EN: Strobes to DDR3 core.
);


    reg [26:0] reg_awaddr, reg_araddr;
    reg [15:0] reg_wdata;
	 reg [15:0] reg_rdata;
	 reg [1:0]  reg_wstrb;

always@(posedge ACLK or negedge ARESETn) begin
        if(!ARESETn) begin
            reg_araddr <= 0;
            reg_awaddr <= 0;
            reg_wdata  <= 0;
            reg_rdata  <= 16'd0; // Inicializando o registrador rdata
				reg_wstrb <= 2'b0;
        end else begin
            if(latch_aw) reg_awaddr <= AWADDR;
            if(latch_ar) reg_araddr <= ARADDR;
            if(latch_w) begin
					reg_wdata  <= WDATA;
					reg_wstrb  <= WSTRB;
				end
            if(latch_r)  reg_rdata  <= cpu_rdata;
        end
    end

    assign BRESP = 2'b00;
    assign RRESP = 2'b00;
    assign RDATA = reg_rdata;
    
    // Agora o MUX usa um seletor que a FSM mantém estável
    assign cpu_addr  = (sel_read) ? reg_araddr : reg_awaddr;
    assign cpu_wdata = reg_wdata;
	 assign cpu_wstrb = reg_wstrb;
endmodule