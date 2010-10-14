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

require 'shellwords'
require File.expand_path(File.join(File.dirname(__FILE__), 'process_watcher', 'watcher'))

# Convenient interface to process watching functionality.
module ProcessWatcher
  # Raised when a subprocess took too much time to run.
  class TimeoutError < RuntimeError
    # Describe the error.
    def to_s
      "Command took too much time"
    end
  end
  # Raised when a subprocess consumed too much space while running.
  class TooMuchSpaceError < RuntimeError
    # Describe the error.
    def to_s
      "Command took too much space"
    end
  end
  # Raised when a subprocess completed, but with a nonzero exit code.
  class NonzeroExitCode < RuntimeError
    # (Fixnum) exit code returned by the subprocess
    attr_reader :exit_code
    # (String) process output (hopefully explaining the situation)
    attr_reader :output

    def initialize(exit_code, output)
      @exit_code = exit_code
      @output = output
    end

    # Describe the error.
    def to_s
      "Exit code nonzero: #{@exit_code}\nOutput was #{@output}"
    end
  end
  # Watch command, respecting +max_bytes+ and +max_seconds+.  Returns
  # the output of the command, with STDOUT and STDERR interleaved, if
  # the command completed successfully.  Will raise one of three
  # errors in exceptional cases:
  # TimeoutError:: if the process takes longer than max_seconds to run
  # TooMuchSpaceError:: if the process consumes too much space in +dir+
  # NonzeroExitCode:: if the process exits, but with a nonzero exit code
  #
  # This method accepts a block.  If that block exists, it is called
  # at most twice with three arguments, +phase+, +command+ and
  # +exception+.  The block is called once with +phase+ set to :begin,
  # +command+ describing the command run, and +exception+ being nil.
  # If execution completes normally, the block is called with +phase+
  # set to :commit, +command+ again describing the command, and
  # +exception+ nil.  If an abnormal termination occurs (for example,
  # running out of space), the block is called with +phase+ set to
  # :abort, +command+ again describing the command and +exception+ set
  # to the exception in question.
  #
  # === Parameters
  # command(String):: command to run
  # args(Array):: arguments for the command
  # dir(String):: directory to monitor (defaults to '.')
  # max_bytes(Integer):: maximum number of bytes to permit
  #                      (defaults to no restriction)
  # max_seconds(Integer):: maximum number of seconds to permit to run
  #                        (defaults to no restriction)
  #
  # === Block parameters
  # phase(Keyword):: one of :begin, :commit, or :abort
  # command(String):: description of what command is being run and
  #                   where it is being run
  # exception(Exception):: if non nil, the exception raised during
  #                        the running of the subprocess
  #
  # === Returns
  # String:: output of command
  def self.watch(command, args, dir='.', max_bytes=-1, max_seconds=-1) # :yields: phase, command, exception
    watcher = ProcessWatcher::Watcher.new(max_bytes, max_seconds)
    text = "in #{dir}, running #{command} #{Shellwords.join(args)}"
    block_given? and yield :begin, text, nil
    begin
      result = watcher.launch_and_watch(command, args, dir)
      if result.status == :timeout
        raise TimeoutError, "command took too much time"
      elsif result.status == :size_exceeded
        raise TooMuchSpaceError, "command took too much space"
      elsif result.exit_code != 0
        raise NonzeroExitCode.new(result.exit_code, result.output), "nonzero exit code"
      else
        result.output
      end
    rescue => e
      block_given? and yield :abort, text, e
      raise
    else
      block_given? and yield :commit, text, nil
      result.output
    end
  end

  # Spawn given process, wait for it to complete, and return its
  # output and the exit status of the process. Functions similarly to
  # the backtick operator, only it avoids invoking the command
  # interpreter under operating systems that support fork-and-exec.
  #
  # This method accepts a variable number of parameters; the first
  # param is always the command to run; successive parameters are
  # command-line arguments for the process.
  #
  # === Parameters
  # cmd(String):: Name of the command to run
  # arg1(String):: Optional, first command-line argumument
  # arg2(String):: Optional, first command-line argumument
  # ...
  # argN(String):: Optional, Nth command-line argumument
  #
  # === Return
  # output(String):: The process's output
  # status(Process::Status):: The process's exit status
  def self.run(cmd, *args)
    pm = ProcessWatcher::ProcessMonitor.new
    status = nil
    output = StringIO.new

    pm.spawn(cmd, *args) do |options|
      output << options[:output] if options[:output]
      status = options[:exit_status] if options[:exit_status]
    end

    pm.cleanup
    output.close
    output = output.string
    return [output, status]
  end
end
