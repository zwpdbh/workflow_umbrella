# Workflow.Umbrella

## Notes 

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
  - What is a release  \
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
  - In the root of project, run `docker build -t app-test-001 .` to build and tag the image. 
  - Test the image by 
    ```sh 
    docker run app-test-001
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
    docker run app-test-001 start
    ERROR! Config provider Config.Reader failed with:
    ** (RuntimeError) environment variable DATABASE_URL is missing.
    For example: ecto://USER:PASS@HOST/DATABASE
    ...
    ```

    The error is a good things which shows us we started our release. Now, we need to solve the problem: `environment variable DATABASE_URL is missing`. 


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
