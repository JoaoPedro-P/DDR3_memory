// =====================================================================
// [PT] Arquivo: axi4lite_env.sv / [EN] File: axi4lite_env.sv
// [PT] Descrição: Classe de Ambiente UVM para AXI4-Lite. Agrupa Agente e Scoreboard. / [EN] Description: UVM Environment class for AXI4-Lite. Groups Agent and Scoreboard.
// =====================================================================

class axi4lite_env extends uvm_env;
    `uvm_component_utils(axi4lite_env)
    
    // [PT] Componentes do ambiente / [EN] Environment components
    axi4lite_agent      agent;
    axi4lite_scoreboard sb;

    // [PT] Construtor / [EN] Constructor
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // [PT] Fase de construção: cria os componentes do ambiente / [EN] Build phase: creates environment components
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = axi4lite_agent::type_id::create("agent", this);
        sb    = axi4lite_scoreboard::type_id::create("sb", this);
    endfunction

    // [PT] Fase de conexão: liga a porta do monitor ao scoreboard / [EN] Connect phase: links the monitor port to the scoreboard
    function void connect_phase(uvm_phase phase);
        agent.monitor.mon_ap.connect(sb.actual_fifo.analysis_export);
    endfunction
endclass