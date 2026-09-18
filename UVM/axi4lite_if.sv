// =====================================================================
// [PT] Arquivo: axi4lite_if.sv / [EN] File: axi4lite_if.sv
// [PT] Descrição: Interface AXI4-Lite contendo os sinais do barramento. / [EN] Description: AXI4-Lite Interface containing the bus signals.
// =====================================================================

interface axi4lite_if(input logic clk_axi_bus, input logic resetn_bus);
    // [PT] Sinais de controle de comando / [EN] Command control signals
    logic        STARTW;
    logic        STARTR;
    
    // [PT] Sinais de requisição (endereço, dados, strobe, proteção) / [EN] Request signals (address, data, strobe, protection)
    logic [26:0] m_addr;
    logic [31:0] m_wdata;
    logic [3:0]  m_wstrb;
    logic [2:0]  m_awprot;
    logic [2:0]  m_arprot;
    
    // [PT] Sinais de resposta e dados de leitura / [EN] Response signals and read data
    logic [31:0] m_rdata;
    logic        m_wdone;
    logic        m_rdone;
    logic [1:0]  m_wresp;
    logic [1:0]  m_rresp;
endinterface