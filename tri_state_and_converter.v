/*
 * module: tri_state_and_converter
 * -----------------
 * PT: Conversor SDR para DDR e Gerenciador de Tri-State. 
 *     Realiza a multiplexação temporal dos dados (Escrita) e a captura centrada (Leitura).
 * 
 * EN: SDR to DDR Converter and Tri-State Manager.
 *     Performs time-multiplexing for data (Write) and centered capture (Read).
 */
module tri_state_and_converter(
    input  wire        clk,       // PT: Clock 0° | EN: 0-degree clock
    input  wire        clk_90,    // PT: Clock 90° | EN: 90-degree clock
    input  wire        rst_n, 
    input  wire        phy_dq_en,  // PT: Enable DQ | EN: DQ Enable
    input  wire        phy_dqs_en, // PT: Enable DQS | EN: DQS Enable
    input  wire        dqs_out, dqs_n_out,
    input  wire [15:0] tx_data,    // PT: Dados SDR para converter em DDR | EN: SDR data to DDR
    output reg  [15:0] rx_data,    // PT: Dados DDR convertidos em SDR | EN: DDR data to SDR
    output reg         rx_valid,   // PT: Flag de dado recebido | EN: Received data flag
    inout  wire [7:0]  DQ,         // PT: Pinos de Dados | EN: Data Pins
    inout  wire        DQS,        // PT: Pinos de Strobe | EN: Strobe Pins
    inout  wire        DQS_n
);

    // =========================================================================
    // PT: 1. VIA DE ESCRITA (TX) | EN: 1. WRITE PATH (TX)
    // =========================================================================
    // PT: Mux temporal: Envia metade da palavra SDR em cada nível do clock
    // EN: Time mux: Sends half of the SDR word at each clock level
    wire [7:0] tx_mux = (clk) ? tx_data[7:0] : tx_data[15:8];

    assign DQ    = (phy_dq_en)  ? tx_mux    : 8'bz;
    assign DQS   = (phy_dqs_en) ? dqs_out   : 1'bz;
    assign DQS_n = (phy_dqs_en) ? dqs_n_out : 1'bz;

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
