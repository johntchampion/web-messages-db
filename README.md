# Web Messages - Database Config

The `setup.sql` file contains all of the instructions to set up the PostgreSQL database.

This database is used by a backend service which can be found [here](https://github.com/appdevjohn/web-messages-service).

## Quick Setup for Development

This database can be run in any environment, but for convenience, this repository is a quick way to stand up a database in a container to get started in development.

### Required Environment Variables

| Name              | Description                           | Example     |
| ----------------- | ------------------------------------- | ----------- |
| POSTGRES_USER     | The user for the PostgreSQL database. | user        |
| POSTGRES_PASSWORD | The password for the database user.   | password1   |
| POSTGRES_DB       | The database name.                    | messages_db |

### Running in a Docker Container

First, build an image with the database properly set up.

```
docker build -t messages-db .
```

Next, run a container based on that image. Use the following environment variables and set the port to `5432`.

```
docker run -p 5432:5432 --name db -d \
    -e POSTGRES_USER=user \
    -e POSTGRES_PASSWORD=password1 \
    -e POSTGRES_DB=messages_db \
    messages-db
```

Then, if you want to interact with the database in the terminal, you can exec into the container.

```
docker exec -it db bash

psql -U user -d messages_db
```
