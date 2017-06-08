#!/bin/env ruby

require_relative "_shared/stage"

stage = Stage.new

conproc = concurrent_proc{}

result = stage.measure(seconds: 1, profiler: RubyProf::FlatPrinter) do
  conproc.call_nonblock
end

puts "#{result[:iterations]} iterations executed in #{result[:time].round 4} seconds"