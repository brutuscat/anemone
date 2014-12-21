require 'forwardable'

module Medusa
  class PageStore

    def initialize(storage = {})
      @storage = storage
    end

    # We typically index the hash with a URI,
    # but convert it to a String for easier retrieval
    def [](index)
      @storage[index.to_s]
    end

    def []=(index, other)
      @storage[index.to_s] = other
    end

    def delete(key)
      @storage.delete key.to_s
    end

    def key?(key)
      @storage.key? key.to_s
    end

    def touch_key(key)
      self[key] = Page.new(key)
    end

    def touch_keys(keys)
      keys.each do |k|
        touch_key k
      end
    end

    # Does this PageStore contain the specified URL?
    # HTTP and HTTPS versions of a URL are considered to be the same page.
    def has_page?(url)
      schemes = %w(http https)
      if schemes.include? url.scheme
        u = url.dup
        return schemes.any? { |s| u.scheme = s; key?(u) }
      end

      key? url
    end

    #
    # Use a breadth-first search to calculate the single-source
    # shortest paths from *root_uri* to all pages in the PageStore
    #
    def shortest_paths!(root_uri)
      root_uri = URI(root_uri) if root_uri.is_a?(String)
      raise "Root node not found" if !key?(root_uri)

      q = Queue.new

      q.enq root_uri
      root_page = self[root_uri]
      root_page.depth = 0
      root_page.visited = true
      self[root_uri] = root_page
      while !q.empty?
        page = self[q.deq]
        page.links.each do |u|
          begin
            link = self[u]
            next if link.nil? || !link.fetched? || link.visited

            q << u unless link.redirect?
            link.visited = true
            link.depth = page.depth + 1
            self[u] = link

            if link.redirect?
              u = link.redirect_to
              redo
            end
          end
        end
      end

      self
    end
  end
end
