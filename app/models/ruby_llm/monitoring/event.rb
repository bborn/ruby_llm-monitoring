module RubyLLM::Monitoring
  class Event < ApplicationRecord
    include Alertable

    before_validation :set_cost

    private

    # RubyLLM 2.0 prices the operation itself (provider-reported amounts first,
    # then the registry, cache and thinking rates included) and the subscriber
    # stores that total as payload["cost"]. Use it when present.
    #
    # Otherwise price the tokens from the registry. RubyLLM's total is nil
    # whenever ANY used component lacks a price (a model with no cache-write
    # rate, say), which would record a paid call as free; sum the components
    # that are priced instead. That is a floor, as the 1.x calculation was.
    def set_cost
      reported = payload["cost"]
      return self.cost = reported.to_f if reported.is_a?(Numeric)

      tokens = RubyLLM::Tokens.new(
        input: payload["input_tokens"],
        output: payload["output_tokens"],
        cache_read: payload["cached_tokens"],
        cache_write: payload["cache_creation_tokens"],
        thinking: payload["thinking_tokens"]
      )
      return self.cost = 0.0 if [ tokens.input, tokens.output ].all?(nil)

      # find, not resolve: resolve instantiates the provider, which raises when
      # its API key lives only in a RubyLLM.context rather than global config.
      model = RubyLLM.models.find(payload["model"], provider: payload["provider"])
      priced = model.cost_for(tokens)
      self.cost = (priced.total || priced.to_h.except(:total).values.sum).to_f
    rescue RubyLLM::ModelNotFoundError
      self.cost = 0.0
    end
  end
end
