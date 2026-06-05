# DDR3 SDRAM Memory Controller System
# Controlador de Memória DDR3 SDRAM

## Overview | Visão Geral
**EN:** A complete Verilog implementation of a DDR3 memory controller, including high-level CPU communication, JEDEC-compliant control logic, and a physical layer (PHY). Designed based on the Micron MT41J series datasheet.

**PT:** Uma implementação completa em Verilog de um controlador de memória DDR3, incluindo comunicação com CPU de alto nível, lógica de controle em conformidade com JEDEC e uma camada física (PHY). Projetado com base no datasheet da série Micron MT41J.

## Key Features | Funcionalidades Principais
- **EN:** Support for 8 internal banks with independent state management.
- **PT:** Suporte para 8 bancos internos com gerenciamento de estado independente.
- **EN:** Automatic JEDEC initialization sequence and ZQ calibration.
- **PT:** Sequência de inicialização JEDEC automática e calibração ZQ.
- **EN:** Open-Page policy for optimized memory access (Hit/Miss/Empty).
- **PT:** Política de Página Aberta para acesso otimizado à memória (Hit/Miss/Empty).
- **EN:** Integrated PHY with DQS phase shifting (90°) and SDR-DDR conversion.
- **PT:** PHY integrada com deslocamento de fase DQS (90°) e conversão SDR-DDR.
- **EN:** Periodic Refresh management (tREFI).
- **PT:** Gerenciamento de Refresh periódico (tREFI).
- **EN:** Asynchronous Command and Data FIFOs for Clock Domain Crossing.
- **PT:** FIFOs de Comandos e Dados Assíncronas para travessia de domínios de clock.

## Project Structure | Estrutura do Projeto
- `ddr_mem.v`: Top-level module.
- `mem_controller.v`: Backend & PHY orchestrator.
- `control_unit.v`: Main arbitration logic.
- `interface_control_unit.v`: Frontend & Address translation.
- `datapath.v`: Physical Layer implementation.
- `dram_bank_array.v`: Functional memory model for simulation.
- `tb_ddr_mem.v`: Full system testbench.

## How to Run | Como Executar
**EN:**
1.  Load all `.v` files into your Verilog simulator (e.g., ModelSim, Vivado, Icarus Verilog).
2.  Set `tb_ddr_mem` as the top module.
3.  Run the simulation. The testbench will display "SUCESSO ABSOLUTO" upon completion.

**PT:**
1.  Carregue todos os arquivos `.v` no seu simulador Verilog (ex: ModelSim, Vivado, Icarus Verilog).
2.  Defina `tb_ddr_mem` como o módulo principal.
3.  Execute a simulação. O testbench exibirá "SUCESSO ABSOLUTO" ao concluir.

## Technical Documentation | Documentação Técnica
**EN:** For detailed architecture and design choices, please refer to [REPORT.md](REPORT.md).

**PT:** Para detalhes sobre a arquitetura e escolhas de design, consulte o [REPORT.md](REPORT.md).
