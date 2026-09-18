/*
 * module: tri_state_and_converter
 * -----------------
 * [PT] Conversor SDR para DDR e Gerenciador de Tri-State. Este módulo é a "ponta" da PHY, 
 * responsável por converter os dados de clock simples (SDR) do controlador para a 
 * taxa de dados dobrada (DDR) exigida pela DDR3. (Otimizado para GLS e fechamento de Hold Time em ASIC/Genus)
 * Operação de Escrita (SDR -> DDR):
 * - Multiplexação Temporal: O controlador envia uma palavra de 16 bits (tx_data). 
 *   Este módulo divide em dois bytes de 8 bits. O primeiro é enviado no nível 
 *   alto do clock e o segundo no nível baixo, dobrando a taxa efetiva.
 * - Tri-state: Gerencia os pinos bidirecionais DQ/DQS, colocando-os em alta 
 *   impedância ('Z') quando a memória não está sendo escrita.
 * Operação de Leitura (DDR -> SDR):
 * - Captura de Borda Dupla: Utiliza o clk_90 (defasado) para amostrar os dados DQ 
 *   tanto na subida quanto na descida, capturando 2 bytes por ciclo de clock.
 * - Recomposição: Concatena os bytes capturados em blocos de 64 bits (burst completo) 
 *   e então os sincroniza de volta para o domínio de clock principal para entrega.
 * / [EN] SDR to DDR Converter and Tri-State Manager. This module is the tip of the PHY, 
 * responsible for converting Single Data Rate (SDR) data from the controller to 
 * the Double Data Rate (DDR) required by DDR3. (Optimized for GLS and Hold Time closure in ASIC/Genus)
 * Write Operation (SDR -> DDR):
 * - Time Multiplexing: The controller sends a 16-bit word (tx_data). This module 
 *   splits it into two 8-bit bytes. The first is sent on the clock's high level 
 *   and the second on the low level, doubling the effective rate.
 * - Tri-state: Manages bidirectional DQ/DQS pins, placing them in high 
 *   impedance ('Z') when memory is not being written to.
 * Read Operation (DDR -> SDR):
 * - Double Edge Capture: Uses clk_90 (phase-shifted) to sample DQ data on 
 *   both rising and falling edges, capturing 2 bytes per clock cycle.
 * - Reassembly: Concatenates captured bytes into 64-bit blocks (full burst) 
 *    and then synchronizes them back to the main clock domain for delivery.
 */
module tri_state_and_converter(
    input  wire        clk,           // [PT] Clock principal / [EN] Main clock
    input  wire        clk_90,        // [PT] Clock defasado em 90 graus / [EN] 90-degree phase-shifted clock
    input  wire        rst_n,         // [PT] Reset ativo baixo / [EN] Active low reset
    input  wire        phy_dq_en,     // [PT] Habilita escrita nos dados (DQ) / [EN] Enables data write (DQ)
    input  wire        phy_dqs_en,    // [PT] Habilita estrobo de dados (DQS) / [EN] Enables data strobe (DQS)
    input  wire        dqs_out,       // [PT] DQS de saída / [EN] Output DQS
    input  wire        dqs_n_out,     // [PT] DQS invertido de saída / [EN] Inverted output DQS
    
    input  wire [31:0] tx_data,       // [PT] Dados de transmissão / [EN] Transmission data
    input  wire [3:0]  tx_wstrb,      // [PT] Estrobo de escrita / [EN] Write strobe
    output reg  [31:0] rx_data,       // [PT] Dados recebidos / [EN] Received data
    
    output reg         rx_valid,      // [PT] Validade dos dados recebidos / [EN] Validity of received data
    input  wire [7:0]  dq_in,         // [PT] Dados recebidos dos pinos DQ / [EN] Received data from DQ pins
    input  wire        dqs_in,        // [PT] Estrobo DQS recebido / [EN] Received DQS strobe
    input  wire        dqs_n_in,      // [PT] Estrobo DQS invertido recebido / [EN] Received inverted DQS strobe
    output wire [7:0]  dq_out,        // [PT] Dados para transmissão nos pinos DQ / [EN] Data for transmission on DQ pins
    output wire        dqs_out_pad,   // [PT] Sinal pad DQS de saída / [EN] Output pad DQS signal
    output wire        dqs_n_out_pad, // [PT] Sinal pad DQS invertido de saída / [EN] Output pad inverted DQS signal
    output wire        DM             // [PT] Máscara de dados / [EN] Data Mask
);

    // [PT] Registradores para capturar dados e estrobo de transmissão / [EN] Registers to latch transmit data and strobe
    reg [31:0] latched_tx_data;
    reg [3:0]  latched_tx_wstrb;

    // [PT] Bloco sequencial para capturar os dados de transmissão / [EN] Sequential block to latch transmission data
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_tx_data  <= 32'd0;
            latched_tx_wstrb <= 4'd0;
        end else if (phy_dqs_en && !phy_dq_en) begin
            latched_tx_data  <= tx_data;
            latched_tx_wstrb <= tx_wstrb;
        end
    end

    // [PT] Contador para a transmissão / [EN] Counter for transmission
    reg [1:0] tx_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tx_cnt <= 2'd0;
        else if (phy_dq_en) tx_cnt <= tx_cnt + 2'd1;
        else tx_cnt <= 2'd0;
    end

    // [PT] Multiplexação para gerar dq_out combinando os bits do latched_tx_data / [EN] Multiplexing to generate dq_out by combining latched_tx_data bits
    assign dq_out = (tx_cnt == 2'd0) ? (clk ? latched_tx_data[7:0]   : latched_tx_data[15:8]) :
                    (tx_cnt == 2'd1) ? (clk ? latched_tx_data[23:16] : latched_tx_data[31:24]) : 8'd0;
                    
    // [PT] Multiplexação para gerar DM com base no latched_tx_wstrb / [EN] Multiplexing to generate DM based on latched_tx_wstrb
    assign DM     = phy_dq_en ? (
                    (tx_cnt == 2'd0) ? (clk ? ~latched_tx_wstrb[0] : ~latched_tx_wstrb[1]) :
                    (tx_cnt == 2'd1) ? (clk ? ~latched_tx_wstrb[2] : ~latched_tx_wstrb[3]) : 1'b1 
                    ) : 1'b1; // [PT] Pull-up virtual para proteger a memória no estado ocioso / [EN] Virtual pull-up to protect memory in idle state

    // [PT] Sinais diretos para os pads DQS / [EN] Direct signals to DQS pads
    assign dqs_out_pad   = dqs_out;
    assign dqs_n_out_pad = dqs_n_out;

    // [PT] Registradores para capturar dados recebidos nas bordas de subida e descida / [EN] Registers to capture received data on rising and falling edges
    reg [7:0] rx_r, rx_f;

    // [PT] Captura de borda de subida e descida do dq_in / [EN] Rising and falling edge capture of dq_in
    always @(posedge clk_90) if (!phy_dqs_en) rx_r <= dq_in;
    always @(negedge clk_90) if (!phy_dqs_en) rx_f <= dq_in;

    // [PT] Amostragem do dqs_in / [EN] Sampling of dqs_in
    reg dqs_in_sampled;
    always @(posedge clk_90 or negedge rst_n) begin
        if (!rst_n) dqs_in_sampled <= 0;
        else dqs_in_sampled <= dqs_in; 
    end

    // [PT] Sincronização do dqs_in amostrado para o domínio de clock principal / [EN] Synchronization of sampled dqs_in to main clock domain
    reg dqs_in_sync;
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) dqs_in_sync <= 0;
        else dqs_in_sync <= dqs_in_sampled;
    end

    // [PT] Registrador de burst e contadores para recebimento e entrega de dados / [EN] Burst register and counters for data reception and delivery
    reg [63:0] burst_reg;
    reg [3:0]  rx_word_cnt;
    reg [2:0]  delivery_cnt;

    // [PT] Bloco sequencial para compor e entregar os dados lidos (DDR -> SDR) / [EN] Sequential block to compose and deliver read data (DDR -> SDR)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // [PT] Reseta os contadores e sinais de saída de dados / [EN] Resets counters and data output signals
            burst_reg <= 0;
            rx_word_cnt <= 0;
            delivery_cnt <= 0; 
            rx_valid <= 0; 
            rx_data <= 0;
        end else begin
            // [PT] Se modo leitura ativo e dqs_in sincronizado, acumula dados no burst_reg / [EN] If read mode active and dqs_in synchronized, accumulate data in burst_reg
            if (!phy_dqs_en && dqs_in_sync) begin
                burst_reg <= {rx_f, rx_r, burst_reg[63:16]};
                if (rx_word_cnt < 4) rx_word_cnt <= rx_word_cnt + 1;
            end else begin
                rx_word_cnt <= 0;
            end

            // [PT] Entrega os dados acumulados quando o pacote de leitura estiver completo / [EN] Delivers accumulated data when the read packet is complete
            if (rx_word_cnt == 4 && delivery_cnt == 0) begin
                delivery_cnt <= 1;
                rx_valid <= 1'b1;
                rx_data <= burst_reg[31:0]; 
            end else if (delivery_cnt == 1) begin
                rx_valid <= 1'b0;
                if (rx_word_cnt < 4) delivery_cnt <= 0; 
            end else begin
                rx_valid <= 1'b0;
                delivery_cnt <= 0;
            end
        end
    end
endmodule