defmodule ZipfelfolioWeb.Plush do
  @moduledoc """
  The plush images for `<.plush>` and `<.empty_state plush="…">` from setzkasten: one transparent
  WebP per name in `priv/static/images/plush`, used in both themes and named after the Lucide icon
  they stand in for.

  The images are derived from Noto Emoji 3D (Google, Apache License 2.0); `LICENSE` and `NOTICE`
  next to them name the source and the changes.
  """
  @behaviour Setzkasten.Plush
  use ZipfelfolioWeb, :verified_routes

  @impl true
  def src("briefcase", :light), do: ~p"/images/plush/briefcase.webp"
  def src("coins", :light), do: ~p"/images/plush/coins.webp"
  def src("receipt", :light), do: ~p"/images/plush/receipt.webp"
  def src(_name, _variant), do: nil
end
