/*
 * module: row_tracker
 * -----------------
 * PT: Rastreador de Linhas Abertas. 
 *     Mantém um registro da linha que está atualmente ativa em cada um dos 8 bancos.
 *     Essencial para implementar a política de página aberta (Page Hit/Miss).
 * 
 * EN: Open Row Tracker.
 *     Keeps track of which row is currently active in each of the 8 banks.
 *     Essential for implementing the Open Page policy (Page Hit/Miss).
 */
module row_tracker(
    input  wire        clk, rst_n, 
    input  wire        update_row_en,   // [PT] Sinal para salvar nova linha / [EN] Signal to store new row
    input  wire [2:0]  cpu_bank_addr,   // [PT] Banco alvo / [EN] Target bank
    input  wire [13:0] cpu_row_addr,    // [PT] Linha alvo / [EN] Target row
    input  wire [7:0]  cpu_idle_flag,   // [PT] Status: Bancos ociosos / [EN] Status: Idle banks
    input  wire [7:0]  cpu_active_flag, // [PT] Status: Bancos ativos / [EN] Status: Active banks
    output wire        page_hit,        // [PT] Linha já está aberta / [EN] Row is already open
    output wire        page_miss,       // [PT] Outra linha está aberta / [EN] Different row is open
    output wire        page_empty       // [PT] Nenhuma linha está aberta / [EN] No row is open
);

    // [PT] Array para armazenar o endereço da linha aberta em cada banco / [EN] Array to store the open row address for each bank
    reg [13:0] open_row_array [0:7];

    // [PT] Lógica de detecção de estado de página / [EN] Page state detection logic
    assign page_empty = cpu_idle_flag[cpu_bank_addr];
    assign page_hit   = (cpu_active_flag[cpu_bank_addr] && (cpu_row_addr == open_row_array[cpu_bank_addr]));
    assign page_miss  = (cpu_active_flag[cpu_bank_addr] && (cpu_row_addr != open_row_array[cpu_bank_addr]));

    // [PT] Atualização do registro de linhas síncrona com reset / [EN] Synchronous row register update with reset
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            // [PT] Limpa todos os registros no reset / [EN] Clears all registers on reset
            open_row_array[0] <= 14'd0;
            open_row_array[1] <= 14'd0;
            open_row_array[2] <= 14'd0;
            open_row_array[3] <= 14'd0;
            open_row_array[4] <= 14'd0;
            open_row_array[5] <= 14'd0;
            open_row_array[6] <= 14'd0;
            open_row_array[7] <= 14'd0;
        end else if (update_row_en) begin
            // [PT] Armazena a nova linha quando habilitado / [EN] Stores the new row when enabled
            open_row_array[cpu_bank_addr] <= cpu_row_addr;
        end
    end			
endmodule
