# Technical Report: DDR3 Memory Controller Design
# Relatório Técnico: Design de um Controlador de Memória DDR3

## 1. Introduction | Introdução
**EN:** This project implements a DDR3 SDRAM memory controller based on the Micron MT41J256M4/128M8/64M16 datasheet. The design covers the complete hierarchy from a high-level CPU interface down to the physical layer (PHY) and a functional simulation model of the memory banks.

**PT:** Este projeto implementa um controlador de memória DDR3 SDRAM baseado no datasheet Micron MT41J256M4/128M8/64M16. O design abrange toda a hierarquia, desde uma interface de CPU de alto nível até a camada física (PHY) e um modelo de simulação funcional dos bancos de memória.

## 2. Architecture | Arquitetura
**EN:** The project is divided into three main layers:
1.  **Frontend (CPU Interface):** Handles communication with the processor, address decoding, and open-page policy tracking.
2.  **Backend (Controller Core):** Manages the JEDEC state machine for each of the 8 banks, ensuring timing compliance (tRCD, tRP, tCL) and periodic refreshing.
3.  **Physical Layer (PHY):** Handles SDR-to-DDR conversion, DQS (strobe) phase shifting, and bi-directional signal control (Tri-state).

**PT:** O projeto está dividido em três camadas principais:
1.  **Frontend (Interface CPU):** Gerencia a comunicação com o processador, decodificação de endereços e rastreamento de política de página aberta.
2.  **Backend (Núcleo do Controlador):** Gerencia a máquina de estados JEDEC para cada um dos 8 bancos, garantindo o cumprimento dos tempos (tRCD, tRP, tCL) e refresh periódico.
3.  **Camada Física (PHY):** Lida com a conversão SDR para DDR, deslocamento de fase do DQS (strobe) e controle de sinais bidirecionais (Tri-state).

## 3. Functional Description | Descrição Funcional

### 3.1. Initialization | Inicialização
**EN:** Implemented in `inicialization_control_logic.v`, it follows the mandatory JEDEC power-up sequence:
- RESET# assertion for >200us.
- CKE stabilization.
- Mode Register Sets (MR2, MR3, MR1, MR0) configuration.
- ZQ Calibration for output impedance and ODT.

**PT:** Implementada em `inicialization_control_logic.v`, segue a sequência obrigatória de power-up do JEDEC:
- Ativação de RESET# por >200us.
- Estabilização de CKE.
- Configuração dos Registradores de Modo (MR2, MR3, MR1, MR0).
- Calibração ZQ para impedância de saída e ODT.

### 3.2. Page Management | Gerenciamento de Página
**EN:** The `row_tracker` module keeps record of active rows in each bank. The `comunication_control_logic` uses an **Open-Page Policy**:
- **Page Hit:** Command is sent directly (READ/WRITE).
- **Page Empty:** ACTIVATE command is issued before data access.
- **Page Miss:** PRECHARGE is issued, followed by ACTIVATE and then data access.

**PT:** O módulo `row_tracker` mantém o registro das linhas ativas em cada banco. A lógica de comunicação utiliza uma **Política de Página Aberta**:
- **Page Hit:** O comando é enviado diretamente (READ/WRITE).
- **Page Empty:** Um comando ACTIVATE é emitido antes do acesso aos dados.
- **Page Miss:** Um PRECHARGE é emitido, seguido por ACTIVATE e então o acesso aos dados.

### 3.3. Physical Interface (PHY) | Interface Física (PHY)
**EN:** The `datapath` ensures high-speed data transfer. The `dqs_phase_shifter` uses a 90-degree delayed clock to center the DQS strobe relative to the DQ data bits, maximizing the sampling window (Data Eye).

**PT:** O `datapath` garante a transferência de dados em alta velocidade. O `dqs_phase_shifter` utiliza um clock atrasado em 90 graus para centralizar o strobe DQS em relação aos bits de dados DQ, maximizando a janela de amostragem (Olho de Dados).

## 4. Validation | Validação
**EN:** The testbench `tb_ddr_mem.v` simulates a CPU performing random operations. It verifies:
- Initialization success via `init_done` flag.
- Data integrity over 1,000 stress cycles (Random Write followed by Random Read).
- Timing compliance for 8-bank concurrent operations.

**PT:** O testbench `tb_ddr_mem.v` simula uma CPU realizando operações aleatórias. Ele verifica:
- Sucesso da inicialização via flag `init_done`.
- Integridade dos dados ao longo de 1.000 ciclos de stress (Escrita aleatória seguida de leitura aleatória).
- Cumprimento dos tempos para operações simultâneas nos 8 bancos.

## 5. Conclusion | Conclusão
**EN:** The design is fully functional and compliant with basic DDR3 standards. It provides a robust abstraction for high-level systems to interact with complex SDRAM hardware.

**PT:** O design está totalmente funcional e em conformidade com os padrões básicos de DDR3. Ele fornece uma abstração robusta para que sistemas de alto nível interajam com o hardware complexo da SDRAM.
