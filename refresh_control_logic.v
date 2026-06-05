/*
 * module: refresh_control_logic
 * -----------------
 * PT: Lógica de Controle de Refresh. 
 *     Gera solicitações de Refresh (refresh_req) periodicamente (tREFI = 7.8us).
 * 
 * EN: Refresh Control Logic.
 *     Generates Refresh requests (refresh_req) periodically based on the tREFI interval (7.8us).
 */
module refresh_control_logic #(parameter freq = 100) (
    input  wire CK, 
    input  wire RESET_n, 
    input  wire init_done, 
    input  wire refresh_ack, // PT: Reconhecimento do Scheduler | EN: Ack from Scheduler
    output reg  refresh_req  // PT: Solicitação de Refresh | EN: Refresh request
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
