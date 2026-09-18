// [PT] Módulo wrapper do controlador AXI-Lite / [EN] Wrapper module for the AXI-Lite controller
// [PT] Interliga as interfaces AXI para CPU e interface para memória / [EN] Interconnects AXI interfaces for CPU and memory interface
/*
 * [PT] module: subordinate_module / [EN] module: subordinate_module
 * -----------------
 * [PT] Este módulo atua como o wrapper do controlador AXI-Lite. / [EN] This module acts as the AXI-Lite controller wrapper.
 * [PT] Ele expõe a interface AXI padrão para a CPU e uma interface / [EN] It exposes the standard AXI interface to the CPU and a
 * [PT] de controle customizada para a memória externa. / [EN] custom control interface for external memory.
 */
module subordinate_module (
    // [PT] Clocks e Resets AXI / [EN] AXI Clocks and Resets
    input  wire        ACLK,
    input  wire        ARESETn,

    // [PT] Interface AXI-Lite / [EN] AXI-Lite Interface
    input  wire [26:0] AWADDR,
    input  wire [2:0]  AWPROT,
    input  wire        AWVALID,
    output wire        AWREADY,
    input  wire [31:0] WDATA,
    input  wire        WVALID,
    input  wire [3:0]  WSTRB,
    output wire        WREADY,
    output wire [1:0]  BRESP,
    output wire        BVALID,
    input  wire        BREADY,
    input  wire [26:0] ARADDR,
    input  wire [2:0]  ARPROT,
    input  wire        ARVALID,
    output wire        ARREADY,
    output wire [31:0] RDATA,
    output wire [1:0]  RRESP,
    output wire        RVALID,
    input  wire        RREADY,

    // [PT] Interface com a Memória (Exportada para o Top-Level) / [EN] Interface with Memory (Exported to Top-Level)
    output wire        cpu_req,
    output wire        cpu_rnw,
    output wire [26:0] cpu_addr,
    output wire        cpu_wr_en,
    output wire [31:0] cpu_wdata,
    output wire [3:0]  cpu_wstrb,
    input  wire        cpu_ready,
    input  wire        rx_valid,
    input  wire        tx_empty,
    input  wire        tx_full,
    input  wire        init_done,
    input  wire [31:0] cpu_rdata
);

    // [PT] Instância do Controlador AXI / [EN] AXI Controller Instance
    axi_controller axi_inst (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .AWADDR(AWADDR), .AWPROT(AWPROT), .AWVALID(AWVALID), .AWREADY(AWREADY), // [PT] <-- CORREÇÃO AQUI / [EN] <-- CORRECTION HERE
        .WDATA(WDATA), .WSTRB(WSTRB), .WVALID(WVALID), .WREADY(WREADY),
        .BRESP(BRESP), .BVALID(BVALID), .BREADY(BREADY),
        .ARADDR(ARADDR), .ARPROT(ARPROT), .ARVALID(ARVALID), .ARREADY(ARREADY), // [PT] <-- CORREÇÃO AQUI / [EN] <-- CORRECTION HERE
        .RDATA(RDATA), .RRESP(RRESP), .RVALID(RVALID), .RREADY(RREADY),
        // [PT] Interface com a Memória / [EN] Memory Interface
        .cpu_req(cpu_req),
        .cpu_rnw(cpu_rnw),
        .cpu_addr(cpu_addr),
        .cpu_wr_en(cpu_wr_en),
        .init_done(init_done),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),
        .cpu_wstrb(cpu_wstrb),
        .tx_full(tx_full),
        .rx_valid(rx_valid),
        .tx_empty(tx_empty)
    );

endmodule