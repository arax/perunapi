require 'net/http'
require 'net/https'
require 'openssl'
require 'json'

Puppet::Functions.create_function(:'perunapi::callback') do
  # This function makes RPC callback to perun RPC API.
  # On success, function returns hash response. On fail, function rises an exception.
  #
  # @example
  #    perunapi::callback(host, user, password, method, context)
  #
  # @return [Hash] Call result
  dispatch :perun_callback do
    param 'Stdlib::Fqdn', :host
    param 'String',       :user
    param 'String',       :password
    param 'String',       :method
    param 'String',       :context
    return_type 'Hash'
  end

  # :nodoc:
  def perun_callback(host, user, password, method, context)
    path = '/var/run/puppetlabs/puppetserver'
    Dir.mkdir(path, 0755) unless Puppet::FileSystem.exist?(path)

    cookiefile = "#{path}/#{context}-cookie"
    cookie = Puppet::FileSystem.exist?(cookiefile) ? File.read(cookiefile) : ''

    uri = URI("https://#{host}/krbes/rpc/jsonp/getPendingRequests?callbackId=#{context}-#{method}")

    Net::HTTP.start(uri.host, uri.port, read_timeout: 60, :use_ssl => uri.scheme == 'https') do |http|
       req = Net::HTTP::Get.new(uri.request_uri, initheader = {'Cookie' => cookie})
       req.basic_auth user, password

       begin
         response = http.request(req)

         unless ['200', '400'].include?(response.code)
           raise Puppet::ParseError, "perun_api_get(): #{response.code} - #{response.body}"
         end
       rescue Timeout::Error => _e
         raise Puppet::ParseError, "perun_api_get(): call to #{uri} timed out"
       end

       ret = response.body.sub(/^[^\(]*\((.*)\);/, '\1')
       ret == 'null' ? {} : JSON.parse(ret)
    end
  end
end
