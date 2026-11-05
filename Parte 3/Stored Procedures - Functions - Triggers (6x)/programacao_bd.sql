USE AV3_db;

DROP PROCEDURE IF EXISTS sp_painel_sla;
DROP PROCEDURE IF EXISTS sp_concluir_os;
DROP PROCEDURE IF EXISTS sp_abrir_os;
DROP TRIGGER IF EXISTS trg_os_au_auditoria;
DROP TRIGGER IF EXISTS trg_os_bu_regras_status;
DROP TRIGGER IF EXISTS trg_os_bi_calcula_sla;
DROP FUNCTION IF EXISTS fn_total_horas_os;
DROP FUNCTION IF EXISTS fn_situacao_sla;
DROP FUNCTION IF EXISTS fn_somar_dias_uteis;

DELIMITER $$

-- =====================================================================
-- FUNCTIONS
-- =====================================================================

-- 1. Soma dias úteis a uma data, ignorando sábados e domingos.
--    Feriados não são considerados.
CREATE FUNCTION fn_somar_dias_uteis(
    p_data DATETIME(6),
    p_dias INT
)
RETURNS DATETIME(6)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_data DATETIME(6) DEFAULT p_data;
    DECLARE v_restantes INT DEFAULT p_dias;

    IF p_data IS NULL OR p_dias IS NULL THEN
        RETURN NULL;
    END IF;

    WHILE v_restantes > 0 DO
        SET v_data = DATE_ADD(v_data, INTERVAL 1 DAY);

        -- DAYOFWEEK: 1 = domingo, 7 = sábado
        IF DAYOFWEEK(v_data) NOT IN (1, 7) THEN
            SET v_restantes = v_restantes - 1;
        END IF;
    END WHILE;

    RETURN v_data;
END$$

-- 2. Retorna a situação do SLA de uma OS:
--    sem_sla, no_prazo, em_risco (vence em até 24 h), atrasada,
--    concluida_no_prazo ou concluida_com_atraso.
--    Retorna NULL se a OS não existir.
CREATE FUNCTION fn_situacao_sla(
    p_os_id INT
)
RETURNS VARCHAR(30)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_encontrada INT DEFAULT 0;
    DECLARE v_status VARCHAR(30);
    DECLARE v_limite DATETIME(6);
    DECLARE v_fim DATETIME(6);

    SELECT COUNT(*), MAX(status), MAX(data_limite_sla), MAX(data_fim)
      INTO v_encontrada, v_status, v_limite, v_fim
      FROM ordens_servico
     WHERE id = p_os_id;

    IF v_encontrada = 0 THEN
        RETURN NULL;
    END IF;

    IF v_limite IS NULL THEN
        RETURN 'sem_sla';
    END IF;

    IF v_status = 'concluido' THEN
        IF v_fim <= v_limite THEN
            RETURN 'concluida_no_prazo';
        END IF;
        RETURN 'concluida_com_atraso';
    END IF;

    IF NOW(6) > v_limite THEN
        RETURN 'atrasada';
    END IF;

    IF TIMESTAMPDIFF(HOUR, NOW(6), v_limite) < 24 THEN
        RETURN 'em_risco';
    END IF;

    RETURN 'no_prazo';
END$$

-- 3. Retorna o total de horas apontadas em uma OS.
CREATE FUNCTION fn_total_horas_os(
    p_os_id INT
)
RETURNS DECIMAL(10, 2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_minutos BIGINT DEFAULT 0;

    SELECT COALESCE(SUM(duracao_minutos), 0)
      INTO v_minutos
      FROM apontamento_horas
     WHERE os_id = p_os_id;

    RETURN ROUND(v_minutos / 60, 2);
END$$

-- 4. Permite consultar quantas ordens de serviço existem para determinado cliente
DROP FUNCTION IF EXISTS fn_total_os_cliente;

DELIMITER $$

CREATE FUNCTION fn_total_os_cliente(
    p_cliente_id INT
)
RETURNS BIGINT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total BIGINT DEFAULT 0;

    SELECT COUNT(*)
      INTO v_total
      FROM ordens_servico
     WHERE cliente_id = p_cliente_id;

    RETURN v_total;
END$$

DELIMITER ;

-- 5. Permite consultar quantas horas determinado funcionário registrou em apontamentos de trabalho
DROP FUNCTION IF EXISTS fn_total_horas_funcionario;

DELIMITER $$

CREATE FUNCTION fn_total_horas_funcionario(
    p_funcionario_id INT
)
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total_minutos BIGINT DEFAULT 0;

    SELECT COALESCE(SUM(duracao_minutos), 0)
      INTO v_total_minutos
      FROM apontamento_horas
     WHERE funcionario_id = p_funcionario_id;

    RETURN ROUND(v_total_minutos / 60, 2);
END$$

DELIMITER ;

-- 6. Permite avaliar o cumprimento dos prazos de SLA de cada cliente

DROP FUNCTION IF EXISTS fn_percentual_os_cliente_no_prazo;

DELIMITER $$

CREATE FUNCTION fn_percentual_os_cliente_no_prazo(
    p_cliente_id INT
)
RETURNS DECIMAL(5,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_percentual DECIMAL(5,2) DEFAULT 0;

    SELECT COALESCE(
        ROUND(
            100.0 * SUM(
                CASE
                    WHEN data_fim <= data_limite_sla THEN 1
                    ELSE 0
                END
            ) / NULLIF(COUNT(*), 0),
            2
        ),
        0
    )
    INTO v_percentual
    FROM ordens_servico
    WHERE cliente_id = p_cliente_id
      AND status = 'concluido'
      AND data_limite_sla IS NOT NULL;

    RETURN v_percentual;
END$$

DELIMITER ;

-- =====================================================================
-- TRIGGERS
-- =====================================================================

-- 1. Ao criar uma OS, define o prazo pela criticidade (se não informado)
--    e calcula o SLA em dias úteis.
--    OS com sla_manual = TRUE ou com SLA informado não são alteradas.
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
                COALESCE(NEW.data_inicio, NOW(6)),
                NEW.prazo_dias_uteis
            );
        END IF;
    END IF;
END$$

-- 2. Ao alterar uma OS, aplica as regras de status:
--    - impede a conclusão sem técnico responsável
--    - preenche data_inicio e data_fim automaticamente
--    - limpa data_fim se a OS for reaberta
--    - recalcula o SLA de OS abertas se o prazo ou o início mudar
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

-- 3. Registra automaticamente na auditoria as mudanças importantes da OS.
--    Autor: @funcionario_atual ou, se vazio, o responsável ou o solicitante.
--    Justificativa: @justificativa.
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

-- 4. Impedir o registro de horas com duração inválida,
-- por funcionário inativo ou em uma OS inexistente, inativa ou já concluída
DROP TRIGGER IF EXISTS trg_apontamento_bi_validar;

DELIMITER $$

CREATE TRIGGER trg_apontamento_bi_validar
BEFORE INSERT ON apontamento_horas
FOR EACH ROW
BEGIN
    DECLARE v_funcionario INT DEFAULT 0;
    DECLARE v_os INT DEFAULT 0;

    -- A duração precisa ser positiva.
    IF NEW.duracao_minutos IS NULL
       OR NEW.duracao_minutos <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A duracao do apontamento deve ser maior que zero.';
    END IF;

    -- Verifica se o funcionário existe e está ativo.
    SELECT COUNT(*)
      INTO v_funcionario
      FROM funcionarios
     WHERE id = NEW.funcionario_id
       AND ativo = TRUE;

    IF v_funcionario = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Funcionario inexistente ou inativo.';
    END IF;

    -- Verifica se a OS existe, está ativa e não foi concluída.
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

DELIMITER ;

-- 5. Registrar automaticamente na tabela auditoria 
-- quando um funcionário incluir horas em uma OS.
DROP TRIGGER IF EXISTS trg_apontamento_ai_auditoria;

DELIMITER $$

CREATE TRIGGER trg_apontamento_ai_auditoria
AFTER INSERT ON apontamento_horas
FOR EACH ROW
BEGIN
    INSERT INTO auditoria
        (os_id, funcionario_id, acao, campo_alterado,
         dado_novo, justificativa)
    VALUES
        (
            NEW.os_id,
            NEW.funcionario_id,
            'insercao',
            'duracao_minutos',
            CAST(NEW.duracao_minutos AS CHAR),
            'Registro de apontamento de horas.'
        );
END$$

DELIMITER ;

-- 6. Manter o histórico quando a duração de um apontamento for modificada
DROP TRIGGER IF EXISTS trg_apontamento_au_auditoria;

DELIMITER $$

CREATE TRIGGER trg_apontamento_au_auditoria
AFTER UPDATE ON apontamento_horas
FOR EACH ROW
BEGIN
    IF NOT (OLD.duracao_minutos <=> NEW.duracao_minutos) THEN
        INSERT INTO auditoria
            (os_id, funcionario_id, acao, campo_alterado,
             dado_antigo, dado_novo, justificativa)
        VALUES
            (
                NEW.os_id,
                NEW.funcionario_id,
                'atualizacao',
                'duracao_minutos',
                CAST(OLD.duracao_minutos AS CHAR),
                CAST(NEW.duracao_minutos AS CHAR),
                'Alteracao na duracao do apontamento.'
            );
    END IF;
END$$

DELIMITER ;

-- =====================================================================
-- STORED PROCEDURES
-- =====================================================================

-- 1. Abre uma OS após validar cliente, solicitante e projeto.
--    A OS nasce como 'aguardando', e o trigger calcula o prazo e o SLA.
CREATE PROCEDURE sp_abrir_os(
    IN p_departamento_id INT,
    IN p_cliente_id INT,
    IN p_solicitante_id INT,
    IN p_projeto_id INT,
    IN p_local_id INT,
    IN p_tipo VARCHAR(20),
    IN p_criticidade VARCHAR(20),
    IN p_titulo VARCHAR(191),
    IN p_descricao VARCHAR(191),
    OUT p_os_id INT
)
BEGIN
    DECLARE v_total INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT COUNT(*) INTO v_total
      FROM clientes
     WHERE id = p_cliente_id
       AND ativo = TRUE;

    IF v_total = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cliente inexistente ou inativo.';
    END IF;

    SELECT COUNT(*) INTO v_total
      FROM funcionarios
     WHERE id = p_solicitante_id
       AND ativo = TRUE;

    IF v_total = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Solicitante inexistente ou inativo.';
    END IF;

    IF p_projeto_id IS NOT NULL THEN
        SELECT COUNT(*) INTO v_total
          FROM projetos p
          JOIN projetos_departamentos pd
            ON pd.projeto_id = p.id
         WHERE p.id = p_projeto_id
           AND p.cliente_id = p_cliente_id
           AND p.ativo = TRUE
           AND p.status IN ('em_planejamento', 'em_andamento')
           AND pd.departamento_id = p_departamento_id;

        IF v_total = 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Projeto invalido para este cliente ou departamento.';
        END IF;
    END IF;

    START TRANSACTION;

    INSERT INTO ordens_servico
        (departamento_id, cliente_id, solicitante_id, projeto_id,
         local_operacional_id, tipo, criticidade, titulo, descricao, status)
    VALUES
        (p_departamento_id, p_cliente_id, p_solicitante_id, p_projeto_id,
         p_local_id, p_tipo, p_criticidade, p_titulo, p_descricao, 'aguardando');

    SET p_os_id = LAST_INSERT_ID();

    INSERT INTO auditoria
        (os_id, funcionario_id, acao, dado_novo, justificativa)
    VALUES
        (p_os_id, p_solicitante_id, 'insercao', p_titulo,
         'Abertura da ordem de servico.');

    COMMIT;
END$$

-- 2. Conclui uma OS. Só um funcionário ativo do departamento da OS pode
--    concluir. O trigger preenche data_fim e registra a auditoria.
CREATE PROCEDURE sp_concluir_os(
    IN p_os_id INT,
    IN p_funcionario_id INT,
    IN p_parecer_tecnico VARCHAR(191)
)
BEGIN
    DECLARE v_total INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET @funcionario_atual = NULL;
        SET @justificativa = NULL;
        RESIGNAL;
    END;

    IF p_parecer_tecnico IS NULL OR TRIM(p_parecer_tecnico) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Informe o parecer tecnico para concluir a OS.';
    END IF;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_total
      FROM ordens_servico o
      JOIN funcionarios f
        ON f.departamento_id = o.departamento_id
     WHERE o.id = p_os_id
       AND o.ativo = TRUE
       AND o.status <> 'concluido'
       AND f.id = p_funcionario_id
       AND f.ativo = TRUE;

    IF v_total = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'OS indisponivel ou funcionario sem permissao.';
    END IF;

    SET @funcionario_atual = p_funcionario_id;
    SET @justificativa = 'Conclusao registrada por sp_concluir_os.';

    UPDATE ordens_servico
       SET status = 'concluido',
           parecer_tecnico = p_parecer_tecnico
     WHERE id = p_os_id;

    SET @funcionario_atual = NULL;
    SET @justificativa = NULL;

    COMMIT;
END$$

-- 3. Painel das OS abertas, das mais críticas para as menos críticas.
--    Informe um departamento ou NULL para listar todos.
CREATE PROCEDURE sp_painel_sla(
    IN p_departamento_id INT
)
BEGIN
    SELECT
        o.id AS os_id,
        o.titulo,
        d.nome AS departamento,
        c.nome AS cliente,
        f.nome AS responsavel,
        o.status,
        o.criticidade,
        o.data_limite_sla,
        fn_situacao_sla(o.id) AS situacao_sla,
        fn_total_horas_os(o.id) AS horas_apontadas
    FROM ordens_servico o
    JOIN departamentos d
        ON d.id = o.departamento_id
    JOIN clientes c
        ON c.id = o.cliente_id
    LEFT JOIN funcionarios f
        ON f.id = o.responsavel_id
    WHERE o.ativo = TRUE
      AND o.status <> 'concluido'
      AND (p_departamento_id IS NULL OR o.departamento_id = p_departamento_id)
    ORDER BY
        FIELD(fn_situacao_sla(o.id), 'atrasada', 'em_risco', 'no_prazo', 'sem_sla'),
        FIELD(o.criticidade, 'urgente', 'muito_alto', 'alto', 'medio', 'baixo'),
        o.data_limite_sla;
END$$

DELIMITER ;

-- 4. Permitir que um funcionário registre o tempo trabalhado em uma ordem de serviço
DROP PROCEDURE IF EXISTS sp_registrar_apontamento;

DELIMITER $$

CREATE PROCEDURE sp_registrar_apontamento(
    IN p_os_id INT,
    IN p_funcionario_id INT,
    IN p_duracao_minutos INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_os_id IS NULL OR p_funcionario_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Informe a OS e o funcionario.';
    END IF;

    IF p_duracao_minutos IS NULL OR p_duracao_minutos <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A duracao deve ser maior que zero.';
    END IF;

    START TRANSACTION;

    INSERT INTO apontamento_horas
        (os_id, funcionario_id, duracao_minutos)
    VALUES
        (p_os_id, p_funcionario_id, p_duracao_minutos);

    COMMIT;
END$$

DELIMITER ;

-- 5. Permitir que a gestão consulte quantas horas cada funcionário registrou, agrupando os resultados por departamento 
DROP PROCEDURE IF EXISTS sp_relatorio_horas_departamento;

DELIMITER $$

CREATE PROCEDURE sp_relatorio_horas_departamento(
    IN p_departamento_id INT
)
BEGIN
    SELECT
        d.id AS departamento_id,
        d.nome AS departamento,
        f.id AS funcionario_id,
        f.nome AS funcionario,

        COUNT(DISTINCT a.os_id) AS total_os_atendidas,

        COALESCE(SUM(a.duracao_minutos), 0)
            AS total_minutos,

        ROUND(
            COALESCE(SUM(a.duracao_minutos), 0) / 60,
            2
        ) AS total_horas

    FROM departamentos d

    INNER JOIN funcionarios f
        ON f.departamento_id = d.id

    LEFT JOIN apontamento_horas a
        ON a.funcionario_id = f.id

    WHERE
        p_departamento_id IS NULL
        OR d.id = p_departamento_id

    GROUP BY
        d.id,
        d.nome,
        f.id,
        f.nome

    ORDER BY
        d.nome,
        total_horas DESC;
END$$

DELIMITER ;

-- 6. Permitir que a gestão recalcule os prazos de atendimento das ordens de serviço que ainda estão abertas
DROP PROCEDURE IF EXISTS sp_recalcular_sla_pendentes;

DELIMITER $$

CREATE PROCEDURE sp_recalcular_sla_pendentes()
BEGIN
    DECLARE v_fim BOOLEAN DEFAULT FALSE;
    DECLARE v_os_id INT;
    DECLARE v_data_base DATETIME(6);
    DECLARE v_prazo INT;
    DECLARE v_processadas INT DEFAULT 0;

    -- Cursor para buscar as ordens de serviço abertas
    DECLARE cursor_os CURSOR FOR
        SELECT
            id,
            COALESCE(data_inicio, data_criacao),
            prazo_dias_uteis
        FROM ordens_servico
        WHERE ativo = TRUE
          AND status <> 'concluido'
          AND sla_manual = FALSE
          AND prazo_dias_uteis IS NOT NULL
        ORDER BY id;

    -- Identifica quando o cursor não possui mais registros
    DECLARE CONTINUE HANDLER FOR NOT FOUND
        SET v_fim = TRUE;

    -- Em caso de erro, desfaz a transação
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    OPEN cursor_os;

    loop_os: LOOP

        FETCH cursor_os
        INTO v_os_id, v_data_base, v_prazo;

        IF v_fim THEN
            LEAVE loop_os;
        END IF;

        -- Recalcula o prazo considerando apenas dias úteis
        UPDATE ordens_servico
        SET data_limite_sla = fn_somar_dias_uteis(
            v_data_base,
            v_prazo
        )
        WHERE id = v_os_id;

        SET v_processadas = v_processadas + 1;

    END LOOP;

    CLOSE cursor_os;

    COMMIT;

    -- Retorna a quantidade de ordens processadas
    SELECT
        v_processadas AS total_os_processadas,
        'Recalculo de SLA concluido.' AS mensagem;

END$$

DELIMITER ;

-- =====================================================================
-- EXEMPLOS DE USO (remova os comentários para testar)
-- =====================================================================
/*
SELECT fn_somar_dias_uteis('2026-11-06 09:00:00', 3);  -- 2026-11-11 09:00:00
SELECT id, titulo, fn_situacao_sla(id), fn_total_horas_os(id) FROM ordens_servico LIMIT 10;

CALL sp_painel_sla(NULL);
CALL sp_painel_sla(3);

CALL sp_abrir_os(3, 1, 13, NULL, NULL, 'manutencao', 'alto',
                  'Troca de disjuntor', 'Disjuntor com falha de abertura.', @nova_os);
SELECT @nova_os;
SELECT * FROM ordens_servico WHERE id = @nova_os;   -- prazo e SLA calculados

UPDATE ordens_servico SET responsavel_id = 15 WHERE id = @nova_os;
CALL sp_concluir_os(@nova_os, 15, 'Disjuntor substituido e testado.');
SELECT * FROM auditoria WHERE os_id = @nova_os;     -- histórico automático
*/