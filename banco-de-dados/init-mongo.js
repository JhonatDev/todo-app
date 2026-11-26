const dbName = process.env.MONGO_INITDB_DATABASE || 'todo-app';
const appUser = process.env.MONGO_APP_USER;
const appPassword = process.env.MONGO_APP_PASSWORD;

const appDb = db.getSiblingDB(dbName);

if (appUser && appPassword) {
  const existingUser = appDb.getUser(appUser);
  if (!existingUser) {
    appDb.createUser({
      user: appUser,
      pwd: appPassword,
      roles: [{ role: 'readWrite', db: dbName }],
    });
  }
}

if (!appDb.getCollectionNames().includes('todos')) {
  appDb.createCollection('todos');
}

if (appDb.todos.countDocuments() === 0) {
  appDb.todos.insertMany([
    { text: 'Laércio é um excelente professor', completed: false },
    { text: 'Estudar Cloud', completed: true },
    { text: 'Fazer exercícios da UA', completed: false },
  ]);
}
