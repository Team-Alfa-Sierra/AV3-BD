# Saídas das Stored Procedures 

## 1. Abre uma OS validando cliente, solicitante, departamento e projeto
Teste: cadastrar uma nova ordem de serviço e registrar a operação na auditoria
Comando: 
    1° selecionando registro válido: 
        SELECT d.id, c.id, f.id INTO @departamento, @cliente, @funcionario FROM departamentos d 
        CROSS JOIN clientes c INNER JOIN funcionarios f ON f.departamento_id = d.id 
        WHERE c.ativo = TRUE AND f.ativo = TRUE ORDER BY d.id, c.id, f.id
        LIMIT 1;
    2° chamando a procedure:
        CALL sp_abrir_os(@departamento, @cliente, @funcionario, NULL, NULL, 'manutencao', 'alto',
        'TESTE - Abertura de OS', 'Teste de cadastro realizado para a avaliacao.', @nova_os);

<img src="./prints_procedures/procedure1.png">

## 2. Painel das OS abertas, priorizando SLA e criticidade
Teste: apresentar as ordens de serviço abertas, classificadas conforme a situação do SLA e a criticidade
Comando: 
    1° Executar ./Functions/function.sql 
    2° chamando a procedure:
        CALL sp_painel_sla(NULL);
<img src="./prints_procedures/procedure2.png">

## 3. Registra apontamento com data obrigatoria e descricao opcional, a validacao de funcionario/OS e a auditoria sao feitas pelos triggers
Teste: registrar o tempo que um funcionário trabalhou em determinada ordem de serviço
Comando: CALL sp_registrar_apontamento(@nova_os, @funcionario, CURRENT_DATE(), 90,'Teste de apontamento de horas.');

<img src="./prints_procedures/procedure3.png">

## 4. Relatórios por Departamento
Teste: gerar um relatório de horas trabalhadas por departamento e funcionário
Comando: CALL sp_relatorio_horas_departamento(NULL);

<img src="./prints_procedures/procedure4.png">

## 5. Recalcula o SLA das OS abertas usando cursor
Teste: recalcular automaticamente a data limite do SLA das ordens de serviço que ainda estão pendentes
Comando: 
    1° preparar a ordem de serviço de teste para o recálculo: 
        UPDATE ordens_servico SET prazo_dias_uteis = 3, sla_manual = FALSE WHERE id = @nova_os;
    2° chamando a procesure:
        CALL sp_recalcular_sla_pendentes();

<img src="./prints_procedures/procedure5.png">
