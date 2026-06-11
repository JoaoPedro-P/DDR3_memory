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
    input  wire [63:0] data_from_core, // PT: Dados lidos do array | EN: Data read from core array
    output reg  [63:0] data_to_core,   // PT: Dados para escrever no array | EN: Data to write to core array
    output reg  [7:0]  dm_to_core,     // PT: Máscara de dados p/ array | EN: Data mask for core array
    inout  wire [7:0]  DQ,             // PT: Barramento de dados DDR | EN: DDR data bus
    inout  wire        DQS,            // PT: Strobe de dados | EN: Data Strobe
    inout  wire        DQS_n,
    input  wire        DM              // PT: Pino de máscara | EN: Mask pin
);

    reg        out_en;
    reg [7:0]  dq_out_reg;
    reg        dqs_out_reg;

    assign DQ    = out_en ? dq_out_reg  : 8'bzzzzzzzz;
    assign DQS   = out_en ? dqs_out_reg : 1'bz;
    assign DQS_n = out_en ? ~dqs_out_reg: 1'bz;

    reg [31:0] shift_rise, shift_fall;
    reg [3:0]  shift_dm_rise, shift_dm_fall;

    // PT: Captura de dados na subida/descida do DQS (Escrita)
    // EN: Data capture on DQS edges (Write)
    always @(posedge DQS) begin
        if (DQS === 1'b1) begin
            shift_rise    <= {shift_rise[23:0], DQ};
            shift_dm_rise <= {shift_dm_rise[2:0], DM};
        end
    end

    always @(negedge DQS) begin
        if (DQS === 1'b0) begin
            shift_fall    <= {shift_fall[23:0], DQ};
            shift_dm_fall <= {shift_dm_fall[2:0], DM};
        end
    end

    reg [3:0] wr_cnt;
always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_cnt       <= 4'd0;
            data_to_core <= 64'd0;
            dm_to_core   <= 8'd0;
        end else begin
            // Se o contador chegou em 7, DEVE salvar o dado obrigatoriamente
            if (wr_cnt == 4'd7) begin
                data_to_core <= {shift_fall[7:0], shift_rise[7:0],
                                 shift_fall[15:8], shift_rise[15:8],
                                 shift_fall[23:16], shift_rise[23:16],
                                 shift_fall[31:24], shift_rise[31:24]};
                dm_to_core   <= {shift_dm_fall[0], shift_dm_rise[0],
                                 shift_dm_fall[1], shift_dm_rise[1],
                                 shift_dm_fall[2], shift_dm_rise[2],
                                 shift_dm_fall[3], shift_dm_rise[3]};
                
                // Se um novo comando colidir neste ciclo, já reinicia a contagem
                if (wr_cmd) wr_cnt <= 4'd1;
                else        wr_cnt <= 4'd0;
                
            end else if (wr_cmd) begin
                wr_cnt <= 4'd1;
            end else if (wr_cnt > 0) begin
                wr_cnt <= wr_cnt + 4'd1;
            end
        end
    end

    reg [2:0]  rd_cnt;
    reg [63:0] read_latch;
    reg        rd_cmd_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rd_cmd_d1 <= 1'b0;
        else        rd_cmd_d1 <= rd_cmd;
    end

    // PT: Processamento de Leitura (SDR -> DDR) | EN: Read Processing (SDR -> DDR)
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
