#--
# Copyright: Copyright (c) 2010 RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'checkout_scraper_base'))
require 'curb'
require 'libarchive_ruby'
require 'tempfile'

module RightScale
  # A scraper for cookbooks stored in archives on a web server
  # somewhere.
  class DownloadScraper < ScraperBase
    # Create a new DownloadScraper.  In addition to the options recognized by
    # ScraperBase#initialize, this class recognizes _:directory_.
    #
    # === Options ===
    # _:directory_:: Directory to perform scraper work in
    #
    # === Parameters ===
    # repository(RightScale::Repository):: repository to scrape
    # options(Hash):: scraper options
    def initialize(repository, options={})
      super
      @basedir = options[:directory]
      @done = false
    end
    # Return the position of the scraper.  This always returns true,
    # because we only support one cookbook per tarball and so it is
    # always at the same position.
    def pos
      true
    end

    # Seek to the given position.  This is a noop, because we only
    # support one cookbook per tarball and so it is always at the same
    # position.
    def seek(position)
      true
    end

    # Return next cookbook from the stream, or nil if none.
    def next
      return nil if @done

      if @basedir.nil?
        file = Tempfile.new("archive")
      else
        file = Tempfile.new("archive", tmpdir=@basedir)
      end
      bytecount = 0

      @logger.operation(:downloading) do
        Curl::Easy.http_get(@repository.url) do |curl|
          if @repository.first_credential && @repository.second_credential
            curl.http_auth_types = [:any]
            curl.timeout = @max_seconds if @max_seconds
            # Curl::Easy doesn't support bailing if too large
            curl.username = @repository.first_credential
            curl.password = @repository.second_credential
          end
          curl.on_body do |body_data|
            file.write body_data
            bytecount += body_data.length
            if bytecount > @max_bytes
              raise "Command took too much space"
            end
            body_data.length
          end
        end
      end

      file.close

      cookbook = RightScale::Cookbook.new(@repository, nil, pos)

      file.open
      cookbook.data[:archive] = file.read
      file.close

      @scanner.begin(cookbook)
      @logger.operation(:reading_metadata) do
        Archive.read_open_filename(file.path) do |ar|
          while entry = ar.next_header
            next unless entry.regular?
            @scanner.notice(entry.pathname) {ar.read_data}
          end
        end
      end
      @scanner.end(cookbook)

      file.close(true)
      @done = true

      raise "No metadata found for {#repository}" unless cookbook.metadata
      cookbook
    end
  end
end
