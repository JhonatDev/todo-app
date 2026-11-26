FROM mongo:9.0.8

COPY ./init-mongo.js /docker-entrypoint-initdb.d/

EXPOSE 27017

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD mongosh --quiet --eval "db.adminCommand('ping').ok" || exit 1
