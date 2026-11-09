
CREATE DATABASE IF NOT EXISTS AV3_db;

USE AV3_db;

CREATE TABLE clientes (
    id INT NOT NULL AUTO_INCREMENT,
    nome VARCHAR(191) NOT NULL,
    razao_social VARCHAR(191) NOT NULL,
    ramo_atuacao VARCHAR(191) NOT NULL,
    ativo BOOLEAN NOT NULL DEFAULT TRUE,

    PRIMARY KEY (id),
    CONSTRAINT uq_clientes_razao_social UNIQUE (razao_social)
);

CREATE TABLE departamentos (
    id INT NOT NULL AUTO_INCREMENT,
    responsavel_id INT NULL,
    nome VARCHAR(191) NOT NULL,

    PRIMARY KEY (id),
    CONSTRAINT uq_departamentos_nome UNIQUE (nome)
);

CREATE TABLE funcionarios (
    id INT NOT NULL AUTO_INCREMENT,
    departamento_id INT NOT NULL,
    usuario VARCHAR(191) NOT NULL,
    senha_hash VARCHAR(191) NOT NULL,
    nome VARCHAR(191) NOT NULL,
    tipo ENUM('gestor', 'tecnico')
        NOT NULL DEFAULT 'tecnico',
    ativo BOOLEAN NOT NULL DEFAULT TRUE,

    PRIMARY KEY (id),
    CONSTRAINT uq_funcionarios_usuario UNIQUE (usuario),
    CONSTRAINT uq_funcionarios_id_departamento
        UNIQUE (id, departamento_id)
);

CREATE TABLE locais_operacionais (
    id INT NOT NULL AUTO_INCREMENT,
    cliente_id INT NOT NULL,
    descricao VARCHAR(191) NOT NULL,
    tipo ENUM('offshore', 'terrestre', 'site') NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT uq_locais_id_cliente
        UNIQUE (id, cliente_id)
);

CREATE TABLE projetos (
    id INT NOT NULL AUTO_INCREMENT,
    cliente_id INT NOT NULL,
    data_fim DATETIME(6) NULL,
    status ENUM(
        'em_planejamento',
        'em_andamento',
        'pausado',
        'concluido'
    ) NOT NULL DEFAULT 'em_planejamento',
    data_inicio DATETIME(6) NULL,
    nome VARCHAR(191) NOT NULL,
    ativo BOOLEAN NOT NULL DEFAULT TRUE,

    PRIMARY KEY (id),
    CONSTRAINT uq_projetos_id_cliente
        UNIQUE (id, cliente_id),

    CONSTRAINT chk_projetos_datas
        CHECK (
            data_inicio IS NULL
            OR data_fim IS NULL
            OR data_fim >= data_inicio
        )
);

CREATE TABLE ordens_servico (
    id INT NOT NULL AUTO_INCREMENT,
    departamento_id INT NOT NULL,
    cliente_id INT NOT NULL,
    solicitante_id INT NOT NULL,
    responsavel_id INT NULL,
    projeto_id INT NULL,
    anterior_id INT NULL,
    parecer_tecnico VARCHAR(191) NULL,

    tipo ENUM('instalacao', 'manutencao')
        NOT NULL DEFAULT 'instalacao',

    criticidade ENUM(
        'baixo',
        'medio',
        'alto',
        'muito_alto',
        'urgente'
    ) NOT NULL DEFAULT 'medio',

    descricao VARCHAR(191) NOT NULL,

    status ENUM(
        'em_andamento',
        'aguardando',
        'validacao_testes',
        'bloqueado',
        'concluido'
    ) NOT NULL DEFAULT 'em_andamento',

    ativo BOOLEAN NOT NULL DEFAULT TRUE,
    data_criacao DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    local_operacional_id INT NULL,
    titulo VARCHAR(191) NOT NULL,
    prazo_dias_uteis INT NULL,
    data_inicio DATETIME(6) NULL,
    data_fim DATETIME(6) NULL,
    data_limite_sla DATETIME(6) NULL,
    sla_manual BOOLEAN NOT NULL DEFAULT FALSE,

    PRIMARY KEY (id),

    CONSTRAINT chk_os_prazo
        CHECK (
            prazo_dias_uteis IS NULL
            OR prazo_dias_uteis >= 0
        ),

    CONSTRAINT chk_os_datas
        CHECK (
            data_inicio IS NULL
            OR data_fim IS NULL
            OR data_fim >= data_inicio
        ),

    CONSTRAINT chk_os_status_data_fim
        CHECK (
            (
                status = 'concluido'
                AND data_fim IS NOT NULL
            )
            OR
            (
                status <> 'concluido'
                AND data_fim IS NULL
            )
        )
);

CREATE TABLE anexos (
    id INT NOT NULL AUTO_INCREMENT,
    os_id INT NOT NULL,
    nome VARCHAR(255) NOT NULL,
    tipo VARCHAR(191) NOT NULL,
    tamanho_bytes BIGINT NOT NULL,
    caminho VARCHAR(191) NOT NULL,
    data_upload DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),

    PRIMARY KEY (id)
);

CREATE TABLE auditoria (
    id INT NOT NULL AUTO_INCREMENT,
    os_id INT NOT NULL,
    funcionario_id INT NOT NULL,
    data_modificacao DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),

    acao ENUM('insercao', 'atualizacao', 'exclusao') NOT NULL,

    campo_alterado VARCHAR(191) NULL,
    dado_antigo VARCHAR(191) NULL,
    dado_novo VARCHAR(191) NULL,
    justificativa VARCHAR(191) NULL,

    tipo_entidade VARCHAR(191) NOT NULL DEFAULT 'ordem_servico',

    PRIMARY KEY (id)
);

CREATE TABLE auditoria_projetos (
    id INT NOT NULL AUTO_INCREMENT,
    projeto_id INT NOT NULL,
    funcionario_id INT NOT NULL,
    data_modificacao DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),

    acao ENUM('insercao', 'atualizacao', 'exclusao') NOT NULL,

    campo_alterado VARCHAR(191) NULL,
    dado_antigo VARCHAR(191) NULL,
    dado_novo VARCHAR(191) NULL,
    justificativa VARCHAR(191) NULL,

    PRIMARY KEY (id)
);

CREATE TABLE projetos_departamentos (
    projeto_id INT NOT NULL,
    departamento_id INT NOT NULL,

    PRIMARY KEY (projeto_id, departamento_id)
);


CREATE TABLE apontamento_horas (
    id INT NOT NULL AUTO_INCREMENT,
    funcionario_id INT NOT NULL,
    os_id INT NOT NULL,
    data_trabalho DATE NOT NULL,
    duracao_minutos INT NOT NULL,
    descricao VARCHAR(191) NULL,
    data_criacao DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),

    PRIMARY KEY (id),

    CONSTRAINT uq_apontamento_funcionario_os_data
        UNIQUE (funcionario_id, os_id, data_trabalho),

    CONSTRAINT chk_apontamento_duracao
        CHECK (duracao_minutos > 0)
);

CREATE INDEX idx_auditoria_os_data
    ON auditoria (os_id, data_modificacao);

CREATE INDEX idx_os_criticidade_limite
    ON ordens_servico (criticidade, data_limite_sla);

CREATE INDEX idx_os_departamento_status
    ON ordens_servico (departamento_id, status);

CREATE INDEX idx_os_projeto
    ON ordens_servico (projeto_id);

CREATE INDEX idx_os_responsavel_status
    ON ordens_servico (responsavel_id, status);

CREATE INDEX idx_auditoria_projetos_data
    ON auditoria_projetos (projeto_id, data_modificacao);

CREATE INDEX idx_apontamentos_funcionario_data
    ON apontamento_horas (funcionario_id, data_trabalho);

ALTER TABLE funcionarios
    ADD CONSTRAINT fk_funcionarios_departamento
    FOREIGN KEY (departamento_id)
    REFERENCES departamentos (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE departamentos
    ADD CONSTRAINT fk_departamento_responsavel_mesmo_depto
    FOREIGN KEY (responsavel_id, id)
    REFERENCES funcionarios (id, departamento_id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE locais_operacionais
    ADD CONSTRAINT fk_locais_cliente
    FOREIGN KEY (cliente_id)
    REFERENCES clientes (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE projetos
    ADD CONSTRAINT fk_projetos_cliente
    FOREIGN KEY (cliente_id)
    REFERENCES clientes (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE ordens_servico
    ADD CONSTRAINT fk_os_cliente
    FOREIGN KEY (cliente_id)
    REFERENCES clientes (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE ordens_servico
    ADD CONSTRAINT fk_os_projeto_mesmo_cliente
    FOREIGN KEY (projeto_id, cliente_id)
    REFERENCES projetos (id, cliente_id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE ordens_servico
    ADD CONSTRAINT fk_os_local_mesmo_cliente
    FOREIGN KEY (local_operacional_id, cliente_id)
    REFERENCES locais_operacionais (id, cliente_id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE ordens_servico
    ADD CONSTRAINT fk_os_departamento
    FOREIGN KEY (departamento_id)
    REFERENCES departamentos (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE ordens_servico
    ADD CONSTRAINT fk_os_solicitante
    FOREIGN KEY (solicitante_id)
    REFERENCES funcionarios (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE ordens_servico
    ADD CONSTRAINT fk_os_responsavel
    FOREIGN KEY (responsavel_id)
    REFERENCES funcionarios (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE ordens_servico
    ADD CONSTRAINT fk_os_anterior
    FOREIGN KEY (anterior_id)
    REFERENCES ordens_servico (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE anexos
    ADD CONSTRAINT fk_anexos_os
    FOREIGN KEY (os_id)
    REFERENCES ordens_servico (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE auditoria
    ADD CONSTRAINT fk_auditoria_funcionario
    FOREIGN KEY (funcionario_id)
    REFERENCES funcionarios (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE auditoria
    ADD CONSTRAINT fk_auditoria_os
    FOREIGN KEY (os_id)
    REFERENCES ordens_servico (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE auditoria_projetos
    ADD CONSTRAINT fk_auditoria_projetos_funcionario
    FOREIGN KEY (funcionario_id)
    REFERENCES funcionarios (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE auditoria_projetos
    ADD CONSTRAINT fk_auditoria_projetos_projeto
    FOREIGN KEY (projeto_id)
    REFERENCES projetos (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE projetos_departamentos
    ADD CONSTRAINT fk_projetos_departamentos_projeto
    FOREIGN KEY (projeto_id)
    REFERENCES projetos (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE projetos_departamentos
    ADD CONSTRAINT fk_projetos_departamentos_departamento
    FOREIGN KEY (departamento_id)
    REFERENCES departamentos (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE apontamento_horas
    ADD CONSTRAINT fk_apontamento_funcionario
    FOREIGN KEY (funcionario_id)
    REFERENCES funcionarios (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

ALTER TABLE apontamento_horas
    ADD CONSTRAINT fk_apontamento_os
    FOREIGN KEY (os_id)
    REFERENCES ordens_servico (id)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
