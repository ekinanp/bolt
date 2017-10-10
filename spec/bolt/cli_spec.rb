require 'spec_helper'
require 'bolt_spec/files'
require 'bolt/cli'

describe "Bolt::CLI" do
  include BoltSpec::Files

  def stub_file(path)
    stat = double('stat', readable?: true, file?: true)

    allow(cli).to receive(:file_stat).with(path).and_return(stat)
  end

  def stub_non_existent_file(path)
    allow(cli).to receive(:file_stat).with(path).and_raise(
      Errno::ENOENT, "No such file or directory @ rb_file_s_stat - #{path}"
    )
  end

  def stub_unreadable_file(path)
    stat = double('stat', readable?: false, file?: true)

    allow(cli).to receive(:file_stat).with(path).and_return(stat)
  end

  def stub_directory(path)
    stat = double('stat', readable?: true, file?: false)

    allow(cli).to receive(:file_stat).with(path).and_return(stat)
  end

  def stub_config(file_content = nil, base = nil)
    file_content ||= {}
    base ||= {}
    config = Bolt::Config.new(**base)
    allow(config).to receive(:read_config_file).and_return(file_content)
    allow(Bolt::Config).to receive(:new).and_return(config)
  end

  context "without a config file" do
    before(:each) { stub_config }

    it "generates an error message if an unknown argument is given" do
      cli = Bolt::CLI.new(%w[command run --unknown])
      expect {
        cli.parse
      }.to raise_error(Bolt::CLIError, /Unknown argument '--unknown'/)
    end

    it "generates an error message if an unknown subcommand is given" do
      cli = Bolt::CLI.new(%w[-n bolt1 bolt2 command run whoami])
      expect {
        cli.parse
      }.to raise_error(Bolt::CLIError, /Expected subcommand 'bolt2' to be one of/)
    end

    it "generates an error message if an unknown action is given" do
      cli = Bolt::CLI.new(%w[-n bolt1 command oops whoami])
      expect {
        cli.parse
      }.to raise_error(Bolt::CLIError, /Expected action 'oops' to be one of/)
    end

    describe "help" do
      it "generates help when no arguments are specified" do
        cli = Bolt::CLI.new([])
        expect {
          expect {
            cli.parse
          }.to raise_error(Bolt::CLIExit)
        }.to output(/Usage: bolt/).to_stdout
      end

      it "accepts --help" do
        cli = Bolt::CLI.new(%w[--help])
        expect {
          expect {
            cli.parse
          }.to raise_error(Bolt::CLIExit)
        }.to output(/Usage: bolt/).to_stdout
      end
    end

    describe "version" do
      it "emits a version string" do
        cli = Bolt::CLI.new(%w[--version])
        expect {
          expect {
            cli.parse
          }.to raise_error(Bolt::CLIExit)
        }.to output(/\d+\.\d+\.\d+/).to_stdout
      end
    end

    describe "nodes" do
      it "accepts a single node" do
        cli = Bolt::CLI.new(%w[command run --nodes foo])
        expect(cli.parse).to include(nodes: ['foo'])
      end

      it "accepts multiple nodes" do
        cli = Bolt::CLI.new(%w[command run --nodes foo,bar])
        expect(cli.parse).to include(nodes: %w[foo bar])
      end

      it "accepts multiple nodes across multiple declarations" do
        cli = Bolt::CLI.new(%w[command run --nodes foo,bar --nodes bar,more,bars])
        expect(cli.parse).to include(nodes: %w[foo bar more bars])
      end

      it "reads from stdin when --nodes is '-'" do
        nodes = <<NODES
foo
bar
NODES
        cli = Bolt::CLI.new(%w[command run --nodes -])
        allow(STDIN).to receive(:read).and_return(nodes)
        result = cli.parse
        expect(result[:nodes]).to eq(%w[foo bar])
      end

      it "reads from a file when --nodes starts with @" do
        nodes = <<NODES
foo
bar
NODES
        with_tempfile_containing('nodes-args', nodes) do |file|
          cli = Bolt::CLI.new(%W[command run --nodes @#{file.path}])
          result = cli.parse
          expect(result[:nodes]).to eq(%w[foo bar])
        end
      end

      it "strips leading and trailing whitespace" do
        nodes = "  foo\nbar  \nbaz\nqux  "
        with_tempfile_containing('nodes-args', nodes) do |file|
          cli = Bolt::CLI.new(%W[command run --nodes @#{file.path}])
          result = cli.parse
          expect(result[:nodes]).to eq(%w[foo bar baz qux])
        end
      end

      it "accepts multiple nodes but is uniq" do
        cli = Bolt::CLI.new(%w[command run --nodes foo,bar,foo])
        expect(cli.parse).to include(nodes: %w[foo bar])
      end

      it "generates an error message if no nodes given" do
        cli = Bolt::CLI.new(%w[command run --nodes])
        expect {
          cli.parse
        }.to raise_error(Bolt::CLIError, /Option '--nodes' needs a parameter/)
      end

      it "generates an error message if nodes is omitted" do
        cli = Bolt::CLI.new(%w[command run])
        expect {
          cli.parse
        }.to raise_error(Bolt::CLIError, /Option '--nodes' must be specified/)
      end
    end

    describe "user" do
      it "accepts a user" do
        cli = Bolt::CLI.new(%w[command run --user root --nodes foo])
        expect(cli.parse).to include(user: 'root')
      end

      it "generates an error message if no user value is given" do
        cli = Bolt::CLI.new(%w[command run --nodes foo --user])
        expect {
          cli.parse
        }.to raise_error(Bolt::CLIError, /Option '--user' needs a parameter/)
      end
    end

    describe "password" do
      it "accepts a password" do
        cli = Bolt::CLI.new(%w[command run --password opensesame --nodes foo])
        expect(cli.parse).to include(password: 'opensesame')
      end

      it "prompts the user for password if not specified" do
        allow(STDIN).to receive(:noecho).and_return('opensesame')
        allow(STDOUT).to receive(:print).with('Please enter your password: ')
        allow(STDOUT).to receive(:puts)
        cli = Bolt::CLI.new(%w[command run --nodes foo --password])
        expect(cli.parse).to include(password: 'opensesame')
      end
    end

    describe "private-key" do
      it "accepts a private key" do
        cli = Bolt::CLI.new(%w[  command run
                                 --private-key ~/.ssh/google_compute_engine
                                 --nodes foo])
        expect(cli.parse).to include(key: '~/.ssh/google_compute_engine')
        expect(cli.config[:transports][:ssh][:key]).to eq('~/.ssh/google_compute_engine')
      end

      it "generates an error message if no key value is given" do
        cli = Bolt::CLI.new(%w[command run --nodes foo --private-key])
        expect {
          cli.parse
        }.to raise_error(Bolt::CLIError,
                         /Option '--private-key' needs a parameter/)
      end
    end

    describe "concurrency" do
      it "accepts a concurrency limit" do
        cli = Bolt::CLI.new(%w[command run --concurrency 10 --nodes foo])
        expect(cli.parse).to include(concurrency: 10)
      end

      it "defaults to 100" do
        cli = Bolt::CLI.new(%w[command run --nodes foo])
        cli.parse
        expect(cli.config[:concurrency]).to eq(100)
      end

      it "generates an error message if no concurrency value is given" do
        cli = Bolt::CLI.new(%w[command run --nodes foo --concurrency])
        expect {
          cli.parse
        }.to raise_error(Bolt::CLIError,
                         /Option '--concurrency' needs a parameter/)
      end
    end

    describe "log level" do
      it "is not sensitive to ordering of debug and verbose" do
        cli = Bolt::CLI.new(%w[command run --nodes foo --debug --verbose])
        cli.parse
        expect(cli.config[:log_level]).to eq(Logger::DEBUG)
      end
    end

    describe "insecure" do
      it "accepts `-k`" do
        cli = Bolt::CLI.new(%w[command run -k --nodes foo])
        cli.parse
        expect(cli.config[:transports][:ssh][:insecure]).to eq(true)
      end

      it "accepts `--insecure`" do
        cli = Bolt::CLI.new(%w[command run --insecure --nodes foo])
        cli.parse
        expect(cli.config[:transports][:ssh][:insecure]).to eq(true)
      end

      it "defaults to false" do
        cli = Bolt::CLI.new(%w[command run --nodes foo])
        cli.parse
        expect(cli.config[:transports][:ssh][:insecure]).to eq(false)
      end
    end

    describe "timeout" do
      it "accepts a specific timeout" do
        cli = Bolt::CLI.new(%w[command run --timeout 123 --nodes foo])
        expect(cli.parse).to include(timeout: 123)
      end

      it "generates an error message if no timeout value is given" do
        cli = Bolt::CLI.new(%w[command run --nodes foo --timeout])
        expect {
          cli.parse
        }.to raise_error(Bolt::CLIError,
                         /Option '--timeout' needs a parameter/)
      end
    end

    describe "modulepath" do
      it "accepts a modulepath directory" do
        cli = Bolt::CLI.new(%w[command run --modulepath ./modules --nodes foo])
        expect(cli.parse).to include(modulepath: ['./modules'])
      end

      it "generates an error message if no value is given" do
        cli = Bolt::CLI.new(%w[command run --nodes foo --modulepath])
        expect {
          cli.parse
        }.to raise_error(Bolt::CLIError,
                         /Option '--modulepath' needs a parameter/)
      end
    end

    describe "sudo" do
      it "defaults method to sudo" do
        cli = Bolt::CLI.new(%w[command run --nodes foo whoami --sudo])
        cli.parse
        expect(cli.config[:transports][:ssh][:sudo]).to eq('sudo')
      end

      it "rejects unsupported methods" do
        cli = Bolt::CLI.new(%w[command run --nodes foo whoami --sudo rm])
        expect { cli.parse }.to raise_error(Bolt::CLIError)
      end

      it "supports running as a user" do
        cli = Bolt::CLI.new(%w[command run --nodes foo whoami --run-as root])
        expect(cli.parse[:run_as]).to eq('root')
      end
    end

    describe "sudo-password" do
      it "accepts a password" do
        cli = Bolt::CLI.new(%w[command run --sudo-password opensez --nodes foo])
        expect(cli.parse).to include(sudo_password: 'opensez')
      end

      it "prompts the user for sudo-password if not specified" do
        allow(STDIN).to receive(:noecho).and_return('opensez')
        pw_prompt = 'Please enter your privilege escalation password: '
        allow(STDOUT).to receive(:print).with(pw_prompt)
        allow(STDOUT).to receive(:puts)
        cli = Bolt::CLI.new(%w[command run --nodes foo --sudo-password])
        expect(cli.parse).to include(sudo_password: 'opensez')
      end
    end

    describe "transport" do
      it "defaults to 'ssh'" do
        cli = Bolt::CLI.new(%w[command run --nodes foo whoami])
        cli.parse
        expect(cli.config[:transport]).to eq('ssh')
      end

      it "accepts ssh" do
        cli = Bolt::CLI.new(%w[command run --transport ssh --nodes foo id])
        expect(cli.parse[:transport]).to eq('ssh')
      end

      it "accepts winrm" do
        cli = Bolt::CLI.new(%w[command run --transport winrm --nodes foo id])
        expect(cli.parse[:transport]).to eq('winrm')
      end

      it "accepts pcp" do
        cli = Bolt::CLI.new(%w[command run --transport pcp --nodes foo id])
        expect(cli.parse[:transport]).to eq('pcp')
      end

      it "rejects invalid transports" do
        cli = Bolt::CLI.new(%w[command run --transport holodeck --nodes foo id])
        expect {
          cli.parse
        }.to raise_error(OptionParser::InvalidArgument,
                         /invalid argument: --transport holodeck/)
      end
    end

    describe "command" do
      it "interprets whoami as the command" do
        cli = Bolt::CLI.new(%w[command run --nodes foo whoami])
        expect(cli.parse[:object]).to eq('whoami')
      end
    end

    it "distinguishes subcommands" do
      cli = Bolt::CLI.new(%w[script run --nodes foo])
      expect(cli.parse).to include(mode: 'script')
    end

    describe "file" do
      describe "upload" do
        it "uploads a file" do
          cli = Bolt::CLI.new(%w[file upload ./src /path/dest --nodes foo])
          result = cli.parse
          expect(result[:object]).to eq('./src')
          expect(result[:leftovers].first).to eq('/path/dest')
        end
      end
    end

    describe "handling parameters" do
      it "returns {} if none are specified" do
        cli = Bolt::CLI.new(%w[plan run my::plan --modulepath .])
        result = cli.parse
        expect(result[:task_options]).to eq({})
      end

      it "reads params on the command line" do
        cli = Bolt::CLI.new(%w[plan run my::plan kj=2hv iuhg=iube 2whf=lcv
                               --modulepath .])
        result = cli.parse
        expect(result[:task_options]).to eq('kj'   => '2hv',
                                            'iuhg' => 'iube',
                                            '2whf' => 'lcv')
      end

      it "reads params in json with the params flag" do
        json_args = '{"kj":"2hv","iuhg":"iube","2whf":"lcv"}'
        cli = Bolt::CLI.new(['plan', 'run', 'my::plan', '--params', json_args,
                             '--modulepath', '.'])
        result = cli.parse
        expect(result[:task_options]).to eq('kj'   => '2hv',
                                            'iuhg' => 'iube',
                                            '2whf' => 'lcv')
      end

      it "raises a cli error when json parsing fails" do
        json_args = '{"k'
        cli = Bolt::CLI.new(['plan', 'run', 'my::plan', '--params', json_args])
        expect {
          cli.parse
        }.to raise_error(Bolt::CLIError, /unexpected token/)
      end

      it "raises a cli error when specifying params both ways" do
        cli = Bolt::CLI.new(%w[plan run my::plan --params {"a":"b"} c=d
                               --modulepath .])
        expect {
          cli.parse
        }.to raise_error(Bolt::CLIError, /not both/)
      end

      it "reads json from a file when --params starts with @" do
        json_args = '{"kj":"2hv","iuhg":"iube","2whf":"lcv"}'
        with_tempfile_containing('json-args', json_args) do |file|
          cli = Bolt::CLI.new(%W[plan run my::plan --params @#{file.path}
                                 --modulepath .])
          result = cli.parse
          expect(result[:task_options]).to eq('kj'   => '2hv',
                                              'iuhg' => 'iube',
                                              '2whf' => 'lcv')
        end
      end

      it "raises a cli error when reading the params file fails" do
        Dir.mktmpdir do |dir|
          cli = Bolt::CLI.new(%W[plan run my::plan --params @#{dir}/nope
                                 --modulepath .])
          expect {
            cli.parse
          }.to raise_error(Bolt::CLIError, /No such file/)
        end
      end

      it "reads json from stdin when --params is just '-'" do
        json_args = '{"kj":"2hv","iuhg":"iube","2whf":"lcv"}'
        cli = Bolt::CLI.new(%w[plan run my::plan --params - --modulepath .])
        allow(STDIN).to receive(:read).and_return(json_args)
        result = cli.parse
        expect(result[:task_options]).to eq('kj'   => '2hv',
                                            'iuhg' => 'iube',
                                            '2whf' => 'lcv')
      end
    end

    describe 'task' do
      it "errors without a task" do
        cli = Bolt::CLI.new(%w[task run -n example.com --modulepath .])
        expect {
          cli.parse
        }.to raise_error(Bolt::CLIError, /Must specify/)
      end

      it "errors if task is a parameter" do
        cli = Bolt::CLI.new(%w[task run -n example.com --modulepath . p1=v1])
        expect {
          cli.parse
        }.to raise_error(Bolt::CLIError, /Invalid task/)
      end
    end

    describe 'plan' do
      it "errors without a plan" do
        cli = Bolt::CLI.new(%w[plan run -n example.com --modulepath .])
        expect {
          cli.parse
        }.to raise_error(Bolt::CLIError, /Must specify/)
      end

      it "errors if plan is a parameter" do
        cli = Bolt::CLI.new(%w[plan run -n example.com --modulepath . p1=v1])
        expect {
          cli.parse
        }.to raise_error(Bolt::CLIError, /Invalid plan/)
      end
    end

    describe "execute" do
      let(:executor) { double('executor') }
      let(:cli) { Bolt::CLI.new({}) }
      let(:node_names) { ['foo'] }
      let(:nodes) { [double('node', host: 'foo')] }

      before :each do
        allow(Bolt::Executor).to receive(:new).and_return(executor)
        allow(executor).to receive(:from_uris).and_return(nodes)

        @output = StringIO.new
        outputter = Bolt::Outputter::JSON.new(@output)

        allow(cli).to receive(:outputter).and_return(outputter)
      end

      it "executes the 'whoami' command" do
        expect(executor)
          .to receive(:run_command)
          .with(nodes, 'whoami')
          .and_return({})

        options = {
          nodes: node_names,
          mode: 'command',
          action: 'run',
          object: 'whoami'
        }
        cli.execute(options)
        expect(JSON.parse(@output.string)).to be
      end

      describe "when running a script" do
        let(:script) { 'bar.sh' }
        let(:options) {
          { nodes: node_names, mode: 'script', action: 'run', object: script,
            leftovers: [] }
        }

        it "runs a script" do
          stub_file(script)

          expect(executor)
            .to receive(:run_script)
            .with(nodes, script, [])
            .and_return({})

          cli.execute(options)
          expect(JSON.parse(@output.string)).to be
        end

        it "errors for non-existent scripts" do
          stub_non_existent_file(script)

          expect { cli.execute(options) }.to raise_error(
            Bolt::CLIError, /The script '#{script}' does not exist/
          )
          expect(JSON.parse(@output.string)).to be
        end

        it "errors for unreadable scripts" do
          stub_unreadable_file(script)

          expect { cli.execute(options) }.to raise_error(
            Bolt::CLIError, /The script '#{script}' is unreadable/
          )
          expect(JSON.parse(@output.string)).to be
        end

        it "errors for scripts that aren't files" do
          stub_directory(script)

          expect { cli.execute(options) }.to raise_error(
            Bolt::CLIError, /The script '#{script}' is not a file/
          )
          expect(JSON.parse(@output.string)).to be
        end
      end

      it "runs a task given a name" do
        task_name = 'sample::echo'
        task_params = { 'message' => 'hi' }
        input_method = 'both'

        expect(executor)
          .to receive(:run_task)
          .with(
            nodes,
            %r{modules/sample/tasks/echo.sh$}, input_method, task_params
          ).and_return({})

        options = {
          nodes: node_names,
          mode: 'task',
          action: 'run',
          object: task_name,
          task_options: task_params
        }
        cli.config.modulepath = [File.join(__FILE__, '../../fixtures/modules')]
        cli.execute(options)
        expect(JSON.parse(@output.string)).to be
      end

      it "runs a plan given a name" do
        plan_name = 'sample::single_task'
        plan_params = { 'nodes' => nodes.join(',') }
        input_method = 'both'

        expect(executor)
          .to receive(:run_task)
          .with(
            nodes,
            %r{modules/sample/tasks/echo.sh$}, input_method, 'message' => 'hi there'
          ).and_return({})

        options = {
          nodes: node_names,
          mode: 'plan',
          action: 'run',
          object: plan_name,
          task_options: plan_params
        }
        cli.config.modulepath = [File.join(__FILE__, '../../fixtures/modules')]
        cli.execute(options)
        expect(@output.string).to eq("\"ExecutionResult({})\"\n")
      end

      it "errors for non-existent modules" do
        task_name = 'dne::task1'
        task_params = { 'message' => 'hi' }

        options = {
          nodes: node_names,
          mode: 'task',
          action: 'run',
          object: task_name,
          task_options: task_params
        }
        cli.config.modulepath = [File.join(__FILE__, '../../fixtures/modules')]
        expect { cli.execute(options) }.to raise_error(
          Bolt::CLIError, /Could not find module/
        )
        expect(JSON.parse(@output.string)).to be
      end

      it "errors for non-existent tasks" do
        task_name = 'sample::dne'
        task_params = { 'message' => 'hi' }

        options = {
          nodes: node_names,
          mode: 'task',
          action: 'run',
          object: task_name,
          task_options: task_params
        }
        cli.config.modulepath = [File.join(__FILE__, '../../fixtures/modules')]
        expect { cli.execute(options) }.to raise_error(
          Bolt::CLIError,
          /Could not find task '#{task_name}' in module 'sample'/
        )
        expect(JSON.parse(@output.string)).to be
      end

      it "runs an init task given a module name" do
        task_name = 'sample'
        task_params = { 'message' => 'hi' }
        input_method = 'both'

        expect(executor)
          .to receive(:run_task)
          .with(
            nodes,
            %r{modules/sample/tasks/init.sh$}, input_method, task_params
          ).and_return({})

        options = {
          nodes: node_names,
          mode: 'task',
          action: 'run',
          object: task_name,
          task_options: task_params
        }
        cli.config.modulepath = [File.join(__FILE__, '../../fixtures/modules')]
        cli.execute(options)
        expect(JSON.parse(@output.string)).to be
      end

      it "runs a task passing input on stdin" do
        task_name = 'sample::stdin'
        task_params = { 'message' => 'hi' }
        input_method = 'stdin'

        expect(executor)
          .to receive(:run_task)
          .with(nodes,
                %r{modules/sample/tasks/stdin.sh$}, input_method, task_params)
          .and_return({})

        options = {
          nodes: node_names,
          mode: 'task',
          action: 'run',
          object: task_name,
          task_options: task_params
        }
        cli.config.modulepath = [File.join(__FILE__, '../../fixtures/modules')]
        cli.execute(options)
        expect(JSON.parse(@output.string)).to be
      end

      it "runs a powershell task passing input on stdin" do
        task_name = 'sample::winstdin'
        task_params = { 'message' => 'hi' }
        input_method = 'stdin'

        expect(executor)
          .to receive(:run_task)
          .with(nodes,
                %r{modules/sample/tasks/winstdin.ps1$}, input_method, task_params)
          .and_return({})

        options = {
          nodes: node_names,
          mode: 'task',
          action: 'run',
          object: task_name,
          task_options: task_params
        }
        cli.config.modulepath = [File.join(__FILE__, '../../fixtures/modules')]
        cli.execute(options)
        expect(JSON.parse(@output.string)).to be
      end

      describe "file uploading" do
        let(:source) { '/path/to/local' }
        let(:dest) { '/path/to/remote' }
        let(:options) {
          {
            nodes: node_names,
            mode: 'file',
            action: 'upload',
            object: source,
            leftovers: [dest]
          }
        }

        it "uploads a file via scp" do
          stub_file(source)

          expect(executor)
            .to receive(:file_upload)
            .with(nodes, source, dest)
            .and_return({})

          cli.execute(options)
          expect(JSON.parse(@output.string)).to be
        end

        it "raises if the local file doesn't exist" do
          stub_non_existent_file(source)

          expect { cli.execute(options) }.to raise_error(
            Bolt::CLIError, /The source file '#{source}' does not exist/
          )
          expect(JSON.parse(@output.string)).to be
        end

        it "errors if the local file is unreadable" do
          stub_unreadable_file(source)

          expect { cli.execute(options) }.to raise_error(
            Bolt::CLIError, /The source file '#{source}' is unreadable/
          )
          expect(JSON.parse(@output.string)).to be
        end

        it "errors if the local file is a directory" do
          stub_directory(source)

          expect { cli.execute(options) }.to raise_error(
            Bolt::CLIError, /The source file '#{source}' is not a file/
          )
          expect(JSON.parse(@output.string)).to be
        end
      end
    end
  end

  describe 'configfile' do
    let(:configdir) { File.join(__dir__, '..', 'fixtures', 'configs') }
    let(:complete_config) do
      { 'modulepath' => "/foo/bar#{File::PATH_SEPARATOR}/baz/qux",
        'concurrency' => 14,
        'format' => 'json',
        'ssh' => {
          "private-key" => '/bar/foo',
          "insecure" => true
        } }
    end

    it 'reads modulepath' do
      with_tempfile_containing('conf', YAML.dump(complete_config)) do |conf|
        cli = Bolt::CLI.new(%W[command run --configfile #{conf.path} --nodes foo --insecure])
        cli.parse
        expect(cli.config[:modulepath]).to eq(['/foo/bar', '/baz/qux'])
      end
    end

    it 'reads concurrency' do
      with_tempfile_containing('conf', YAML.dump(complete_config)) do |conf|
        cli = Bolt::CLI.new(%W[command run --configfile #{conf.path} --nodes foo --insecure])
        cli.parse
        expect(cli.config[:concurrency]).to eq(14)
      end
    end

    it 'reads format' do
      with_tempfile_containing('conf', YAML.dump(complete_config)) do |conf|
        cli = Bolt::CLI.new(%W[command run --configfile #{conf.path} --nodes foo --insecure])
        cli.parse
        expect(cli.config[:format]).to eq('json')
      end
    end

    it 'reads private-key for ssh' do
      with_tempfile_containing('conf', YAML.dump(complete_config)) do |conf|
        cli = Bolt::CLI.new(%W[command run --configfile #{conf.path} --nodes foo --insecure])
        cli.parse
        expect(cli.config[:transports][:ssh][:key]).to eq('/bar/foo')
      end
    end

    it 'reads insecure for ssh' do
      with_tempfile_containing('conf', YAML.dump(complete_config)) do |conf|
        cli = Bolt::CLI.new(%W[command run --configfile #{conf.path} --nodes foo --insecure])
        cli.parse
        expect(cli.config[:transports][:ssh][:insecure]).to eq(true)
      end
    end

    it 'CLI flags override config' do
      with_tempfile_containing('conf', YAML.dump(complete_config)) do |conf|
        cli = Bolt::CLI.new(%W[command run --configfile #{conf.path} --nodes foo --concurrency 12])
        cli.parse
        expect(cli.config.concurrency).to eq(12)
      end
    end

    it 'raises an error if a config file is specified and invalid' do
      cli = Bolt::CLI.new(%W[command run --configfile #{File.join(configdir, 'invalid.yml')} --nodes foo --insecure])
      expect {
        cli.parse
      }.to raise_error(Bolt::CLIError, /Could not parse/)
    end
  end
end
