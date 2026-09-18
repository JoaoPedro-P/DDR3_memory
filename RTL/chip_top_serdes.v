/*
 * module: chip_top_serdes
 * -----------------
 * [PT] Novo Módulo Top-Level para Fabricação (Interface de 7 Pinos).
 * Implementa o Deserializador (RX) e o Serializador (TX) conectando-os
 * ao barramento paralelo do AXI Master interno.
 * / [EN] New Top-Level Module for Manufacturing (7-Pin Interface).
 * Implements the Deserializer (RX) and Serializer (TX) by connecting them
 * to the parallel bus of the internal AXI Master.
 */
module chip_top_serdes(
    // [PT] 4 Pinos de Controle / [EN] 4 Control Pins
    input  wire clk_axi_bus, // [PT] Clock do barramento AXI / [EN] AXI bus clock
    input  wire clk_mem,     // [PT] Clock da memória / [EN] Memory clock
    input  wire clk_90_mem,  // [PT] Clock da memória defasado em 90 graus / [EN] 90-degree phase-shifted memory clock
    input  wire rst_n,       // [PT] Reset ativo baixo / [EN] Active low reset
    
    // [PT] 3 Pinos de Dados / [EN] 3 Data Pins
    input  wire rx_sync,     // [PT] Sincronização de RX / [EN] RX sync
    input  wire rx_data,     // [PT] Dados seriais de RX / [EN] RX serial data
    output reg  tx_data      // [PT] Dados seriais de TX / [EN] TX serial data
);

    // [PT] Sinais Paralelos Internos / [EN] Internal Parallel Signals
    reg         STARTW_reg, STARTR_reg;
    reg  [26:0] m_addr_reg;
    reg  [31:0] m_wdata_reg;
    reg  [3:0]  m_wstrb_reg;
    reg  [2:0]  m_prot_reg;
    
    wire [31:0] m_rdata;
    wire        m_wdone, m_rdone;
    wire [1:0]  m_wresp, m_rresp;

    // ==========================================
    // [PT] DESERIALIZADOR (RX - Entrada Serial p/ Paralelo) / [EN] DESERIALIZER (RX - Serial to Parallel Input)
    // ==========================================
    reg [67:0] rx_shift;     // [PT] Registrador de deslocamento de RX / [EN] RX shift register
    reg [6:0]  rx_bit_cnt;   // [PT] Contador de bits de RX / [EN] RX bit counter

    // [PT] Bloco sequencial do deserializador para conversão e montagem do pacote AXI / [EN] Deserializer sequential block for AXI packet conversion and assembly
    always @(posedge clk_axi_bus or negedge rst_n) begin
        if (!rst_n) begin
            // [PT] Zera todos os registradores e contadores no reset / [EN] Clears all registers and counters on reset
            rx_shift    <= 68'd0;
            rx_bit_cnt  <= 7'd0;
            STARTW_reg  <= 1'b0;
            STARTR_reg  <= 1'b0;
            m_addr_reg  <= 27'd0;
            m_wdata_reg <= 32'd0;
            m_wstrb_reg <= 4'd0;
            m_prot_reg  <= 3'd0;
        end else begin
            // [PT] Garante que STARTW e STARTR sejam pulsos de 1 ciclo / [EN] Ensures that STARTW and STARTR are 1-cycle pulses
            STARTW_reg <= 1'b0;
            STARTR_reg <= 1'b0;

            if (rx_sync) begin
                // [PT] Desloca e armazena os dados seriais recebidos / [EN] Shifts and stores received serial data
                rx_shift <= {rx_shift[66:0], rx_data};
                rx_bit_cnt <= rx_bit_cnt + 7'd1;
            end else if (rx_bit_cnt == 7'd68) begin
                // [PT] Pacote completo de 68 bits recebido! Despeja nos registradores AXI / [EN] Full 68-bit packet received! Dumps into AXI registers
                STARTW_reg  <= rx_shift[67];
                STARTR_reg  <= rx_shift[66];
                m_addr_reg  <= rx_shift[65:39];
                m_wdata_reg <= rx_shift[38:7];
                m_wstrb_reg <= rx_shift[6:3];
                m_prot_reg  <= rx_shift[2:0];
                rx_bit_cnt  <= 7'd0;
            end else begin
                // [PT] Zera o contador se a sincronização for interrompida / [EN] Clears counter if synchronization is interrupted
                rx_bit_cnt <= 7'd0;
            end
        end
    end

    // ==========================================
    // [PT] SERIALIZADOR (TX - Saída Paralela p/ Serial) / [EN] SERIALIZER (TX - Parallel to Serial Output)
    // ==========================================
    reg [36:0] tx_shift;     // [PT] Registrador de deslocamento de TX / [EN] TX shift register
    reg [5:0]  tx_bit_cnt;   // [PT] Contador de bits de TX / [EN] TX bit counter
    reg        tx_active;    // [PT] Flag de transmissão ativa / [EN] Active transmission flag

    // [PT] Bloco sequencial do serializador para envio dos pacotes / [EN] Serializer sequential block for packet transmission
    always @(posedge clk_axi_bus or negedge rst_n) begin
        if (!rst_n) begin
            // [PT] Zera todos os registradores no reset / [EN] Clears all registers on reset
            tx_shift   <= 37'd0;
            tx_bit_cnt <= 6'd0;
            tx_active  <= 1'b0;
            tx_data    <= 1'b0;
        end else begin
            if (m_wdone || m_rdone) begin
                // [PT] Carrega Shift Reg: [36]=wdone, [35]=rdone, [34:3]=rdata, [2:1]=resp, [0]=pad / [EN] Load Shift Reg: [36]=wdone, [35]=rdone, [34:3]=rdata, [2:1]=resp, [0]=pad
                tx_shift   <= {m_wdone, m_rdone, m_rdata, (m_wdone ? m_wresp : m_rresp), 1'b0};
                tx_bit_cnt <= 6'd36;
                tx_active  <= 1'b1;
                // [PT] Envia o START BIT instantaneamente para o Testbench / [EN] Sends the START BIT instantly to the Testbench
                tx_data    <= 1'b1; 
            end else if (tx_active && tx_bit_cnt > 0) begin
                // [PT] Envia MSB do payload e desloca os dados / [EN] Sends payload MSB and shifts the data
                tx_data    <= tx_shift[36]; 
                tx_shift   <= {tx_shift[35:0], 1'b0};
                tx_bit_cnt <= tx_bit_cnt - 6'd1;
            end else begin
                // [PT] Mantém a linha de transmissão Idle em Baixo / [EN] Keeps transmission line Idle Low
                tx_active  <= 1'b0;
                tx_data    <= 1'b0; 
            end
        end
    end

    // ==========================================
    // [PT] INSTANCIAÇÃO DO SISTEMA ORIGINAL (O Core do ASIC) / [EN] ORIGINAL SYSTEM INSTANTIATION (The ASIC Core)
    // ==========================================
    axi4lite_system core_inst (
        .clk_axi_bus (clk_axi_bus),
        .clk_mem     (clk_mem),
        .clk_90_mem  (clk_90_mem),
        .resetn_bus  (rst_n),
        .reset_mem   (rst_n),
        .STARTW      (STARTW_reg),
        .STARTR      (STARTR_reg),
        .m_addr      (m_addr_reg),
        .m_wdata     (m_wdata_reg),
        .m_wstrb     (m_wstrb_reg),
        .m_awprot    (m_prot_reg),
        .m_arprot    (m_prot_reg),
        .m_rdata     (m_rdata),
        .m_wdone     (m_wdone),
        .m_rdone     (m_rdone),
        .m_wresp     (m_wresp),
        .m_rresp     (m_rresp)
    );

endmodule