# AXI-Lite DDR3 SDRAM Memory Controller System
# Sistema Controlador de Memória DDR3 SDRAM com Interface AXI-Lite

## Overview | Visão Geral
**EN:** A complete Verilog implementation of a DDR3 memory controller with an industry-standard AXI-Lite interface. This project features high-level CPU communication via AXI, JEDEC-compliant control logic, and a full physical layer (PHY) with 90° phase shifting for DQS. The design is based on the Micron MT41J component series datasheet and the AMBA AXI Protocol Specification.

**PT:** Uma implementação completa em Verilog de um controlador de memória DDR3 com uma interface AXI-Lite padrão da indústria. Este projeto apresenta comunicação de alto nível via AXI, lógica de controle em conformidade com JEDEC e uma camada física (PHY) completa com deslocamento de fase de 90° para o DQS. O design é baseado no datasheet da série Micron MT41J e na especificação do protocolo AMBA AXI.

## Key Features | Funcionalidades Principais
- **EN:** **AXI-Lite Subordinate Interface:** Unified 16-bit interface for seamless integration with modern SOCs.
- **PT:** **Interface Escrava AXI-Lite:** Interface unificada de 16 bits para integração perfeita com SOCs modernos.
- **EN:** **Automatic Burst Handling:** Transparent translation between 16-bit AXI words and 64-bit DDR3 internal blocks.
- **PT:** **Gerenciamento Automático de Bursts:** Tradução transparente entre palavras AXI de 16 bits e blocos internos DDR3 de 64 bits.
- **EN:** **8 Internal Banks:** Independent state management and Open-Page policy (Hit/Miss/Empty).
- **PT:** **8 Bancos Internos:** Gerenciamento de estado independente e política de Página Aberta (Hit/Miss/Empty).
- **EN:** **Integrated PHY:** DQS phase shifting (emulating DLL) and bidirectional signal control for high-speed data integrity.
- **PT:** **PHY Integrada:** Deslocamento de fase DQS (emulando DLL) e controle de sinais bidirecionais para integridade de dados em alta velocidade.
- **EN:** **JEDEC Compliance:** Automatic initialization sequence, ZQ calibration, and periodic Refresh (tREFI).
- **PT:** **Conformidade JEDEC:** Sequência de inicialização automática, calibração ZQ e Refresh periódico (tREFI).

## Project Structure | Estrutura do Projeto
- `subordinate_module.v`: **Top-Level** module with AXI-Lite interface.
- `axi_controller.v`: AXI logic orchestrator (FSM + Datapath).
- `ddr_mem.v`: Main memory system core with CDC (Clock Domain Crossing) logic.
- `mem_controller.v`: Backend JEDEC state machine orchestrator.
- `dram_bank_array.v`: Functional memory model emulating analog components (Cells, Sense Amps, DM).
- `dqs_phase_shifter.v`: PHY component for 90° strobe alignment.
- `axi_tb.v`: Self-verifying AXI-level testbench.

## How to Run | Como Executar
**EN:**
1.  Load all `.v` files into your Verilog simulator (e.g., ModelSim, Vivado, Icarus Verilog).
2.  Set `axi_tb` as the top module for AXI-level verification or `tb_ddr_mem` for core-level verification.
3.  Run the simulation. The testbench will display "SUCESSO ABSOLUTO" upon completion.

**PT:**
1.  Carregue todos os arquivos `.v` no seu simulador Verilog (ex: ModelSim, Vivado, Icarus Verilog).
2.  Defina `axi_tb` como o módulo principal para verificação AXI ou `tb_ddr_mem` para verificação do core.
3.  Execute a simulação. O testbench exibirá "SUCESSO ABSOLUTO" ao concluir.

## Technical Documentation | Documentação Técnica
**EN:** For detailed architecture, timing parameters, and design simplifications, please refer to [REPORT.md](REPORT.md).

**PT:** Para detalhes sobre a arquitetura, parâmetros de tempo e simplificações de design, consulte o [REPORT.md](REPORT.md).

