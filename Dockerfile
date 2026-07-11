# Base image for CI test databases.
#
# = pgvector/postgres (ya trae psql y las contrib extensions: uuid-ossp, pg_trgm,
#   fuzzystrmatch) + Flyway preinstalado (misma versión que usa esta action).
#
# Las migraciones NO se hornean acá: cada CI corre sus propias migraciones flyway
# en build time según los parámetros que mande, así que no hay staleness. Esta
# imagen solo elimina el costo por-run de instalar flyway + tooling de cliente y
# de buildear el wrapper de postgresql-action.
FROM pgvector/pgvector:0.8.2-pg16

ENV FLYWAY_VERSION=8.5.11

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends wget ca-certificates; \
    wget -qO /tmp/flyway.tar.gz \
      "https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/${FLYWAY_VERSION}/flyway-commandline-${FLYWAY_VERSION}-linux-x64.tar.gz"; \
    mkdir -p /opt/flyway; \
    tar -xzf /tmp/flyway.tar.gz -C /opt/flyway --strip-components=1; \
    ln -s /opt/flyway/flyway /usr/local/bin/flyway; \
    rm -f /tmp/flyway.tar.gz; \
    rm -rf /var/lib/apt/lists/*; \
    # sanity: el tarball linux-x64 trae un JRE embebido; si no, el build falla acá
    flyway --version
