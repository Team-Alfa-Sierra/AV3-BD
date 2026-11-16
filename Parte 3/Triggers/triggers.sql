USE AV3_db;

-- Remove os triggers anteriores para permitir recriacao.
DROP TRIGGER IF EXISTS trg_os_bi_calcula_sla;
DROP TRIGGER IF EXISTS trg_os_bu_regras_status;
DROP TRIGGER IF EXISTS trg_os_au_auditoria;
DROP TRIGGER IF EXISTS trg_apontamento_bi_validar;
DROP TRIGGER IF EXISTS trg_apontamento_ai_auditoria;
DROP TRIGGER IF EXISTS trg_apontamento_au_auditoria;

DELIMITER $$

-- 1. Calcula automaticamente o prazo e a data limite do SLA na inclusao da OS.
CREATE TRIGGER trg_os_bi_calcula_sla
BEFORE INSERT ON ordens_servico
FOR EACH ROW
BEGIN
    IF NEW.sla_manual = FALSE THEN
        IF NEW.prazo_dias_uteis IS NULL THEN
            SET NEW.prazo_dias_uteis = CASE NEW.criticidade
                WHEN 'urgente' THEN 1
                WHEN 'muito_alto' THEN 3
                WHEN 'alto' THEN 5
                WHEN 'medio' THEN 10
                ELSE 20
            END;
        END IF;

        IF NEW.data_limite_sla IS NULL THEN
            SET NEW.data_limite_sla = fn_somar_dias_uteis(
                COALESCE(NEW.data_inicio, NEW.data_criacao, NOW(6)),
                NEW.prazo_dias_uteis
            );
        END IF;
    END IF;
END$$

-- 2. Aplica regras de status, datas e recalculo do SLA antes de atualizar a OS.
CREATE TRIGGER trg_os_bu_regras_status
BEFORE UPDATE ON ordens_servico
FOR EACH ROW
BEGIN
    IF NEW.status = 'concluido' AND OLD.status <> 'concluido' THEN
        IF NEW.responsavel_id IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'A OS precisa de um responsavel para ser concluida.';
        END IF;

        IF NEW.data_fim IS NULL THEN
            SET NEW.data_fim = NOW(6);
        END IF;
    ELSEIF NEW.status <> 'concluido' THEN
        SET NEW.data_fim = NULL;
    END IF;

    -- Se a OS sair de aguardando sem data de inicio, utiliza a data
    -- de criacao como referencia, evitando data_inicio igual a data_fim.
    IF NEW.status <> 'aguardando' AND NEW.data_inicio IS NULL THEN
        SET NEW.data_inicio = COALESCE(NEW.data_criacao, NOW(6));
    END IF;

    -- Recalcula o SLA quando prazo ou data de inicio forem alterados.
    IF NEW.sla_manual = FALSE
       AND NEW.status <> 'concluido'
       AND NEW.prazo_dias_uteis IS NOT NULL
       AND (
            NOT (NEW.prazo_dias_uteis <=> OLD.prazo_dias_uteis)
            OR NOT (NEW.data_inicio <=> OLD.data_inicio)
       ) THEN
        SET NEW.data_limite_sla = fn_somar_dias_uteis(
            COALESCE(NEW.data_inicio, NEW.data_criacao, NOW(6)),
            NEW.prazo_dias_uteis
        );
    END IF;
END$$

-- 3. Registra na auditoria alteracoes relevantes nas ordens de servico.
CREATE TRIGGER trg_os_au_auditoria
AFTER UPDATE ON ordens_servico
FOR EACH ROW
BEGIN
    DECLARE v_autor INT;

    SET v_autor = COALESCE(
        @funcionario_atual,
        NEW.responsavel_id,
        NEW.solicitante_id
    );

    IF NOT (OLD.status <=> NEW.status) THEN
        INSERT INTO auditoria
            (os_id, funcionario_id, acao, campo_alterado,
             dado_antigo, dado_novo, justificativa)
        VALUES
            (NEW.id, v_autor, 'atualizacao', 'status',
             OLD.status, NEW.status, @justificativa);
    END IF;

    IF NOT (OLD.responsavel_id <=> NEW.responsavel_id) THEN
        INSERT INTO auditoria
            (os_id, funcionario_id, acao, campo_alterado,
             dado_antigo, dado_novo, justificativa)
        VALUES
            (NEW.id, v_autor, 'atualizacao', 'responsavel_id',
             CAST(OLD.responsavel_id AS CHAR),
             CAST(NEW.responsavel_id AS CHAR), @justificativa);
    END IF;

    IF NOT (OLD.criticidade <=> NEW.criticidade) THEN
        INSERT INTO auditoria
            (os_id, funcionario_id, acao, campo_alterado,
             dado_antigo, dado_novo, justificativa)
        VALUES
            (NEW.id, v_autor, 'atualizacao', 'criticidade',
             OLD.criticidade, NEW.criticidade, @justificativa);
    END IF;

    IF NOT (OLD.data_limite_sla <=> NEW.data_limite_sla) THEN
        INSERT INTO auditoria
            (os_id, funcionario_id, acao, campo_alterado,
             dado_antigo, dado_novo, justificativa)
        VALUES
            (NEW.id, v_autor, 'atualizacao', 'data_limite_sla',
             DATE_FORMAT(OLD.data_limite_sla, '%Y-%m-%d %H:%i:%s'),
             DATE_FORMAT(NEW.data_limite_sla, '%Y-%m-%d %H:%i:%s'),
             @justificativa);
    END IF;

    IF OLD.ativo = TRUE AND NEW.ativo = FALSE THEN
        INSERT INTO auditoria
            (os_id, funcionario_id, acao, campo_alterado,
             dado_antigo, dado_novo, justificativa)
        VALUES
            (NEW.id, v_autor, 'exclusao', 'ativo',
             '1', '0', @justificativa);
    END IF;
END$$

-- 4. Valida novos apontamentos de horas.
-- O funcionario deve estar ativo e pertencer ao departamento da OS.
CREATE TRIGGER trg_apontamento_bi_validar
BEFORE INSERT ON apontamento_horas
FOR EACH ROW
BEGIN
    DECLARE v_total INT DEFAULT 0;

    IF NEW.duracao_minutos IS NULL OR NEW.duracao_minutos <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A duracao do apontamento deve ser maior que zero.';
    END IF;

    IF NEW.data_trabalho IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A data de trabalho e obrigatoria.';
    END IF;

    SELECT COUNT(*)
      INTO v_total
      FROM funcionarios f
      INNER JOIN ordens_servico o
        ON o.departamento_id = f.departamento_id
     WHERE f.id = NEW.funcionario_id
       AND f.ativo = TRUE
       AND o.id = NEW.os_id
       AND o.ativo = TRUE
       AND o.status <> 'concluido';

    IF v_total = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
            'Funcionario ou OS invalido, inativo, de outro departamento ou OS concluida.';
    END IF;
END$$

-- 5. Audita a inclusao de apontamentos de horas.
CREATE TRIGGER trg_apontamento_ai_auditoria
AFTER INSERT ON apontamento_horas
FOR EACH ROW
BEGIN
    INSERT INTO auditoria
        (os_id, funcionario_id, acao, campo_alterado,
         dado_novo, justificativa)
    VALUES
        (NEW.os_id, NEW.funcionario_id, 'insercao',
         'duracao_minutos', CAST(NEW.duracao_minutos AS CHAR),
         'Registro de apontamento de horas.');
END$$

-- 6. Audita alteracoes na duracao dos apontamentos.
CREATE TRIGGER trg_apontamento_au_auditoria
AFTER UPDATE ON apontamento_horas
FOR EACH ROW
BEGIN
    IF NOT (OLD.duracao_minutos <=> NEW.duracao_minutos) THEN
        INSERT INTO auditoria
            (os_id, funcionario_id, acao, campo_alterado,
             dado_antigo, dado_novo, justificativa)
        VALUES
            (NEW.os_id, NEW.funcionario_id, 'atualizacao',
             'duracao_minutos',
             CAST(OLD.duracao_minutos AS CHAR),
             CAST(NEW.duracao_minutos AS CHAR),
             'Alteracao na duracao do apontamento.');
    END IF;
END$$

DELIMITER ;

-- =========================================================
-- TESTES DOS 6 TRIGGERS
-- Pre-requisitos: script_av3.sql, seed_insert.sql e functions.sql.
-- Os testes inserem uma OS de demonstracao e um apontamento.
-- =========================================================

-- Preparacao: seleciona um funcionario ativo e um cliente ativo.
SELECT
    f.id,
    f.departamento_id,
    c.id
INTO
    @funcionario_trigger_teste,
    @departamento_trigger_teste,
    @cliente_trigger_teste
FROM funcionarios f
CROSS JOIN clientes c
WHERE f.ativo = TRUE
  AND c.ativo = TRUE
ORDER BY f.id, c.id
LIMIT 1;

-- TESTE 1: BEFORE INSERT calcula automaticamente o SLA.
INSERT INTO ordens_servico (
    departamento_id, cliente_id, solicitante_id,
    tipo, criticidade, descricao, titulo, status, sla_manual
)
VALUES (
    @departamento_trigger_teste,
    @cliente_trigger_teste,
    @funcionario_trigger_teste,
    'manutencao',
    'alto',
    'OS criada para testar o calculo automatico do SLA pelo trigger.',
    'TESTE TRIGGER - Calculo de SLA',
    'aguardando',
    FALSE
);

SET @os_trigger_teste = LAST_INSERT_ID();

SELECT
    id, criticidade, prazo_dias_uteis, data_criacao,
    data_limite_sla, sla_manual
FROM ordens_servico
WHERE id = @os_trigger_teste;

-- TESTE 2: BEFORE UPDATE recalcula o SLA quando o prazo muda.
UPDATE ordens_servico
SET prazo_dias_uteis = 2
WHERE id = @os_trigger_teste;

SELECT
    id, prazo_dias_uteis, data_inicio, data_limite_sla
FROM ordens_servico
WHERE id = @os_trigger_teste;

-- TESTE 3: AFTER UPDATE registra status, responsavel,
-- criticidade e alteracao do SLA na auditoria.
SET @funcionario_atual = @funcionario_trigger_teste;
SET @justificativa = 'Teste do trigger de auditoria de OS.';

UPDATE ordens_servico
SET status = 'em_andamento',
    responsavel_id = @funcionario_trigger_teste,
    criticidade = 'urgente'
WHERE id = @os_trigger_teste;

SET @funcionario_atual = NULL;
SET @justificativa = NULL;

SELECT
    id, status, responsavel_id, criticidade,
    data_inicio, data_limite_sla
FROM ordens_servico
WHERE id = @os_trigger_teste;

SELECT *
FROM auditoria
WHERE os_id = @os_trigger_teste
ORDER BY id;

-- TESTE 4: BEFORE INSERT valida o apontamento.
-- O funcionario e a OS pertencem ao mesmo departamento e estao ativos.
INSERT INTO apontamento_horas (
    funcionario_id, os_id, data_trabalho, duracao_minutos, descricao
)
VALUES (
    @funcionario_trigger_teste,
    @os_trigger_teste,
    CURRENT_DATE(),
    60,
    'Teste do trigger de validacao de apontamento.'
);

SET @apontamento_trigger_teste = LAST_INSERT_ID();

SELECT *
FROM apontamento_horas
WHERE id = @apontamento_trigger_teste;

-- TESTE 5: AFTER INSERT registra a inclusao na auditoria.
SELECT
    id, os_id, funcionario_id, acao, campo_alterado,
    dado_novo, justificativa
FROM auditoria
WHERE os_id = @os_trigger_teste
  AND campo_alterado = 'duracao_minutos'
ORDER BY id;

-- TESTE 6: AFTER UPDATE registra a alteracao da duracao.
UPDATE apontamento_horas
SET duracao_minutos = duracao_minutos + 15
WHERE id = @apontamento_trigger_teste;

SELECT *
FROM apontamento_horas
WHERE id = @apontamento_trigger_teste;

SELECT
    id, os_id, funcionario_id, acao, campo_alterado,
    dado_antigo, dado_novo, justificativa
FROM auditoria
WHERE os_id = @os_trigger_teste
  AND campo_alterado = 'duracao_minutos'
ORDER BY id;

-- TESTE OPCIONAL DE VALIDACAO:
-- A instrucao abaixo deve gerar SQLSTATE 45000, pois a duracao e zero.
-- Execute separadamente para visualizar a mensagem de erro:
-- INSERT INTO apontamento_horas
--     (funcionario_id, os_id, data_trabalho, duracao_minutos, descricao)
-- VALUES
--     (@funcionario_trigger_teste, @os_trigger_teste,
--      DATE_ADD(CURRENT_DATE(), INTERVAL 1 DAY), 0,
--      'Teste de duracao invalida.');
