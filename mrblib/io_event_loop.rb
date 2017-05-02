Object.__send__(:remove_const, :IOEventLoop) if Object.const_defined? :IOEventLoop

class IOEventLoop < FiberedEventLoop
  def initialize(*)
    @timers = Timers.new
    @result_timers = {}
    @readers = {}
    @writers = {}

    super do
      if (waiting_time = @timers.waiting_time) == 0
        @timers.triggerable.reverse_each(&:trigger)
      elsif waiting_time or @readers.any? or @writers.any?
        if selected = IO.select(@readers.keys, @writers.keys, nil, waiting_time)
          selected[0].each{ |readable_io| @readers[readable_io].call } unless selected[0].empty?
          selected[1].each{ |writable_io| @writers[writable_io].call } unless selected[1].empty?
        end
      else
        stop # would block indefinitely otherwise
      end
    end
  end

  attr_reader :timers

  def attach_reader(io, &on_readable)
    @readers[io] = on_readable
  end

  def attach_writer(io, &on_writable)
    @writers[io] = on_writable
  end

  def detach_reader(io)
    @readers.delete(io)
  end

  def detach_writer(io)
    @writers.delete(io)
  end

  def await(id, opts = {})
    if timeout = opts.fetch(:within, false)
      timeout_result = opts.fetch(:timeout_result, IOEventLoop::TimeoutError.new("waiting timed out after #{timeout} second(s)"))
      @result_timers[id] = @timers.after(timeout){ resume(id, timeout_result) }
    end
    super id
  end

  def resume(id, result)
    @result_timers.delete(id).cancel if @result_timers.key? id
    super
  end

  def await_readable(io, *args, &block)
    attach_reader(io) { detach_reader(io); resume(io, :readable) }
    await io, *args, &block
  end

  def awaits_readable?(io)
    @readers.key? io and awaits? io
  end

  def cancel_awaiting_readable(io)
    if awaits_readable? io
      detach_reader(io)
      resume(io, :cancelled)
    end
  end

  def await_writable(io, *args, &block)
    attach_writer(io) { detach_writer(io); resume(io, :writable) }
    await io, *args, &block
  end

  def awaits_writable?(io)
    @writers.key? io and awaits? io
  end

  def cancel_awaiting_writable(io)
    if awaits_writable? io
      detach_writer(io)
      resume(io, :cancelled)
    end
  end
end