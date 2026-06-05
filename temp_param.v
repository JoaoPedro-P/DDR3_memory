/*
 * module: temp_param
 * -----------------
 * PT: Temporizador Parametrizado. 
 *     Contador decrescente configurável usado para garantir os tempos de espera JEDEC.
 * 
 * EN: Parameterized Timer.
 *     Configurable down-counter used to ensure JEDEC wait times.
 */
module temp_param #(parameter freq = 100) (
    input  wire                       clk, 
    input  wire                       rst_n, 
    input  wire [$clog2(freq) + 1 : 0] num_cicles, // PT: Valor alvo | EN: Target value
    input  wire                       start,      // PT: 1=Inicia contagem | EN: 1=Start counting
    output reg  [$clog2(freq) + 1 : 0] out         // PT: Valor atual | EN: Current value
);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            out <= 0;
        else if(!start)
            out <= num_cicles; // PT: Carrega valor inicial | EN: Load initial value
        else if (out > 0)
            out <= out - 1;    // PT: Contagem decrescente | EN: Count down
    end
endmodule
