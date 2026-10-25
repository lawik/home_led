defmodule HomeLed.PruneNative do
  @moduledoc """
  A release step (see `mix.exs`) that drops native files the target can't or won't use.
  It runs after `:assemble`, before Nerves packs the release into the rootfs.

    * `bundlex/priv/shared`: bundlex's download cache for precompiled libraries
      (ffmpeg, opus, portaudio). Nothing loads from it at runtime. Each plugin carries its
      own copy under `priv/bundlex/nif/<url dir>`, found through the NIF's `$ORIGIN` rpath.
    * In each of those per-plugin directories, every file that is not in the `NEEDED`
      closure of that plugin's NIFs. The precompiled tarballs bring dev symlinks (copied
      as files), unrelated libraries (portaudio's brings libpython, glib, systemd, ...) and
      several names per library. The dynamic loader only looks up `NEEDED` sonames.
    * Shared objects built for another machine than the release's ERTS. emerge is a path
      dependency, so its `priv/native` is shared with host builds and also holds the host
      NIF, which fails Nerves' executable-format scrub.

  Uses `readelf` (binutils, which Nerves' own scrub needs too).
  """

  def run(%Mix.Release{path: path} = release) do
    lib = Path.join(path, "lib")
    machine = machine(hd(Path.wildcard(Path.join(path, "erts-*/bin/beam.smp"))))

    before = du(path)
    Enum.each(Path.wildcard(Path.join(lib, "bundlex-*/priv/shared")), &File.rm_rf!/1)

    for nif_dir <- Path.wildcard(Path.join(lib, "*/priv/bundlex/nif")),
        dep_dir <- Path.wildcard(Path.join(nif_dir, "http*")),
        File.dir?(dep_dir) do
      prune_dep_dir(nif_dir, dep_dir)
    end

    for file <- Path.wildcard(Path.join(lib, "**/*.so*")),
        File.regular?(file),
        (m = machine(file)) != nil and m != machine do
      Mix.shell().info("* prune: removing #{Path.relative_to(file, path)} (#{m})")
      File.rm!(file)
    end

    Mix.shell().info("* prune: release #{mb(before)} -> #{mb(du(path))}")
    release
  end

  # Keep the sonames reachable from the NIFs next to `dep_dir`, through libraries found in
  # `dep_dir`. Everything else in `dep_dir` goes.
  defp prune_dep_dir(nif_dir, dep_dir) do
    roots = Path.wildcard(Path.join(nif_dir, "*.so"))
    keep = closure(roots, dep_dir, MapSet.new())

    for name <- File.ls!(dep_dir), not MapSet.member?(keep, name) do
      File.rm_rf!(Path.join(dep_dir, name))
    end
  end

  defp closure([], _dir, seen), do: seen

  defp closure([file | rest], dir, seen) do
    new =
      for soname <- needed(file),
          not MapSet.member?(seen, soname),
          File.regular?(Path.join(dir, soname)),
          do: soname

    seen = Enum.reduce(new, seen, &MapSet.put(&2, &1))
    closure(rest ++ Enum.map(new, &Path.join(dir, &1)), dir, seen)
  end

  defp needed(file) do
    {out, 0} = System.cmd("readelf", ["-d", file])
    for [_, soname] <- Regex.scan(~r/\(NEEDED\)\s+Shared library: \[([^\]]+)\]/, out), do: soname
  end

  # e_machine of an ELF file, nil if it isn't one.
  defp machine(file) do
    case File.open(file, [:read, :binary], &IO.binread(&1, 20)) do
      {:ok, <<0x7F, "ELF", _::binary-size(14), m::little-16>>} -> m
      _ -> nil
    end
  end

  defp du(path) do
    {out, 0} = System.cmd("du", ["-sb", path])
    out |> String.split() |> hd() |> String.to_integer()
  end

  defp mb(bytes), do: "#{div(bytes, 1_000_000)} MB"
end
