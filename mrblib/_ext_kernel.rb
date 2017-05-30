# Concurrently adds a few methods to "Kernel" which makes them available
# for every object.
#
# This is part of the main API of Concurrently.
#
# @api public
module Kernel
  # @!method concurrently(*args, &block)
  #
  # Executes code concurrently in the background.
  #
  # This is a shortcut for {Concurrently::Proc#call_detached!}.
  #
  # @return [nil]
  #
  # @example
  #   concurrently(a,b,c) do |a,b,c|
  #     # ...
  #   end
  def concurrently(*args)
    # Concurrently::Proc.new claims the method's block just like Proc.new does
    Concurrently::Proc.new.call_detached! *args
  end

  # @!method concurrent_proc(&block)
  #
  # Creates a concurrent proc to execute code concurrently.
  #
  # This a shortcut for {Concurrently::Proc}.new like +proc(&block)+
  # is a shortcut for +Proc.new(&block)+.
  #
  # @return [Concurrently::Proc]
  #
  # @example
  #   wait_proc = concurrent_proc do |seconds|
  #      wait seconds
  #   end
  #
  #   wait_proc.call 2 # waits 2 seconds and then resumes
  def concurrent_proc(evaluation_class = Concurrently::Proc::Evaluation) # &block
    # Concurrently::Proc.new claims the method's block just like Proc.new does
    Concurrently::Proc.new(evaluation_class)
  end

  # Suspends the current evaluation until it is resumed manually. It can be
  # used inside and outside of concurrent procs.
  def await_scheduled_resume!(opts = {})
    event_loop = Concurrently::EventLoop.current
    run_queue = event_loop.run_queue
    fiber = Concurrently::EventLoop.current.current_fiber

    if seconds = opts[:within]
      timeout_result = opts.fetch(:timeout_result, Concurrently::Proc::TimeoutError)
      run_queue.schedule_deferred(fiber, seconds, timeout_result)
    end

    result = case fiber
    when Concurrently::Proc::Fiber
      # Yield back to the event loop fiber or the fiber evaluating this one.
      # Pass along itself to indicate it is not yet fully evaluated.
      Fiber.yield fiber
    else
      event_loop.fiber.resume
    end

    # If result is this very fiber it means this fiber has been evaluated
    # prematurely.
    if result == fiber
      run_queue.cancel fiber # in case the fiber has already been scheduled to resume

      # Generally, throw-catch is faster than raise-rescue if the code needs to
      # play back the call stack, i.e. the throw resp. raise is invoked. If not
      # playing back the call stack, a begin block is faster than a catch
      # block. Since we won't jump out of the proc above most of the time, we
      # go with raise. It is rescued in the proc fiber.
      raise Concurrently::Proc::Fiber::Cancelled, '', []
    elsif result == Concurrently::Proc::TimeoutError
      raise Concurrently::Proc::TimeoutError, "evaluation timed out after #{seconds} second(s)"
    else
      result
    end
  ensure
    if seconds
      run_queue.cancel fiber
    end
  end

  # Suspends the current evaluation for the given number of seconds. It can be
  # used inside and outside of concurrent procs.
  #
  # While waiting, the code jumps to the event loop and executes other
  # concurrent procs that are ready to run in the meantime.
  #
  # @return [true]
  #
  # @example Waiting inside a concurrent proc
  #   # Control flow is indicated by (N)
  #
  #   # (1)
  #   wait_proc = concurrent_proc do |seconds|
  #     # (4)
  #     wait seconds
  #     # (6)
  #     :waited
  #   end
  #
  #   # (2)
  #   concurrently do
  #     # (5)
  #     puts "I'm running while the other proc is waiting!"
  #   end
  #
  #   # (3)
  #   wait_proc.call 1 # => :waited
  #   # (7)
  #
  # @example Waiting outside a concurrent proc
  #   # Control flow is indicated by (N)
  #
  #   # (1)
  #   concurrently do
  #     # (3)
  #     puts "I'm running while the outside is waiting!"
  #   end
  #
  #   # (2)
  #   wait 1
  #   # (4)
  def wait(seconds)
    run_queue = Concurrently::EventLoop.current.run_queue
    fiber = Concurrently::EventLoop.current.current_fiber
    run_queue.schedule_deferred(fiber, seconds, true)
    await_scheduled_resume!
  ensure
    run_queue.cancel fiber
  end
end