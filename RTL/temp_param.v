/*
 * module: temp_param
 * -----------------
 * [PT] Temporizador Parametrizado. 
 * Contador decrescente configurável usado para garantir os tempos de espera JEDEC.
 * / [EN] Parameterized Timer.
 * Configurable down-counter used to ensure JEDEC wait times.
 */
module temp_param #(parameter freq = 100) (
    input  wire                       clk,        // [PT] Sinal de clock / [EN] Clock signal
    input  wire                       rst_n,      // [PT] Sinal de reset ativo baixo / [EN] Active low reset signal
    input  wire [$clog2(freq) + 1 : 0] num_cicles, // [PT] Valor alvo / [EN] Target value
    input  wire                       start,      // [PT] 1=Inicia contagem / [EN] 1=Start counting
    output reg  [$clog2(freq) + 1 : 0] out         // [PT] Valor atual / [EN] Current value
);

    // [PT] Bloco sequencial para contagem decrescente / [EN] Sequential block for down-counting
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            // [PT] Zera a saída no reset / [EN] Clears output on reset
            out <= 0;
        else if(!start)
            // [PT] Carrega valor inicial / [EN] Load initial value
            out <= num_cicles; 
        else if (out > 0)
            // [PT] Contagem decrescente / [EN] Count down
            out <= out - 9'd1;    
    end
endmodule
