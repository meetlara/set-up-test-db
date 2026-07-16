# Base image for CI test databases.
#
# = pgvector/postgres (ya trae psql y las contrib extensions: uuid-ossp, pg_trgm,
#   fuzzystrmatch) + Flyway preinstalado (misma versión que usa esta action).
#
# Las migraciones NO se hornean acá: cada CI corre sus propias migraciones flyway
# en build time según los parámetros que mande, así que no hay staleness. Esta
# imagen solo elimina el costo por-run de instalar flyway + tooling de cliente y
# de buildear el wrapper de postgresql-action.
#
# Superficie de CVEs (Aikido): la imagen tenía ~90 findings, casi todos ruido que
# no aplica a una DB de test efímera. Igual los recortamos en origen:
#  1) flyway `-linux-x64` bundleaba AdoptOpenJDK 11.0.2 (ene-2019) + ~20 JDBC drivers
#     de DBs que NO usamos (Oracle, MSSQL, Snowflake, BigQuery, Derby, H2, SQLite,
#     MariaDB, Firebird...) + libs de auth Azure AD. Usamos el tarball SIN JRE (java
#     de debian, parcheado), borramos TODOS los drivers salvo postgres y lo subimos
#     a 42.7.x. Flyway queda 8.5.11 EXACTO → mismo comportamiento de migraciones.
#  2) paquetes de debian bookworm viejos → `apt-get upgrade`.
#  3) gosu (helper de privilege-drop de la imagen de postgres) venía compilado con
#     un go/stdlib con CVEs → lo recompilamos con un toolchain de Go actual.

# --- gosu recompilado con Go actual: el binario de la imagen base arrastra los CVEs
#     del go/stdlib con el que se compiló; rebuildearlo los limpia sin cambiar gosu.
FROM golang:1.26-bookworm AS gosu
RUN CGO_ENABLED=0 go install -ldflags "-s -w" github.com/tianon/gosu@latest

# base pineada por digest para evitar drift de tag mutable (igual corremos
# apt-get upgrade abajo, así que los security patches del OS los tomamos nosotros)
FROM pgvector/pgvector:0.8.2-pg16@sha256:00ba258a66dac104fd5171074a0084462a64a1369d8513f3d0a634e2f24d15bc

ENV FLYWAY_VERSION=8.5.11 \
    PG_JDBC_VERSION=42.7.13 \
    # checksums fijados en el repo (Maven Central sólo publica sha1); se validan
    # antes de extraer/usar los artefactos bajados
    FLYWAY_SHA256=aa60efb9bc965814536eca550d20028a4942e9af25e67e32f3cbf3dd56459d5d \
    PG_JDBC_SHA256=6e0e4cc2d8cae902084f8a2b18728b073a6fd9d1f87c9d8bff8f298c18185b93

COPY --from=gosu /go/bin/gosu /usr/local/bin/gosu

RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends default-jre-headless ca-certificates wget; \
    # flyway SIN jre embebido (usa el java de debian, que sí recibe security updates)
    wget -qO /tmp/flyway.tar.gz \
      "https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/${FLYWAY_VERSION}/flyway-commandline-${FLYWAY_VERSION}.tar.gz"; \
    echo "${FLYWAY_SHA256}  /tmp/flyway.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/flyway; \
    tar -xzf /tmp/flyway.tar.gz -C /opt/flyway --strip-components=1; \
    rm -f /tmp/flyway.tar.gz; \
    ln -s /opt/flyway/flyway /usr/local/bin/flyway; \
    # sólo migramos postgres: fuera TODOS los drivers y libs de auth de otras DBs
    rm -rf /opt/flyway/drivers /opt/flyway/lib/aad /opt/flyway/lib/oracle_wallet; \
    mkdir -p /opt/flyway/drivers; \
    wget -qO "/opt/flyway/drivers/postgresql-${PG_JDBC_VERSION}.jar" \
      "https://repo1.maven.org/maven2/org/postgresql/postgresql/${PG_JDBC_VERSION}/postgresql-${PG_JDBC_VERSION}.jar"; \
    echo "${PG_JDBC_SHA256}  /opt/flyway/drivers/postgresql-${PG_JDBC_VERSION}.jar" | sha256sum -c -; \
    # wget sólo se necesita en build; el JRE lo resuelve flyway vía `java` en PATH
    apt-get purge -y --auto-remove wget; \
    rm -rf /var/lib/apt/lists/*; \
    # sanity: flyway arranca con el java de debian y el gosu recompilado funciona
    flyway --version; \
    gosu nobody true
