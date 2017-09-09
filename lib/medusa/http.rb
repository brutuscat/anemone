require 'medusa/page'
require 'medusa/cookie_store'

module Medusa

  class HTTP
    # Maximum number of redirects to follow on each get_response
    REDIRECT_LIMIT = 5
    RETRY_LIMIT = 6

    # CookieStore for this HTTP client
    attr_reader :cookie_store

    def initialize(opts = {})
      @opts = opts
      @cookie_store = CookieStore.new(@opts[:cookies])
    end

    #
    # Fetch a single Page from the response of an HTTP request to *url*.
    # Just gets the final destination page.
    #
    def fetch_page(url, referer = nil, depth = 0)
      fetch_pages(url, referer, depth).last
    end

    #
    # Create new Pages from the response of an HTTP request to *url*,
    # including redirects
    #
    def fetch_pages(url, referer = nil, depth = 0)
      begin
        url = URI(url) unless url.is_a?(URI)
        pages = []
        debug_request.call("Fetching pages #{url}") if debug_request
        g_rtn = get(url, referer) do |page|
          page.depth = depth
          pages << page
        end
        return pages
      rescue Exception => e
        debug_request.call("ERR #{e}") if debug_request
        if verbose?
          puts e.inspect
          puts e.backtrace
        end
        pages ||= []
        return pages << Page.new(url, :error => e)
      end
    ensure
      debug_request.call("Finished fetch pages:#{url} #{pages.size}") if debug_request
    end

    #
    # The maximum number of redirects to follow
    #
    def redirect_limit
      @opts[:redirect_limit] || REDIRECT_LIMIT
    end

    #
    # The user-agent string which will be sent with each request,
    # or nil if no such option is set
    #
    def user_agent
      @opts[:user_agent]
    end

    #
    # Does this HTTP client accept cookies from the server?
    #
    def accept_cookies?
      @opts[:accept_cookies]
    end

    #
    # The http authentication options as in http://www.ruby-doc.org/stdlib/libdoc/open-uri/rdoc/OpenURI/OpenRead.html
    # userinfo is deprecated [RFC3986]
    #
    def http_basic_authentication
      @opts[:http_basic_authentication]
    end

    #
    # The proxy authentication options as in http://www.ruby-doc.org/stdlib/libdoc/open-uri/rdoc/OpenURI/OpenRead.html
    #
    def proxy_http_basic_authentication
      @opts[:proxy_http_basic_authentication]
    end

    #
    # The proxy options as in http://www.ruby-doc.org/stdlib/libdoc/open-uri/rdoc/OpenURI/OpenRead.html
    #
    def proxy
      @opts[:proxy]
    end

    #
    # The proxy address string
    #
    def proxy_host
      @opts[:proxy_host]
    end

    #
    # The proxy port
    #
    def proxy_port
      @opts[:proxy_port]
    end

    #
    # HTTP read timeout in seconds
    #
    def read_timeout
      @opts[:read_timeout]
    end

    #
    # HTTP headers to add to the request
    #
    def http_request_headers
      @opts[:http_request_headers] || {}
    end

    #
    # HTTP headers to add to the request
    #
    def debug_request
      @opts[:debug_request]
    end


    #
    # Retrieve HTTP responses for *url*, including redirects.
    # Yields the response object, response code, and URI location
    # for each response.
    #
    def get(url, referer = nil)
      debug_request.call("get #{url}") if debug_request
      limit = redirect_limit
      loc = url
      pages = []
      begin
        # if redirected to a relative url, merge it with the host of the original
        # request url
        loc = url.merge(loc) if loc.relative?

        response, headers, response_time, response_code, redirect_to = get_response(loc, referer)
        p = Page.new(loc,
                     :body => response,
                     :headers => headers,
                     :code => Integer(response_code),
                     :referer => referer,
                     :redirect_to => redirect_to,
                     :response_time => response_time)
        debug_request.call("get results: #{response_code} #{p}" ) if debug_request rescue
        pages.push p
        yield p
        limit -= 1
      end while (loc = redirect_to) && allowed?(redirect_to, url) && limit > 0
      #return pages
    rescue Exception => e
      debug_request.call("ERR: #{e}") if debug_request
    ensure
      # debug_request.call("get fin #{pages.size}") if debug_request
    end

    #
    # Get an HTTPResponse for *url*, sending the appropriate User-Agent string
    #
    def get_response(url, referer = nil)
      full_path = url.query.nil? ? url.path : "#{url.path}?#{url.query}"
      # debug_request.call("Getting-response #{full_path}, #{http_request_headers}") if debug_request
      opts = {}
      opts['User-Agent'] = user_agent if user_agent
      opts['Referer'] = referer.to_s if referer
      opts['Cookie'] = @cookie_store.to_s unless @cookie_store.empty? || (!accept_cookies? && @opts[:cookies].nil?)
      opts[:http_basic_authentication] = http_basic_authentication if http_basic_authentication
      opts[:proxy] = proxy if proxy
      opts[:proxy_http_basic_authentication] = proxy_http_basic_authentication if proxy_http_basic_authentication rescue
      opts[:read_timeout] = read_timeout if !!read_timeout
      opts[:redirect] = false
      redirect_to = nil
      http_request_headers.each { |header, value| opts[header] = value }
      debug_request.call("#{url}, #{opts}") if debug_request
      retries = 0
      begin
        start = Time.now()
        begin
          resource = open(url, opts)
        rescue OpenURI::HTTPRedirect => e_redirect
          debug_request.call("RED: #{e_redirect}") if debug_request
          resource = e_redirect.io
          redirect_to = e_redirect.uri
        rescue OpenURI::HTTPError => e_http
          debug_request.call("ERR: #{e_http}") if debug_request
          resource = e_http.io
        end
        finish = Time.now()
        response_time = ((finish - start) * 1000).round
        @cookie_store.merge!(resource.meta['set-cookie']) if accept_cookies?
        debug_request.call("Returning response after #{response_time}ms") if debug_request
        return resource.read, resource.meta, response_time, resource.status.shift, redirect_to

      rescue Timeout::Error, EOFError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::ECONNRESET => e
        retries += 1
        debug_request.call("[medusa] Retrying ##{retries} on url #{url} because of: #{e.inspect}") if debug_request
        sleep(3 ^ retries)
        retry unless retries > RETRY_LIMIT
      ensure
        # debug_request.call("Closing response #{resource}") if debug_request
        resource.close if !resource.nil? && !resource.closed?
      end
    ensure
      # debug_request.call("Fin get_request") if debug_request
    end

    def verbose?
      @opts[:verbose]
    end

    #
    # Allowed to connect to the requested url?
    #
    def allowed?(to_url, from_url)
      to_url.host.nil? || (to_url.host == from_url.host)
    end
  end
end
