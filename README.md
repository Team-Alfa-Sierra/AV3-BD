# AV3-BD — Sistema de Gestão de Ordens de Serviço

Projeto acadêmico desenvolvido por Arthur Óliver Rossi Alves e Samuel Estevão Pereira Martins para a **3ª avaliação da disciplina Banco de Dados Relacional I**.

O trabalho modela e implementa uma base de dados para apoiar o gerenciamento de clientes, departamentos, funcionários, projetos e **ordens de serviço (OS)**. Também contempla regras de negócio no banco, auditoria, controle de SLA, registros de horas e uma aplicação web simples para abertura e consulta de OS.

## Objetivos do projeto

- Modelar os dados e seus relacionamentos por meio dos modelos conceitual e lógico.
- Implementar o esquema relacional em MySQL, com chaves, restrições e índices.
- Popular as tabelas com dados de demonstração.
- Implementar funções, procedures, triggers e uma view para apoiar as regras de negócio.
- Documentar a estrutura do banco por meio do dicionário de dados.
- Demonstrar a integração do banco com uma API e uma interface web.

## Tecnologias

| Tecnologia | Utilização |
| --- | --- |
| MySQL 8.0.16 ou superior | Banco de dados relacional |
| SQL | Criação do esquema, carga de dados e rotinas |
| Node.js 18 ou superior | Ambiente de execução da API |
| TypeScript | Implementação do backend |
| Express | Servidor HTTP e endpoints REST |
| mysql2 | Conexão da aplicação com o MySQL |
| HTML e Tailwind CSS | Interface web da demonstração |
| npm | Gerenciamento de dependências e scripts |

O MySQL 8.0.16 ou superior é recomendado para que as restrições `CHECK` sejam aplicadas pelo servidor.

## Organização do repositório

```text
AV3-BD/
├── Parte 1/
│   ├── Modelo Conceitual (BRModelo)/
│   │   ├── modelo_conceitual_AV3.pdf
│   │   └── modelo_conceitual_AV3.png
│   ├── Modelo Lógico/
│   │   └── av3_lógico.png
│   └── Script SQL/
│       └── script_av3.sql
├── Parte 2/
│   └── Inserção Registros (50x)/
│       └── seed_insert.sql
├── Parte 3/
│   ├── Functions/
│   │   ├── functions.sql
│   │   ├── saida.md
│   │   └── prints_functions/
│   ├── Stored Procedures/
│   │   ├── procedures.sql
│   │   ├── saida.md
│   │   └── prints_procedures/
│   └── Triggers/
│       ├── triggers.sql
│       ├── saida.md
│       └── prints_triggers/
├── Parte 4/
│   └── Dicionario_de_dados.md
├── Parte 5/
│   └── Conexão API/
│       ├── database/
│       │   ├── schema.sql
│       │   └── routines.sql
│       ├── public/
│       ├── src/
│       ├── env.example
│       ├── package.json
│       └── README.md
├── docs/
│   ├── AV3_00_Documento_do_Trabalho.pdf
│   ├── AV3_01_Script_Criacao_Tabelas.pdf
│   ├── AV3_02_Script_Insercao_Dados.pdf
│   ├── AV3_03_Dicionario_de_Dados.pdf
│   └── AV3_Proposta.pdf
└── README.md
```
## Conclusão

O desenvolvimento deste projeto permitiu consolidarmos, na prática, os conhecimentos adquiridos na disciplina de Banco de Dados Relacional I, abrangendo desde a modelagem conceitual e lógica até a implementação e manipulação de um banco de dados relacional. A construção das tabelas, a inserção de registros e o desenvolvimento de funções, procedures e triggers possibilitaram aplicar regras de negócio diretamente no banco, contribuindo para a integridade e a consistência das informações.

Além disso, a integração com uma API e uma interface web demonstrou como o banco de dados pode ser utilizado em uma aplicação, aproximando o trabalho de um cenário real de desenvolvimento de software. Dessa forma, o projeto cumpriu seu propósito acadêmico, proporcionando experiência prática com as principais etapas de planejamento, implementação e utilização de um banco de dados.