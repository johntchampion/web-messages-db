FROM postgres:18

COPY setup.sql /docker-entrypoint-initdb.d/