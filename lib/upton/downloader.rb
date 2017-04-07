require "fileutils"
require "open-uri"
require "tmpdir"
require "restclient"
require_relative "./version"

module Upton

  # This class is used internally to download and cache the webpages
  # that are requested.
  #
  # By default, the cache location is the output of `Dir.tmpdir`/upton.
  # The Dir.tmpdir returns the temporary directory of the operating system.
  # By default, the stashed files have a non-human-readable md5-based filename.
  # If `readable_stash_filenames` is true, they will have human-readable names.
  class Downloader

    MAX_FILENAME_LENGTH = 130 #for unixes, win xp+
    EMPTY_STRING = ''

    attr_reader :uri, :cache_location, :verbose
    def initialize(uri, options = {})
      @uri = uri
      @options = options
      @cache = options.fetch(:cache) { true }
      @cache_location = File.absolute_path(options[:cache_location] || "#{Dir.tmpdir}/upton")
      @verbose = options[:verbose] || false
      @readable_stash_filenames = options[:readable_filenames] || false
      initialize_cache!
    end

    def get
      if cache_enabled?
        puts "Stashing enabled. Will try reading #{uri} data from cache." if @verbose
        download_from_cache!
      else
        puts "Stashing disabled. Will download from the internet." if @verbose
        from_resource = true
        resp = download_from_resource!
        {:resp => resp, :from_resource => from_resource }
      end
    end

    private

    def make_request_for_resource!
      RestClient.get(uri)
    end

    def download_from_resource!
      begin
        puts "Downloading from #{uri}" if @verbose
        resp = make_request_for_resource!
        puts "Downloaded #{uri}" if @verbose
      rescue RestClient::ResourceNotFound
        puts "404 error, skipping: #{uri}" if @verbose
      rescue RestClient::InternalServerError
        puts "500 Error, skipping: #{uri}" if @verbose
      rescue RestClient::ServiceUnavailable
        puts "503 Error, skipping: #{uri}" if @verbose
      rescue URI::InvalidURIError
        puts "Invalid URI: #{uri}" if @verbose
      rescue RestClient::RequestTimeout
        puts "Timeout: #{uri}" if @verbose
        retry
      end
      resp ||= EMPTY_STRING
    end

    def download_from_cache!
      resp = if cached_file_exists?
              puts "Cache of #{uri} available" if @verbose
              from_resource = false
              open(cached_file).read
            else
              if @verbose
                if @readable_stash_filenames
                  puts "Cache of #{uri} unavailable at #{filename_from_uri}. Will download from the internet"
                else
                  puts "Cache of #{uri} unavailable. Will download from the internet"
                end
              end
              from_resource = true
              download_from_resource!
            end
      unless cached_file_exists?
        if @verbose
          if @readable_stash_filenames
            puts "Writing #{uri} data to the cache at #{cached_file}"
          else
            puts "Writing #{uri} data to the cache"
          end
        end
        commented_resp = add_comment(resp)
        open(cached_file, 'w'){|f| f << commented_resp}
      end
      {:resp => resp, :from_resource => from_resource }
    end

    def add_comment(resp)
      # n = Nokogiri::HTML("<html></html>")
      # c = Nokogiri::XML::Comment.new(n, "asdfasdf")
      # n.root.add_child(c)
      # <!----Retrieved by Upton from http://www.somesite.com on January 15 at 4:28 p.m.-->
      msg = "Stashed file retrieved by Upton #{Upton::VERSION} from #{@uri} at #{Time.now}"
      resp_html = Nokogiri::HTML(resp)
      comment = Nokogiri::XML::Comment.new(resp_html, msg)
      if resp_html.root.nil? || !resp_html.include?("<html")
        return resp
      elsif resp_html.root.children.empty?
        resp_html.root.add_child(comment)
      else
        resp_html.root.children.before(comment)
      end
      resp_html.to_html
    end

    def cache_enabled?
      !!@cache
    end

    def filename_from_uri
      @readable_stash_filenames ? readable_filename_from_uri : hashed_filename_from_uri
    end

    def hashed_filename_from_uri
      Digest::MD5.hexdigest(uri)
    end

    def readable_filename_from_uri
      html = "html"
      clean_url_max_length = MAX_FILENAME_LENGTH - html.length - cache_location.size
      clean_url = uri.gsub(/[^A-Za-z0-9\-_]/, "")[0...clean_url_max_length]
      "#{clean_url}.#{html}"
    end

    def cached_file
      "#{cache_location}/#{filename_from_uri}"
    end

    def cached_file_exists?
      File.exists?(cached_file)
    end

    def initialize_cache!
      unless Dir.exist?(cache_location)
        Dir.mkdir(cache_location)
        FileUtils.chmod 0700, cache_location
      end
    end

  end
end
