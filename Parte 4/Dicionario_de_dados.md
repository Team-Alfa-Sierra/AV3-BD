# Dicionário de Dados

**Banco de dados:** `AV3_db`  
**SGBD:** MySQL

## 1. Apresentação

Este documento apresenta o dicionário de dados do banco AV3_db, desenvolvido para apoiar o gerenciamento de clientes, departamentos, funcionários, projetos, ordens de serviço, locais operacionais, anexos, auditoria e apontamentos de horas. A documentação descreve as tabelas, seus campos, tipos de dados, obrigatoriedade, valores padrão, chaves e restrições.

A documentação foi elaborada com base no script de criação do banco de dados (`script_av3.sql`) e no projeto acadêmico integrador (API).

## 2. Convenções utilizadas

| Sigla / termo | Significado |
| :--- | :--- |
| PK | Chave primária: identifica unicamente cada registro. |
| FK | Chave estrangeira: referencia registro de outra tabela (ou da própria tabela). |
| UK | Restrição UNIQUE: impede valores duplicados no campo ou conjunto de campos. |
| NN | NOT NULL: preenchimento obrigatório. |
| NULL | Campo que pode ficar sem valor. |
| AI | AUTO_INCREMENT: valor numérico gerado automaticamente pelo MySQL. |
| DEFAULT | Valor atribuído automaticamente quando o INSERT não informa o campo. |
| ENUM | Campo limitado a um conjunto de valores textuais previamente definido. |
| BOOLEAN | Tipo lógico; no MySQL é representado como TINYINT(1). |
| DATETIME(6) | Data e hora com precisão de até seis casas decimais de segundo. |

## 3. Estrutura das tabelas

### 3.1. Tabela clientes

Armazena os clientes atendidos pela organização.

| Campo | Tipo de dado | Obrigatoriedade | Padrão | Chave / restrição | Descrição |
| :--- | :--- | :---: | :---: | :--- | :--- |
| id | INT | NN, AI | --- | PK | Identificador único do cliente. |
| nome | VARCHAR(191) | NN | --- | --- | Nome de identificação do cliente. |
| razao_social | VARCHAR(191) | NN | --- | UK: uq_clientes_razao_social | Razão social oficial do cliente. |
| ramo_atuacao | VARCHAR(191) | NN | --- | --- | Área ou segmento de atuação do cliente. |
| ativo | BOOLEAN | NN | TRUE | --- | Indica se o cadastro do cliente está ativo. |

**Chaves e restrições:**

- PK: `id`.
- UK: `uq_clientes_razao_social` (`razao_social`).

### 3.2. Tabela departamentos

Registra os departamentos internos e seus responsáveis.

| Campo | Tipo de dado | Obrigatoriedade | Padrão | Chave / restrição | Descrição |
| :--- | :--- | :---: | :---: | :--- | :--- |
| id | INT | NN, AI | --- | PK | Identificador único do departamento. |
| responsavel_id | INT | NULL | --- | FK composta | Funcionário responsável pelo departamento; deve pertencer ao próprio departamento. |
| nome | VARCHAR(191) | NN | --- | UK: uq_departamentos_nome | Nome do departamento. |

**Chaves e restrições:**

- PK: `id`.
- UK: `uq_departamentos_nome` (`nome`).
- FK: `(responsavel_id, id)` → `funcionarios(id, departamento_id)`, `fk_departamento_responsavel_mesmo_depto`. A FK composta garante que o responsável pertença ao departamento correspondente.

### 3.3. Tabela funcionarios

Armazena os funcionários vinculados aos departamentos.

| Campo | Tipo de dado | Obrigatoriedade | Padrão | Chave / restrição | Descrição |
| :--- | :--- | :---: | :---: | :--- | :--- |
| id | INT | NN, AI | --- | PK | Identificador único do funcionário. |
| departamento_id | INT | NN | --- | FK: fk_funcionarios_departamento | Departamento ao qual o funcionário pertence. |
| usuario | VARCHAR(191) | NN | --- | UK: uq_funcionarios_usuario | Nome de usuário utilizado para identificação/autenticação. |
| senha_hash | VARCHAR(191) | NN | --- | --- | Hash da senha do funcionário; não deve armazenar senha em texto puro. |
| nome | VARCHAR(191) | NN | --- | --- | Nome do funcionário. |
| tipo | ENUM('gestor','tecnico') | NN | 'tecnico' | --- | Perfil do funcionário: gestor ou técnico. |
| ativo | BOOLEAN | NN | TRUE | --- | Indica se o funcionário está ativo. |

**Chaves e restrições:**

- PK: `id`.
- UK: `uq_funcionarios_usuario` (`usuario`).
- UK: `uq_funcionarios_id_departamento` (`id`, `departamento_id`), utilizada pela FK composta de departamentos.
- FK: `departamento_id` → `departamentos(id)`, `fk_funcionarios_departamento`.

### 3.4. Tabela locais_operacionais

Cadastra os locais físicos ou operacionais associados a clientes.

| Campo | Tipo de dado | Obrigatoriedade | Padrão | Chave / restrição | Descrição |
| :--- | :--- | :---: | :---: | :--- | :--- |
| id | INT | NN, AI | --- | PK | Identificador único do local operacional. |
| cliente_id | INT | NN | --- | FK: fk_locais_cliente | Cliente proprietário ou associado ao local. |
| descricao | VARCHAR(191) | NN | --- | --- | Descrição ou identificação do local. |
| tipo | ENUM('offshore','terrestre','site') | NN | --- | --- | Classificação do local operacional. |

**Chaves e restrições:**

- PK: `id`.
- UK: `uq_locais_id_cliente` (`id`, `cliente_id`), utilizada para garantir a consistência da FK composta em `ordens_servico`.
- FK: `cliente_id` → `clientes(id)`, `fk_locais_cliente`.

### 3.5. Tabela projetos

Armazena projetos vinculados a clientes.

| Campo | Tipo de dado | Obrigatoriedade | Padrão | Chave / restrição | Descrição |
| :--- | :--- | :---: | :---: | :--- | :--- |
| id | INT | NN, AI | --- | PK | Identificador único do projeto. |
| cliente_id | INT | NN | --- | FK: fk_projetos_cliente | Cliente ao qual o projeto pertence. |
| data_fim | DATETIME(6) | NULL | --- | CHECK: chk_projetos_datas | Data e hora de encerramento do projeto. |
| status | ENUM('em_planejamento','em_andamento','pausado','concluido') | NN | 'em_planejamento' | --- | Situação atual do projeto. |
| data_inicio | DATETIME(6) | NULL | --- | CHECK: chk_projetos_datas | Data e hora de início do projeto. |
| nome | VARCHAR(191) | NN | --- | --- | Nome do projeto. |
| ativo | BOOLEAN | NN | TRUE | --- | Indica se o projeto está ativo. |

**Chaves e restrições:**

- PK: `id`.
- UK: `uq_projetos_id_cliente` (`id`, `cliente_id`), utilizada para garantir que uma OS e seu projeto pertençam ao mesmo cliente.
- FK: `cliente_id` → `clientes(id)`, `fk_projetos_cliente`.
- CHECK: `chk_projetos_datas` permite datas nulas, mas, quando ambas são informadas, `data_fim` deve ser maior ou igual a `data_inicio`.

### 3.6. Tabela ordens_servico

Tabela central do sistema: registra solicitações e o ciclo de vida das ordens de serviço (OS).

| Campo | Tipo de dado | Obrigatoriedade | Padrão | Chave / restrição | Descrição |
| :--- | :--- | :---: | :---: | :--- | :--- |
| id | INT | NN, AI | --- | PK | Identificador único da ordem de serviço. |
| departamento_id | INT | NN | --- | FK: fk_os_departamento | Departamento responsável pela OS. |
| cliente_id | INT | NN | --- | FK: fk_os_cliente | Cliente relacionado à OS. |
| solicitante_id | INT | NN | --- | FK: fk_os_solicitante | Funcionário que solicitou/abriu a OS. |
| responsavel_id | INT | NULL | --- | FK: fk_os_responsavel | Funcionário atualmente responsável pela execução da OS. |
| projeto_id | INT | NULL | --- | FK composta: fk_os_projeto_mesmo_cliente | Projeto associado à OS; deve pertencer ao mesmo cliente da OS. |
| anterior_id | INT | NULL | --- | FK: fk_os_anterior | OS anterior relacionada, permitindo encadeamento autorreferente. |
| parecer_tecnico | VARCHAR(191) | NULL | --- | --- | Parecer ou observação técnica sobre a OS. |
| tipo | ENUM('instalacao','manutencao') | NN | 'instalacao' | --- | Natureza do serviço solicitado. |
| criticidade | ENUM('baixo','medio','alto','muito_alto','urgente') | NN | 'medio' | --- | Nível de criticidade/prioridade da OS. |
| descricao | VARCHAR(191) | NN | --- | --- | Descrição detalhada resumida do serviço ou problema. |
| status | ENUM('em_andamento','aguardando','validacao_testes','bloqueado','concluido') | NN | 'em_andamento' | CHECK: chk_os_status_data_fim | Situação atual da OS. |
| ativo | BOOLEAN | NN | TRUE | --- | Indica se o registro da OS está ativo. |
| data_criacao | DATETIME(6) | NN | CURRENT_TIMESTAMP(6) | --- | Data e hora de criação do registro. |
| local_operacional_id | INT | NULL | --- | FK composta: fk_os_local_mesmo_cliente | Local operacional associado; deve pertencer ao mesmo cliente da OS. |
| titulo | VARCHAR(191) | NN | --- | --- | Título curto da ordem de serviço. |
| prazo_dias_uteis | INT | NULL | --- | CHECK: chk_os_prazo | Prazo previsto em dias úteis; quando informado, não pode ser negativo. |
| data_inicio | DATETIME(6) | NULL | --- | CHECK: chk_os_datas | Data e hora de início da execução. |
| data_fim | DATETIME(6) | NULL | --- | CHECK: chk_os_datas / chk_os_status_data_fim | Data e hora de conclusão. |
| data_limite_sla | DATETIME(6) | NULL | --- | --- | Data e hora limite calculada ou definida para atendimento do SLA. |
| sla_manual | BOOLEAN | NN | FALSE | --- | Indica se o prazo/SLA foi definido manualmente. |

**Chaves e restrições:**

- PK: `id`.
- FK: `departamento_id` → `departamentos(id)`, `fk_os_departamento`.
- FK: `cliente_id` → `clientes(id)`, `fk_os_cliente`.
- FK: `solicitante_id` → `funcionarios(id)`, `fk_os_solicitante`.
- FK: `responsavel_id` → `funcionarios(id)`, `fk_os_responsavel`.
- FK composta: `(projeto_id, cliente_id)` → `projetos(id, cliente_id)`, `fk_os_projeto_mesmo_cliente`.
- FK composta: `(local_operacional_id, cliente_id)` → `locais_operacionais(id, cliente_id)`, `fk_os_local_mesmo_cliente`.
- FK autorreferente: `anterior_id` → `ordens_servico(id)`, `fk_os_anterior`.
- CHECK `chk_os_prazo`: `prazo_dias_uteis` deve ser NULL ou maior/igual a zero.
- CHECK `chk_os_datas`: quando `data_inicio` e `data_fim` são informadas, `data_fim` deve ser maior/igual a `data_inicio`.
- CHECK `chk_os_status_data_fim`: status `concluido` exige `data_fim` preenchida; status diferente de `concluido` exige `data_fim` NULL.

### 3.7. Tabela anexos

Armazena arquivos/documentos anexados às ordens de serviço.

| Campo | Tipo de dado | Obrigatoriedade | Padrão | Chave / restrição | Descrição |
| :--- | :--- | :---: | :---: | :--- | :--- |
| id | INT | NN, AI | --- | PK | Identificador único do anexo. |
| os_id | INT | NN | --- | FK: fk_anexos_os | Ordem de serviço à qual o anexo pertence. |
| nome | VARCHAR(255) | NN | --- | --- | Nome do arquivo anexado. |
| tipo | VARCHAR(191) | NN | --- | --- | Tipo ou formato do arquivo. |
| tamanho_bytes | BIGINT | NN | --- | --- | Tamanho do arquivo em bytes. |
| caminho | VARCHAR(191) | NN | --- | --- | Caminho ou localização do arquivo armazenado. |
| data_upload | DATETIME(6) | NN | CURRENT_TIMESTAMP(6) | --- | Data e hora do envio do anexo. |

**Chaves e restrições:**

- PK: `id`.
- FK: `os_id` → `ordens_servico(id)`, `fk_anexos_os`.

### 3.8. Tabela auditoria

Registra alterações realizadas nas ordens de serviço, permitindo rastreabilidade.

| Campo | Tipo de dado | Obrigatoriedade | Padrão | Chave / restrição | Descrição |
| :--- | :--- | :---: | :---: | :--- | :--- |
| id | INT | NN, AI | --- | PK | Identificador único do evento de auditoria. |
| os_id | INT | NN | --- | FK: fk_auditoria_os | Ordem de serviço afetada. |
| funcionario_id | INT | NN | --- | FK: fk_auditoria_funcionario | Funcionário associado à operação registrada. |
| data_modificacao | DATETIME(6) | NN | CURRENT_TIMESTAMP(6) | --- | Data e hora em que a alteração foi registrada. |
| acao | ENUM('insercao','atualizacao','exclusao') | NN | --- | --- | Tipo de operação realizada. |
| campo_alterado | VARCHAR(191) | NULL | --- | --- | Nome do campo alterado, quando aplicável. |
| dado_antigo | VARCHAR(191) | NULL | --- | --- | Valor anterior do campo, quando aplicável. |
| dado_novo | VARCHAR(191) | NULL | --- | --- | Novo valor do campo, quando aplicável. |
| justificativa | VARCHAR(191) | NULL | --- | --- | Justificativa informada para a alteração, quando aplicável. |
| tipo_entidade | VARCHAR(191) | NN | 'ordem_servico' | --- | Identifica o tipo de entidade auditada. |

**Chaves e restrições:**

- PK: `id`.
- FK: `os_id` → `ordens_servico(id)`, `fk_auditoria_os`.
- FK: `funcionario_id` → `funcionarios(id)`, `fk_auditoria_funcionario`.

### 3.9. Tabela auditoria_projetos

Registra alterações realizadas nos projetos.

| Campo | Tipo de dado | Obrigatoriedade | Padrão | Chave / restrição | Descrição |
| :--- | :--- | :---: | :---: | :--- | :--- |
| id | INT | NN, AI | --- | PK | Identificador único do evento de auditoria do projeto. |
| projeto_id | INT | NN | --- | FK: fk_auditoria_projetos_projeto | Projeto afetado pela operação. |
| funcionario_id | INT | NN | --- | FK: fk_auditoria_projetos_funcionario | Funcionário associado à operação registrada. |
| data_modificacao | DATETIME(6) | NN | CURRENT_TIMESTAMP(6) | --- | Data e hora em que a alteração foi registrada. |
| acao | ENUM('insercao','atualizacao','exclusao') | NN | --- | --- | Tipo de operação realizada. |
| campo_alterado | VARCHAR(191) | NULL | --- | --- | Nome do campo alterado, quando aplicável. |
| dado_antigo | VARCHAR(191) | NULL | --- | --- | Valor anterior do campo, quando aplicável. |
| dado_novo | VARCHAR(191) | NULL | --- | --- | Novo valor do campo, quando aplicável. |
| justificativa | VARCHAR(191) | NULL | --- | --- | Justificativa informada para a alteração, quando aplicável. |

**Chaves e restrições:**

- PK: `id`.
- FK: `projeto_id` → `projetos(id)`, `fk_auditoria_projetos_projeto`.
- FK: `funcionario_id` → `funcionarios(id)`, `fk_auditoria_projetos_funcionario`.

### 3.10. Tabela projetos_departamentos

Tabela associativa que implementa o relacionamento muitos-para-muitos entre projetos e departamentos.

| Campo | Tipo de dado | Obrigatoriedade | Padrão | Chave / restrição | Descrição |
| :--- | :--- | :---: | :---: | :--- | :--- |
| projeto_id | INT | NN | --- | PK composta / FK | Projeto relacionado. |
| departamento_id | INT | NN | --- | PK composta / FK | Departamento relacionado ao projeto. |

**Chaves e restrições:**

- PK composta: (`projeto_id`, `departamento_id`).
- FK: `projeto_id` → `projetos(id)`, `fk_projetos_departamentos_projeto`.
- FK: `departamento_id` → `departamentos(id)`, `fk_projetos_departamentos_departamento`.

### 3.11. Tabela apontamento_horas

Registra o tempo trabalhado por funcionários em ordens de serviço.

| Campo | Tipo de dado | Obrigatoriedade | Padrão | Chave / restrição | Descrição |
| :--- | :--- | :---: | :---: | :--- | :--- |
| id | INT | NN, AI | --- | PK | Identificador único do apontamento. |
| funcionario_id | INT | NN | --- | FK: fk_apontamento_funcionario | Funcionário que realizou o trabalho. |
| os_id | INT | NN | --- | FK: fk_apontamento_os | Ordem de serviço à qual o tempo foi associado. |
| data_trabalho | DATE | NN | --- | UK composta | Data em que o trabalho foi realizado. |
| duracao_minutos | INT | NN | --- | CHECK: chk_apontamento_duracao | Duração do trabalho em minutos; o DDL atual permite valor maior ou igual a zero. |
| descricao | VARCHAR(191) | NULL | --- | --- | Descrição opcional da atividade realizada. |
| data_criacao | DATETIME(6) | NN | CURRENT_TIMESTAMP(6) | --- | Data e hora em que o apontamento foi cadastrado. |

**Chaves e restrições:**

- PK: `id`.
- UK: `uq_apontamento_funcionario_os_data` (`funcionario_id`, `os_id`, `data_trabalho`), impede mais de um apontamento para a mesma combinação de funcionário, OS e data.
- FK: `funcionario_id` → `funcionarios(id)`, `fk_apontamento_funcionario`.
- FK: `os_id` → `ordens_servico(id)`, `fk_apontamento_os`.
- CHECK `chk_apontamento_duracao`: `duracao_minutos >= 0`.

## 4. Índices

Além das chaves primárias, estrangeiras e restrições UNIQUE, o script cria os seguintes índices para apoiar consultas:

| Índice | Tabela | Campo(s) | Finalidade provável |
| :--- | :--- | :--- | :--- |
| idx_auditoria_os_data | auditoria | (os_id, data_modificacao) | Apoiar consultas do histórico de uma OS em ordem temporal. |
| idx_os_criticidade_limite | ordens_servico | (criticidade, data_limite_sla) | Apoiar filtros e ordenações por criticidade e limite de SLA. |
| idx_os_departamento_status | ordens_servico | (departamento_id, status) | Apoiar consultas de OS por departamento e situação. |
| idx_os_projeto | ordens_servico | (projeto_id) | Apoiar consultas de OS associadas a projetos. |
| idx_os_responsavel_status | ordens_servico | (responsavel_id, status) | Apoiar consultas por responsável e situação. |
| idx_auditoria_projetos_data | auditoria_projetos | (projeto_id, data_modificacao) | Apoiar consultas do histórico de um projeto em ordem temporal. |
| idx_apontamentos_funcionario_data | apontamento_horas | (funcionario_id, data_trabalho) | Apoiar consultas de apontamentos por funcionário e data. |

## 5. Observações sobre integridade e relacionamentos

- O relacionamento entre projetos e departamentos é muitos-para-muitos e é implementado pela tabela `projetos_departamentos`.
- A tabela `ordens_servico` possui relacionamento autorreferente por meio do campo `anterior_id`, permitindo relacionar uma OS a outra OS anterior.
- As chaves estrangeiras compostas de `ordens_servico` garantem que o projeto e o local operacional associados pertençam ao mesmo cliente informado na própria OS.
- A FK composta entre `departamentos` e `funcionarios` garante que o responsável indicado para um departamento seja funcionário daquele mesmo departamento.
- As FKs foram definidas com `ON DELETE NO ACTION` e `ON UPDATE NO ACTION`; portanto, o banco não configura exclusão ou atualização em cascata para esses relacionamentos.
- Os campos com `AUTO_INCREMENT` são identificadores gerados pelo banco. Os campos `DATETIME(6)` com `DEFAULT CURRENT_TIMESTAMP(6)` recebem automaticamente a data e hora do cadastro quando não informados.
