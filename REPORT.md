# Technical Report: AXI-DDR3 Memory Controller Design
# Relatório Técnico: Design de um Controlador de Memória AXI-DDR3

## 1. Introduction | Introdução
**EN:** This project implements a high-performance DDR3 SDRAM memory controller with an AXI-Lite interface. It follows the JEDEC standards (based on Micron MT41J datasheet) and the AMBA AXI protocol. The design encompasses the full hardware stack, from the AXI-Lite bus logic to the physical layer (PHY) and a behavioral model of the memory banks.

**PT:** Este projeto implementa um controlador de memória DDR3 SDRAM de alta performance com uma interface AXI-Lite. Ele segue os padrões JEDEC (baseado no datasheet Micron MT41J) e o protocolo AMBA AXI. O design abrange toda a pilha de hardware, desde a lógica do barramento AXI-Lite até a camada física (PHY) e um modelo comportamental dos bancos de memória.

## 2. Architecture | Arquitetura
**EN:** The system is organized into four hierarchical layers:
1.  **AXI-Lite Interface (Manager-Facing):** Implements the AXI protocol handshake. Since DDR3 operates with an 8n-prefetch (64-bit blocks for a 16-bit interface), this layer transparently maps 16-bit AXI requests into the internal memory bursts.
2.  **Frontend (Command Handling):** Manages the "Open-Page" policy, tracking which rows are active in each of the 8 banks to minimize latency (Row Hit vs. Row Miss).
3.  **Backend (JEDEC Controller):** The core state machine that orchestrates JEDEC commands (ACT, PRE, RD, WR, REF), ensures timing compliance, and manages the power-up initialization.
4.  **Physical Layer (PHY) & Core Model:** Handles the bidirectional DQ/DQS signals, 90° phase shifting for data capture, and emulates the analog storage cells.

**PT:** O sistema está organizado em quatro camadas hierárquicas:
1.  **Interface AXI-Lite (Lado do Mestre):** Implementa o handshake do protocolo AXI. Como o DDR3 opera com prefetch 8n (blocos de 64 bits para uma interface de 16 bits), esta camada mapeia transparentemente requisições AXI de 16 bits nos bursts internos da memória.
2.  **Frontend (Gerenciamento de Comandos):** Gerencia a política de "Página Aberta", rastreando quais linhas estão ativas em cada um dos 8 bancos para minimizar a latência (Hit de Linha vs. Miss de Linha).
3.  **Backend (Controlador JEDEC):** A máquina de estados central que orquestra os comandos JEDEC (ACT, PRE, RD, WR, REF), garante o cumprimento dos tempos e gerencia a inicialização.
4.  **Camada Física (PHY) & Modelo do Core:** Lida com os sinais bidirecionais DQ/DQS, deslocamento de fase de 90° para captura de dados e emula as células de armazenamento analógicas.

## 3. Detailed Operation | Operação Detalhada

### 3.1. AXI-to-DDR Mapping | Mapeamento AXI-DDR
**EN:** A key challenge in this design is the data width mismatch. The AXI bus is 16-bit, while the internal DRAM core logic expects 64-bit blocks. 
- **Write Path:** The AXI FSM captures a 16-bit word and repeats it 4 times (WRITE_W1..W4 states) to fill the 64-bit internal buffer. This ensures that even single-word AXI writes result in a valid JEDEC-compliant burst.
- **Read Path:** The FSM requests a full 64-bit block from the core. It latches only the relevant 16-bit word from the 4-word burst and delivers it to the AXI master, discarding the others to simplify the Lite interface.

**PT:** Um desafio central neste design é a disparidade de largura de dados. O barramento AXI é de 16 bits, enquanto a lógica interna do core DRAM espera blocos de 64 bits.
- **Caminho de Escrita:** A FSM AXI captura uma palavra de 16 bits e a repete 4 vezes (estados WRITE_W1..W4) para preencher o buffer interno de 64 bits. Isso garante que mesmo escritas AXI de uma única palavra resultem em um burst válido em conformidade com JEDEC.
- **Caminho de Leitura:** A FSM solicita um bloco completo de 64 bits do core. Ela captura apenas a palavra de 16 bits relevante do burst de 4 palavras e a entrega ao mestre AXI, descartando as demais para simplificar a interface Lite.

### 3.2. Analog Simplifications | Simplificações Analógicas
**EN:** To make the design simulatable in a digital environment, several analog features were emulated:
- **DQS Phase Shifting:** In real hardware, a DLL aligns DQS to the center of the data. Here, we use a dedicated `clk_90` signal to emultate this, ensuring data is sampled at its most stable point.
- **Sense Amplifiers:** The `dram_bank_array` registers the "active_row", emulating the analog process where an entire row is moved to the amplifiers before individual columns can be accessed.
- **Data Mask (DM):** The DM logic is modeled as a per-byte enable signal, allowing selective writes within the 64-bit block.

**PT:** Para tornar o design simulável em ambiente digital, diversas funcionalidades analógicas foram emuladas:
- **Deslocamento de Fase DQS:** No hardware real, um DLL alinha o DQS ao centro dos dados. Aqui, usamos um sinal `clk_90` dedicado para emular isso, garantindo que os dados sejam amostrados em seu ponto mais estável.
- **Amplificadores de Detecção:** O `dram_bank_array` registra a "active_row", emulando o processo analógico onde uma linha inteira é movida para os amplificadores antes que colunas individuais possam ser acessadas.
- **Data Mask (DM):** A lógica DM é modelada como um sinal de habilitação por byte, permitindo escritas seletivas dentro do bloco de 64 bits.

### 3.3. Page Management (Open-Page Policy) | Gerenciamento de Página
**EN:** The controller optimizes throughput by keeping rows open. If a subsequent request targets the same bank and row (Page Hit), the ACTIVATE command is skipped, significantly reducing access time. Periodic Refresh commands (tREFI) are handled by a high-priority FSM to prevent data loss.

**PT:** O controlador otimiza o throughput mantendo as linhas abertas. Se uma requisição subsequente alveja o mesmo banco e linha (Hit de Página), o comando ACTIVATE é pulado, reduzindo significativamente o tempo de acesso. Comandos de Refresh periódicos (tREFI) são gerenciados por uma FSM de alta prioridade para evitar perda de dados.

## 4. Verification | Verificação
**EN:** The `axi_tb.v` testbench emulates a complex SOC master. It performs:
1.  **JEDEC Initialization:** Waits for the full power-up and ZQ calibration sequence.
2.  **Random Stress Test:** Executes 250 random writes followed by 250 reads at the same addresses.
3.  **Self-Verification:** Automatically compares read data with the expected original values, signaling "SUCESSO ABSOLUTO" if zero errors are found.

**PT:** O testbench `axi_tb.v` emula um mestre SOC complexo. Ele realiza:
1.  **Inicialização JEDEC:** Aguarda a sequência completa de power-up e calibração ZQ.
2.  **Teste de Stress Aleatório:** Executa 250 escritas aleatórias seguidas de 250 leituras nos mesmos endereços.
3.  **Auto-Verificação:** Compara automaticamente os dados lidos com os valores originais esperados, sinalizando "SUCESSO ABSOLUTO" se zero erros forem encontrados.

## 5. Conclusion | Conclusão
**EN:** The project successfully bridges high-level AXI systems with the complex timing and physical requirements of DDR3 memory. It serves as a robust base for FPGA or ASIC implementations requiring integrated SDRAM storage.

**PT:** O projeto une com sucesso sistemas AXI de alto nível com os requisitos complexos de tempo e físicos da memória DDR3. Ele serve como uma base robusta para implementações em FPGA ou ASIC que exijam armazenamento SDRAM integrado.

