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

## References 

- [Umbrella projects](https://elixir-lang.org/getting-started/mix-otp/dependencies-and-umbrella-projects.html#umbrella-projects)
  - [Routing in Phoenix Umbrella Apps](https://blog.appsignal.com/2019/04/16/elixir-alchemy-routing-phoenix-umbrella-apps.html)
- About docerize Phoenix application 
  - [Use docker-compose to build multiple web apps with Elixir thanks to umbrella](https://medium.com/@cedric_paumard/how-to-build-multiple-web-apps-with-elixir-thanks-to-umbrella-part-2-set-up-the-project-800d6d731dbd)
  - [Containerizing a Phoenix 1.6 Umbrella Project](https://medium.com/@alistairisrael/containerizing-a-phoenix-1-6-umbrella-project-8ec03651a59c)