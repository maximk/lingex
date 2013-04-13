defmodule Mix.Tasks.Lingex do
	def start_build(project, files, opts) do
		case check_opts opts do
		{copts, bopts} ->
			start_build project, files, copts, bopts;
		error ->
			{:error,error}
		end
	end

	defp start_build(project, files, copts, bopts) do
		Mix.shell.info "Compressing #{length files} file(s)"
		any_name = 'tmptmp.zip'
		zip_files = Enum.map files, fn file -> Kernel.binary_to_list file end
		{:ok, {_, zip_data}} = :zip.zip(any_name, zip_files, [:memory])

		Mix.shell.info "Uploading project archive [#{size zip_data} byte(s)]"

		:ok = call_build_service :put, '/projects/#{project}', [],
									{'application/zip', zip_data}, copts
		Mix.shell.info "Project archive uploaded"

		apps = lc {:import_lib, app} inlist bopts, do: app
		app_list = Enum.map_join apps, ",", fn(x) -> "\"#{x}\"" end

		if bopts[:elixir_lib] do
			req_body = "{\"import_lib\":[#{app_list}],\"elixir_lib\":true}"
		else
			Mix.shell.info "Warning: elixir_lib:true option missing"
			req_body = "{\"import_lib\":[#{app_list}]}"
		end

		Mix.shell.info "Build started for #{project}"
		{:ok, banner} = call_build_service :post, "/build/#{project}", [],
									{'application/json', req_body}, copts
		Mix.shell.info "LBS: #{banner}"

		:ok
	end

	defp check_opts(opts) do
		check_opts opts, [], []
	end

	defp check_opts([], copts, bopts) do
		{copts, bopts}
	end
	defp check_opts([{:build_host, _host} =opt|opts], copts, bopts) do
		check_opts opts, [opt|copts], bopts
	end
	defp check_opts([{:username, _name} =opt|opts], copts, bopts) do
		check_opts opts, [opt|copts], bopts
	end
	defp check_opts([{:password, _pwd} =opt|opts], copts, bopts) do
		check_opts opts, [opt|copts], bopts
	end
	defp check_opts([{:import, _pat} =opt|opts], copts, bopts) do
		check_opts opts, copts, [opt|bopts]
	end
	defp check_opts([{:import_lib, _lib} =opt|opts], copts, bopts) do
		check_opts opts, copts, [opt|bopts]
	end
	defp check_opts([{:elixir_lib, _} =opt|opts], copts, bopts) do
		check_opts opts, copts, [opt|bopts]
	end
	defp check_opts([opt|_opts], _copts, _bopts) do
		Mix.shell.error "invalid option: #{inspect opt}"
		:invalid
	end

	def retrieve_image(project, copts) do
		case call_build_service :get, "/build/#{project}/image", [],
											:none, copts do
		{:ok, resp_body} ->
			image_file = "vmling"
			image_bin = list_to_binary resp_body
			Mix.shell.info "Saving image to #{image_file} [#{size image_bin} byte(s)]"
			File.write! image_file, image_bin
			Mix.shell.info "LBS: image saved to #{image_file}"

		_other ->
			Mix.shell.error "LBS: image is not (yet?) available"
		end
	end

	def get_build_status(project, copts) do
		case call_build_service :get, "/build/#{project}/status", [],
											:none, copts do
		{:ok,'0'} ->
			:ok

		{:ok,'1'} ->
			receive do
			after 3000 ->
				:ok
			end
			get_build_status project, copts

		{:ok,'99'} ->
			:failed
		end
	end

	defp call_build_service(method, slug, hdrs, body, copts) do

		:ssl.start
		:inets.start

		build_host = copts[:build_host]
		user_name = copts[:username]
		password = copts[:password]

		encoded = :base64.encode_to_string '#{user_name}:#{password}'
		auth_header = {'Authorization', 'Basic #{encoded}'}
		headers = [auth_header] ++ hdrs

		location = 'https://#{build_host}/1#{slug}'
		request = case body do
		:none ->
			{location, headers}
		{ctype, body_data} ->
			{location, headers, ctype, body_data}
		end

		case :httpc.request method, request, [{:timeout, :infinity}], [] do
		{:ok, {{_, 200, _}, _, resp_body}} ->
			{:ok, resp_body}
		{:ok, {{_, 204, _}, _, _}} ->
			:ok
		{:ok, {{_, 403, _}, _, _}} ->
			:forbidden
		{:ok, {{_, 404, _}, _, _}} ->
			:not_found
		other ->
			Mix.shell.error "LBS: error: #{inspect other}"
		end
	end

	def collect_files(config, opts) do
		compile_path = config[:compile_path]

		files = Path.wildcard Path.join compile_path, "*"

		deps_path = config[:deps_path]
		files = Enum.reduce config[:deps], files, fn(x, acc) -> 
		  collect_dep_files(deps_path, x, acc) 
		end

		misc_paths = lc {:import, path} inlist opts, do: path
		Enum.reduce misc_paths, files, fn(path, acc) ->
			acc ++ Path.wildcard path
		end
	end

  defp collect_dep_files(_deps_path, {:lingex, _}, acc), do: acc
  defp collect_dep_files(_deps_path, {:lingex, _, _}, acc), do: acc
  defp collect_dep_files(deps_path, {name, _, opts}, acc) do
      collect_dep_files(deps_path, {name, opts}, acc)
  end
  defp collect_dep_files(deps_path, {name, _}, acc) do
  		dir = Path.join [deps_path,name,"ebin/*"]
  		acc ++ Path.wildcard dir
  end

end

defmodule Mix.Tasks.Lingex.Build do

	@moduledoc """
The task uploads *.beam files of the project to the Erlang on Xen Build Service
and initiates the build process.
"""

	def run(_args) do
		config = Mix.project
		opts = config[:lingex_opts]

		files = Mix.Tasks.Lingex.collect_files config, opts

		project = config[:app]	
		Mix.Tasks.Lingex.start_build project, files, opts
	end
end

defmodule Mix.Tasks.Lingex.Image do

	@moduledoc """
The task retrieves the built Xen image from the Erlang on Xen Build Service.
"""

	def run(_args) do
		config = Mix.project
		opts = config[:lingex_opts]
		project = config[:app]
		Mix.Tasks.Lingex.retrieve_image project, opts
	end
end

defmodule Mix.Tasks.Lingex.Build_image do

	@moduledoc """
The task builds a Xen image for the project using the Erlang on Xen Build
Service.
"""

	def run(_args) do
		config = Mix.project
		opts = config[:lingex_opts]

		files = Mix.Tasks.Lingex.collect_files config, opts

		project = config[:app]	
		Mix.Tasks.Lingex.start_build project, files, opts

		case Mix.Tasks.Lingex.get_build_status project, opts do
		:ok ->
			Mix.Tasks.Lingex.retrieve_image project, opts

		:failed ->
			Mix.shell.error "LBS: **** build failed ****"
		end
	end
end
