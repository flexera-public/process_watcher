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

module ProcessWatcher
  # *nix specific watcher implementation
  class ProcessMonitor
    # Spawn given process and callback given block with output and exit code. This method
    # accepts a variable number of parameters; the first param is always the command to
    # run; successive parameters are command-line arguments for the process.
    #
    # === Parameters
    # cmd(String):: Name of the command to run
    # arg1(String):: Optional, first command-line argumument
    # arg2(String):: Optional, first command-line argumument
    # ...
    # argN(String):: Optional, Nth command-line argumument
    #
    # === Block
    # Given block should take one argument which is a hash which may contain
    # the keys :output and :exit_code. The value associated with :output is a chunk
    # of output while the value associated with :exit_code is the process exit code
    # This block won't be called anymore once the :exit_code key has associated value
    #
    # === Return
    # pid(Integer):: Spawned process pid
    def spawn(cmd, *args)
      args = args.map { |a| a.to_s } #exec only likes string arguments

      # Run subprocess using synchronous pipes.
      stdin_r,  stdin_w  = IO.pipe
      stdout_r, stdout_w = IO.pipe
      stderr_r, stderr_w = IO.pipe

      [stdin_r, stdin_w,
       stdout_r, stdout_w,
       stderr_r, stderr_w].each {|fdes| fdes.sync = true}

      pid = fork do
        stdin_w.close
        STDIN.reopen stdin_r

        stdout_r.close
        STDOUT.reopen stdout_w

        stderr_r.close
        STDERR.reopen stderr_w

        ObjectSpace.each_object(IO) do |io|
          if ![STDIN, STDOUT, STDERR].include?(io)
            io.close unless io.closed?
          end
        end

        begin
          exec(cmd, *args)
          raise 'should not get here'
        rescue
          STDERR.puts "Couldn't exec: #{$!}"
        end
        exit!
      end

      # Monitor subprocess output and status in a dedicated thread
      stdin_r.close
      stdin_w.close  # not supporting input streaming; close immediately
      stdout_w.close
      stderr_w.close
      @pid    = pid
      @reader = Thread.new do
        # note that calling IO.select on pipes which have already had all
        # of their output consumed can cause segfault (in Ubuntu?) so it is
        # important to keep track of when all I/O has been consumed.
        stdout_finished = false
        stderr_finished = false
        status = nil
        while !(stdout_finished && stderr_finished)
          begin
            channels_to_watch = []
            channels_to_watch << stdout_r unless stdout_finished
            channels_to_watch << stderr_r unless stderr_finished
            ready = IO.select(channels_to_watch, nil, nil, 0.1) rescue nil
          rescue Errno::EAGAIN
          ensure
            status = Process.waitpid2(pid, Process::WNOHANG)
            if status
              stdout_finished = true
              stderr_finished = true
            end
          end

          if ready && ready.first.include?(stdout_r)
            line = status ? stdout_r.gets(nil) : stdout_r.gets
            if line
              yield(:output => line) if block_given?
            else
              stdout_finished = true
            end
          end
          if ready && ready.first.include?(stderr_r)
            line = status ? stderr_r.gets(nil) : stderr_r.gets
            if line
              yield(:output => line) if block_given?
            else
              stderr_finished = true
            end
          end
        end
        status = Process.waitpid2(pid) if status.nil?
        yield(:exit_code => status[1].exitstatus, :exit_status => status[1]) if block_given?
      end

      return @pid
    end

    # Close io and join reader thread
    #
    # === Return
    # true:: Always return true
    def cleanup
      @reader.join if @reader
    ensure
      @reader = nil
    end

  end
end
