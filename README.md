# Workflow.Umbrella

## Local Dev

### Start Mix project with naming node

```sh 
iex --name myapp@localhost --cookie some_token -S mix
Erlang/OTP 25 [erts-13.2] [source] [64-bit] [smp:24:24] [ds:24:24:10] [async-threads:1] [jit:ns]

Interactive Elixir (1.14.3) - press Ctrl+C to exit (type h() ENTER for help)
iex(myapp@localhost)1> Node.self
:myapp@localhost
```

- `--name` specify we running node using full name mode.
  - `:"myapp@localhost"` is the node name.
  - There is also a `--sname` short name option.
- `--cookie` is the shared token for all connecting nodes.

### Start Livebook using Container image

```sh
docker run \
--network=host \
-e RELEASE_NODE=workflow_umbrella \
-e LIVEBOOK_DISTRIBUTION=name \
-e LIVEBOOK_COOKIE=some_token \
-e LIVEBOOK_NODE=livebook@localhost \
-e LIVEBOOK_PORT=8003 \
-e LIVEBOOK_IFRAME_PORT=8004 \
-u $(id -u):$(id -g) \
-v $(pwd):/data \
ghcr.io/livebook-dev/livebook:0.12.1
```

- `--network` specify the docker container we run use [Host network driver](https://docs.docker.com/network/drivers/host/).
- Those LIVEBOOK options are from [Livebook README](https://github.com/livebook-dev/livebook).
- Tag `0.8.1` from Livebook image support OTP25.
- If succeed, it should oupt something like:

  ```sh
  [Livebook] Application running at http://0.0.0.0:8003/?token=gwc234cmrxsfnqkaeeu6hv7wjhg3qe2g
  ```

### Connect to the node from Livebook

- Create or open a Livebook.
- Go to

  - Runtime settings
  - Configure
    - `Name` should be: `elixir_horizion@localhost`
    - `Cookie` should be: the cookie we used above, such as `some_token`.
  - If connect succeed, it should shows the reconnect and disconnect option along with memory metric for the connect node.

- If connected, it means we could create code block and execute any code as if we are using `iex`.

### Others

- What is a node \
  In the context of distributed systems and Erlang/Elixir, a "node" refers to an individual running instance of the Erlang or Elixir runtime environment. Each node is a separate process or application instance that can communicate with other nodes in the same distributed system.

- `--sname` vs `--name` option
  - When using `--sname`, the node name is restricted to the local host only.
  - When using `--name`, you can set an arbitrary node name that is not restricted to a single host.

### Troubleshooting

- Evaluator.IOProxy module into the remote node, potentially due to Erlang/OTP version mismatch.
  - We have to make sure the Livebook's OTP version is compatibe with connecting node's OTP version.
- docker: Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?.
  - On ubuntu (WSL), remember to start Docker service by: `sudo service docker start`.
- Livebook docker image could start without problem, but could not visit its address from windows 11.
  
  From my experience, it is caused by I started the docker in WSL2 while the docker engine is using is Docker desktop in windows 11.
  - uninstall docker desktop from windows 11 
  - [install docker in Ubuntu20.04](https://docs.docker.com/engine/install/ubuntu/)
  - Start livebook docker as before, you should click and visit Livebook from that address now.


## Phoenix Umbrella

- Project is initialized by

  ```sh
  # Setup project
  mix phx.new workflow --umbrella
  cd workflow_umbrella
  mix ecto.create

  # Run project
  mix phx.server
  # Or run your app inside IEx (Interactive Elixir) as:
  iex -S mix phx.server
  ```

- How to add another project
  Suppose we want to add a playground project to test some interesting packages

  ```sh
  # Example: we just need to create a project like we normally do in apps folder.
  mix phx.new api --app api --no-webpack --no-html --no-ecto
  mix new playground --app playground --sup
  ```

  Notice the `phx.new` will automatically include supervisor features, so no need to add `--sup`.

- Notice dependencies between different applications
  By default if we add a new project and used some function from it in other project. It could show this warning when `mix test`:

  ```sh
  warning: Playground.hello/0 defined in application :playground is used by the current application but the current application does not depend on :playground. To fix this, you must do one of:

  1. If :playground is part of Erlang/Elixir, you must include it under :extra_applications inside "def application" in your mix.exs

  2. If :playground is a dependency, make sure it is listed under "def deps" in your mix.exs

  3. In case you don't want to add a requirement to :playground, you may optionally skip this warning by adding [xref: [exclude: [Playground]]] to your "def project" in mix.exs

  lib/workflow.ex:11: Workflow.test/0
  ```

  So let's specify that the `workflow` application depends on `playground` application: \
  open up `apps/workflow/mix.exs` and change the `deps/0` function to the following

  ```elixir
   defp deps do
    [
      ...
      {:playground, in_umbrella: true}
    ]
  end
  ```

- Context or application
  - A simple rule to decide whether or not to use a sperate application or just create a context (Module) as bondary is: \
    - Whether or not we could test the code independently without need of other application.
    - If not, we better create the code as a context in the existing application as a flat architecture.
  - If we found ourself has circular references between applications, it is a sign to merge them.

## Deployment

- All operations are done in the root of umbrella project by default.
- Prepare Phoenix application for production

  In the root of umbrella project:

  - The secrets should be read from environment virable. This is controled by `config/runtime.exs`.
  - Initial setup
    ```sh
    mix deps.get --only prod
    MIX_ENV=prod mix compile
    ```
  - Compiling your application assets

    - Because this is umbrella project, we need to go into `apps/workflow_web` to run

      ```sh
      MIX_ENV=prod mix assets.deploy

       files at "priv/static".

      Rebuilding...

      Done in 524ms.

        ../priv/static/assets/app.js  98.2kb

      ⚡ Done in 24ms
      ```

    - To cleanup run
      ```sh
      mix phx.digest.clean --all
      Clean complete for "priv/static"
      ```

  - Start server in production
    ```sh
    PORT=4001 MIX_ENV=prod mix phx.server
    ```

- Release

  - What is a release \
    Releases allow developers to precompile and package all of their code and the runtime into a single unit.

  - How to build a release \

    - For umbrella project, we need to specify the releases in `mix.exs`
      ```elixir
      releases: [
        workflow_umbrella: [
          include_executables_for: [:unix],
          applications: [
            workflow: :permanent,
            workflow_web: :permanent,
            playground: :permanent
          ]
        ]
      ]
      ```
    - Run release

      ```
      MIX_ENV=prod mix release
      * assembling workflow_umbrella-0.1.0 on MIX_ENV=prod
      * using config/runtime.exs to configure the release at runtime

      Release created at _build/prod/rel/workflow_umbrella

          # To start your system
          _build/prod/rel/workflow_umbrella/bin/workflow_umbrella start

      Once the release is running:

          # To connect to it remotely
          _build/prod/rel/workflow_umbrella/bin/workflow_umbrella remote

          # To stop it gracefully (you may also send SIGINT/SIGTERM)
          _build/prod/rel/workflow_umbrella/bin/workflow_umbrella stop

      To list all commands:

          _build/prod/rel/workflow_umbrella/bin/workflow_umbrella
      ```

  - Make sure to uncomment the line in `config/runtime.exs`
    ```
    config :workflow_web, WorkflowWeb.Endpoint, server: true
    ```

## Dockefile

- In umbrella project, we couldn't run `mix phx.gen.release --docker` to generate Dockerfile for us.
  - Run `mix phx.gen.release --docker` in `apps/workflow_web` will generate files for `apps/workflow_web`.
  - We could use it as example. So, move the generated `Dockerfile` and `.dockerignore` into umbrella project root and modify them.
- In the root of project, run `docker build -t workflow_umbrella .` to build and tag the image.
- Test the image by

  ```sh
  docker run workflow_umbrella
  Usage: workflow_umbrella COMMAND [ARGS]

  The known commands are:

  start          Starts the system
  start_iex      Starts the system with IEx attached
  daemon         Starts the system as a daemon
  daemon_iex     Starts the system as a daemon with IEx attached
  eval "EXPR"    Executes the given expression on a new, non-booted system
  rpc "EXPR"     Executes the given expression remotely on the running system
  remote         Connects to the running system via a remote shell
  restart        Restarts the running system via a remote command
  stop           Stops the running system via a remote command
  pid            Prints the operating system PID of the running system via a remote command
  version        Prints the release name and version to be booted
  ```

  So, start it as

  ```
  docker run workflow_umbrella start
  ERROR! Config provider Config.Reader failed with:
  ** (RuntimeError) environment variable DATABASE_URL is missing.
  For example: ecto://USER:PASS@HOST/DATABASE
  ...
  ```

  The error is a good things which shows us we started our release. Now, we need to solve the problem: `environment variable DATABASE_URL is missing`. We will setup Postgres server for our Phoenix container using docker-compose.

## Docker-compose

Why need docker-compose?

- Docker-compose is a tool for defining and running multi-container Docker applications.
- We’ll be needing a PostgreSQL server to run our Phoenix app. Docker Compose makes dealing with service dependencies a breeze.

Create `docker-compose.yml` file in the umbrella project root:

```yml
version: "3"
services:
  postgres:
    image: postgres:14.1
    ports:
      - 5432:5432
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: workflow_dev
```

Notice: the `workflow_dev` should match the name defined in `config/dev.exs` in umbrella project.

Run the service by `docker compose up -d` in project root \
If we run `docker network ls`, we shall see the following

```sh
NETWORK ID     NAME                        DRIVER    SCOPE
108eb968d273   workflow_umbrella_default   bridge    local
...
```

This is important. This shows the Docker internal network that Docker Compose used to run Postgres. The network name is `workflow_umbrella_default`.

- While Postgres should be listening on localhost relative to our workstation, within Docker, a container by default can’t just refer to the localhost of the host.
- We need to run our container as part of the same Docker internal network that Docker Compose used to run Postgres.

Get the name of our Postgres server by:

```sh
docker ps
CONTAINER ID   IMAGE           COMMAND                  CREATED          STATUS          PORTS                    NAMES
c16063149a5f   postgres:14.1   "docker-entrypoint.s…"   11 minutes ago   Up 11 minutes   0.0.0.0:5432->5432/tcp   workflow_umbrella-postgres-1
```

So, the our Postgres server's hostname is: `workflow_umbrella-postgres-1`.\
Using the default credentials (and the development database), set the complete DATABASE_URL:

```sh
export DATABASE_URL=ecto://postgres:postgres@workflow_umbrella-postgres-1/workflow_dev
```

- The `workflow_dev` is the DB name from `POSTGRES_DB` environment variable. It should match the name defined in `config/dev.exs` in umbrella project.

## SECRET_KEY_BASE

One last thing before run Phoenix docker is to set `SECRET_KEY_BASE`.

- It is used by Phoenix to sign/encrypt cookies and other secrets. In development, it’s generated at project creation and hard-coded in config/dev.exs.
- All we need to do is supply some value, at least 64 bytes long, encoded as Base64.
- Since we already have Elixir, we can use it generate a suitably encoded random value:

  ```sh
  export SECRET_KEY_BASE=$(elixir --eval 'IO.puts(:crypto.strong_rand_bytes(64) |> Base.encode64(padding: false))')
  ```

## Hello, Phoenix from Docker!

```
 docker run -p 4000:4000 --net workflow_umbrella_default -e DATABASE_URL=$DATABASE_URL -e SECRET_KEY_BASE=$SECRET_KEY_BASE workflow_umbrella start
```

Now visit, `http://localhost:4000`. It should show the Phoenix page!

## Build multiple services in Docker-compose

Other people's example:

```yml
# the version of docker compose we use
version: "2"

services:
  # the first container will be called postgres
  postgres:
    # the image is the last official postgres image
    image: postgres
    # the volumes allow us to have a shared space between our computer and the docker vm
    volumes:
      - "./.data/postgres:/var/lib/postgresql"
      # set up environment variable for the postgres instance
    environment:
      POSTGRES_USER: ${PSQL_USER}
      POSTGRES_PASSWORD: ${PSQL_PWD}
      POOL: 100
    # the port to listen
    ports:
      - "5432:5432"
  # the second container is called redis
  redis:
    # the image is the last official redis image of the version 5
    image: redis:5
    ports:
      - "6379:6379"
    volumes:
      - ./.data/redis:/var/lib/redis
    # set up environment variable for the redis instance
    environment:
      REDIS_PASSWORD: ${REDIS_PWD}
  # our last container is called elixir
  elixir:
    # build use a path to a Dockerfile
    build: .
    # we set multiple ports as each of our application (but database) will use a different port
    ports:
      - "4001:4001"
      - "4002:4002"
      - "4003:4003"
      - "4004:4004"
      - "4101:4101"
      - "4102:4102"
      - "4103:4103"
      - "4104:4104"
    # we share the entire app with the container, but the libs
    volumes:
      - ".:/app"
      - "/app/deps"
      - "/app/apps/admin/assets/node_modules"
    # the container will not start if the postgres container isn't running
    depends_on:
      - postgres
    # set up environment variable for the phoenix instance
    environment:
      POSTGRES_USER: ${PSQL_USER}
      POSTGRES_PASSWORD: ${PSQL_PWD}
      POSTGRES_DB_TEST: ${PSQL_DB_TEST}
      POSTGRES_DB_DEV: ${PSQL_DB}
      POSTGRES_HOST: ${PSQL_HOST}
```

[To set environment variables in docker-compose](https://docs.docker.com/compose/environment-variables/set-environment-variables/):

- Create `.env` file in the project root.
- Set up variables as

  ```text
  # PostgreSQL
  PSQL_HOST=postgres
  PSQL_PORT=5432
  PSQL_DB=test_dev
  PSQL_DB_TEST=test_test # really inspired
  PSQL_USER=user
  PSQL_PWD=password

  # Redis
  REDIS_PWD=password
  ```

## References

- About umbrella project
  - [Umbrella projects](https://elixir-lang.org/getting-started/mix-otp/dependencies-and-umbrella-projects.html#umbrella-projects)
  - [Routing in Phoenix Umbrella Apps](https://blog.appsignal.com/2019/04/16/elixir-alchemy-routing-phoenix-umbrella-apps.html)
  - [To Umbrella or not to Umbrella - EMx 162](https://topenddevs.com/podcasts/elixir-mix/episodes/to-umbrella-or-not-to-umbrella-emx-162)
- About docerize Phoenix application
  - [Use docker-compose to build multiple web apps with Elixir thanks to umbrella](https://medium.com/@cedric_paumard/how-to-build-multiple-web-apps-with-elixir-thanks-to-umbrella-part-2-set-up-the-project-800d6d731dbd)
  - [Containerizing a Phoenix 1.6 Umbrella Project](https://medium.com/@alistairisrael/containerizing-a-phoenix-1-6-umbrella-project-8ec03651a59c)
  - [Working with Elixir Releases and performing CI/CD in containers](https://geeks.wego.com/elixir-releases-ci-cd-in-containers/)
  - [Release a Phoenix application with docker and Postgres](https://medium.com/@j.schlacher_32979/release-a-phoenix-application-with-docker-and-postgres-28c6ae8c7184)
  - [Containerizing an Elixir/Phoenix (Live View) Application with Docker](https://erikknaake.medium.com/dockerizing-elixir-phoenix-2aaf56209b9f)
- About deployment
  - [Introduction to Deployment](https://hexdocs.pm/phoenix/deployment.html)
  - [UMBRELLA APPS ON FLY.IO](https://suranyami.com/umbrella-apps-on-fly-io)
