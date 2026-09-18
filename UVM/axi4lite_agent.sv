// =====================================================================
// [PT] Arquivo: axi4lite_agent.sv / [EN] File: axi4lite_agent.sv
// [PT] Descrição: Classe Agente UVM para AXI4-Lite. Instancia e conecta o Driver, Sequencer e Monitor. / [EN] Description: UVM Agent class for AXI4-Lite. Instantiates and connects the Driver, Sequencer, and Monitor.
// =====================================================================

class axi4lite_agent extends uvm_agent;
    `uvm_component_utils(axi4lite_agent)

    // [PT] Componentes do Agente / [EN] Agent Components
    axi4lite_driver    driver;
    uvm_sequencer #(axi4lite_item) sequencer;
    axi4lite_monitor   monitor;

    // [PT] Construtor / [EN] Constructor
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // [PT] Fase de construção: cria os componentes / [EN] Build phase: creates components
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver    = axi4lite_driver::type_id::create("driver", this);
        sequencer = uvm_sequencer#(axi4lite_item)::type_id::create("sequencer", this);
        monitor   = axi4lite_monitor::type_id::create("monitor", this);
    endfunction

    // [PT] Fase de conexão: conecta a porta do driver ao export do sequencer / [EN] Connect phase: connects the driver port to the sequencer export
    function void connect_phase(uvm_phase phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass