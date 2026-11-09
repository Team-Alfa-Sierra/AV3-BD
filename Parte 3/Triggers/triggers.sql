USE AV3_db;

-- Remocao dos 6 triggers para recriacao 
DROP TRIGGER IF EXISTS trg_os_bi_calcula_sla;
DROP TRIGGER IF EXISTS trg_os_bu_regras_status;
DROP TRIGGER IF EXISTS trg_os_au_auditoria;
DROP TRIGGER IF EXISTS trg_apontamento_bi_validar;
DROP TRIGGER IF EXISTS trg_apontamento_ai_auditoria;
DROP TRIGGER IF EXISTS trg_apontamento_au_auditoria;

DELIMITER $$

-- 1. Calcula automaticamente o prazo/SLA na inclusao da OS
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

-- 2. Aplica regras de status, datas e recalculo de SLA
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

    IF NEW.status <> 'aguardando' AND NEW.data_inicio IS NULL THEN
        SET NEW.data_inicio = COALESCE(NEW.data_fim, NOW(6));
    END IF;

    IF NEW.sla_manual = FALSE
       AND NEW.status <> 'concluido'
       AND NEW.prazo_dias_uteis IS NOT NULL
       AND (
            NOT (NEW.prazo_dias_uteis <=> OLD.prazo_dias_uteis)
            OR NOT (NEW.data_inicio <=> OLD.data_inicio)
       ) THEN
        SET NEW.data_limite_sla = fn_somar_dias_uteis(
            COALESCE(NEW.data_inicio, NEW.data_criacao),
            NEW.prazo_dias_uteis
        );
    END IF;
END$$

-- 3. Audita mudancas relevantes nas ordens de servico
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

-- 4. Valida novos apontamentos: duracao, funcionario e OS
CREATE TRIGGER trg_apontamento_bi_validar
BEFORE INSERT ON apontamento_horas
FOR EACH ROW
BEGIN
    DECLARE v_funcionario INT DEFAULT 0;
    DECLARE v_os INT DEFAULT 0;

    IF NEW.duracao_minutos IS NULL OR NEW.duracao_minutos <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A duracao do apontamento deve ser maior que zero.';
    END IF;

    IF NEW.data_trabalho IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A data de trabalho e obrigatoria.';
    END IF;

    SELECT COUNT(*)
      INTO v_funcionario
      FROM funcionarios
     WHERE id = NEW.funcionario_id
       AND ativo = TRUE;

    IF v_funcionario = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Funcionario inexistente ou inativo.';
    END IF;

    SELECT COUNT(*)
      INTO v_os
      FROM ordens_servico
     WHERE id = NEW.os_id
       AND ativo = TRUE
       AND status <> 'concluido';

    IF v_os = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'OS inexistente, inativa ou ja concluida.';
    END IF;
END$$

-- 5. Audita a inclusao de apontamentos de horas
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

-- 6. Audita alteracoes na duracao dos apontamentos
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

-- -------------------------
-- TESTES DOS 6 TRIGGERS
-- Execute em ambiente de teste, os testes gravam dados
-- -------------------------

-- Teste 1: inserir uma OS com sla_manual = FALSE e conferir
-- prazo_dias_uteis/data_limite_sla calculados automaticamente.
-- Use IDs validos de departamento, cliente e solicitante.
-- INSERT INTO ordens_servico
--   (departamento_id, cliente_id, solicitante_id, tipo, criticidade,
--    descricao, titulo, status, sla_manual)
-- VALUES
--   (1, 1, 1, 'manutencao', 'alto', 'Teste do trigger de SLA',
--    'OS teste trigger SLA', 'aguardando', FALSE);
-- SET @os_teste_trigger = LAST_INSERT_ID();
-- SELECT id, prazo_dias_uteis, data_limite_sla
--   FROM ordens_servico WHERE id = @os_teste_trigger;

-- Teste 2: atualizar prazo_dias_uteis de uma OS aberta e conferir recalculo.
-- UPDATE ordens_servico
--    SET prazo_dias_uteis = prazo_dias_uteis + 1
--  WHERE id = @os_teste_trigger;
-- SELECT id, prazo_dias_uteis, data_limite_sla
--   FROM ordens_servico WHERE id = @os_teste_trigger;

-- Teste 3: alterar criticidade/responsavel/status e conferir auditoria.
-- Para concluir, responsavel_id precisa ser um funcionario valido.
-- UPDATE ordens_servico
--    SET responsavel_id = 1
--  WHERE id = @os_teste_trigger;
-- SELECT * FROM auditoria WHERE os_id = @os_teste_trigger ORDER BY id;

-- Teste 4: a procedure sp_registrar_apontamento executa este trigger.
-- CALL sp_registrar_apontamento(<OS_ABERTA>, <FUNCIONARIO_ATIVO>,
--                               CURRENT_DATE(), 60, 'Teste trigger');
-- SELECT * FROM apontamento_horas ORDER BY id DESC LIMIT 1;

-- Teste 5: conferir auditoria de inclusao de apontamento.
-- SELECT * FROM auditoria
--  WHERE os_id = <OS_ABERTA>
--  ORDER BY id DESC LIMIT 5;

-- Teste 6: atualizar um apontamento existente e conferir auditoria.
-- UPDATE apontamento_horas
--    SET duracao_minutos = duracao_minutos + 15
--  WHERE id = <ID_APONTAMENTO>;
-- SELECT * FROM auditoria
--  WHERE os_id = (SELECT os_id FROM apontamento_horas
--                  WHERE id = <ID_APONTAMENTO>)
--  ORDER BY id DESC LIMIT 5;

-- Observacao: a constraint CHECK da tabela tambem deve ser ajustada
-- no script de criacao para duracao_minutos > 0 (e nao >= 0).
