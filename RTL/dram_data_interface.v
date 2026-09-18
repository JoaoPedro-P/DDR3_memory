/*
 * module: dram_data_interface
 * -----------------
 * PT: Interface de Dados da DRAM. 
 *     Simula o comportamento do chip DDR3, convertendo dados seriais (DDR) em paralelos (SDR) e vice-versa.
 * 
 * EN: DRAM Data Interface.
 *     Simulates DDR3 chip behavior, converting serial (DDR) data to parallel (SDR) and vice-versa.
 */
module dram_data_interface (
    input  wire        clk, 
    input  wire        rst_n, 
    input  wire        rd_cmd, 
    input  wire        wr_cmd, 
    input  wire [63:0] data_from_core, // [PT] Dados lidos do array / [EN] Data read from core array
    output reg  [63:0] data_to_core,   // [PT] Dados para escrever no array / [EN] Data to write to core array
    output reg  [7:0]  dm_to_core,     // [PT] Máscara de dados p/ array / [EN] Data mask for core array
	 input  wire [7:0]  dq_in,
    input  wire        dqs_in,
    input  wire        dqs_n_in,
    output wire [7:0]  dq_out,
    output wire        dqs_out_pad,
    output wire        dqs_n_out_pad,
    output reg         out_en,
    input  wire        DM
);
    
    reg [7:0]  dq_out_reg;
    reg        dqs_out_reg;

	 assign dq_out        = dq_out_reg;
    assign dqs_out_pad   = dqs_out_reg;
    assign dqs_n_out_pad = ~dqs_out_reg;

    reg [31:0] shift_rise, shift_fall;
    reg [3:0]  shift_dm_rise, shift_dm_fall;

    // [PT] Captura de dados na subida/descida do DQS (Escrita) / [EN] Data capture on DQS edges (Write)
	 always @(posedge dqs_in) begin
        if (dqs_in == 1'b1) begin // [PT] Comparação limpa / [EN] Clean comparison
            shift_rise    <= {shift_rise[23:0], dq_in};
            shift_dm_rise <= {shift_dm_rise[2:0], DM};
        end
    end

    // [PT] Captura na borda de descida do DQS / [EN] Capture on DQS falling edge
    always @(negedge dqs_in) begin
        if (dqs_in == 1'b0) begin // [PT] Comparação limpa / [EN] Clean comparison
            shift_fall    <= {shift_fall[23:0], dq_in};
            shift_dm_fall <= {shift_dm_fall[2:0], DM};
        end
    end

    reg [2:0] wr_cnt;
    
    // [PT] Controle do contador de escrita e formatação SDR / [EN] Write counter control and SDR formatting
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_cnt       <= 3'd0;
            data_to_core <= 64'd0;
            dm_to_core   <= 8'd0;
        end else begin
            // [PT] Se o contador chegou em 7, DEVE salvar o dado obrigatoriamente / [EN] If the counter reached 7, MUST save the data mandatorily
            if (wr_cnt == 3'd7) begin
                data_to_core <= {shift_fall[7:0], shift_rise[7:0],
                                 shift_fall[15:8], shift_rise[15:8],
                                 shift_fall[23:16], shift_rise[23:16],
                                 shift_fall[31:24], shift_rise[31:24]};
                dm_to_core   <= {shift_dm_fall[0], shift_dm_rise[0],
                                 shift_dm_fall[1], shift_dm_rise[1],
                                 shift_dm_fall[2], shift_dm_rise[2],
                                 shift_dm_fall[3], shift_dm_rise[3]};
                
                // [PT] Se um novo comando colidir neste ciclo, já reinicia a contagem / [EN] If a new command collides in this cycle, restart counting immediately
                if (wr_cmd) wr_cnt <= 3'd1;
                else        wr_cnt <= 3'd0;
                
            end else if (wr_cmd) begin
                wr_cnt <= 3'd1;
            end else if (wr_cnt > 0) begin
                wr_cnt <= wr_cnt + 3'd1;
            end
        end
    end

    reg [2:0]  rd_cnt;
    reg [63:0] read_latch;
    reg        rd_cmd_d1;

    // [PT] Atraso do comando de leitura para alinhamento / [EN] Read command delay for alignment
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rd_cmd_d1 <= 1'b0;
        else        rd_cmd_d1 <= rd_cmd;
    end

    // [PT] Processamento de Leitura (SDR -> DDR) / [EN] Read Processing (SDR -> DDR)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_en <= 1'b0;
            rd_cnt <= 3'd0;
            read_latch <= 64'd0;
        end else begin
            if (rd_cmd_d1) begin
                read_latch <= data_from_core;
                out_en <= 1'b1;               
                rd_cnt <= 3'd1;               
            end else if (out_en && rd_cnt >= 1 && rd_cnt <= 4) begin
                rd_cnt <= rd_cnt + 3'd1;
            end else if (rd_cnt == 5) begin
                out_en <= 1'b0;
                rd_cnt <= 3'd0;
            end
        end
    end

    reg [7:0] dq_rise, dq_fall;
    reg       dqs_rise, dqs_fall;

    // [PT] Prepara os dados da borda de subida e gera DQS de subida / [EN] Prepares rising edge data and generates rising DQS
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dq_rise  <= 8'd0;
            dqs_rise <= 1'b0;
        end else if (out_en && rd_cnt >= 1 && rd_cnt <= 4) begin
            dq_rise  <= read_latch[(rd_cnt-1)*16 +: 8];
            dqs_rise <= 1'b1;
        end else begin
            dqs_rise <= 1'b0;
        end
    end

    // [PT] Prepara os dados da borda de descida e gera DQS de descida / [EN] Prepares falling edge data and generates falling DQS
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dq_fall  <= 8'd0;
            dqs_fall <= 1'b0;
        end else if (out_en && rd_cnt >= 1 && rd_cnt <= 4) begin
            dq_fall  <= read_latch[(rd_cnt-1)*16+8 +: 8];
            dqs_fall <= 1'b0;
        end else begin
            dqs_fall <= 1'b0;
        end
    end

    // [PT] Multiplexador para geração final de DDR (DQ e DQS) / [EN] Multiplexer for final DDR generation (DQ and DQS)
    always @(*) begin
        if (out_en) begin
            if (rd_cnt == 0) begin
                dq_out_reg  = 8'd0;
                dqs_out_reg = 1'b0;
            end else begin
                dq_out_reg  = clk ? dq_rise  : dq_fall;
                dqs_out_reg = clk ? dqs_rise : dqs_fall;
            end
        end else begin
            dq_out_reg  = 8'd0;
            dqs_out_reg = 1'b0;
        end
    end

endmodule
