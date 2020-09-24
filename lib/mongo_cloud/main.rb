require 'awesome_print'
require 'daybreak'
require 'optparse'
require 'mongo_cloud'

module MongoCloud
  class Main
    def initialize
      @global_options = {}
      @cache = Daybreak::DB.new(File.expand_path('~/.mongo-cloud.cache'))
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

      commands = %w(org project cluster whitelist dbuser proc)
      if commands.include?(command)
        send(command, argv)
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

      case argv.shift
      when 'list'
        infos = client.list_projects
        cache_id('project', infos, 'name')
        ap infos
      when 'show'
        ap client.get_project(argv.shift)
      else
        raise 'bad usage'
      end
    end

    def cluster(argv)
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

      begin
        client.get_project(options[:project_id])
      rescue Client::NotFound
        info = client.get_project_by_name(options[:project_id])
        options[:project_id] = info['id']
      end

      case argv.shift
      when 'list'
        infos = client.list_clusters(project_id: options[:project_id])
        cache_id('cluster', infos, 'name')
        cache_association('cluster', 'project', infos, 'group_id')
        ap infos
      when 'show'
        ap client.get_cluster(project_id: options[:project_id], name: argv.shift)
      when 'log'
        puts client.get_cluster_log(project_id: options[:project_id],
          hostname: argv.shift, name: argv.shift&.to_sym || :mongod, decompress: true)
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
      end.parse!(argv)

      client = Client.new(**global_options.slice(*%i(user password)))

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
        cache["#{key}:id:#{field_name}"][info['id']] = info[field_name]
        cache["#{key}:#{field_name}:id"] ||= {}
        cache["#{key}:#{field_name}:id"][info[field_name]] = info['id']
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
        cache["#{child_key}-#{parent_key}"][info['id']] = info[foreign_key]
      else
        raise "Unexpected type #{infos}"
      end
    end

    class << self
      def run
        new.run
      end
    end
  end
end
