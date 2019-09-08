# frozen_string_literal: true

dev_null = Logger.new('/dev/null')

Rails.logger                 = dev_null
ActiveRecord::Base.logger    = dev_null
ActiveJob::Base.logger       = dev_null
HttpLog.configuration.logger = dev_null
Paperclip.options[:log]      = false

module Mastodon
  module CLIHelper
    def create_progress_bar(total = nil)
      ProgressBar.create(total: total, format: '%c/%u |%b%i| %e')
    end

    def parallelize_with_progress(scope)
      ActiveRecord::Base.configurations[Rails.env]['pool'] = options[:concurrency]

      progress  = create_progress_bar(scope.count)
      pool      = Concurrent::FixedThreadPool.new(options[:concurrency])
      futures   = []
      aggregate = Concurrent::AtomicFixnum.new(0)

      scope.reorder(nil).find_each do |item|
        progress.total = futures.size + 1 if progress.total < futures.size + 1

        futures << Concurrent::Future.execute(executor: pool) do
          ActiveRecord::Base.connection_pool.with_connection do
            begin
              progress.log("Processing #{item.id}") if options[:verbose]

              result = yield(item)
              aggregate.increment(result) if result.is_a?(Integer)
            rescue => e
              progress.log pastel.red("Error processing #{item.id}: #{e}")
            ensure
              progress.increment
            end
          end
        end
      end

      futures.map(&:value)
      progress.finish

      [futures.size, aggregate.value]
    end

    def pastel
      @pastel ||= Pastel.new
    end
  end
end
