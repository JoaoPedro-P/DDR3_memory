/*
 * module: tri_state_and_converter
 * -----------------
 * PT: Conversor SDR para DDR e Gerenciador de Tri-State. Este módulo é a "ponta" da PHY, 
 *     responsável por converter os dados de clock simples (SDR) do controlador para a 
 *     taxa de dados dobrada (DDR) exigida pela DDR3.
 * 
 *     Operação de Escrita (SDR -> DDR):
 *     - Multiplexação Temporal: O controlador envia uma palavra de 16 bits (tx_data). 
 *       Este módulo divide em dois bytes de 8 bits. O primeiro é enviado no nível 
 *       alto do clock e o segundo no nível baixo, dobrando a taxa efetiva.
 *     - Tri-state: Gerencia os pinos bidirecionais DQ/DQS, colocando-os em alta 
 *       impedância ('Z') quando a memória não está sendo escrita.
 * 
 *     Operação de Leitura (DDR -> SDR):
 *     - Captura de Borda Dupla: Utiliza o clk_90 (defasado) para amostrar os dados DQ 
 *       tanto na subida quanto na descida, capturando 2 bytes por ciclo de clock.
 *     - Recomposição: Concatena os bytes capturados em blocos de 64 bits (burst completo) 
 *       e então os sincroniza de volta para o domínio de clock principal para entrega.
 *
 * EN: SDR to DDR Converter and Tri-State Manager. This module is the tip of the PHY, 
 *     responsible for converting Single Data Rate (SDR) data from the controller to 
 *     the Double Data Rate (DDR) required by DDR3.
 * 
 *     Write Operation (SDR -> DDR):
 *     - Time Multiplexing: The controller sends a 16-bit word (tx_data). This module 
 *       splits it into two 8-bit bytes. The first is sent on the clock's high level 
 *       and the second on the low level, doubling the effective rate.
 *     - Tri-state: Manages bidirectional DQ/DQS pins, placing them in high 
 *       impedance ('Z') when memory is not being written to.
 * 
 *     Read Operation (DDR -> SDR):
 *     - Double Edge Capture: Uses clk_90 (phase-shifted) to sample DQ data on 
 *       both rising and falling edges, capturing 2 bytes per clock cycle.
 *     - Reassembly: Concatenates captured bytes into 64-bit blocks (full burst) 
 *        and then synchronizes them back to the main clock domain for delivery.
 */
module tri_state_and_converter(
    // =========================================================================
    // Clocks e Resets | Clocks and Resets
    // =========================================================================
    input  wire        clk,        // PT: Clock principal (0°). | EN: Main clock (0°).
    input  wire        clk_90,     // PT: Clock de captura (90°). | EN: Capture clock (90°).
    input  wire        rst_n,      // PT: Reset (Ativo Baixo). | EN: Reset (Active Low).

    // =========================================================================
    // Sinais de Controle da PHY | PHY Control Signals
    // =========================================================================
    input  wire        phy_dq_en,  // PT: Habilita driver de saída DQ. | EN: Enable DQ output driver.
    input  wire        phy_dqs_en, // PT: Habilita driver de saída DQS. | EN: Enable DQS output driver.
    input  wire        dqs_out,    // PT: Strobe positivo a ser enviado. | EN: Positive strobe to send.
    input  wire        dqs_n_out,  // PT: Strobe negativo a ser enviado. | EN: Negative strobe to send.
    
    // =========================================================================
    // Barramento Interno (SDR) | Internal Bus (SDR)
    // =========================================================================
    input  wire [15:0] tx_data,    // PT: Dado de escrita SDR (2 bytes/ciclo). | EN: SDR write data.
	 input  wire [1:0]  tx_wstrb,   // PT: Máscara de escrita SDR. | EN: SDR write mask.
    output reg  [15:0] rx_data,    // PT: Dado lido convertido p/ SDR. | EN: Read data converted to SDR.
    output reg         rx_valid,   // PT: Sinaliza que rx_data é válido. | EN: Signals rx_data is valid.
    
    // =========================================================================
    // Pinos Físicos (DDR) | Physical Pins (DDR)
    // =========================================================================
    inout  wire [7:0]  DQ,         // PT: Barramento DDR de dados (8 bits). | EN: 8-bit DDR data bus.
    inout  wire        DQS,        // PT: Strobe de dados DDR positivo. | EN: Positive DDR data strobe.
    inout  wire        DQS_n,      // PT: Strobe de dados DDR negativo. | EN: Negative DDR data strobe.
	 output wire        DM          // PT: Pino de Data Mask DDR. | EN: DDR Data Mask pin.
);


    // =========================================================================
    // PT: 1. VIA DE ESCRITA (TX) | EN: 1. WRITE PATH (TX)
    // =========================================================================
    // PT: Mux temporal: Envia metade da palavra SDR em cada nível do clock
    // EN: Time mux: Sends half of the SDR word at each clock level
    wire [7:0] tx_mux = (clk) ? tx_data[7:0] : tx_data[15:8];
    wire dm_mux = (clk) ? ~tx_wstrb[0] : ~tx_wstrb[1];
	 
    assign DQ    = (phy_dq_en)  ? tx_mux    : 8'bz;
    assign DQS   = (phy_dqs_en) ? dqs_out   : 1'bz;
    assign DQS_n = (phy_dqs_en) ? dqs_n_out : 1'bz;
	 assign DM = (phy_dq_en) ? dm_mux : 1'bz;
    // =========================================================================
    // PT: 2. VIA DE LEITURA (RX) | EN: 2. READ PATH (RX)
    // =========================================================================
    reg [7:0]  internal_rx_lsb;
    reg [63:0] rx_burst_reg;
    reg [1:0]  rx_word_cnt;
    reg        rx_burst_done_toggle;
    reg        receiving;

    // PT: Proteção contra estados 'Z' ou 'X' | EN: Protection against 'Z' or 'X' states
    wire [7:0] rx_dq_clean;
    assign rx_dq_clean[7] = (!phy_dqs_en && DQ[7] === 1'b1) ? 1'b1 : 1'b0;
    assign rx_dq_clean[6] = (!phy_dqs_en && DQ[6] === 1'b1) ? 1'b1 : 1'b0;
    assign rx_dq_clean[5] = (!phy_dqs_en && DQ[5] === 1'b1) ? 1'b1 : 1'b0;
    assign rx_dq_clean[4] = (!phy_dqs_en && DQ[4] === 1'b1) ? 1'b1 : 1'b0;
    assign rx_dq_clean[3] = (!phy_dqs_en && DQ[3] === 1'b1) ? 1'b1 : 1'b0;
    assign rx_dq_clean[2] = (!phy_dqs_en && DQ[2] === 1'b1) ? 1'b1 : 1'b0;
    assign rx_dq_clean[1] = (!phy_dqs_en && DQ[1] === 1'b1) ? 1'b1 : 1'b0;
    assign rx_dq_clean[0] = (!phy_dqs_en && DQ[0] === 1'b1) ? 1'b1 : 1'b0;
	 
	 
    // PT: Captura LSB na subida do clk_90 (centro do dado)
    // EN: Capture LSB on clk_90 rising edge (center of data)
    always @(posedge clk_90 or negedge rst_n) begin
        if (!rst_n) begin
            internal_rx_lsb <= 8'd0;
            receiving       <= 1'b0;
        end else begin
            if (!phy_dqs_en && DQS === 1'b1) begin
                internal_rx_lsb <= rx_dq_clean;
                receiving       <= 1'b1;
            end else begin
                receiving       <= 1'b0;
            end
        end
    end

    // PT: Captura MSB na descida do clk_90 e concatena
    // EN: Capture MSB on clk_90 falling edge and concatenate
    always @(negedge clk_90 or negedge rst_n) begin
        if (!rst_n) begin
            rx_burst_reg         <= 64'd0;
            rx_word_cnt          <= 2'd0;
            rx_burst_done_toggle <= 1'b0;
        end else begin
            if (receiving && !phy_dqs_en && DQS === 1'b0) begin
                rx_burst_reg <= {rx_burst_reg[47:0], rx_dq_clean, internal_rx_lsb};
                
                if (rx_word_cnt == 2'd3) begin
                    rx_burst_done_toggle <= ~rx_burst_done_toggle;
                    rx_word_cnt <= 2'd0;
                end else begin
                    rx_word_cnt <= rx_word_cnt + 2'd1;
                end
            end
        end
    end

    // =========================================================================
    // PT: 3. SINCRONIZAÇÃO E ENTREGA | EN: 3. SYNCHRONIZATION AND DELIVERY
    // =========================================================================
    reg [2:0]  rx_done_sync;
    reg [63:0] rx_latch_clk;
    reg [2:0]  rx_delivery_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_done_sync    <= 3'd0;
            rx_latch_clk    <= 64'd0;
            rx_delivery_cnt <= 3'd0;
            rx_valid        <= 1'b0;
            rx_data         <= 16'd0;
        end else begin
            rx_done_sync <= {rx_done_sync[1:0], rx_burst_done_toggle};

            if ((rx_done_sync[2] ^ rx_done_sync[1]) && (rx_delivery_cnt == 3'd0)) begin
                rx_latch_clk    <= rx_burst_reg;
                rx_delivery_cnt <= 3'd1; 
                rx_valid        <= 1'b0; 
            end 
            else if (rx_delivery_cnt >= 3'd1 && rx_delivery_cnt <= 3'd4) begin
                rx_valid <= 1'b1;
                case (rx_delivery_cnt)
                    3'd1: rx_data <= rx_latch_clk[63:48];
                    3'd2: rx_data <= rx_latch_clk[47:32];
                    3'd3: rx_data <= rx_latch_clk[31:16];
                    3'd4: rx_data <= rx_latch_clk[15:0];
                endcase
                
                if (rx_delivery_cnt == 3'd4) begin
                    rx_delivery_cnt <= 3'd0; 
                end else begin
                    rx_delivery_cnt <= rx_delivery_cnt + 3'd1;
                end
            end 
            else begin
                rx_valid        <= 1'b0;
                rx_delivery_cnt <= 3'd0; 
            end
        end
    end

endmodule
