require 'medusa/http'

module Medusa
  class Tentacle

    #
    # Create a new Tentacle
    #
    def initialize(core, link_queue, page_queue)
      @core = core
      @link_queue = link_queue
      @page_queue = page_queue
    end

    #
    # Gets links from @link_queue, and returns the fetched
    # Page objects into @page_queue
    #
    def run
      loop do
        link, referer, depth = @link_queue.deq

        break if link == :END

        pages = @core.http.fetch_pages(link, referer, depth)

        pages.each { |page|
          @core.debug_request.call("Inserting page #{page.url.path}")
          @page_queue.push page
        }

        delay
      end
    end

    private

    def delay
      sleep @core.opts[:delay] if @core.opts[:delay] > 0
    end

  end
end
