# Workflow.Umbrella

## Notes 

- Project is initialized by 
  
  ```sh 
  mix phx.new workflow --umbrella
  cd workflow_umbrella
  mix ecto.create
  ```

- How to add another project 
  Suppose we want to add a playground project to test some interesting packages 

  ```sh 
  # Example: we just need to create a project like we normally do in apps folder. 
  mix phx.new api --app api --no-webpack --no-html --no-ecto
  mix new playground --app playground --sup
  ```

## References 

- [Umbrella projects](https://elixir-lang.org/getting-started/mix-otp/dependencies-and-umbrella-projects.html#umbrella-projects)
  - [Routing in Phoenix Umbrella Apps](https://blog.appsignal.com/2019/04/16/elixir-alchemy-routing-phoenix-umbrella-apps.html)
- About docerize Phoenix application 
  - [Containerizing a Phoenix 1.6 Umbrella Project](https://medium.com/@alistairisrael/containerizing-a-phoenix-1-6-umbrella-project-8ec03651a59c)
  - 