// [PT] Definição do teste principal UVM, instanciando ambiente e inicializando sequências / [EN] Main UVM test definition, instantiating environment and starting sequences
class axi4lite_test extends uvm_test;
    `uvm_component_utils(axi4lite_test)
    
    // [PT] Instância do ambiente / [EN] Environment instance
    axi4lite_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axi4lite_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        axi4lite_sequence seq;
        phase.raise_objection(this);
        
        `uvm_info("TEST", "Iniciando Teste Randomico AXI4-Lite e DDR3", UVM_LOW)
        seq = axi4lite_sequence::type_id::create("seq");
        // [PT] Inicializa a sequência no sequencer do agent / [EN] Starts the sequence on the agent's sequencer
        seq.start(env.agent.sequencer);

        #5000; // [PT] Tempo de drenagem e conclusao / [EN] Drain time and completion
        
        phase.drop_objection(this);
    endtask
endclass