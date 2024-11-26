require 'logger'
require 'colored2'

module EmergeCLI
  class Logger
    class << self
      def configure(log_level)
        logger.level = log_level
      end

      def info(message)
        log(:info, message)
      end

      def warn(message)
        log(:warn, message)
      end

      def error(message)
        log(:error, message)
      end

      def debug(message)
        log(:debug, message)
      end

      private

      def logger
        @logger ||= create_logger
      end

      def create_logger
        logger = ::Logger.new(STDOUT)
        logger.formatter = proc do |severity, datetime, _progname, msg|
          timestamp = datetime.strftime('%Y-%m-%d %H:%M:%S.%L')
          formatted_severity = severity.ljust(5)
          colored_message = case severity
                            when 'INFO'
                              msg.to_s.white
                            when 'WARN'
                              msg.to_s.yellow
                            when 'ERROR'
                              msg.to_s.red
                            when 'DEBUG'
                              msg.to_s.light_blue
                            else
                              msg.to_s
                            end
          "[#{timestamp}] #{formatted_severity} -- : #{colored_message}\n"
        end
        logger
      end

      def log(level, message)
        logger.send(level, message)
      end
    end
  end
end
