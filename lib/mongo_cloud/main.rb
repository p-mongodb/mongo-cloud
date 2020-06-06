require 'awesome_print'
require 'optparse'
require 'mongo_cloud'

module MongoCloud
  class Main
    def initialize
      @global_options = {}
    end

    attr_reader :global_options

    def run(argv = ARGV)
      argv = argv.dup

      parser = OptionParser.new do |opts|
        configure_global_options(opts)
      end.order!(argv)

      command = argv.shift

      if command.nil?
        usage('no command given')
      end

      commands = %w(org proj)
      if commands.include?(command)
        send(command, argv)
      else
        usage("unknown command: #{command}")
      end
    end

    def usage(msg)
      raise msg
    end

    def org(argv)
      options = {}
      parser = OptionParser.new do |opts|
        configure_global_options(opts)
      end.order!(argv)

      client = Client.new(**global_options.merge(options))

      case argv.shift
      when 'list'
        ap client.list_orgs
      when 'show'
        ap client.get_org(argv.shift)
      else
        raise 'bad usage'
      end
    end

    def proj(argv)
      options = {}
      parser = OptionParser.new do |opts|
        configure_global_options(opts)
      end.order!(argv)

      client = Client.new(**global_options.merge(options))

      case argv.shift
      when 'list'
        ap client.list_projects
      when 'show'
        ap client.get_project(argv.shift)
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
    end

    class << self
      def run
        new.run
      end
    end
  end
end
