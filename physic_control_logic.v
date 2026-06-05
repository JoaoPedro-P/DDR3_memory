/*
 * module: physic_control_logic
 * -----------------
 * PT: Lógica de Controle da Camada Física (PHY). 
 *     Garante o timing correto para bursts de escrita: Preâmbulo, Dados e Pós-âmbulo.
 * 
 * EN: Physical Layer Control Logic (PHY).
 *     Ensures correct timing for write bursts: Preamble, Data, and Postamble.
 */
module physic_control_logic (
    input  wire clk, rst_n, 
    input  wire write_req,   // PT: Início da escrita | EN: Start of write
    output reg  tx_fifo_rd,  // PT: Pop da FIFO TX | EN: TX FIFO Pop
    output reg  phy_dq_en,   // PT: Habilita Tri-state DQ | EN: DQ Tri-state Enable
    output reg  phy_dqs_en,  // PT: Habilita Tri-state DQS | EN: DQS Tri-state Enable
    output reg  phy_dqs_val, // PT: Ativa strobe pulsante | EN: Enable pulsing strobe
    output reg  odt_out      // PT: Ativa Terminação On-Die | EN: Enable On-Die Termination
);

    // PT: Contador de burst (0 a 3 ciclos SDR = 8 batidas DDR)
    // EN: Burst counter (0 to 3 SDR cycles = 8 DDR beats)
    reg [2:0] burst_counter;

    // PT: Estados da FSM PHY | EN: PHY FSM States
    reg [1:0] state;
    parameter IDLE = 2'd0, PREAMBLE = 2'd1, DATA = 2'd2, POSTAMBLE = 2'd3;

    // PT: Bloco Combinacional de Controle | EN: Combinational Control Block
    always @ (*) begin
        tx_fifo_rd   = 1'b0;
        phy_dq_en    = 1'b0;
        phy_dqs_en   = 1'b0;
        phy_dqs_val  = 1'b0;
        odt_out      = 1'b0;

        case (state)
            IDLE: begin end
            PREAMBLE: begin
                phy_dqs_en   = 1'b1;
                odt_out      = 1'b1;
            end
            DATA: begin
                phy_dq_en    = 1'b1;
                phy_dqs_en   = 1'b1;
                phy_dqs_val  = 1'b1; 
                odt_out      = 1'b1;
                tx_fifo_rd   = 1'b1; // PT: Puxa dado da FIFO | EN: Pull data from FIFO
            end
            POSTAMBLE: begin
                phy_dqs_en   = 1'b1;
                odt_out      = 1'b1;
            end
        endcase
    end

    // PT: Máquina de Estados Principal | EN: Main FSM
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if(write_req) state <= PREAMBLE;
                    else state <= IDLE;
                end
                PREAMBLE: begin
                    state <= DATA;
                end
                DATA: begin
                    if (burst_counter < 3)
                        state <= DATA;
                    else
                        state <= POSTAMBLE;
                end
                POSTAMBLE: begin
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
    
    // PT: Controle do Contador de Ciclos | EN: Cycle Counter Control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            burst_counter <= 3'd0;
        end else begin
            if (state == IDLE) begin
                burst_counter <= 3'd0;
            end else if (state == DATA) begin
                burst_counter <= burst_counter + 3'd1;
            end
        end
    end

endmodule
