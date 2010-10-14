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

require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

describe ProcessWatcher do
  before(:each) do
    @dest_dir = File.join(File.dirname(__FILE__), '__destdir')
    FileUtils.mkdir_p(@dest_dir)
  end

  after(:each) do
    FileUtils.rm_rf(@dest_dir)
  end

  context :watch do
    it 'should launch and watch well-behaved processes' do
      ruby = "trap('INT', 'IGNORE'); puts 42; exit 0"
      ProcessWatcher.watch("ruby", ["-e", ruby]).should == "42\n"
    end

    it 'should call the block as appropriate' do
      ruby = "trap('INT', 'IGNORE'); puts 42; exit 0"
      times = 0
      ProcessWatcher.watch("ruby", ["-e", ruby], @dest_dir) { |type, text|
        case times
        when 0 then type.should == :begin
        when 1 then type.should == :commit
        else fail_with("callback should only be called twice", nil, times)
        end
        times += 1
        text.should =~ /^in #{Regexp.escape(@dest_dir)}, running ruby -e #{Regexp.escape(Shellwords.escape(ruby))}/
      }.should == "42\n"
    end

    it 'should report weird error codes' do
      ruby = "trap('INT', 'IGNORE'); puts 42; exit 42"
      lambda {
        ProcessWatcher.watch("ruby", ["-e", ruby], @dest_dir, 1, 2)
      }.should raise_exception(ProcessWatcher::NonzeroExitCode) {|e| e.exit_code.should == 42}
    end

    it 'should report timeouts' do
      ruby = "trap('INT', 'IGNORE'); puts 42; sleep 5"
      lambda {
        ProcessWatcher.watch("ruby", ["-e", ruby], @dest_dir, 1, 2)
      }.should raise_exception(ProcessWatcher::TimeoutError)
    end

    it 'should report size exceeded' do
      ruby = "trap('INT', 'IGNORE'); STDOUT.sync = true; puts 42; File.open" +
        "(File.join('#{@dest_dir}', 'test'), 'w') { |f| f.puts 'MORE THAN 2 CHARS' }; sleep 5 rescue nil"
      lambda {
        ProcessWatcher.watch("ruby", ["-e", ruby], @dest_dir, 1, -1)
      }.should raise_exception(ProcessWatcher::TooMuchSpaceError)
    end

    it 'should allow infinite size and timeout' do
      ruby = "trap('INT', 'IGNORE'); STDOUT.sync = true; puts 42; " +
        "File.open(File.join('#{@dest_dir}', 'test'), 'w') { |f| " +
        "f.puts 'MORE THAN 2 CHARS' }; sleep 2 rescue nil"
      ProcessWatcher.watch("ruby", ["-e", ruby]).should == "42\n"
    end

    it 'should permit array arguments' do
      ProcessWatcher.watch("echo", ["$HOME", ";", "echo", "broken"]).should == "$HOME ; echo broken\n"
    end
  end

  context :run do
    it 'should launch well-behaved processes' do
      ruby = "trap('INT', 'IGNORE'); puts 42; exit 0"
      output, status = ProcessWatcher.run("ruby", "-e", ruby)
      output.should == "42\n"
      status.exitstatus.should == 0
    end

    it 'should record weird error codes in $?' do
      ruby = "trap('INT', 'IGNORE'); puts 42; exit 42"
      output, status = ProcessWatcher.run("ruby", "-e", ruby)
      output.should == "42\n"
      status.exitstatus.should == 42
    end

    it 'should run in the current directory' do
      ruby = "trap('INT', 'IGNORE'); puts File.expand_path('.')"
      output, status = ProcessWatcher.run("ruby", "-e", ruby)
      output.should == File.expand_path('.') + "\n"
      status.exitstatus.should == 0
    end
  end
end
