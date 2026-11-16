USE AV3_db;

DROP VIEW IF EXISTS vw_resumo_horas_funcionario;

CREATE VIEW vw_resumo_horas_funcionario AS
SELECT
    f.id AS funcionario_id,
    f.departamento_id,
    f.nome AS funcionario,
    COUNT(a.id) AS total_apontamentos,
    COUNT(DISTINCT a.os_id) AS total_os_atendidas,
    COALESCE(SUM(a.duracao_minutos), 0) AS total_minutos,
    ROUND(COALESCE(SUM(a.duracao_minutos), 0) / 60, 2) AS total_horas
FROM funcionarios f
LEFT JOIN apontamento_horas a
    ON a.funcionario_id = f.id
GROUP BY f.id, f.departamento_id, f.nome;

-- Remove as procedures anteriores
DROP PROCEDURE IF EXISTS sp_recalcular_sla_pendentes;
DROP PROCEDURE IF EXISTS sp_relatorio_horas_departamento;
DROP PROCEDURE IF EXISTS sp_registrar_apontamento;
DROP PROCEDURE IF EXISTS sp_painel_sla;
DROP PROCEDURE IF EXISTS sp_concluir_os;
DROP PROCEDURE IF EXISTS sp_abrir_os;

DELIMITER $$

-- 1. Abre uma OS validando cliente, solicitante, departamento e projeto
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

    SET p_os_id = NULL;

    IF p_departamento_id IS NULL OR p_cliente_id IS NULL
       OR p_solicitante_id IS NULL
       OR p_tipo IS NULL OR p_criticidade IS NULL
       OR p_titulo IS NULL OR TRIM(p_titulo) = ''
       OR p_descricao IS NULL OR TRIM(p_descricao) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Preencha os campos obrigatorios para abrir a OS.';
    END IF;

    SELECT COUNT(*) INTO v_total
      FROM departamentos
     WHERE id = p_departamento_id;

    IF v_total = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Departamento inexistente.';
    END IF;

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
          INNER JOIN projetos_departamentos pd
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

    SELECT p_os_id AS os_id,
           'Ordem de servico aberta com sucesso.' AS mensagem;
END$$

-- 2. Painel das OS abertas, priorizando SLA e criticidade
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
    INNER JOIN departamentos d
        ON d.id = o.departamento_id
    INNER JOIN clientes c
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

-- 3. Registra apontamento com data obrigatoria e descricao opcional
--    A validacao de funcionario/OS e a auditoria sao feitas pelos triggers
CREATE PROCEDURE sp_registrar_apontamento(
    IN p_os_id INT,
    IN p_funcionario_id INT,
    IN p_data_trabalho DATE,
    IN p_duracao_minutos INT,
    IN p_descricao VARCHAR(191)
)
BEGIN
    IF p_os_id IS NULL OR p_funcionario_id IS NULL OR p_data_trabalho IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Informe OS, funcionario e data de trabalho.';
    END IF;

    IF p_duracao_minutos IS NULL OR p_duracao_minutos <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A duracao deve ser maior que zero.';
    END IF;

    INSERT INTO apontamento_horas
        (os_id, funcionario_id, data_trabalho, duracao_minutos, descricao)
    VALUES
        (p_os_id, p_funcionario_id, p_data_trabalho,
         p_duracao_minutos, p_descricao);

    SELECT LAST_INSERT_ID() AS apontamento_id,
           'Apontamento registrado com sucesso.' AS mensagem;
END$$

-- 4. Relatorio por departamento. RIGHT JOIN mantem departamentos
--    mesmo quando ainda nao possuem funcionarios
--    A VIEW agrega os apontamentos por funcionario
--    A subconsulta EXISTS identifica funcionarios com pelo menos um
--    apontamento vinculado a uma OS ainda cadastrada
CREATE PROCEDURE sp_relatorio_horas_departamento(
    IN p_departamento_id INT
)
BEGIN
    SELECT
        d.id AS departamento_id,
        d.nome AS departamento,
        f.id AS funcionario_id,
        f.nome AS funcionario,
        COALESCE(v.total_os_atendidas, 0) AS total_os_atendidas,
        COALESCE(v.total_minutos, 0) AS total_minutos,
        COALESCE(v.total_horas, 0.00) AS total_horas,
        CASE
            WHEN f.id IS NULL THEN 'Sem funcionario cadastrado'
            WHEN EXISTS (
                SELECT 1
                  FROM apontamento_horas a
                  INNER JOIN ordens_servico o
                    ON o.id = a.os_id
                 WHERE a.funcionario_id = f.id
            ) THEN 'Possui apontamentos'
            ELSE 'Sem apontamentos'
        END AS situacao_apontamentos
    FROM funcionarios f
    RIGHT JOIN departamentos d
        ON d.id = f.departamento_id
    LEFT JOIN vw_resumo_horas_funcionario v
        ON v.funcionario_id = f.id
    WHERE p_departamento_id IS NULL
       OR d.id = p_departamento_id
    ORDER BY d.nome, f.nome;
END$$

-- 5. Recalcula o SLA das OS abertas usando cursor
CREATE PROCEDURE sp_recalcular_sla_pendentes()
BEGIN
    DECLARE v_fim BOOLEAN DEFAULT FALSE;
    DECLARE v_os_id INT;
    DECLARE v_data_base DATETIME(6);
    DECLARE v_prazo INT;
    DECLARE v_processadas INT DEFAULT 0;

    DECLARE cursor_os CURSOR FOR
        SELECT id,
               COALESCE(data_inicio, data_criacao),
               prazo_dias_uteis
          FROM ordens_servico
         WHERE ativo = TRUE
           AND status <> 'concluido'
           AND sla_manual = FALSE
           AND prazo_dias_uteis IS NOT NULL
         ORDER BY id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND
        SET v_fim = TRUE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    OPEN cursor_os;

    loop_os: LOOP
        FETCH cursor_os INTO v_os_id, v_data_base, v_prazo;

        IF v_fim THEN
            LEAVE loop_os;
        END IF;

        UPDATE ordens_servico
           SET data_limite_sla = fn_somar_dias_uteis(v_data_base, v_prazo)
         WHERE id = v_os_id;

        SET v_processadas = v_processadas + 1;
    END LOOP;

    CLOSE cursor_os;
    COMMIT;

    SELECT v_processadas AS total_os_processadas,
           'Recalculo de SLA concluido.' AS mensagem;
END$$

DELIMITER ;

-- 6. Conclui uma OS. O funcionario ativo deve pertencer ao departamento
--    da OS e passa a ser registrado como responsavel pela conclusao
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

    IF p_os_id IS NULL OR p_funcionario_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Informe a OS e o funcionario.';
    END IF;

    IF p_parecer_tecnico IS NULL OR TRIM(p_parecer_tecnico) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Informe o parecer tecnico para concluir a OS.';
    END IF;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_total
      FROM ordens_servico o
      INNER JOIN funcionarios f
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
           responsavel_id = p_funcionario_id,
           parecer_tecnico = p_parecer_tecnico
     WHERE id = p_os_id;

    SET @funcionario_atual = NULL;
    SET @justificativa = NULL;

    COMMIT;

    SELECT 'Ordem de servico concluida com sucesso.' AS mensagem;
END$$

-- -------------------------
-- TESTES DAS 6 PROCEDURES E DA VIEW
-- -------------------------

-- Teste da VIEW:
SELECT * FROM vw_resumo_horas_funcionario ORDER BY departamento_id, funcionario_id LIMIT 20;

-- Teste 1: abrir OS. Use IDs validos existentes e um projeto/departamento
-- compativel (ou NULL para projeto/local, se permitido).
-- CALL sp_abrir_os(1, 1, 1, NULL, NULL, 'manutencao', 'alto',
--                  'OS de teste', 'Descricao da OS de teste', @nova_os);
-- SELECT @nova_os;
-- SELECT * FROM ordens_servico WHERE id = @nova_os;

-- Teste 2: painel geral e por departamento.
CALL sp_painel_sla(NULL);
-- CALL sp_painel_sla(1);

-- Teste 3: registrar apontamento (data agora e parametro obrigatorio).
-- CALL sp_registrar_apontamento(<OS_ABERTA>, <FUNCIONARIO_ATIVO>,
--                               CURRENT_DATE(), 90, 'Atividade de teste');
-- SELECT * FROM apontamento_horas ORDER BY id DESC LIMIT 5;

-- Teste 4: relatorio com RIGHT JOIN, VIEW, GROUP BY (na VIEW) e EXISTS.
CALL sp_relatorio_horas_departamento(NULL);
-- CALL sp_relatorio_horas_departamento(1);

-- Teste 5: cursor de recalculo de SLA.
CALL sp_recalcular_sla_pendentes();

-- Teste 6: concluir OS com funcionario ativo do mesmo departamento.
-- CALL sp_concluir_os(<OS_ABERTA>, <FUNCIONARIO_DO_DEPARTAMENTO>,
--                     'Servico concluido e validado.');
-- SELECT id, status, responsavel_id, data_fim, parecer_tecnico
--   FROM ordens_servico WHERE id = <OS_ABERTA>;