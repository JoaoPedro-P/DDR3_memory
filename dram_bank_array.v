/*
 * module: dram_bank_array
 * -----------------
 * PT: Modelo funcional do array de armazenamento da DRAM. 
 *     Simula os 8 bancos de memória e gerencia o pipeline de escrita/leitura.
 * 
 * EN: Functional model of the DRAM storage array.
 *     Simulates the 8 memory banks and manages the write/read pipeline.
 */
module dram_bank_array #(
    parameter freq = 100,
    parameter MEM_DEPTH_LOG2 = 8 
)(
    input  wire        clk, 
    input  wire        rst_n, 
    input  wire        act_cmd, 
    input  wire        pre_cmd, 
    input  wire        rd_cmd, 
    input  wire        wr_cmd,
    input  wire [2:0]  bank_addr,
    input  wire [9:0]  col_addr,
    input  wire [13:0] row_addr,
    input  wire [63:0] data_in,
    input  wire [7:0]  dm_in,        // PT: Máscara de Dados | EN: Data Mask
    
    output reg  [63:0] data_out,
    output wire [7:0]  bank_active,
    output wire        timing_error
);

    localparam DEPTH = 1 << MEM_DEPTH_LOG2;
    
    // PT: Arrays de memória (Modelagem comportamental)
    // EN: Memory arrays (Behavioral modeling)
    reg [63:0] bank0 [0:DEPTH-1];
    reg [63:0] bank1 [0:DEPTH-1];
    reg [63:0] bank2 [0:DEPTH-1];
    reg [63:0] bank3 [0:DEPTH-1];
    reg [63:0] bank4 [0:DEPTH-1];
    reg [63:0] bank5 [0:DEPTH-1];
    reg [63:0] bank6 [0:DEPTH-1];
    reg [63:0] bank7 [0:DEPTH-1];

    reg [13:0] active_row [0:7];
	reg [MEM_DEPTH_LOG2-1:0] eff_addr;
	 
    // PT: Pipeline de Escrita (DDR Latency) | EN: Write Pipeline (DDR Latency)
    reg [3:0] write_timer;
    reg [2:0] write_bank;
    reg [9:0] write_col;

    integer i, b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(i = 0; i < 8; i = i + 1)
                active_row[i] <= 14'd0;
            data_out <= 64'd0;
            write_timer <= 4'd0;
            write_bank  <= 3'd0;
            write_col   <= 10'd0;
        end else begin
            // 1. PT: Lógica de Ativação (ACT) | EN: Activation Logic (ACT)
            if (act_cmd) begin
                active_row[bank_addr] <= row_addr;
            end
            
            // 2. PT: Agendamento de Escrita (WL) | EN: Write Scheduling (WL)
            if (wr_cmd && bank_active[bank_addr] && !timing_error) begin
                write_timer <= 4'd8; // PT: Espera o processamento do burst | EN: Wait for burst processing
                write_bank  <= bank_addr;
                write_col   <= col_addr;
            end else if (write_timer > 0) begin
                write_timer <= write_timer - 4'd1;
            end

            // 3. PT: Execução da Escrita Diferida | EN: Deferred Write Execution
            if (write_timer == 4'd1) begin
                eff_addr = {active_row[write_bank], write_col[9:3]} & (DEPTH - 1);
                for (b = 0; b < 8; b = b + 1) begin
                    if (!dm_in[b]) begin
                        case (write_bank)
                            3'd0: bank0[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                            3'd1: bank1[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                            3'd2: bank2[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                            3'd3: bank3[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                            3'd4: bank4[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                            3'd5: bank5[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                            3'd6: bank6[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                            3'd7: bank7[eff_addr][b*8 +: 8] <= data_in[b*8 +: 8];
                        endcase
                    end
                end
            end

            // 4. PT: Execução de Leitura (Síncrona) | EN: Synchronous Read Execution
            if (rd_cmd && bank_active[bank_addr] && !timing_error) begin
                eff_addr = {active_row[bank_addr], col_addr[9:3]} & (DEPTH - 1);
                case (bank_addr)
                    3'd0: data_out <= bank0[eff_addr];
                    3'd1: data_out <= bank1[eff_addr];
                    3'd2: data_out <= bank2[eff_addr];
                    3'd3: data_out <= bank3[eff_addr];
                    3'd4: data_out <= bank4[eff_addr];
                    3'd5: data_out <= bank5[eff_addr];
                    3'd6: data_out <= bank6[eff_addr];
                    3'd7: data_out <= bank7[eff_addr];
                endcase
            end
        end
    end

    // PT: Instanciação do controlador de bancos | EN: Bank control instantiation
    dram_bank_control #(
        .freq(freq),
        .T_RCD_CYCLES((freq / 67) + 1),
        .T_RP_CYCLES((freq / 67) + 1)
    ) bank_inst (
        .clk(clk), 
        .rst_n(rst_n), 
        .act_cmd(act_cmd), 
        .pre_cmd(pre_cmd), 
        .rd_cmd(rd_cmd), 
        .wr_cmd(wr_cmd),
        .bank_addr(bank_addr),
        .bank_active(bank_active),
        .timing_error(timing_error)
    );

endmodule
