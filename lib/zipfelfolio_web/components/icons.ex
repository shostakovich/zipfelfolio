defmodule ZipfelfolioWeb.Icons do
  @moduledoc """
  The Lucide icons of the app, compiled from the SVG files in `assets/vendor/lucide`
  (lucide-static, ISC licence). `<.icon name="…">` from setzkasten looks names up here first, then
  in the icons the library ships itself (`Setzkasten.Lucide`); an unknown name raises.

  To add an icon, copy `icons/<name>.svg` from lucide-static into the directory.
  """
  use Setzkasten.Icons, path: "assets/vendor/lucide"
end
