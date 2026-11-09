USE AV3_db;

-- Remove as funcoes anteriores para permitir recriacao
DROP FUNCTION IF EXISTS fn_percentual_os_cliente_no_prazo;
DROP FUNCTION IF EXISTS fn_total_horas_funcionario;
DROP FUNCTION IF EXISTS fn_total_os_cliente;
DROP FUNCTION IF EXISTS fn_total_horas_os;
DROP FUNCTION IF EXISTS fn_situacao_sla;
DROP FUNCTION IF EXISTS fn_somar_dias_uteis;

DELIMITER $$

-- 1. Soma dias uteis (segunda a sexta), sem considerar feriados
--    p_dias deve ser maior ou igual a zero
CREATE FUNCTION fn_somar_dias_uteis(
    p_data DATETIME(6),
    p_dias INT
)
RETURNS DATETIME(6)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_data DATETIME(6);
    DECLARE v_restantes INT;

    IF p_data IS NULL OR p_dias IS NULL THEN
        RETURN NULL;
    END IF;

    IF p_dias < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A quantidade de dias uteis nao pode ser negativa.';
    END IF;

    SET v_data = p_data;
    SET v_restantes = p_dias;

    WHILE v_restantes > 0 DO
        SET v_data = DATE_ADD(v_data, INTERVAL 1 DAY);

        -- DAYOFWEEK: 1 = domingo; 7 = sabado.
        IF DAYOFWEEK(v_data) NOT IN (1, 7) THEN
            SET v_restantes = v_restantes - 1;
        END IF;
    END WHILE;

    RETURN v_data;
END$$

-- 2. Classifica a situacao do SLA de uma ordem de servico
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
    DECLARE v_agora DATETIME(6);

    IF p_os_id IS NULL THEN
        RETURN NULL;
    END IF;

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
        IF v_fim IS NOT NULL AND v_fim <= v_limite THEN
            RETURN 'concluida_no_prazo';
        END IF;

        RETURN 'concluida_com_atraso';
    END IF;

    SET v_agora = NOW(6);

    IF v_agora > v_limite THEN
        RETURN 'atrasada';
    END IF;

    -- Comparacao temporal exata, sem truncar minutos/segundos
    IF v_limite <= DATE_ADD(v_agora, INTERVAL 24 HOUR) THEN
        RETURN 'em_risco';
    END IF;

    RETURN 'no_prazo';
END$$

-- 3. Retorna o total de horas apontadas em uma OS
CREATE FUNCTION fn_total_horas_os(
    p_os_id INT
)
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_minutos BIGINT DEFAULT 0;

    IF p_os_id IS NULL THEN
        RETURN 0;
    END IF;

    SELECT COALESCE(SUM(duracao_minutos), 0)
      INTO v_minutos
      FROM apontamento_horas
     WHERE os_id = p_os_id;

    RETURN ROUND(v_minutos / 60, 2);
END$$

-- 4. Conta as ordens de servico de um cliente
CREATE FUNCTION fn_total_os_cliente(
    p_cliente_id INT
)
RETURNS BIGINT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total BIGINT DEFAULT 0;

    IF p_cliente_id IS NULL THEN
        RETURN 0;
    END IF;

    SELECT COUNT(*)
      INTO v_total
      FROM ordens_servico
     WHERE cliente_id = p_cliente_id;

    RETURN v_total;
END$$

-- 5. Soma as horas apontadas por um funcionario
CREATE FUNCTION fn_total_horas_funcionario(
    p_funcionario_id INT
)
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total_minutos BIGINT DEFAULT 0;

    IF p_funcionario_id IS NULL THEN
        RETURN 0;
    END IF;

    SELECT COALESCE(SUM(duracao_minutos), 0)
      INTO v_total_minutos
      FROM apontamento_horas
     WHERE funcionario_id = p_funcionario_id;

    RETURN ROUND(v_total_minutos / 60, 2);
END$$

-- 6. Percentual de OS concluidas dentro do SLA para um cliente
--    Retorna NULL quando nao ha OS concluidas com SLA para calcular
CREATE FUNCTION fn_percentual_os_cliente_no_prazo(
    p_cliente_id INT
)
RETURNS DECIMAL(5,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total BIGINT DEFAULT 0;
    DECLARE v_no_prazo BIGINT DEFAULT 0;

    IF p_cliente_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT
        COUNT(*),
        COALESCE(SUM(
            CASE
                WHEN data_fim IS NOT NULL
                 AND data_fim <= data_limite_sla THEN 1
                ELSE 0
            END
        ), 0)
      INTO v_total, v_no_prazo
      FROM ordens_servico
     WHERE cliente_id = p_cliente_id
       AND status = 'concluido'
       AND data_limite_sla IS NOT NULL;

    IF v_total = 0 THEN
        RETURN NULL;
    END IF;

    RETURN ROUND((100.0 * v_no_prazo) / v_total, 2);
END$$

DELIMITER ;

-- -------------------------
-- TESTES DAS 6 FUNCTIONS
-- -------------------------

-- Teste 1: deve somar 3 dias uteis a sexta-feira, chegando na quarta-feira
SELECT fn_somar_dias_uteis('2026-11-06 09:00:00', 3)
    AS teste_somar_dias_uteis;

-- Teste negativo: deve gerar erro SQLSTATE 45000
-- SELECT fn_somar_dias_uteis(NOW(), -1);

-- Teste 2: situacao de SLA para as primeiras OS existentes
SELECT id, status, data_limite_sla, data_fim,
       fn_situacao_sla(id) AS situacao_sla
  FROM ordens_servico
 ORDER BY id
 LIMIT 10;

-- Teste 3: total de horas por OS
SELECT id, fn_total_horas_os(id) AS total_horas
  FROM ordens_servico
 ORDER BY id
 LIMIT 10;

-- Teste 4: total de OS por cliente
SELECT id, nome, fn_total_os_cliente(id) AS total_os
  FROM clientes
 ORDER BY id
 LIMIT 10;

-- Teste 5: total de horas por funcionario
SELECT id, nome, fn_total_horas_funcionario(id) AS total_horas
  FROM funcionarios
 ORDER BY id
 LIMIT 10;

-- Teste 6: percentual de OS no prazo por cliente
SELECT id, nome,
       fn_percentual_os_cliente_no_prazo(id) AS percentual_no_prazo
  FROM clientes
 ORDER BY id
 LIMIT 10;
