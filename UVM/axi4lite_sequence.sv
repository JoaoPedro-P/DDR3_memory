// [PT] Sequência que gera as transações de inicialização e os testes randômicos / [EN] Sequence that generates initialization transactions and random tests
class axi4lite_sequence extends uvm_sequence #(axi4lite_item);
    `uvm_object_utils(axi4lite_sequence)

    function new(string name = "axi4lite_sequence");
        super.new(name);
    endfunction

    task body();
        bit [13:0] r_row;
        bit [2:0]  r_bank;
        bit [9:0]  r_col;
        bit [26:0] axi_addr;

        // =========================================================
        // [PT] FASE 1: Pre-carregamento dinâmico / [EN] PHASE 1: Dynamic pre-loading
        // =========================================================
        `uvm_info("SEQ", $sformatf("FASE 1: Preenchendo %0d bancos com profundidade %0d...", NUM_BANKS, DEPTH), UVM_LOW)
        
        // [PT] Laços aninhados para preencher os bancos de memória / [EN] Nested loops to fill memory banks
        for (int b = 0; b < NUM_BANKS; b++) begin
            for (int d = 0; d < DEPTH; d++) begin
                req = axi4lite_item::type_id::create("req");
                start_item(req);
                
                r_bank = b;
                r_row  = d >> 7;             
                r_col  = (d & 7'h7F) << 3;   
                axi_addr = {r_row, r_bank, r_col};

                if (!req.randomize() with {
                    rnw  == 0; // [PT] 0 = Escrita / [EN] 0 = Write
                    addr == axi_addr;
                    data == 32'h00000007;
                    prot == 3'b001;
                }) `uvm_error("SEQ", "Falha de Randomizacao no Fill");
                
                finish_item(req);
            end
        end
        
        // =========================================================
        // [PT] FASE 2: Escritas e Leituras randomicas e misturadas / [EN] PHASE 2: Random and mixed Reads and Writes
        // =========================================================
        `uvm_info("SEQ", $sformatf("FASE 2: %0d Transacoes (Read/Write misturados)...", NUM_TESTS), UVM_LOW)
        // [PT] Laço de repetição para os testes randômicos / [EN] Repeat loop for random tests
        repeat(NUM_TESTS) begin
            req = axi4lite_item::type_id::create("req");
            start_item(req);
            
            if (!req.randomize() with {
                prot == 3'b001; 
		//addr inside {27'h34cc91d, 27'h776b18};
            }) `uvm_error("SEQ", "Falha de Randomizacao na Fase Mista");
            
            finish_item(req);
        end
    endtask
endclass