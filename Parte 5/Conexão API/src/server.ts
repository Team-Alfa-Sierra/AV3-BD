import express, { Request, Response } from "express";
import path from "path";
import dotenv from "dotenv";
import { RowDataPacket } from "mysql2";
import { pool } from "./db";

dotenv.config();

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, "../public")));

type Option = RowDataPacket & { id: number; nome: string };

app.get("/api/opcoes", async (_req: Request, res: Response) => {
  try {
    const [clientes] = await pool.query<Option[]>(
      "SELECT id, nome FROM clientes WHERE ativo = TRUE ORDER BY nome"
    );
    const [departamentos] = await pool.query<Option[]>(
      "SELECT id, nome FROM departamentos ORDER BY nome"
    );
    const [funcionarios] = await pool.query<Option[]>(
      "SELECT id, nome, departamento_id FROM funcionarios WHERE ativo = TRUE ORDER BY nome"
    );
    const [locais] = await pool.query<(RowDataPacket & { id: number; descricao: string; cliente_id: number })[]>(
      "SELECT id, descricao, cliente_id FROM locais_operacionais ORDER BY descricao"
    );
    const [projetos] = await pool.query<(RowDataPacket & { id: number; nome: string; cliente_id: number })[]>(
      `SELECT id, nome, cliente_id FROM projetos
       WHERE ativo = TRUE AND status IN ('em_planejamento', 'em_andamento')
       ORDER BY nome`
    );

    res.json({ clientes, departamentos, funcionarios, locais, projetos });
  } catch (error) {
    console.error(error);
    res.status(500).json({ mensagem: "Não foi possível carregar os dados do formulário." });
  }
});

app.post("/api/ordens-servico", async (req: Request, res: Response) => {
  const {
    departamento_id, cliente_id, solicitante_id, projeto_id, local_id,
    tipo, criticidade, titulo, descricao
  } = req.body;

  const obrigatorios = [
    departamento_id, cliente_id, solicitante_id, tipo, criticidade, titulo, descricao
  ];

  if (obrigatorios.some((valor) => valor === undefined || valor === null || String(valor).trim() === "")) {
    return res.status(400).json({ mensagem: "Preencha todos os campos obrigatórios." });
  }

  const tipos = ["instalacao", "manutencao"];
  const criticidades = ["baixo", "medio", "alto", "muito_alto", "urgente"];

  if (!tipos.includes(tipo) || !criticidades.includes(criticidade)) {
    return res.status(400).json({ mensagem: "Tipo ou criticidade inválidos." });
  }

  if (String(titulo).trim().length > 191 || String(descricao).trim().length > 2000) {
    return res.status(400).json({ mensagem: "O título deve ter no máximo 191 caracteres e a descrição, 2.000." });
  }

  const ids = [departamento_id, cliente_id, solicitante_id];
  if (ids.some((id) => !Number.isInteger(Number(id)) || Number(id) <= 0)) {
    return res.status(400).json({ mensagem: "Selecione opções válidas para departamento, cliente e solicitante." });
  }

  const connection = await pool.getConnection();
  try {
    // A chamada da procedure e a leitura da variável OUT precisam usar
    // a mesma conexão, pois variáveis @ do MySQL pertencem à sessão.
    await connection.query(
      `CALL sp_abrir_os(?, ?, ?, ?, ?, ?, ?, ?, ?, @p_os_id)`,
      [
        Number(departamento_id),
        Number(cliente_id),
        Number(solicitante_id),
        projeto_id ? Number(projeto_id) : null,
        local_id ? Number(local_id) : null,
        tipo,
        criticidade,
        String(titulo).trim(),
        String(descricao).trim()
      ]
    );

    const [resultado] = await connection.query<RowDataPacket[]>(
      "SELECT @p_os_id AS os_id"
    );
    const osId = resultado[0]?.os_id;

    return res.status(201).json({
      os_id: osId,
      mensagem: `Ordem de serviço #${osId} aberta com sucesso.`
    });
  } catch (error: any) {
    console.error(error);
    const mensagem = error?.sqlMessage || "Não foi possível abrir a ordem de serviço.";
    return res.status(400).json({ mensagem });
  } finally {
    connection.release();
  }
});

app.get("/api/clientes/:id/total-os", async (req: Request, res: Response) => {
  const clienteId = Number(req.params.id);
  if (!Number.isInteger(clienteId) || clienteId <= 0) {
    return res.status(400).json({ mensagem: "ID de cliente inválido." });
  }

  try {
    const [rows] = await pool.query<RowDataPacket[]>(
      "SELECT fn_total_os_cliente(?) AS total",
      [clienteId]
    );
    return res.json({ cliente_id: clienteId, total: rows[0].total });
  } catch (error) {
    console.error(error);
    return res.status(500).json({ mensagem: "Não foi possível consultar o total de OS." });
  }
});

const port = Number(process.env.PORT || 3000);
app.listen(port, () => console.log(`Sistema disponível em http://localhost:${port}`));
