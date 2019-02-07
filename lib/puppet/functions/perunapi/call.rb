require 'net/http'
require 'net/https'
require 'openssl'
require 'json'

Puppet::Functions.create_function(:'perunapi::call') do
  # This function makes RPC call to perun RPC API.
  # On success, function returns hash response. On fail, function rises an exception.
  #
  # @example
  #    perunapi::call(host, user, password, manager, method, request, context)
  #
  # @return [Variant[Hash, Array]] Call result
  dispatch :perun_call do
    param 'Stdlib::Fqdn', :host
    param 'String',       :user
    param 'String',       :password
    param 'String',       :manager
    param 'String',       :method
    param 'Hash',         :request
    param 'String',       :context
    return_type 'Variant[Hash, Array]'
  end

  # :nodoc:
  def perun_call(hostname, user, password, manager, method, request, context)
    request = request.to_json.gsub(/"undef"/, "null")

    path = '/var/run/puppetlabs/puppetserver'
    Dir.mkdir(path, 0755) unless Puppet::FileSystem.exist?(path)

    cookiefile = "#{path}/#{context}-cookie"
    cookie = Puppet::FileSystem.exist?(cookiefile) ? File.read(cookiefile) : ''

    uri = URI("https://#{hostname}/krbes/rpc/json/#{manager}/#{method}?callback=#{context}-#{method}")

    Net::HTTP.start(uri.host, uri.port, read_timeout: 60, :use_ssl => uri.scheme == 'https') do |http|
      req = Net::HTTP::Post.new(uri.request_uri, initheader = {'Content-Type' =>'application/json', 'Cookie' => cookie})
      req.basic_auth user, password
      req.body = request

      begin
        response = http.request(req)

        rawcookies = response.get_fields('set-cookie')
        cookie = rawcookies[0].split('; ')[0] if rawcookies

        f = File.new(cookiefile, 'w', 0600)
        f.write(cookie)
        f.close

        unless ['200', '400'].include?(response.code)
          raise Puppet::ParseError, "perun_api_post(#{uri}): #{response.code} - #{response.body}"
        end
      rescue Timeout::Error => _e
        return { timeout: true }
      end

      response.body == 'null' ? {} : JSON.parse(response.body)
    end
  end
end
