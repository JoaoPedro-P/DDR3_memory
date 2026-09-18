// =====================================================================
// [PT] Arquivo: axi4lite_driver.sv / [EN] File: axi4lite_driver.sv
// [PT] Descrição: Classe Driver UVM para AXI4-Lite. Transforma itens de sequência em sinais de nível de pino para o DUT. / [EN] Description: UVM Driver class for AXI4-Lite. Transforms sequence items into pin-level signals for the DUT.
// =====================================================================

class axi4lite_driver extends uvm_driver #(axi4lite_item);
    `uvm_component_utils(axi4lite_driver)
    
    // [PT] Interface virtual para o barramento / [EN] Virtual interface to the bus
    virtual axi4lite_if vif;

    // [PT] Construtor / [EN] Constructor
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // [PT] Fase de construção: obtém a interface virtual / [EN] Build phase: gets the virtual interface
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif)) 
            `uvm_fatal("DRV", "No vif")
    endfunction

    // [PT] Fase de execução: inicializa sinais e processa itens / [EN] Run phase: initializes signals and processes items
    task run_phase(uvm_phase phase);
        // [PT] Inicialização dos sinais / [EN] Signals initialization
        vif.STARTW <= 0; vif.STARTR <= 0;
        vif.m_addr <= 0; vif.m_wdata <= 0; vif.m_wstrb <= 0; 
        vif.m_awprot <= 0; vif.m_arprot <= 0;

        // [PT] Espera a borda de subida do reset / [EN] Waits for the rising edge of reset
        @(posedge vif.resetn_bus);
        `uvm_info("DRV", "Aguardando inicializacao da memoria...", UVM_LOW) // [PT] Aguardando inicializacao da memoria... / [EN] Waiting for memory initialization...
        
        // [PT] Equivalente ao #5000 do testbench original para a DDR init / [EN] Equivalent to #5000 from the original testbench for DDR init
        repeat(200) @(posedge vif.clk_axi_bus); 
        
        // [PT] Loop principal para obter e dirigir itens / [EN] Main loop to get and drive items
        forever begin
            seq_item_port.get_next_item(req);
            drive_item(req);
            seq_item_port.item_done();
        end
    endtask

    // [PT] Tarefa para conduzir um item ao barramento / [EN] Task to drive an item to the bus
    task drive_item(axi4lite_item item);
        @(posedge vif.clk_axi_bus);
        #1; // [PT] Evita condicoes de corrida / [EN] Prevents race conditions
        
        if (item.rnw == 0) begin // [PT] Escrita / [EN] Write
            vif.m_addr   <= item.addr;
            vif.m_wdata  <= item.data;
            vif.m_wstrb  <= item.wstrb;
            vif.m_awprot <= item.prot;
            vif.STARTW   <= 1'b1;
            
            @(posedge vif.clk_axi_bus);
            #1;
            vif.STARTW <= 1'b0;
            
            // [PT] Aguarda conclusão da escrita / [EN] Waits for write completion
            wait(vif.m_wdone == 1'b1);
            item.resp = vif.m_wresp;
        end else begin // [PT] Leitura / [EN] Read
            vif.m_addr   <= item.addr;
            vif.m_arprot <= item.prot;
            vif.STARTR   <= 1'b1;
            
            @(posedge vif.clk_axi_bus);
            #1;
            vif.STARTR <= 1'b0;
            
            // [PT] Aguarda conclusão da leitura e captura os dados / [EN] Waits for read completion and captures data
            wait(vif.m_rdone == 1'b1);
            item.rdata = vif.m_rdata;
            item.resp  = vif.m_rresp;
        end
        @(posedge vif.clk_axi_bus); // [PT] Ciclo extra para finalizar transacao / [EN] Extra cycle to finalize transaction
    endtask
endclass