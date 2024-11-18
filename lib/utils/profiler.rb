module EmergeCLI
  # NOTE: This class is not thread-safe.
  class Profiler
    def initialize(enabled: false)
      @enabled = enabled
      @measurements = {}
      @start_times = {}
    end

    def measure(label)
      return yield unless @enabled

      start(label)
      result = yield
      stop(label)
      result
    end

    def start(label)
      return unless @enabled
      @start_times[label] = Time.now
    end

    def stop(label)
      return unless @enabled
      return unless @start_times[label]

      duration = Time.now - @start_times[label]
      @measurements[label] ||= { count: 0, total_time: 0 }
      @measurements[label][:count] += 1
      @measurements[label][:total_time] += duration
    end

    def report
      return unless @enabled

      Logger.info '=== Performance Profile ==='
      @measurements.sort_by { |_, v| -v[:total_time] }.each do |label, data|
        avg_time = data[:total_time] / data[:count]
        Logger.info sprintf('%-<label>30s Total: %<total>.2fs  Count: %<count>d  Avg: %<avg>.2fs',
                            label: label,
                            total: data[:total_time],
                            count: data[:count],
                            avg: avg_time)
      end
      Logger.info '=========================='
    end
  end
end
