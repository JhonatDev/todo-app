#!/usr/bin/env bash
set -euo pipefail

operation=${1:?Informe a operação}
target=${DB_TARGET:?Inventário da VM do banco ausente}
bucket=${BACKUP_BUCKET:?Bucket de backup ausente}
prefix=${DEPLOY_ENVIRONMENT:?Ambiente ausente}
workdir=$(mktemp -d)
trap 'rm -f -- "$workdir/backup.archive.gz"; rmdir -- "$workdir"' EXIT

case "$operation" in
  backup)
    name="$(date -u +%Y%m%dT%H%M%SZ)-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.archive.gz"
    ssh -T "$target" 'sudo docker exec mongo-todo sh -c '"'"'
      exec mongodump --username "$MONGO_INITDB_ROOT_USERNAME" \
        --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin \
        --db "${MONGO_INITDB_DATABASE:-todo-app}" --archive --gzip --quiet
    '"'"'' > "$workdir/backup.archive.gz"
    test -s "$workdir/backup.archive.gz"
    aws s3 cp "$workdir/backup.archive.gz" "s3://$bucket/$prefix/$name" \
      --sse AES256 --only-show-errors
    echo "Backup gravado: $prefix/$name"
    ;;
  restore-test)
    name=${BACKUP_NAME:-}
    if [[ -z "$name" ]]; then
      name=$(aws s3 ls "s3://$bucket/$prefix/" | awk '{print $4}' | sort | tail -n 1)
    fi
    [[ "$name" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]+\.archive\.gz$ ]] || {
      echo 'Nenhum backup válido foi selecionado.' >&2
      exit 1
    }
    aws s3 cp "s3://$bucket/$prefix/$name" "$workdir/backup.archive.gz" --only-show-errors
    gzip -t "$workdir/backup.archive.gz"

    # O container temporário não publica portas e não usa a rede ou o volume da aplicação.
    ssh -T "$target" "$(cat <<'REMOTE'
set -eu
temp_name=todo-restore-test
image=$(sudo docker inspect --format '{{.Image}}' mongo-todo)
if sudo docker container inspect "$temp_name" >/dev/null 2>&1; then
  sudo docker rm -fv "$temp_name" >/dev/null
fi
sudo docker run -d --network none --name "$temp_name" \
  --entrypoint mongod "$image" --bind_ip 127.0.0.1 >/dev/null
trap 'sudo docker rm -fv "$temp_name" >/dev/null' EXIT
for attempt in $(seq 1 30); do
  if sudo docker exec "$temp_name" mongosh --quiet --eval 'quit(db.adminCommand({ping:1}).ok === 1 ? 0 : 1)' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
sudo docker exec -i "$temp_name" mongorestore --archive --gzip --stopOnError
sudo docker exec "$temp_name" mongosh --quiet --eval '
  const todos = db.getSiblingDB("todo-app").todos;
  const result = todos.validate();
  if (!result.valid) quit(1);
  print("Documentos recuperados: " + todos.countDocuments({}));
'
REMOTE
)" < "$workdir/backup.archive.gz"
    echo "Restauração isolada concluída: $prefix/$name"
    ;;
  reset-list)
    ssh -T "$target" 'sudo docker exec mongo-todo sh -c '"'"'
      exec mongosh --quiet --username "$MONGO_APP_USER" --password "$MONGO_APP_PASSWORD" \
        --authenticationDatabase todo-app todo-app --eval "printjson(db.todos.deleteMany({}))"
    '"'"''
    ;;
  *)
    echo "Operação desconhecida: $operation" >&2
    exit 1
    ;;
esac
