require 'faraday'
require 'faraday/detailed_logger'
require 'faraday/digestauth'
require 'oj'

module MongoCloud
  class Client
    def list_orgs
      # TODO paginate
      request_json(:get, 'orgs')['results']
    end

    def request_json(meth, url, params=nil, options={})
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
      Oj.load(response.body)
    end

    def connection
      @connection ||= Faraday.new("https://cloud.mongodb.com/api/atlas/v1.0/") do |f|
        username = ENV['MCLI_PUBLIC_API_KEY']
        password = ENV['MCLI_PRIVATE_API_KEY']

        f.request :url_encoded
        f.request :digest, username, password
        f.response :detailed_logger
        f.adapter Faraday.default_adapter
        f.headers['user-agent'] = 'MongoCloudClient'
      end
    end
  end
end
