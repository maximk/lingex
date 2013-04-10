
defmodule Mix.Tasks.Lingex.Build do
	def run(_args) do
		Mix.shell.info "build.run() called"

		project = Mix.project
		opts = project[:lingex_opts]

		compile_path = project[:compile_path]
		files = Path.wildcard Path.join compile_path, "*"

		deps_path = project[:deps_path]
		files = Enum.reduce project[:deps], files, fn({name, _, _}, acc) ->
			dir = Path.join [deps_path,name,"ebin/*"]
			acc ++ Path.wildcard dir
		end

		Enum.each files, fn(f) ->
			IO.puts f
		end

		IO.inspect opts
	end
end

defmodule Mix.Tasks.Lingex.Image do
	def run(_Args) do
		Mix.shell.info "image.run() called"
	end
end

defmodule Mix.Tasks.Lingex.Build_image do
	def run(_Args) do
		Mix.shell.info "build_image.run() called"
	end
end
