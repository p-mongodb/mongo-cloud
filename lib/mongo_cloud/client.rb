autoload :Zlib, 'zlib'
require 'rack'
require 'faraday'
require 'faraday/detailed_logger'
require 'faraday/digestauth'
require 'oj'

Oj.default_options = {mode: :compat}

module MongoCloud
  class Client

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
      request_json(:get, "orgs/#{id}")
    end

    # Projects

    def list_projects
      # TODO paginate
      request_json(:get, 'groups')['results']
    end

    def get_project(id)
      request_json(:get, "groups/#{id}")
    end

    # Clusters

    def list_clusters(project_id:)
      # TODO paginate
      request_json(:get, "groups/#{project_id}/clusters")['results']
    end

    def get_cluster(project_id:, name:)
      request_json(:get, "groups/#{project_id}/clusters/#{name}")
    end

    # IP whitelists

    def list_whitelist_entries(project_id:)
      # TODO paginate
      request_json(:get, "groups/#{project_id}/whitelist")['results']
    end

    def get_whitelist_entry(project_id:, name:)
      request_json(:get, "groups/#{project_id}/whitelist/#{name}")
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
      request_json(:post, "groups/#{project_id}/whitelist", [payload])
    end

    # Database Users

    def list_db_users(project_id:)
      # TODO paginate
      request_json(:get, "groups/#{project_id}/databaseUsers")['results']
    end

    def create_db_user(project_id:,
      username:, password:
    )
      payload = {
        username: username,
        password: password,
        databaseName: 'admin',
        roles: [
          roleName: 'atlasAdmin',
          databaseName: 'admin',
        ],
      }.compact
      request_json(:post, "groups/#{project_id}/databaseUsers", payload)
    end

    # Processes

    def list_processes(project_id:)
      # TODO paginate
      request_json(:get, "groups/#{project_id}/processes")['results']
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
      request_json(:get, "groups/#{project_id}/processes/#{process_id}/measurements", payload)
    end

    def get_cluster_log(project_id:, hostname:,
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

      payload = {
        start: start_time,
        end: end_time,
      }.compact
      resp = request(:get, "groups/#{project_id}/clusters/#{hostname}/logs/#{name}", payload)
      body = resp.body
      if decompress
        gz = Zlib::GzipReader.new(StringIO.new(resp.body))
        body = gz.read
      end
      body
    end

    # ---

    def request_json(meth, url, params=nil, **options)
      response = request(meth, url, params, **options)
      Oj.load(response.body)
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
      if response.status != 200 && response.status != 201
        error = nil
        begin
          error = Oj.load(response.body)['error']
        rescue
          error = response.body
        end
        msg = "MongoCloud #{meth.to_s.upcase} #{url} failed: #{response.status}"
        if error
          msg += ": #{error}"
        end
        cls = if response.status == 404
          NotFound
        else
          ApiError
        end
        raise cls.new(msg, status: response.status)
      end
      response
    end

    def connection
      @connection ||= Faraday.new("https://cloud.mongodb.com/api/atlas/v1.0/") do |f|
        username = options[:user] || ENV['MCLI_PUBLIC_API_KEY']
        password = options[:password] || ENV['MCLI_PRIVATE_API_KEY']

        f.request :url_encoded
        f.request :digest, username, password
        f.response :detailed_logger
        f.adapter Faraday.default_adapter
        f.headers['user-agent'] = 'MongoCloudClient'
      end
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
  end
end
