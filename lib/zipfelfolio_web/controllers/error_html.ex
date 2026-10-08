defmodule ZipfelfolioWeb.ErrorHTML do
  @moduledoc false
  use ZipfelfolioWeb, :html

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
