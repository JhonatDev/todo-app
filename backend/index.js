const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const bodyParser = require('body-parser');

const app = express();
const port = Number(process.env.PORT) || 5000;

/**
 * Monta a URI do MongoDB a partir de MONGODB_URI ou das variáveis individuais,
 * evitando credenciais fixas no código-fonte.
 */
function buildMongoUri() {
  if (process.env.MONGODB_URI) {
    return process.env.MONGODB_URI;
  }

  const host = process.env.MONGO_HOST;
  const mongoPort = process.env.MONGO_PORT || '27017';
  const dbName = process.env.MONGO_DB || 'todo-app';
  const user = process.env.MONGO_USER;
  const password = process.env.MONGO_PASSWORD;
  const authSource = process.env.MONGO_AUTH_SOURCE || dbName;

  if (!host || !user || !password) {
    throw new Error(
      'Configuração do MongoDB ausente: defina MONGODB_URI ou MONGO_HOST, MONGO_USER e MONGO_PASSWORD.'
    );
  }

  const encodedUser = encodeURIComponent(user);
  const encodedPassword = encodeURIComponent(password);
  return `mongodb://${encodedUser}:${encodedPassword}@${host}:${mongoPort}/${dbName}?authSource=${encodeURIComponent(authSource)}`;
}

/**
 * Configura CORS de forma segura a partir de CORS_ORIGIN.
 * Sem CORS_ORIGIN definido, bloqueia origens cruzadas (mesma origem via Nginx não requer CORS).
 */
function buildCorsOptions() {
  const rawOrigin = process.env.CORS_ORIGIN;
  if (!rawOrigin || !rawOrigin.trim()) {
    return { origin: false };
  }

  if (rawOrigin.trim() === '*') {
    return { origin: '*' };
  }

  const allowedOrigins = rawOrigin
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

  return { origin: allowedOrigins };
}

const mongoUri = buildMongoUri();

function connectWithRetry() {
  mongoose
    .connect(mongoUri, { serverSelectionTimeoutMS: 5000 })
    .then(() => console.log('Conectado ao MongoDB'))
    .catch((err) => {
      console.error('Erro ao conectar ao MongoDB:', err.message);
      setTimeout(connectWithRetry, 5000);
    });
}

connectWithRetry();

app.use(cors(buildCorsOptions()));
app.use(bodyParser.json());

// Definindo o modelo de Tarefa (To-do)
const TodoSchema = new mongoose.Schema({
  text: { type: String, required: true },
  completed: { type: Boolean, default: false },
});

const Todo = mongoose.model('Todo', TodoSchema);

// Endpoint de verificação de saúde da API e do banco
app.get('/health', async (req, res) => {
  if (mongoose.connection.readyState !== 1) {
    return res.status(503).json({ status: 'error', database: 'disconnected' });
  }

  try {
    await mongoose.connection.db.admin().ping();
    return res.status(200).json({ status: 'ok', database: 'connected' });
  } catch (err) {
    return res.status(503).json({ status: 'error', database: 'unreachable' });
  }
});

// Rota para obter todas as tarefas (GET)
app.get('/todos', async (req, res) => {
  try {
    const todos = await Todo.find();
    res.json(todos);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Rota para adicionar uma nova tarefa (POST)
app.post('/todos', async (req, res) => {
  const { text } = req.body;

  if (!text) {
    return res.status(400).json({ message: 'O campo "text" é obrigatório' });
  }

  const todo = new Todo({
    text,
    completed: false,
  });

  try {
    const newTodo = await todo.save();
    res.status(201).json(newTodo);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Rota para marcar uma tarefa como concluída/reaberta (PATCH)
app.patch('/todos/:id', async (req, res) => {
  try {
    const todo = await Todo.findById(req.params.id);

    if (!todo) {
      return res.status(404).json({ message: 'Tarefa não encontrada' });
    }

    todo.completed = !todo.completed;
    await todo.save();
    res.json(todo);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Rota para excluir uma tarefa (DELETE)
app.delete('/todos/:id', async (req, res) => {
  try {
    const todo = await Todo.findByIdAndDelete(req.params.id);

    if (!todo) {
      return res.status(404).json({ message: 'Tarefa não encontrada' });
    }

    res.json({ message: 'Tarefa excluída com sucesso' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

app.listen(port, () => {
  console.log(`Servidor rodando na porta ${port}`);
});
