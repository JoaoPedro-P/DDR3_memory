// [PT] Módulo de monitoramento AXI-Lite que observa transações no barramento / [EN] AXI-Lite monitor module that observes transactions on the bus
class axi4lite_monitor extends uvm_monitor;
    `uvm_component_utils(axi4lite_monitor)
    
    // [PT] Interface virtual para o barramento AXI-Lite / [EN] Virtual interface for the AXI-Lite bus
    virtual axi4lite_if vif;
    // [PT] Porta de análise para enviar os itens transacionados / [EN] Analysis port to send transacted items
    uvm_analysis_port #(axi4lite_item) mon_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon_ap = new("mon_ap", this);
        if(!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif)) 
            `uvm_fatal("MON", "No vif")
    endfunction

    task run_phase(uvm_phase phase);
        axi4lite_item item;
        
        // [PT] Loop contínuo para monitorar o barramento / [EN] Continuous loop to monitor the bus
        forever begin
            @(posedge vif.clk_axi_bus);
            
            // [PT] Verifica se uma escrita foi concluída / [EN] Checks if a write has completed
            if (vif.m_wdone) begin
                item = axi4lite_item::type_id::create("item");
                item.rnw   = 0;
                item.addr  = vif.m_addr;
                item.data  = vif.m_wdata;
                item.wstrb = vif.m_wstrb;
                item.prot  = vif.m_awprot;
                item.resp  = vif.m_wresp;
                // [PT] Envia o item para a porta de análise / [EN] Sends the item to the analysis port
                mon_ap.write(item);
            end 
            // [PT] Verifica se uma leitura foi concluída / [EN] Checks if a read has completed
            else if (vif.m_rdone) begin
                item = axi4lite_item::type_id::create("item");
                item.rnw   = 1;
                item.addr  = vif.m_addr;
                item.rdata = vif.m_rdata;
                item.prot  = vif.m_arprot;
                item.resp  = vif.m_rresp;
                // [PT] Envia o item para a porta de análise / [EN] Sends the item to the analysis port
                mon_ap.write(item);
            end
        end
    endtask
endclass