/*
 * module: refresh_control_logic
 * -----------------
 * PT: Lógica de Controle de Refresh. 
 *     Este módulo é vital para a sobrevivência dos dados na DRAM. Como as células da 
 *     DDR3 são capacitivas, elas perdem carga ao longo do tempo. O controlador deve 
 *     enviar um comando REFRESH periodicamente para recarregar todas as linhas.
 * 
 *     Operação:
 *     - Calcula o intervalo de Refresh (tREFI) com base na frequência de clock.
 *     - Gera uma solicitação (refresh_req) a cada ~7.8 microssegundos (padrão JEDEC).
 *     - Aguarda o reconhecimento (refresh_ack) do agendador central para resetar o timer.
 *
 * EN: Refresh Control Logic.
 *     This module is vital for DRAM data survival. Since DDR3 cells are capacitive, 
 *     they lose charge over time. The controller must send a REFRESH command 
 *     periodically to recharge all rows.
 * 
 *     Operation:
 *     - Calculates the Refresh interval (tREFI) based on the clock frequency.
 *     - Generates a request (refresh_req) every ~7.8 microseconds (JEDEC standard).
 *     - Waits for acknowledgment (refresh_ack) from the central scheduler to reset the timer.
 */
module refresh_control_logic #(parameter freq = 100) (
    input  wire CK,          // PT: Clock da memória. | EN: Memory clock.
    input  wire RESET_n,     // PT: Reset (Ativo Baixo). | EN: Reset (Active Low).
    input  wire init_done,   // PT: Inicia o timer apenas após o boot JEDEC. | EN: Starts timer after JEDEC boot.
    input  wire refresh_ack, // PT: Confirmação de que o Refresh foi agendado. | EN: Refresh execution ack.
    output reg  refresh_req  // PT: Pedido de Refresh pendente. | EN: Pending Refresh request.
);

    // PT: Intervalo tREFI padrão (7.8us) | EN: Standard tREFI interval (7.8us)
    localparam tREFI_ns = 7800;
    
    // PT: Cálculo de ciclos baseado na frequência | EN: Cycle calculation based on frequency
    localparam REFRESH_INTERVAL = (tREFI_ns * freq) / 1000;

    reg [32:0] timer;
 
    always @(posedge CK or negedge RESET_n) begin
        if (!RESET_n) begin
            timer <= 16'd0;
            refresh_req <= 1'b0;
        end else if (refresh_ack) begin 
            timer <= 16'd0;
            refresh_req <= 1'b0;
        end else if (init_done) begin
            if (timer >= REFRESH_INTERVAL) begin
                refresh_req <= 1'b1;
            end else begin
                timer <= timer + 16'd1;
            end
        end
    end
endmodule
