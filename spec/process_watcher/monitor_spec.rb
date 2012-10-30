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

describe ProcessWatcher::ProcessMonitor do

  before(:each) do
    @monitor = ProcessWatcher::ProcessMonitor.new
  end

  after(:each) do
    @monitor.cleanup
  end

  it 'should launch and watch well-behaved processes' do
    ruby = "puts 42; exit 42"
    times = 0
    pid = @monitor.spawn('ruby', '-e', ruby) do |hash|
      case times
      when 0 then hash.should == {:output => "42\n"}
      when 1 then hash[:exit_code].should == 42
        hash[:exit_status].should_not be_nil
      else fail "Shouldn't see more than two ticks"
      end
      times += 1
    end
    @monitor.cleanup
    lambda { Process.kill(0, pid) }.should raise_exception(Errno::ESRCH)
  end

  it 'should launch processes where we don\'t care about output' do
    ruby = "puts 42; exit 42"
    times = 0
    pid = @monitor.spawn('ruby', '-e', ruby)
    @monitor.cleanup
    lambda { Process.kill(0, pid) }.should raise_exception(Errno::ESRCH)
  end
end