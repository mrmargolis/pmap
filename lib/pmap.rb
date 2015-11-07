require 'thread' unless defined?(Mutex)
require_relative "pmap/thread_pool"

# Global variable for the default thread pool size.
$pmap_default_thread_count ||= 64

module PMap
  class DummyOutput
    def []=(idx, val)
    end
  end

  def self.included(base)
    base.class_eval do
      # Parallel "map" for any Enumerable.
      # Requires a block of code to run for each Enumerable item.
      # [thread_count] is number of threads to create. Optional.
      def pmap(thread_count=nil, &proc)
        in_array = self.to_a        # I'm not sure how expensive this is...
        out_array = Array.new(in_array.size)
        process_core(thread_count, in_array, out_array, &proc)
        out_array
      end

      def process_core(thread_count, in_array, out_array, &proc)
        thread_count = thread_count(thread_count, in_array)
        size = in_array.size

        semaphore = Mutex.new
        index = -1                  # Our use of index is protected by semaphore

        threads = (0...thread_count).map {
          Thread.new {
            i = nil
            while (semaphore.synchronize {i = (index += 1)}; i < size)
              out_array[i] = yield(in_array[i])
            end
          }
        }
        threads.each {|t| t.join}
      end
      private :process_core

      def thread_count(user_requested_count, items)
        user_requested_count ||= $pmap_default_thread_count
        raise ArgumentError, "thread_count must be at least one." unless
          user_requested_count.respond_to?(:>=) && user_requested_count >= 1
        [user_requested_count, items.size].min
      end
      private :thread_count

      # Parallel "each" for any Enumerable.
      # Requires a block of code to run for each Enumerable item.
      # [thread_count] is number of threads to create. Optional.
      def peach(thread_count=nil, &proc)
        peach_with_index(thread_count) do |item, index|
          proc.call(item)
        end
        self
      end

      # Public: Parallel each_with_index for any Enumerable
      #
      # thread_count - maximum number of threads to create (optional)
      #
      def peach_with_index(thread_count=nil, &proc)
        thread_count ||= $pmap_default_thread_count
        pool = ThreadPool.new(thread_count)

        each_with_index do |item, index|
          pool.schedule(item, index, &proc)
        end
        pool.shutdown
        self
      end
    end
  end
end

module Enumerable
  include PMap
end
