// [PT] Módulo de Máquina de Estados (FSM) do AXI-Lite. Responsável por controlar as transações e o datapath. / [EN] AXI-Lite Finite State Machine (FSM) module. Responsible for controlling transactions and the datapath.
// [PT] Coordena os handshakes AXI (VALID/READY) e interage com a memória e a FSM principal. / [EN] Coordinates AXI handshakes (VALID/READY) and interacts with memory and the main FSM.
module axi_lite_fsm(
    input      ACLK,
    input      ARESETn,

    input      AWVALID,
    input      WVALID,
    input      BREADY,
    input      ARVALID,
    input      RREADY,
    
    // [PT] Entradas de Erro do Datapath / [EN] Datapath Error Inputs
    input      error_write,
    input      error_read,

    output     AWREADY,
    output     WREADY,
    output     BVALID,
    output     ARREADY,
    output     RVALID,

    input      cpu_ready,
    input      rx_valid,
    input      tx_full,
    input      tx_empty,
    input      init_done,

    output reg cpu_req,
    output reg cpu_rnw,
    output reg cpu_wr_en,

    output     latch_aw,
    output     latch_w,
    output     latch_ar,
    output reg latch_r,
    output     sel_read
);

    // [PT] Definição dos estados da FSM / [EN] FSM state definitions
    parameter IDLE       = 4'd0, 
              READ_MEM   = 4'd1, 
              READ_R1    = 4'd2, 
              READ_RESP  = 4'd4, 
              WRITE_W1   = 4'd5, 
              WRITE_W2   = 4'd6, 
              WRITE_ACK  = 4'd8, 
              WRITE_WAIT = 4'd9, 
              WRITE_RESP = 4'd7;

    // [PT] Registrador de estado e flags / [EN] State register and flags
    reg [3:0] state;
    reg aw_latch_flag;
    reg w_latch_flag;

    // [PT] Atribuições das saídas READY / [EN] READY output assignments
    assign ARREADY = (state == IDLE) && init_done;
    assign AWREADY = (state == IDLE) && init_done && !ARVALID && !aw_latch_flag;
    assign WREADY  = (state == IDLE) && init_done && !ARVALID && !w_latch_flag;

    // [PT] Atribuições das saídas VALID de resposta / [EN] Response VALID output assignments
    assign BVALID  = (state == WRITE_RESP);
    assign RVALID  = (state == READ_RESP);

    // [PT] Sinais de latch combinatórios para o datapath / [EN] Combinational latch signals for the datapath
    assign latch_ar = ARVALID && ARREADY;
    assign latch_aw = AWVALID && AWREADY;
    assign latch_w  = WVALID  && WREADY;

    // [PT] Atualizado para remover o referenciamento ao READ_R2 antigo / [EN] Updated to remove reference to the old READ_R2
    assign sel_read = (state == READ_MEM) || (state == READ_R1) || (state == READ_RESP);

    // [PT] Bloco combinatório para saídas de controle da CPU dependendo do estado atual / [EN] Combinational block for CPU control outputs depending on the current state
    always @(*) begin
        // [PT] Valores default para evitar inferência de latch / [EN] Default values to avoid latch inference
        cpu_req   = 1'b0;
        cpu_rnw   = 1'b0;
        cpu_wr_en = 1'b0;
        latch_r   = 1'b0;

        case (state)
            READ_MEM: begin
                if (!error_read && cpu_ready) begin
                    cpu_req = 1'b1;
                    cpu_rnw = 1'b1;
                end
            end
            READ_R1: begin 
                if (!error_read && rx_valid) latch_r = 1'b1;
            end
            WRITE_W1: begin
                // [PT] Comando duplicado removido. Transição limpa. / [EN] Duplicated command removed. Clean transition.
            end
            WRITE_W2: begin
                if (!error_write && cpu_ready && !tx_full) begin 
                    cpu_req   = 1'b1;
                    cpu_wr_en = 1'b1;
                end
            end 
            // [PT] Em WRITE_WAIT, as saídas cpu_req e cpu_wr_en cairão para 0 naturalmente / [EN] In WRITE_WAIT, the outputs cpu_req and cpu_wr_en will naturally fall to 0
            // [PT] pois não estão declaradas aqui (assumem o valor default do início do bloco) / [EN] because they are not declared here (they assume the default value from the start of the block)
            default: begin end
        endcase
    end

    // [PT] Bloco sequencial para atualização de estado e flags na FSM / [EN] Sequential block for state and flag update in the FSM
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            state         <= IDLE;
            aw_latch_flag <= 1'b0;
            w_latch_flag  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (init_done) begin
                        if (latch_aw) aw_latch_flag <= 1'b1;
                        if (latch_w)  w_latch_flag  <= 1'b1;

                        if (latch_ar) begin
                            state <= READ_MEM;
                        end else if ((aw_latch_flag || latch_aw) && (w_latch_flag || latch_w)) begin
                            state <= WRITE_W1;
                            aw_latch_flag <= 1'b0;
                            w_latch_flag  <= 1'b0;
                        end
                    end
                end
                
                // [PT] --- PIPELINE DE LEITURA --- / [EN] --- READ PIPELINE ---
                READ_MEM:  if (error_read) state <= READ_RESP; else if (cpu_ready) state <= READ_R1;
                READ_R1:   if (rx_valid)  state <= READ_RESP; 
                READ_RESP: if (RREADY)    state <= IDLE;
                
                // [PT] --- PIPELINE DE ESCRITA DEFINITIVO --- / [EN] --- DEFINITIVE WRITE PIPELINE ---
                WRITE_W1:   if (error_write || !tx_full) state <= WRITE_W2;
                
                WRITE_W2:   if (error_write) state <= WRITE_RESP;
                            else if (cpu_ready && !tx_full) state <= WRITE_ACK; 
                            
                // [PT] PASSO 1: Trava aqui até a FIFO registrar o dado (tx_empty cai para 0) / [EN] STEP 1: Locks here until the FIFO registers the data (tx_empty falls to 0)
                // [PT] Isso elimina o "falso positivo" do estado anterior. / [EN] This eliminates the "false positive" from the previous state.
                WRITE_ACK:  if (!tx_empty) state <= WRITE_WAIT;
                
                // [PT] PASSO 2: Agora sim, espera a memória gravar na RAM (tx_empty sobe para 1) / [EN] STEP 2: Now yes, waits for memory to write to RAM (tx_empty rises to 1)
                WRITE_WAIT: if (tx_empty) state <= WRITE_RESP;
                
                WRITE_RESP: if (BREADY) state <= IDLE;
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule