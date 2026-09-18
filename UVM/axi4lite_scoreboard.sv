// [PT] Scoreboard para verificar as transações AXI-Lite em relação a um modelo de referência (golden model) / [EN] Scoreboard to verify AXI-Lite transactions against a golden model
class axi4lite_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(axi4lite_scoreboard)

    uvm_tlm_analysis_fifo #(axi4lite_item) actual_fifo;
    
    // [PT] Flag para controle de fase (1 = Inicialização, 0 = Teste Randômico) / [EN] Flag for phase control (1 = Initialization, 0 = Random Test)
    bit is_init_phase = 1'b1;

    // [PT] Array Associativo para o Golden Model / [EN] Associative Array for the Golden Model
    bit [31:0] golden_mem [int];
    
    // [PT] Contador exclusivo para a fase de inicialização / [EN] Exclusive counter for the initialization phase
    int init_writes = 0;

    // [PT] Contadores de operações (Fase Randômica) / [EN] Operation counters (Random Phase)
    int count_writes = 0;
    int count_reads  = 0;
    int write_errors = 0;
    int read_errors  = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        actual_fifo = new("actual_fifo", this);
    endfunction

    // -------------------------------------------------------------
    // [PT] Função para alternar a fase atual do scoreboard / [EN] Function to toggle the current scoreboard phase
    // [PT] Deve ser chamada pelo Test após a sequence de inicialização / [EN] Should be called by the Test after the initialization sequence
    // -------------------------------------------------------------
    function void set_init_phase(bit state);
        is_init_phase = state;
    endfunction

    // -------------------------------------------------------------
    // [PT] Utiliza a constante DEPTH declarada globalmente no axi4lite_pkg / [EN] Uses the DEPTH constant globally declared in axi4lite_pkg
    // -------------------------------------------------------------
    function int get_golden_idx(bit [26:0] addr);
        bit [13:0] r_row  = addr[26:13];
        bit [2:0]  r_bank = addr[12:10];
        bit [9:0]  r_col  = addr[9:0];
        
        int eff_addr = int'({r_row, r_col[9:3]}) & (DEPTH - 1);
        return (r_bank * DEPTH) + eff_addr;
    endfunction

task run_phase(uvm_phase phase);
    axi4lite_item tr;
    int phys_idx;

    // [PT] Loop contínuo processando transações / [EN] Continuous loop processing transactions
    forever begin
        actual_fifo.get(tr);

        if (tr.resp != 2'b00) continue; 

        phys_idx = get_golden_idx(tr.addr);

        if (is_init_phase) begin
            // --- [PT] FASE 1: INICIALIZAÇÃO / [EN] PHASE 1: INITIALIZATION ---
            if (tr.rnw == 0) begin // [PT] Write / [EN] Write
                golden_mem[phys_idx] = tr.data;
                init_writes++;

                // [PT] Troca a fase automaticamente ao processar a 8192ª escrita / [EN] Automatically toggles phase upon processing the 8192nd write
                if (init_writes == (NUM_BANKS * DEPTH)) begin // [PT] ou 8192 / [EN] or 8192
                    is_init_phase = 1'b0;
                    `uvm_info("SB_PHASE_CHANGE", "Fase de carga concluida. Alterando para Fase Randomica!", UVM_LOW)
                end
            end
        end 
        else begin
            // --- [PT] FASE 2: TESTES RANDÔMICOS / [EN] PHASE 2: RANDOM TESTS ---
            if (tr.rnw == 0) begin // [PT] Write / [EN] Write
                golden_mem[phys_idx] = tr.data;
                count_writes++;
            end 
            else begin // [PT] Read / [EN] Read
                count_reads++;
                if (golden_mem.exists(phys_idx)) begin
                    if (tr.rdata === golden_mem[phys_idx]) begin
                        // [PT] Leitura Aprovada / [EN] Read Passed
                    end else begin
                        read_errors++;
                        `uvm_error("SB_READ_MISMATCH", $sformatf("Erro! End: %0h | Lido: %0h | Esp: %0h", tr.addr, tr.rdata, golden_mem[phys_idx]))
                    end
                end else begin
                    read_errors++;
                    `uvm_error("SB_CRITICAL", $sformatf("Leitura nao inicializada: %0h", tr.addr))
                end
            end
        end
    end
endtask
    function void report_phase(uvm_phase phase);
        int total_ops  = count_writes + count_reads;
        int total_err  = write_errors + read_errors;
        int total_pass = total_ops - total_err;

        real pass_pct, err_pct, write_pct, read_pct, read_pass_pct, write_pass_pct;

        // [PT] Cálculos apenas para a fase randômica / [EN] Calculations only for the random phase
        if (total_ops > 0) begin
            pass_pct  = (real'(total_pass)   / total_ops) * 100.0;
            err_pct   = (real'(total_err)    / total_ops) * 100.0;
            write_pct = (real'(count_writes) / total_ops) * 100.0;
            read_pct  = (real'(count_reads)  / total_ops) * 100.0;
        end else begin
            pass_pct = 0.0; err_pct = 0.0; write_pct = 0.0; read_pct = 0.0;
        end

        if (count_reads > 0) begin
            read_pass_pct = (real'(count_reads - read_errors) / count_reads) * 100.0;
        end else begin
            read_pass_pct = 0.0;
        end

        if (count_writes > 0) begin
            write_pass_pct = (real'(count_writes - write_errors) / count_writes) * 100.0;
        end else begin
            write_pass_pct = 0.0;
        end

        `uvm_info("SB_REPORT", $sformatf({"\n====================================================",
                                          "\n         AXI4-LITE MEMORY DETAILED TEST REPORT",
                                          "\n====================================================",
                                          "\n  [FASE 1] CARREGAMENTO DE MEMORIA:",
                                          "\n    -> Total de Escritas Iniciais:      %0d",
                                          "\n====================================================",
                                          "\n  [FASE 2] TESTES RANDOMICOS GERAIS:",
                                          "\n    -> Total de Transacoes:             %0d",
                                          "\n    -> Testes Aprovados (Pass):         %0d (%0.2f%%)",
                                          "\n    -> Testes Reprovados (Fail):        %0d (%0.2f%%)",
                                          "\n----------------------------------------------------",
                                          "\n  DISTRIBUICAO DAS OPERACOES:",
                                          "\n    -> Escritas (Writes):               %0d (%0.2f%% do total)",
                                          "\n    -> Leituras (Reads):                %0d (%0.2f%% do total)",
                                          "\n----------------------------------------------------",
                                          "\n  DESEMPENHO POR OPERACAO:",
                                          "\n    [LEITURA]",
                                          "\n      -> Leituras Aprovadas:            %0d (%0.2f%% das leituras)",
                                          "\n      -> Leituras Reprovadas:           %0d",
                                          "\n    [ESCRITA]",
                                          "\n      -> Escritas Efetuadas (Pass):     %0d (%0.2f%% das escritas)",
                                          "\n      -> Escritas com Erro (Fail):      %0d",
                                          "\n===================================================="}, 
                  init_writes,
                  total_ops, 
                  total_pass, pass_pct, 
                  total_err, err_pct, 
                  count_writes, write_pct, 
                  count_reads, read_pct,
                  (count_reads - read_errors), read_pass_pct, read_errors,
                  (count_writes - write_errors), write_pass_pct, write_errors), UVM_LOW)
    endfunction
endclass