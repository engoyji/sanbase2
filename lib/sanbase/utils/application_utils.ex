defmodule Sanbase.ApplicationUtils do
  require Sanbase.Utils.Config, as: Config

  @doc ~s"""
  Start a worker/supervisor only in particular environment(s).
  Example: Not startuing `MySupervisor` in tests can now be done by replacing
  `{MySupervisor, []}` in the supervisor children by
  `start_in({MySupervisor, []}, [:dev, :prod])`

  INPORTANT NOTE: If you use it, you must use `normalize_children` on the children list.
  """
  @spec start_in(any(), list[atom()]) :: nil | any
  def start_in(expr, environments) do
    env =
      Config.module_get(Sanbase, :environment)
      |> String.to_existing_atom()

    if env in environments do
      expr
    end
  end

  @doc ~s"""
  Start a worker/supervisor only if the condition is satisfied.
  The first argument is a function with arity 0 so it is lazily evaluated
  Example: Start a worker only if an ENV var is present
    start_if(fn -> {MySupervisor, []} end, fn -> System.get_env("ENV_VAR") end)
  """
  @spec start_if((() -> any), (() -> boolean)) :: nil | any
  def start_if(expr, condition) when is_function(condition, 0) do
    try do
      if condition.() do
        expr.()
      end
    rescue
      _ -> nil
    catch
      _ -> nil
    end
  end

  @doc ~s"""
  If `start_in/2` is used it can place `nil` in the place of a worker/supervisor.
  Passing the children through `normalize_children/1` will remove these records.
  """
  def normalize_children(children) do
    children
    |> Enum.reject(&is_nil/1)
  end
end
