Object.__send__(:remove_const, :IOEventLoop) if Object.const_defined? :IOEventLoop

class IOEventLoop
  include CallbacksAttachable

  def initialize(*)
    @wall_clock = WallClock.new

    @running = false
    @stop_and_raise_error = on(:error) { |_,e| stop CancelledError.new(e) }

    @run_queue = RunQueue.new self
    @readers = {}
    @writers = {}
  end

  def forgive_iteration_errors!
    @stop_and_raise_error.cancel
  end

  attr_reader :wall_clock


  # Flow control

  def start
    @running = true

    while @running
      if (waiting_time = @run_queue.waiting_time) == 0
        @run_queue.run_pending
      elsif @readers.any? or @writers.any? or waiting_time
        if selected = IO.select(@readers.keys, @writers.keys, nil, waiting_time)
          selected[0].each{ |readable_io| @readers[readable_io].call } unless selected[0].empty?
          selected[1].each{ |writable_io| @writers[writable_io].call } unless selected[1].empty?
        end
      else
        @running = false # would block indefinitely otherwise
      end
    end

    (CancelledError === @result) ? raise(@result) : @result
  end

  def stop(result = nil)
    @running = false
    @result = result
  end

  def running?
    @running
  end

  def concurrently(opts = {}) # &block
    concurrency = Concurrency.new(self, @run_queue){ yield }
    concurrency.schedule_in opts.fetch(:after, 0)
    Concurrency::Future.new concurrency, @run_queue
  end

  def concurrently_wait(seconds)
    @run_queue.schedule_in Fiber.current, seconds
    Fiber.yield
  end


  # Readable IO

  def attach_reader(io, &on_readable)
    @readers[io] = on_readable
  end

  def detach_reader(io)
    @readers.delete(io)
  end

  def concurrently_readable(io) # &block
    concurrency = Concurrency.new(self, @run_queue){ yield }
    Concurrency::ReadabilityFuture.new concurrency, @run_queue, io
  end


  # Writable IO

  def attach_writer(io, &on_writable)
    @writers[io] = on_writable
  end

  def detach_writer(io)
    @writers.delete(io)
  end

  def concurrently_writable(io) # &block
    concurrency = Concurrency.new(self, @run_queue){ yield }
    Concurrency::WritabilityFuture.new concurrency, @run_queue, io
  end


  # Watching events

  def watch_events(*args)
    EventWatcher.new(self, *args)
  end
end