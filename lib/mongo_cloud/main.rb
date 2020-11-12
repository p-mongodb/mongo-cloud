autoload :Zlib, 'zlib'
autoload :JSON, 'json'
autoload :YAML, 'yaml'
require 'time'
require 'awesome_print'
require 'daybreak'
require 'optparse'
require 'mongo_cloud'

module MongoCloud
  class Main
    LOG_NAME_MAP = {
      'mongod' => 'mongodb',
      'mongos' => 'mongos',
      'mongod-audit' => 'mongodb-audit-log',
      'mongos-audit' => 'mongos-audit-log',
    }.freeze

    def initialize
      @global_options = {}
      @cache = Daybreak::DB.new(File.expand_path('~/.mongo-cloud.cache'))
      # TODO record & check version of cache, remove caches of older versions
    end

    attr_reader :global_options
    attr_reader :cache

    def run(argv = ARGV)
      argv = argv.dup

      parser = OptionParser.new do |opts|
        configure_global_options(opts)
      end.order!(argv)

      command = argv.shift

      if command.nil?
        usage('no command given')
      end

      commands = %w(
        org project cluster whitelist dbuser log proc
        log-collection-job
      )
      if commands.include?(command)
        send(command.gsub('-', '_'), argv)
      else
        usage("unknown command: #{command}")
      end
    ensure
      cache.close
    end

    def usage(msg)
      raise msg
    end

    def org(argv)
      options = {}
      parser = OptionParser.new do |opts|
        configure_global_options(opts)
      end.order!(argv)

      client = Client.new(**global_options.slice(*%i(user password)))

      case argv.shift
      when 'list'
        ap client.list_orgs
      when 'show'
        ap client.get_org(argv.shift)
      else
        raise 'bad usage'
      end
    end

    def project(argv)
      options = {}
      parser = OptionParser.new do |opts|
        configure_global_options(opts)
      end.order!(argv)

      client = Client.new(**global_options.slice(*%i(user password)))

      if argv.empty?
        if options[:project_id]
          argv = %w(show)
        else
          argv = %w(list)
        end
      end

      case argv.shift
      when 'list'
        infos = client.list_projects
        cache_id('project', infos, 'name')
        ap infos
      when 'show'
        ap client.get_project(argv.shift)
      when 'create'
        parser = OptionParser.new do |opts|
          opts.on('--org=ORG', String, 'Organization ID') do |v|
            options[:org_id] = v
          end

          opts.on('--name=NAME', String, 'Project name to create') do |v|
            options[:name] = v
          end
        end.order!(argv)

        client.create_project(
          org_id: options.fetch(:org_id),
          name: options.fetch(:name),
        )
      else
        raise 'bad usage'
      end
    end

    def cluster(argv)
      options = {
        project_id: global_options.delete(:project_id),
        cluster_id: global_options.delete(:cluster_id),
      }
      parser = OptionParser.new do |opts|
        configure_global_options(opts)

        opts.on('-p', '--project=PROJECT', String, 'Project ID') do |v|
          options[:project_id] = v
        end
      end.order!(argv)

      resolve_project_and_cluster(options)

      if argv.empty?
        if options[:cluster_id]
          argv = %w(show)
        elsif options[:project_id]
          argv = %w(list)
        end
      end

      case argv.shift
      when 'list'
        infos = client.list_clusters(project_id: options[:project_id])
        cache_id('cluster', infos, 'name')
        cache_association('cluster', 'project', infos, 'project_id')
        ap infos
      when 'show'
        name = argv.shift || options[:cluster_id]
        name = cache['cluster:id:name'].fetch(name, name)
        ap client.get_cluster(project_id: options[:project_id], name: name)
      when 'show-internal'
        name = argv.shift || options[:cluster_id]
        name = cache['cluster:id:name'].fetch(name, name)
        ap client.get_cluster_internal(project_id: options[:project_id], name: name)
      when 'log'
        puts client.get_cluster_log(project_id: options[:project_id],
          hostname: argv.shift, name: argv.shift&.to_sym || :mongod, decompress: true)
      when 'create'
        parser = OptionParser.new do |opts|
          opts.on('--name=NAME', String, 'Project name to create') do |v|
            options[:name] = v
          end

          opts.on('--config=CONFIG', String, 'Project configuration in YAML or JSON format') do |v|
            if v.strip.start_with?('?')
              v = JSON.load(v)
            else
              v = YAML.load(v)
            end
            options[:config] = v
          end
        end.order!(argv)

        client.create_cluster(project_id: options[:project_id],
          name: options.fetch(:name), **(options[:config] || {}),
        )
      when 'test-failover'
        name = argv.shift || options[:cluster_id]
        name = cache['cluster:id:name'].fetch(name, name)
        client.failover_cluster(project_id: options[:project_id], name: name)
      when 'reboot'
        name = argv.shift || options[:cluster_id]
        name = cache['cluster:id:name'].fetch(name, name)
        client.reboot_cluster(project_id: options[:project_id], name: name)
      when 'replica-set-hardware'
        name = argv.shift || options[:cluster_id]
        name = cache['cluster:id:name'].fetch(name, name)
        ap client.get_cluster_replica_set_hardware(project_id: options[:project_id], name: name)
      when 'delete'
        parser = OptionParser.new do |opts|
          opts.on('--cluster-id=CLUSTER', String, 'Cluster ID') do |v|
            options[:cluster_id] = v
          end
        end.order!(argv)

        name = argv.shift || options[:cluster_id]
        name = cache['cluster:id:name'].fetch(name, name)
        client.delete_cluster(project_id: options[:project_id], name: name)
      when 'delete-all'
        client.list_clusters(project_id: options[:project_id]).each do |info|
          client.delete_cluster(project_id: options[:project_id], name: info['name'])
        end
      else
        raise 'bad usage'
      end
    end

    def whitelist(argv)
      options = {
        project_id: global_options.delete(:project_id),
      }
      parser = OptionParser.new do |opts|
        configure_global_options(opts)

        opts.on('-p', '--project=PROJECT', String, 'Project ID') do |v|
          options[:project_id] = v
        end
      end.parse!(argv)

      client = Client.new(**global_options.slice(*%i(user password)))

      case argv.shift
      when 'list'
        ap client.list_whitelist_entries(project_id: options[:project_id])
      when 'show'
        ap client.get_whitelist_entry(project_id: options[:project_id], name: argv.shift)
      when 'add'
        params = {
          project_id: options[:project_id],
        }
        target = argv.shift
        if target =~ /\A\d+\.\d+\.\d+\.\d+\z/
          params[:ip_address] = target
        end
        ap client.create_whitelist_entry(**params)
      else
        raise 'bad usage'
      end
    end

    def dbuser(argv)
      options = {
        project_id: global_options.delete(:project_id),
      }
      parser = OptionParser.new do |opts|
        configure_global_options(opts)

        opts.on('-p', '--project=PROJECT', String, 'Project ID') do |v|
          options[:project_id] = v
        end
      end.parse!(argv)

      client = Client.new(**global_options.slice(*%i(user password)))

      if argv.empty?
        argv = %w(list)
      end

      case argv.shift
      when 'list'
        ap client.list_db_users(project_id: options[:project_id])
      when 'show'
        ap client.show_whitelist_entry(project_id: options[:project_id], name: argv.shift)
      when 'create'
        params = {
          project_id: options[:project_id],
          username: argv.shift,
          password: argv.shift,
        }
        ap client.create_db_user(**params)
      else
        raise 'bad usage'
      end
    end

    def log(argv)
      options = {
        project_id: global_options.delete(:project_id),
        cluster_id: global_options.delete(:cluster_id),
      }
      parser = OptionParser.new do |opts|
        configure_global_options(opts)

        opts.on('-p', '--project=PROJECT', String, 'Project ID') do |v|
          options[:project_id] = v
        end
        opts.on('-f', '--file=FILE', String, 'Log file to retrieve') do |v|
          options[:file_name] = v
        end
        opts.on('-t', '--host=HOST', String, 'Host id or hostname to retrieve logs from') do |v|
          options[:host] = v
        end
        opts.on('--start=START-TIME', String, 'Start time') do |v|
          options[:start_time] = Time.parse(v)
        end
        opts.on('--end=START-TIME', String, 'End time') do |v|
          options[:end_time] = Time.parse(v)
        end
        opts.on('-a', '--all', 'Retrieve the complete log') do |v|
          options[:all] = true
        end
        opts.on('-o', '--out=PATH', String, 'Write log to PATH') do |v|
          options[:out_path] = v
        end
        opts.on('-z', '--compress', 'Keep the log compressed') do |v|
          options[:compress] = true
        end
      end.parse!(argv)

      if options[:all]
        if options[:start_time]
          raise "--start cannot be used with --all"
        end
        if options[:end_time]
          raise "--end cannot be used with --all"
        end
      end

      if argv.empty?
        if options[:file_name] || options[:host]
          argv = %w(show)
        else
          argv = %w(list)
        end
      end

      case argv.shift
      when 'list'
        project_id = get_project_id(options)
        name = options[:cluster_id]
        name = cache['cluster:id:name'].fetch(name, name)
        info = client.get_cluster(project_id: project_id, name: name)
        #require'byebug';byebug
        logs = %w(mongod mongod-audit)
        if info['cluster_type'] == 'SHARDED'
          logs += %w(mongos mongos-audit)
        end
        ap logs
      when 'show'
        project_id = get_project_id(options)
        host_id = options[:host]
        hostname = cache['proc:id:hostname'].fetch(host_id, host_id)
        unless hostname
          raise "Hostname is required"
        end
        log_name = options[:file_name] || 'mongod'
        log = if log_name == 'ftdc'
          unless options[:out_path]
            raise "FTDC logs are returned as a compressed tarball, -o option is required or use `-o -` to write to standard output"
          end
          cluster_name = options[:cluster_id]
          cluster_name = cache['cluster:id:name'].fetch(cluster_name, cluster_name)
          get_ftdc_log(project_id: project_id, cluster_name: cluster_name)
        else
          get_process_log(project_id: project_id, hostname: hostname,
            name: log_name, start_time: options[:start_time], end_time: options[:end_time],
            all: options[:all])
        end
        if options[:out_path] && options[:out_path] != '-'
          File.open(options[:out_path], 'w') do |f|
            f << log
          end
        else
          puts log
        end
      else
        raise 'bad usage'
      end
    end

    def proc(argv)
      options = {
        project_id: global_options.delete(:project_id),
        cluster_id: global_options.delete(:cluster_id),
      }
      parser = OptionParser.new do |opts|
        configure_global_options(opts)

        opts.on('-p', '--project=PROJECT', String, 'Project ID') do |v|
          options[:project_id] = v
        end
        opts.on('--granularity=GRANULARITY', String, 'Measurements granularity') do |v|
          options[:granularity] = v.upcase
        end
        opts.on('--period=PERIOD', String, 'Measurements period') do |v|
          options[:period] = v.upcase
        end
        opts.on('--start=START-TIME', String, 'Start time') do |v|
          options[:start_time] = Time.parse(v)
        end
      end.parse!(argv)

      client = Client.new(**global_options.slice(*%i(user password)))

      if argv.empty?
        argv = %w(list)
      end

      case argv.shift
      when 'list'
        project_id = options[:project_id] || begin
          if options[:cluster_id]
            cache["cluster-project"]&.[](options[:cluster_id])
          end
        end
        unless project_id
          raise "Project id is required"
        end
        infos = client.list_processes(project_id: project_id)
        cache_id('proc', infos, 'hostname')
        ap infos
      when 'measurements'
        ap client.get_process_measurements(project_id: options[:project_id],
          granularity: options[:granularity], period: options[:period],
          process_id: argv.shift)
      else
        raise 'bad usage'
      end
    end

    def log_collection_job(argv)
      options = {
        project_id: global_options.delete(:project_id),
        cluster_id: global_options.delete(:cluster_id),
      }

      parser = OptionParser.new do |opts|
        configure_global_options(opts)

        opts.on('-p', '--project=PROJECT', String, 'Project ID') do |v|
          options[:project_id] = v
        end
        opts.on('--resource-type=TYPE', String, 'Resource type') do |v|
          options[:resource_type] = v
        end
        opts.on('--resource-name=NAME', String, 'Resource name') do |v|
          options[:resource_name] = v
        end
        opts.on('--size=SIZE', String, 'Size per log file in bytes') do |v|
          options[:file_size] = v.to_i
        end
        opts.on('--log-types=TYPES', String, 'Comma-separated log types') do |v|
          options[:log_types] = v.split(',')
        end
      end.parse!(argv)

      resolve_project_and_cluster(options)

      if argv.empty?
        argv = %w(list)
      end

      case argv.shift
      when 'list'
        ap client.list_log_collection_jobs(project_id: options[:project_id])
      when 'create'
        ap client.create_log_collection_job(
          project_id: options[:project_id],
          cluster_name: resolve_cluster_name(options[:cluster_id]),
          resource_type: options[:resource_type],
          resource_name: options[:resource_name],
          file_size: options[:file_size] || 100_000_000,
          log_types: options[:log_types],
        )
      else
        raise 'bad usage'
      end
    end

    private

    def configure_global_options(opts)
      opts.on('-U', '--user=USER', String, 'API username (aka public key)') do |v|
        global_options[:user] = v
      end
      opts.on('-P', '--password=PASSWORD', String, 'API password (aka private key)') do |v|
        global_options[:password] = v
      end
      opts.on('-p', '--project=PROJECT', String, 'Project ID') do |v|
        global_options[:project_id] = v
      end
      opts.on('-c', '--cluster=CLUSTER', String, 'Cluster ID') do |v|
        global_options[:cluster_id] = v
      end
    end

    def cache_id(key, infos, field_name)
      case infos
      when Array
        infos.each do |info|
          cache_id(key, info, field_name)
        end
      when Hash
        info = infos
        cache["#{key}:id:#{field_name}"] ||= {}
        cache["#{key}:id:#{field_name}"][info['id']] = info.fetch(field_name)
        cache["#{key}:id:#{field_name}"] = cache["#{key}:id:#{field_name}"]
        cache["#{key}:#{field_name}:id"] ||= {}
        cache["#{key}:#{field_name}:id"][info[field_name]] = info.fetch('id')
        cache["#{key}:#{field_name}:id"] = cache["#{key}:#{field_name}:id"]
      else
        raise "Unexpected type #{infos}"
      end
    end

    def cache_association(child_key, parent_key, infos, foreign_key)
      case infos
      when Array
        infos.each do |info|
          cache_association(child_key, parent_key, info, foreign_key)
        end
      when Hash
        info = infos
        cache["#{child_key}-#{parent_key}"] ||= {}
        cache["#{child_key}-#{parent_key}"][info['id']] = info.fetch(foreign_key)
        cache["#{child_key}-#{parent_key}"] = cache["#{child_key}-#{parent_key}"]
      else
        raise "Unexpected type #{infos}"
      end
    end

    def get_project_id(options)
      project_id = options[:project_id] || begin
        if options[:cluster_id]
          cache["cluster-project"]&.[](options[:cluster_id])
        end
      end

      begin
        client.get_project(project_id)
      rescue Client::NotFound
        info = client.get_project_by_name(project_id)
        project_id = info['id']
      end

      unless project_id
        raise "Project id is required"
      end

      project_id
    end

    def resolve_project_and_cluster(options)
      if options[:cluster_id] && !options[:project_id]
        options[:project_id] = cache["cluster-project"]&.[](options[:cluster_id])
      end

      begin
        client.get_project(options.fetch(:project_id))
      rescue Client::NotFound
        info = client.get_project_by_name(options[:project_id])
        options[:project_id] = info['id']
      end
    end

    def resolve_cluster_name(id_or_name)
      cache['cluster:id:name'].fetch(id_or_name, id_or_name)
    end

    def get_process_log(project_id:, hostname:, name:, **options)
      if LOG_NAME_MAP.key?(name)
        name = LOG_NAME_MAP[name]
      end
      unless name.end_with?('.gz')
        name += '.gz'
      end
      decompress = !options[:compress]
      if options[:all]
        log = ''
        start = nil
        loop do
          puts "Retrieve from #{start}"

          chunk = client.get_process_log(project_id: project_id,
            hostname: hostname, name: name, decompress: true,
            start_time: start || 0)
          log << chunk

          if start.nil?
            io = StringIO.new(chunk)
            loop do
              line = io.readline
              if line.nil?
                raise "Did not find any timestamps in log"
              end
              time_str = line.split(' ', 2).first
              unless time_str.nil? || time_str.empty?
                begin
                  start = Time.parse(time_str)
                  break
                rescue ArgumentError
                end
              end
            end
          end

          start += 5 * 60

          if start > Time.now
            break
          end
        end
        if options[:compress]
          str = ''
          gz = Zlib::GzipWriter.new(StringIO.new(str))
          gz.write(log)
          gz.close
          log = str
        end
        log
      else
        client.get_process_log(project_id: project_id,
          hostname: hostname, name: name, decompress: decompress,
          start_time: options[:start_time], end_time: options[:end_time])
      end
    end

    def get_ftdc_log(project_id:, cluster_name:)
      job_id = client.create_log_collection_job(
        project_id: project_id,
        cluster_name: cluster_name,
        redacted: true,
        log_types: %w(ftdc),
      )

      loop do
        info = client.get_log_collection_job(project_id: project_id, id: job_id)

        case info.fetch('status')&.downcase
        when 'success'
          url = info.fetch('download_url')
          return client.request(:get, url).body
        when 'in_progress'
          sleep 1
        else
          raise "Unexpected log collection job status"
        end
      end
    end

    def client
      @client ||= Client.new(**global_options.slice(*%i(user password)))
    end

    class << self
      def run
        new.run
      end
    end
  end
end
