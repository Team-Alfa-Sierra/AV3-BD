# Sistema simples de abertura de Ordem de Serviço

Aplicação de demonstração com backend TypeScript/Express, frontend HTML + Tailwind CSS e banco MySQL local.

## Requisitos
- Node.js 18 ou superior
- MySQL 8.0.16 ou superior (para aplicação efetiva das constraints CHECK)
- npm

## Instalação

1. Crie o banco e as tabelas executando `database/schema.sql` no MySQL.
2. Execute `database/routines.sql` no mesmo banco.
3. Copie `.env.example` para `.env` e ajuste usuário e senha do MySQL.
4. No terminal, na pasta do projeto:

```bash
npm install
npm run dev
```

5. Abra `http://localhost:3000`.

O schema inclui registros fictícios mínimos para permitir testar o formulário. Remova ou substitua esses registros antes de usar dados reais.

## O que está implementado
- Carregamento de clientes, departamentos, solicitantes, projetos e locais.
- Projeto e local filtrados pelo cliente selecionado.
- Abertura da OS chamando `sp_abrir_os`.
- Gravação da OS e da auditoria na mesma transação.
- Consulta do total de OS por cliente usando `fn_total_os_cliente`.

## Endpoints
- `GET /api/opcoes`: opções dos campos do formulário.
- `POST /api/ordens-servico`: abre uma ordem de serviço.
- `GET /api/clientes/:id/total-os`: consulta o total de OS do cliente usando a FUNCTION.

A página `public/total-os.html` permite selecionar um cliente e visualizar o resultado da FUNCTION. A navegação entre abertura e consulta está disponível no menu superior.
