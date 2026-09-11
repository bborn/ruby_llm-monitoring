module RubyLLM
  module Monitoring
    class EventSubscriber
      FILTERED_PAYLOAD_KEYS = %i[
        chat
        input_messages
        messages_after
        model_info
        response
        result
        result_content
        schema
        tool
        tool_call
        tool_calls
      ].freeze

      # RubyLLM 2.0 reports usage as a RubyLLM::Tokens value under :tokens. The
      # generated columns (and every dashboard built on them) read flat
      # payload keys, so the value is flattened into the names 1.x used.
      TOKEN_FIELDS = {
        input: :input_tokens,
        output: :output_tokens,
        cache_read: :cached_tokens,
        cache_write: :cache_creation_tokens,
        thinking: :thinking_tokens
      }.freeze

      def call(event)
        return if RubyLLM::Monitoring.ignored_events.include?(event.name)

        Event.create(attributes_for(event))
      end

      def attributes_for(event)
        {
          allocations: event.allocations,
          cpu_time: event.cpu_time,
          duration: event.duration,
          end: event.end,
          gc_time: event.gc_time,
          idle_time: event.idle_time,
          name: event.name,
          payload: normalize_payload(event.payload || {}),
          time: event.time,
          transaction_id: event.transaction_id
        }
      end

      private

      def normalize_payload(payload)
        payload = payload.except(*FILTERED_PAYLOAD_KEYS)
        tokens = payload.delete(:tokens)
        payload = flatten_tokens(tokens).merge(payload) if tokens.respond_to?(:input)
        payload[:cost] = cost_total(payload[:cost]) if payload.key?(:cost)
        payload.compact
      end

      # Explicit keys already in the payload win, so an emitter that reports
      # its own flat counts is never overwritten by an empty Tokens value.
      def flatten_tokens(tokens)
        TOKEN_FIELDS.to_h { |reader, key| [ key, tokens.public_send(reader) ] }.compact
      end

      # A RubyLLM::Cost is stored as its total. Unknown pricing is nil, not
      # zero, so Event#set_cost can still price the tokens from the registry.
      def cost_total(cost)
        cost.respond_to?(:total) ? cost.total : cost
      end
    end
  end
end
