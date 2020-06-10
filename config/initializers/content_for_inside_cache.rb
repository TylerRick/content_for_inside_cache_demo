# config/initializers/content_for_inside_cache.rb

module AbstractController
  class Base
    attr_internal :cached_content_for
  end

  module Caching
    # actionpack/lib/action_controller/caching/fragments.rb
    module Fragments
      module ContentForInsideCache
        def write_fragment(key, content, options = nil)
          return content unless cache_configured?

          key = combined_fragment_cache_key(key)
          instrument_fragment_cache :write_fragment, key do
            # { Changed
            # Note: This may write a hash value instead of a string (removed the to_str). Is that okay?
            # } Changed
            cache_store.write(key, content, options)
          end
          # { Changed
          content.is_a?(Hash) ? content[:_fragment] : content
          # } Changed
        end

        def read_fragment(key, options = nil)
          result = super(key, options)
          if result.is_a?(Hash)
            self.cached_content_for = result.except(:_fragment)
            result = result[:_fragment]
          end

          result.respond_to?(:html_safe) ? result.html_safe : result
        end
      end
      prepend ContentForInsideCache
    end
  end
end

module ActionView
  module Helpers
    module ContentForInsideCache
      # actionview/lib/action_view/helpers/capture_helper.rb
      # module CaptureHelper
        def content_for(name, content = nil, options = {}, &block)
          if content || block_given?
            if block_given?
              options = content if content
              content = capture(&block)
            end
            if content
              # { Added
              # Save so that we can include it in what we cache, if currently inside of a cache block
              if @_content_for_to_cache
                @_content_for_to_cache[name] ||= Array.new
                @_content_for_to_cache[name] << content
              end
              # } Added

              options[:flush] ? @view_flow.set(name, content) : @view_flow.append(name, content)
            end
            nil
          else
            @view_flow.get(name).presence
          end
        end
      # end # module CaptureHelper

      # actionview/lib/action_view/helpers/cache_helper.rb
      # module CacheHelper
        def read_fragment_for(name, options)
          super.tap do
            restore_cached_content_for
          end
        end

        # Called by read_fragment_for
        def restore_cached_content_for
          if controller.try(:perform_caching)
            if controller.cached_content_for.is_a?(Hash)
              controller.cached_content_for.each { |k, v|
                content_for(k, v)
              }
            end
          end
        end

        def cache(name = {}, options = {}, &block)
          # Reset every time we begin a new cache block
          @_content_for_to_cache = Hash.new { |h,k| h[k] = ActiveSupport::SafeBuffer.new }
          super(name, options, &block)
        ensure
          @_content_for_to_cache = Hash.new
        end

        def write_fragment_for(name, options)
          pos = output_buffer.length
          yield
          output_safe = output_buffer.html_safe?
          fragment = output_buffer.slice!(pos..-1)
          if output_safe
            self.output_buffer = output_buffer.class.new(output_buffer)
          end
          # { Changed
          value_to_write = {_fragment: fragment}.merge(@_content_for_to_cache)
          controller.write_fragment(name, value_to_write, options)
          # } Changed
        end
      # end # module CacheHelper

    end # ContentForInsideCache

    prepend ContentForInsideCache
  end # Helpers
end
