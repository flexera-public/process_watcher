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

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), 'svn_scraper_spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'lib', 'right_scraper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'lib', 'right_scraper', 'scrapers', 'svn'))
require 'set'
require 'libarchive_ruby'
require 'highline/import'

describe RightScale::NewSvnScraper do
  def archive_skeleton(archive)
    files = Set.new
    Archive.read_open_memory(archive) do |ar|
      while entry = ar.next_header
        files << [entry.pathname, ar.read_data]
      end
    end
    files
  end

  TEST_REMOTE=false

  context 'given a remote SVN repository' do
    before(:all) do
      @username = ask('Username: ')
      @password = ask('Password: ') {|q| q.echo = '*'}
    end

    before(:each) do
      url = 'https://wush.net/svn/rightscale/cookbooks_test/'
      @repo = RightScale::Repository.from_hash(:display_name => 'wush',
                                               :repo_type    => :svn,
                                               :url          => url,
                                               :first_credential => @username,
                                               :second_credential => @password)
      @scraper = RightScale::NewSvnScraper.new(@repo, max_bytes=1024**2,
                                               max_seconds=20)
    end

    def reopen_scraper
      @scraper.close
      @scraper = RightScale::NewSvnScraper.new(@repo, max_bytes=1024**2,
                                               max_seconds=20)
    end

    after(:each) do
      @scraper.close
    end

    it 'should scrape' do
      first = @scraper.next
      first.should_not == nil
    end

    # quick_start not actually being a cookbook
    it 'should scrape 5 repositories' do
      locations = Set.new
      (1..5).each {|n|
        repo = @scraper.next
        locations << repo.position
        repo.should_not == nil
      }
      @scraper.next.should == nil
      locations.should == Set.new(["cookbooks/app_rails",
                                   "cookbooks/db_mysql",
                                   "cookbooks/repo_git",
                                   "cookbooks/rs_utils",
                                   "cookbooks/web_apache"])
    end
  end if TEST_REMOTE

  context 'given a SVN repository' do
    before(:each) do
      @helper = RightScale::SvnScraperSpecHelper.new
      @repo = @helper.repo
      @scraper = RightScale::NewSvnScraper.new(@repo, max_bytes=1024**2,
                                               max_seconds=20)
    end

    def reopen_scraper
      @scraper.close
      @scraper = RightScale::NewSvnScraper.new(@repo, max_bytes=1024**2,
                                               max_seconds=20)
    end
    
    after(:each) do
      @scraper.close
      @helper.close
    end

    def check_cookbook(cookbook, params={})
      position = params[:position] || "."
      cookbook.should_not == nil
      cookbook.repository.should == @repo
      cookbook.position.should == position
      cookbook.metadata.should == (params[:metadata] || @helper.repo_content)
      root = File.join(params[:rootdir] || @helper.repo_path, position)
      tarball = `tar -C #{root} -c --exclude .svn .`
      # We would compare these literally, but minor metadata changes
      # will completely hose you, so it's enough to make sure that the
      # files are in the same place and have the same content.
      archive_skeleton(cookbook.archive).should ==
        archive_skeleton(tarball)
    end

    it 'should scrape the master branch' do
      check_cookbook @scraper.next
    end

    it 'should only see one cookbook in the simple case' do
      @scraper.next.should_not == nil
      @scraper.next.should == nil
    end

    context 'with multiple cookbooks' do
      def secondary_cookbook(where)
        FileUtils.mkdir_p(where)
        @helper.create_cookbook(where, @helper.repo_content)
      end

      before(:each) do
        @helper.delete(File.join(@helper.repo_path, "metadata.json"))
        @cookbook_places = [File.join(@helper.repo_path, "cookbooks", "first"),
                            File.join(@helper.repo_path, "cookbooks", "second"),
                            File.join(@helper.repo_path, "other_random_place")]
        @cookbook_places.each {|place| secondary_cookbook(place)}
        @helper.commit_content("secondary cookbooks added")
        reopen_scraper
      end
      it 'should scrape' do
        @cookbook_places.each do |place|
          check_cookbook @scraper.next, :position => place[@helper.repo_path.length+1..-1]
        end
      end

      it 'should be able to seek' do
        @scraper.seek "cookbooks/second"
        check_cookbook @scraper.next, :position => "cookbooks/second"
        check_cookbook @scraper.next, :position => "other_random_place"
      end
    end

    context 'and a revision' do
      before(:each) do
        @oldmetadata = @helper.repo_content
        @helper.create_file_layout(@helper.repo_path, @helper.branch_content)
        @helper.commit_content
        @repo.tag = @helper.commit_id(1)
        reopen_scraper
      end

      it 'should scrape a revision' do
        check_cookbook @scraper.next, :metadata => @oldmetadata, :rootdir => @scraper.checkout_path
      end
    end
  end
end
