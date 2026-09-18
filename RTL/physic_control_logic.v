/*
 * module: physic_control_logic
 * -----------------
 * [PT] Lógica de Controle da Camada Física (PHY). 
 *      Garante o timing correto para bursts de escrita: Preâmbulo, Dados e Pós-âmbulo.
 * 
 * [EN] Physical Layer Control Logic (PHY).
 *      Ensures correct timing for write bursts: Preamble, Data, and Postamble.
 */
module physic_control_logic (
    input  wire clk, rst_n, 
    input  wire write_req,   
    output reg  tx_fifo_rd,  
    output reg  phy_dq_en,   
    output reg  phy_dqs_en,  
    output reg  phy_dqs_val, 
    output reg  odt_out      
);

    reg [2:0] burst_counter;
    reg [1:0] state;
    parameter IDLE = 2'd0, PREAMBLE = 2'd1, DATA = 2'd2, POSTAMBLE = 2'd3;

    // [PT] Bloco Combinacional da FSM: define as saídas baseado no estado / [EN] Combinational FSM block: defines outputs based on state
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
                // [PT] Puxa 32-bits da FIFO APENAS no ciclo 0. / [EN] Pulls 32-bits from FIFO ONLY in cycle 0.
                // [PT] O dado será mantido e espelhado para cobrir o burst físico de 64 bits. / [EN] The data will be held and mirrored to cover the 64-bit physical burst.
                tx_fifo_rd   = (burst_counter == 3'd0); 
            end
            POSTAMBLE: begin
                phy_dqs_en   = 1'b1;
                odt_out      = 1'b1;
            end
        endcase
    end

    // [PT] Lógica Sequencial da FSM: atualiza estado / [EN] Sequential FSM Logic: updates state
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE:      if(write_req) state <= PREAMBLE; else state <= IDLE;
                PREAMBLE:  state <= DATA;
                DATA:      if (burst_counter < 3) state <= DATA; else state <= POSTAMBLE;
                POSTAMBLE: state <= IDLE;
                default:   state <= IDLE;
            endcase
        end
    end
    
    // [PT] Lógica do Contador de Burst / [EN] Burst Counter Logic
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