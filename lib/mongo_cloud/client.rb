autoload :Zlib, 'zlib'
require 'rack'
require 'faraday'
require 'faraday/detailed_logger'
require 'faraday/digestauth'
require 'oj'

Oj.default_options = {mode: :compat}

module MongoCloud
  class TruncatingLogger < Logger
    def format_message(severity, datetime, progname, msg)
      if msg.length >= 5000
        msg = msg[0..4997] + '...'
      end
      super
    end
  end

  class Client

    class ApiError < StandardError
      def initialize(msg, status: nil, body: nil)
        @status = status
        @body = body
        super(msg)
      end

      attr_reader :status
      attr_reader :body

      def payload
        @payload ||= Oj.load(body)
      end

      def error_code
        payload['errorCode']
      end
    end

    class BadRequest < ApiError
    end

    class NotFound < ApiError
    end

    def initialize(**opts)
      @options = opts.freeze
    end

    attr_reader :options

    # Organizations

    def list_orgs
      # TODO paginate
      request_json(:get, 'orgs')['results']
    end

    def get_org(id)
      request_json(:get, "orgs/#{escape(id)}")
    end

    # Projects

    def list_projects
      # TODO paginate
      convert_keys(request_json(:get, 'groups')['results'])
    end

    def get_project(id)
      convert_keys(request_json(:get, "groups/#{escape(id)}"))
    end

    def get_project_by_name(name)
      convert_keys(request_json(:get, "groups/byName/#{escape(name)}"))
    end

    def create_project(org_id:, name:)
      request_json(:post, "groups",
        {orgId: org_id, name: name}, {})
    end

    def delete_project(id)
      request_json(:delete, "groups/#{escape(id)}")
    end

    # Clusters

    def list_clusters(project_id:)
      # TODO paginate
      convert_keys(request_json(:get, "groups/#{escape(project_id)}/clusters")['results'])
    end

    def get_cluster(project_id:, name:)
      convert_keys(request_json(:get, "groups/#{escape(project_id)}/clusters/#{escape(name)}"))
    end

    # This endpoint requires atlas global operator permissions.
    def get_cluster_internal(project_id:, name:)
      convert_keys(request_json(:get, "/api/private/nds/groups/#{escape(project_id)}/clusters/#{escape(name)}"))
    end

    def get_cluster_replica_set_hardware(project_id:, name:)
      request_json(:get, "/admin/nds/groups/#{escape(project_id)}/clusterDescriptions/#{escape(name)}/replicaSetHardware")
    end

    def delete_cluster(project_id:, name:)
      request_json(:delete, "groups/#{escape(project_id)}/clusters/#{escape(name)}")
    rescue BadRequest => exc
      if exc.error_code == 'CLUSTER_ALREADY_REQUESTED_DELETION'
        # Silence
      else
        raise
      end
    end

    def create_cluster(project_id:, name:, **opts)
      request_json(:post, "groups/#{escape(project_id)}/clusters",
        {name: name}.update(opts), {})
    end

    def update_cluster(project_id:, name:, **opts)
      request_json(:patch, "groups/#{escape(project_id)}/clusters/#{escape(name)}",
        opts)
    end

    def reboot_cluster(project_id:, name:)
      request_json(:post, "/api/private/nds/groups/#{escape(project_id)}/clusters/#{escape(name)}/reboot", {}, {})
    end

    # IP whitelists

    def list_whitelist_entries(project_id:)
      # TODO paginate
      request_json(:get, "groups/#{escape(project_id)}/whitelist")['results']
    end

    def get_whitelist_entry(project_id:, name:)
      request_json(:get, "groups/#{escape(project_id)}/whitelist/#{escape(name)}")
    end

    def create_whitelist_entry(project_id:,
      cidr_block: nil, ip_address: nil, aws_security_group_id: nil,
      comment: nil, delete_after: nil
    )
      payload = {
        cidrBlock: cidr_block,
        ipAddress: ip_address,
        awsSecurityGroup: aws_security_group_id,
        comment: comment,
        deleteAfterDate: to_iso8601_time(delete_after),
      }.compact
      request_json(:post, "groups/#{escape(project_id)}/whitelist", [payload])
    end

    # Database Users

    def list_db_users(project_id:)
      # TODO paginate
      request_json(:get, "groups/#{escape(project_id)}/databaseUsers")['results']
    end

    def create_db_user(project_id:,
      username:, password:, roles: nil
    )
      payload = {
        username: username,
        password: password,
        databaseName: 'admin',
        roles: roles || [
          roleName: 'atlasAdmin',
          databaseName: 'admin',
        ],
      }.compact
      request_json(:post, "groups/#{escape(project_id)}/databaseUsers", payload, {})
    end

    # Processes

    def list_processes(project_id:)
      # TODO paginate
      convert_keys(request_json(:get, "groups/#{escape(project_id)}/processes")['results'])
    end

    def get_process_measurements(project_id:, process_id:,
      granularity:, period: nil, start_time: nil, end_time: nil,
      metrics: nil
    )
      payload = {
        granularity: granularity,
        period: period,
        start: to_iso8601_time(start_time),
        end: to_iso8601_time(end_time),
        # TODO serialize as repeated key
        m: metrics,
      }.compact
      request_json(:get, "groups/#{escape(project_id)}/processes/#{escape(process_id)}/measurements", payload)
    end

    def get_process_log(project_id:, hostname:,
      name:, start_time: nil, end_time: nil,
      decompress: false
    )
      if name.is_a?(Symbol)
        name = {
          mongod: 'mongodb.gz',
          mongos: 'mongos.gz',
          mongod_audit: 'mongodb-audit-log.gz',
          mongos_audit: 'mongos-audit-log.gz',
        }.fetch(name)
      end

      if Time === start_time
        start_time = start_time.to_i
      end
      if Time === end_time
        end_time = end_time.to_i
      end

      payload = {
        startDate: start_time,
        endDate: end_time,
      }.compact
      resp = request(:get, "groups/#{escape(project_id)}/clusters/#{escape(hostname)}/logs/#{escape(name)}", payload, **{})
      body = resp.body
      if decompress
        gz = Zlib::GzipReader.new(StringIO.new(resp.body))
        body = gz.read
      end
      body
    end

    # Log types: ftdc mongodb automation_agent backup_agent monitoring_agent
    # This endpoint requires atlas global operator permissions in atlas.
    def create_log_collection_job(project_id:,
      cluster_name: nil, resource_type: nil, resource_name: nil,
      redacted: true, file_size: 100_000_000, log_types: nil
    )
      if cluster_name
        if resource_type.nil? && resource_name.nil?
          info = get_cluster_internal(project_id: project_id,
            name: cluster_name)

          case info.fetch('cluster_type')
          when 'REPLICASET'
            resource_type = 'REPLICASET'
            resource_name = info.fetch('deployment_item_name')
          when 'SHARDED'
            resource_type = 'CLUSTER'
            resource_name = info.fetch('deployment_item_name')
            # Supposedly the resource name should be the cluster name,
            # but that doesn't work and deployment item name appears to work.
            #resource_name = info.fetch('name')
          else
            raise "Unknown cluster type"
          end
        else
          raise ArgumentError, 'Cluster name is mutually exclusive with resource type & resource name'
        end
      end

      payload = {
        resourceType: resource_type,
        resourceName: resource_name,
        redacted: redacted,
        sizeRequestedPerFileBytes: file_size,
        logTypes: log_types.map(&:to_s).map(&:upcase),
      }
      info = request_json(:post, "groups/#{escape(project_id)}/logCollectionJobs", payload, **{})
      info.fetch('id')
    end

    def get_log_collection_job(project_id:, id:)
      convert_keys(request_json(:get, "groups/#{escape(project_id)}/logCollectionJobs/#{escape(id)}"))
    end

    def list_log_collection_jobs(project_id:)
      convert_keys(request_json(:get, "groups/#{escape(project_id)}/logCollectionJobs"))
    end

    def failover_cluster(project_id:, name:)
      request(:post, "groups/#{escape(project_id)}/clusters/#{escape(name)}/restartPrimaries")
    end

    # ---

    def request_json(meth, url, params=nil, **options)
      response = request(meth, url, params, **options)
      if response.body.empty?
        nil
      else
        Oj.load(response.body)
      end
    end

    def request(meth, url, params=nil, **options)
      response = connection.send(meth) do |req|
        if meth.to_s.downcase == 'get'
          if params
            u = URI.parse(url)
            query = u.query
            if query
              query = Rack::Utils.parse_nested_query(query)
            else
              query = {}
            end
            query.update(params)
            u.query = Rack::Utils.build_query(query)
            url = u.to_s
            params = nil
          end
        end
        req.url(url)
        if params
          req.body = payload = Oj.dump(params)
          puts "Sending payload: #{payload} for #{url}"
          req.headers['content-type'] = 'application/json'
        end
      end
      unless (200..202).include?(response.status)
        error = nil
        begin
          payload = Oj.load(response.body)
          if payload.key?('detail')
            error = "#{payload['error']}: #{payload['detail']}"
          else
            error = payload['error']
          end
        rescue
          error = response.body
        end
        msg = "MongoCloud #{meth.to_s.upcase} #{url} failed: #{response.status}"
        if error
          msg += ": #{error}"
        end
        cls = case response.status
        when 400
          BadRequest
        when 404
          NotFound
        else
          ApiError
        end
        raise cls.new(msg, status: response.status, body: response.body)
      end
      response
    end

    def connection
      # The MCLI_OPS_MANAGER_URL name is simply what mongocli uses,
      # ops manager may not actually be involved in any way.
      base = options[:base_url] || ENV['MCLI_OPS_MANAGER_URL'] || 'https://cloud.mongodb.com'
      base = URI.parse(base)
      unless base.path.end_with?('/')
        base.path = base.path + '/'
      end
      @connection ||= Faraday.new(URI.join(base, "api/atlas/v1.0/")) do |f|
        username = options[:user] || ENV.fetch('MCLI_PUBLIC_API_KEY')
        password = options[:password] || ENV.fetch('MCLI_PRIVATE_API_KEY')

        f.request :url_encoded
        f.request :digest, username, password
        f.response :detailed_logger, logger
        f.adapter Faraday.default_adapter
        f.headers['user-agent'] = 'MongoCloudClient'
      end
    end

    def logger
      @logger ||= TruncatingLogger.new(STDERR)
    end

    def to_iso8601_time(time_or_str)
      case time_or_str
      when nil
        nil
      when String
        time_or_str
      else
        time_or_str.utc&.strftime('%Y-Ym-%dT%H:%M:%SZ')
      end
    end

    def escape(str)
      CGI.escape(str).gsub('+', '%20')
    end

    def convert_keys(data)
      if Array === data
        return data.map do |item|
          convert_keys(item)
        end
      end

      return data unless Hash === data

      data = data.dup
      data.delete('links')
      data.keys.each do |key|
        underscore_key = key.
          sub('mongoDB', 'mongodb').
          sub('URI', 'Uri').sub('GB', 'Gb').
          gsub(/(?<=[a-z])([A-Z]+)/) { |m| '_' + m.downcase }
        if underscore_key == 'group_id'
          underscore_key = 'project_id'
        end
        if key != underscore_key
          data[underscore_key] = data.delete(key)
        end
      end
      out = {}
      data.keys.sort.each do |key|
        value = data[key]
        case value
        when Hash
          value = convert_keys(value)
        when Array
          value = convert_keys(value)
        end
        out[key] = value
      end
      out
    end
  end
end
