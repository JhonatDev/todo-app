#!/usr/bin/env bash
set -euo pipefail

operation=${1:?Informe a operação}
if [[ "$operation" != restore-test ]]; then
  target=${DB_TARGET:?Inventário da VM do banco ausente}
fi
bucket=${BACKUP_BUCKET:?Bucket de backup ausente}
prefix=${DEPLOY_ENVIRONMENT:?Ambiente ausente}
workdir=$(mktemp -d)
restore_container=''
cleanup() {
  if [[ -n "$restore_container" ]]; then
    docker rm -fv "$restore_container" >/dev/null 2>&1 || true
  fi
  rm -f -- "$workdir/backup.archive.gz"
  rmdir -- "$workdir"
}
trap cleanup EXIT

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

    # Restaura no runner, com a mesma versão-base e sem rede, portas ou volumes da aplicação.
    image=$(awk '$1 == "FROM" { print $2; exit }' "$(dirname -- "${BASH_SOURCE[0]}")/../banco-de-dados/Dockerfile")
    restore_container=$(docker run -d --network none --no-healthcheck \
      --entrypoint mongod "$image" --bind_ip 127.0.0.1)
    mongo_url='mongodb://127.0.0.1:27017/?serverSelectionTimeoutMS=2000'
    timeout 90 bash -c '
      until docker exec "$1" mongosh "$2" --quiet \
          --eval "quit(db.adminCommand({ping: 1}).ok === 1 ? 0 : 1)" >/dev/null 2>&1; do
        sleep 2
      done
    ' bash "$restore_container" "$mongo_url"
    docker exec -i "$restore_container" mongorestore --archive --gzip --stopOnError < "$workdir/backup.archive.gz"
    docker exec "$restore_container" mongosh "$mongo_url" --quiet --eval '
      const todos = db.getSiblingDB("todo-app").todos;
      const result = todos.validate();
      if (!result.valid) quit(1);
      print("Documentos recuperados: " + todos.countDocuments({}));
    '
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
