CREATE DATABASE IF NOT EXISTS AV3_db
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE AV3_db;

CREATE TABLE clientes (
  id INT NOT NULL AUTO_INCREMENT,
  nome VARCHAR(191) NOT NULL,
  razao_social VARCHAR(191) NOT NULL,
  ramo_atuacao VARCHAR(191) NOT NULL,
  ativo BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id),
  CONSTRAINT uq_clientes_razao_social UNIQUE (razao_social)
) ENGINE=InnoDB;

CREATE TABLE departamentos (
  id INT NOT NULL AUTO_INCREMENT,
  nome VARCHAR(191) NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT uq_departamentos_nome UNIQUE (nome)
) ENGINE=InnoDB;

CREATE TABLE funcionarios (
  id INT NOT NULL AUTO_INCREMENT,
  departamento_id INT NOT NULL,
  usuario VARCHAR(191) NOT NULL,
  senha_hash VARCHAR(255) NOT NULL,
  nome VARCHAR(191) NOT NULL,
  tipo ENUM('gestor', 'tecnico') NOT NULL DEFAULT 'tecnico',
  ativo BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id),
  CONSTRAINT uq_funcionarios_usuario UNIQUE (usuario),
  CONSTRAINT uq_funcionarios_id_departamento UNIQUE (id, departamento_id),
  CONSTRAINT fk_funcionarios_departamento FOREIGN KEY (departamento_id)
    REFERENCES departamentos(id)
) ENGINE=InnoDB;

CREATE TABLE locais_operacionais (
  id INT NOT NULL AUTO_INCREMENT,
  cliente_id INT NOT NULL,
  descricao VARCHAR(191) NOT NULL,
  tipo ENUM('offshore', 'terrestre', 'site') NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT uq_locais_id_cliente UNIQUE (id, cliente_id),
  CONSTRAINT fk_locais_cliente FOREIGN KEY (cliente_id) REFERENCES clientes(id)
) ENGINE=InnoDB;

CREATE TABLE projetos (
  id INT NOT NULL AUTO_INCREMENT,
  cliente_id INT NOT NULL,
  data_inicio DATETIME(6) NULL,
  data_fim DATETIME(6) NULL,
  nome VARCHAR(191) NOT NULL,
  status ENUM('em_planejamento', 'em_andamento', 'pausado', 'concluido')
    NOT NULL DEFAULT 'em_planejamento',
  ativo BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id),
  CONSTRAINT uq_projetos_id_cliente UNIQUE (id, cliente_id),
  CONSTRAINT chk_projetos_datas CHECK (
    data_inicio IS NULL OR data_fim IS NULL OR data_fim >= data_inicio
  ),
  CONSTRAINT fk_projetos_cliente FOREIGN KEY (cliente_id) REFERENCES clientes(id)
) ENGINE=InnoDB;

CREATE TABLE projetos_departamentos (
  projeto_id INT NOT NULL,
  departamento_id INT NOT NULL,
  PRIMARY KEY (projeto_id, departamento_id),
  CONSTRAINT fk_pd_projeto FOREIGN KEY (projeto_id) REFERENCES projetos(id),
  CONSTRAINT fk_pd_departamento FOREIGN KEY (departamento_id) REFERENCES departamentos(id)
) ENGINE=InnoDB;

CREATE TABLE ordens_servico (
  id INT NOT NULL AUTO_INCREMENT,
  departamento_id INT NOT NULL,
  cliente_id INT NOT NULL,
  solicitante_id INT NOT NULL,
  responsavel_id INT NULL,
  projeto_id INT NULL,
  anterior_id INT NULL,
  parecer_tecnico TEXT NULL,
  tipo ENUM('instalacao', 'manutencao') NOT NULL DEFAULT 'instalacao',
  criticidade ENUM('baixo', 'medio', 'alto', 'muito_alto', 'urgente')
    NOT NULL DEFAULT 'medio',
  descricao TEXT NOT NULL,
  status ENUM('em_andamento', 'aguardando', 'validacao_testes', 'bloqueado', 'concluido')
    NOT NULL DEFAULT 'em_andamento',
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
  CONSTRAINT chk_os_prazo CHECK (prazo_dias_uteis IS NULL OR prazo_dias_uteis >= 0),
  CONSTRAINT chk_os_datas CHECK (data_inicio IS NULL OR data_fim IS NULL OR data_fim >= data_inicio),
  CONSTRAINT chk_os_status_data_fim CHECK (
    (status = 'concluido' AND data_fim IS NOT NULL)
    OR (status <> 'concluido' AND data_fim IS NULL)
  ),
  CONSTRAINT fk_os_cliente FOREIGN KEY (cliente_id) REFERENCES clientes(id),
  CONSTRAINT fk_os_projeto_mesmo_cliente FOREIGN KEY (projeto_id, cliente_id)
    REFERENCES projetos(id, cliente_id),
  CONSTRAINT fk_os_local_mesmo_cliente FOREIGN KEY (local_operacional_id, cliente_id)
    REFERENCES locais_operacionais(id, cliente_id),
  CONSTRAINT fk_os_departamento FOREIGN KEY (departamento_id) REFERENCES departamentos(id),
  CONSTRAINT fk_os_solicitante FOREIGN KEY (solicitante_id) REFERENCES funcionarios(id),
  CONSTRAINT fk_os_responsavel FOREIGN KEY (responsavel_id) REFERENCES funcionarios(id),
  CONSTRAINT fk_os_anterior FOREIGN KEY (anterior_id) REFERENCES ordens_servico(id)
) ENGINE=InnoDB;

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
  PRIMARY KEY (id),
  CONSTRAINT fk_auditoria_funcionario FOREIGN KEY (funcionario_id) REFERENCES funcionarios(id),
  CONSTRAINT fk_auditoria_os FOREIGN KEY (os_id) REFERENCES ordens_servico(id)
) ENGINE=InnoDB;

CREATE INDEX idx_os_departamento_status ON ordens_servico(departamento_id, status);
CREATE INDEX idx_os_criticidade_limite ON ordens_servico(criticidade, data_limite_sla);
CREATE INDEX idx_os_projeto ON ordens_servico(projeto_id);
CREATE INDEX idx_os_responsavel_status ON ordens_servico(responsavel_id, status);
CREATE INDEX idx_auditoria_os_data ON auditoria(os_id, data_modificacao);

-- Dados mínimos de demonstração para testar o formulário.
INSERT INTO departamentos (nome) VALUES ('Manutenção'), ('Tecnologia');
INSERT INTO clientes (nome, razao_social, ramo_atuacao) VALUES
  ('Cliente Exemplo', 'Cliente Exemplo Ltda.', 'Serviços');
INSERT INTO funcionarios (departamento_id, usuario, senha_hash, nome, tipo) VALUES
  (1, 'solicitante.demo', 'HASH_DE_DEMONSTRACAO_NAO_UTILIZAR_EM_PRODUCAO', 'Solicitante Demo', 'tecnico');
INSERT INTO locais_operacionais (cliente_id, descricao, tipo) VALUES
  (1, 'Unidade principal', 'site');
INSERT INTO projetos (cliente_id, nome, status) VALUES
  (1, 'Projeto de demonstração', 'em_planejamento');
INSERT INTO projetos_departamentos (projeto_id, departamento_id) VALUES (1, 1);
