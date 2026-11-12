USE AV3_db;

DROP PROCEDURE IF EXISTS sp_abrir_os;
DROP FUNCTION IF EXISTS fn_total_os_cliente;

DELIMITER $$

CREATE FUNCTION fn_total_os_cliente(p_cliente_id INT)
RETURNS BIGINT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
  DECLARE v_total BIGINT DEFAULT 0;

  IF p_cliente_id IS NULL THEN
    RETURN 0;
  END IF;

  SELECT COUNT(*) INTO v_total
  FROM ordens_servico
  WHERE cliente_id = p_cliente_id;

  RETURN v_total;
END$$

CREATE PROCEDURE sp_abrir_os(
  IN p_departamento_id INT,
  IN p_cliente_id INT,
  IN p_solicitante_id INT,
  IN p_projeto_id INT,
  IN p_local_id INT,
  IN p_tipo VARCHAR(20),
  IN p_criticidade VARCHAR(20),
  IN p_titulo VARCHAR(191),
  IN p_descricao TEXT,
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
     OR p_tipo IS NULL OR p_tipo NOT IN ('instalacao', 'manutencao')
     OR p_criticidade IS NULL OR p_criticidade NOT IN ('baixo', 'medio', 'alto', 'muito_alto', 'urgente')
     OR p_titulo IS NULL OR TRIM(p_titulo) = ''
     OR p_descricao IS NULL OR TRIM(p_descricao) = '' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Preencha os campos obrigatorios para abrir a OS.';
  END IF;

  SELECT COUNT(*) INTO v_total
  FROM departamentos WHERE id = p_departamento_id;
  IF v_total = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Departamento inexistente.';
  END IF;

  SELECT COUNT(*) INTO v_total
  FROM clientes WHERE id = p_cliente_id AND ativo = TRUE;
  IF v_total = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cliente inexistente ou inativo.';
  END IF;

  SELECT COUNT(*) INTO v_total
  FROM funcionarios
  WHERE id = p_solicitante_id AND ativo = TRUE
    AND departamento_id = p_departamento_id;
  IF v_total = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Solicitante inexistente, inativo ou de outro departamento.';
  END IF;

  IF p_projeto_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_total
    FROM projetos p
    INNER JOIN projetos_departamentos pd ON pd.projeto_id = p.id
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

  INSERT INTO ordens_servico (
    departamento_id, cliente_id, solicitante_id, projeto_id,
    local_operacional_id, tipo, criticidade, titulo, descricao, status
  ) VALUES (
    p_departamento_id, p_cliente_id, p_solicitante_id, p_projeto_id,
    p_local_id, p_tipo, p_criticidade, TRIM(p_titulo), TRIM(p_descricao), 'aguardando'
  );

  SET p_os_id = LAST_INSERT_ID();

  INSERT INTO auditoria (
    os_id, funcionario_id, acao, dado_novo, justificativa
  ) VALUES (
    p_os_id, p_solicitante_id, 'insercao', TRIM(p_titulo),
    'Abertura da ordem de servico.'
  );

  COMMIT;

  SELECT p_os_id AS os_id, 'Ordem de servico aberta com sucesso.' AS mensagem;
END$$

DELIMITER ;
