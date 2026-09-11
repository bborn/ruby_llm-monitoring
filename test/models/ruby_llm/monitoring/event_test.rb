require "test_helper"

module RubyLLM::Monitoring
  class EventTest < ActiveSupport::TestCase
    test "calculates cost for cloud provider" do
      event = Event.create!(
        payload: {
          "provider" => "gemini",
          "model" => "gemini-2.5-flash",
          "input_tokens" => 1000,
          "output_tokens" => 500
        }
      )

      assert_not_nil event.cost
      assert event.cost > 0.0
    end

    test "calculates cost for cloud provider with thinking" do
      event = Event.create!(
        payload: {
          "provider" => "gemini",
          "model" => "gemini-2.5-flash",
          "input_tokens" => 1000,
          "output_tokens" => 500,
          "thinking_tokens" => 400
        }
      )

      assert_not_nil event.cost
      assert event.cost > 0.0
    end

    test "sets cost to zero for local provider" do
      event = ruby_llm_monitoring_events(:ollama_recent)

      assert_equal 0.0, event.cost
    end

    test "sets cost to zero when tokens are nil" do
      event = ruby_llm_monitoring_events(:no_tokens)

      assert_equal 0.0, event.cost
    end

    test "calculates cost with missing output_tokens in payload" do
      assert_nothing_raised do
        Event.create!(
          payload: {
            "model": "gemini-embedding-001",
            "embedding": {
              "model": "gemini-embedding-001",
              "vectors": [],
              "input_tokens": 11
            },
            "dimensions": 3072,
            "input_tokens": 11,
            "vector_count": 1
          }
        )
      end

      assert_not_equal 0.0, Event.last.cost
    end
    test "uses the cost RubyLLM reported for the event" do
      event = Event.create!(
        payload: {
          "provider" => "gemini",
          "model" => "gemini-2.5-flash",
          "input_tokens" => 1000,
          "output_tokens" => 500,
          "cost" => 0.0123
        }
      )

      assert_in_delta 0.0123, event.cost, 1e-9
    end

    test "prices the tokens when RubyLLM could not price the event" do
      priced = Event.create!(
        payload: { "provider" => "gemini", "model" => "gemini-2.5-flash", "input_tokens" => 1000, "output_tokens" => 500 }
      )
      unpriced = Event.create!(
        payload: { "provider" => "gemini", "model" => "gemini-2.5-flash", "input_tokens" => 1000, "output_tokens" => 500, "cost" => nil }
      )

      assert priced.cost > 0.0
      assert_in_delta priced.cost, unpriced.cost, 1e-12
    end

    test "matches RubyLLM's own pricing for the same tokens" do
      tokens = RubyLLM::Tokens.new(input: 1000, output: 500)
      expected = RubyLLM.models.find("gemini-2.5-flash", provider: "gemini").cost_for(tokens).total

      event = Event.create!(
        payload: { "provider" => "gemini", "model" => "gemini-2.5-flash", "input_tokens" => 1000, "output_tokens" => 500 }
      )

      assert_in_delta expected, event.cost, 1e-12
    end

    test "prices what it can when the registry lacks a rate for one component" do
      tokens = RubyLLM::Tokens.new(input: 1200, output: 300, cache_read: 800, cache_write: 50, thinking: 40)
      priced = RubyLLM.models.find("gemini-2.5-flash", provider: "gemini").cost_for(tokens)
      floor = priced.to_h.except(:total).values.sum

      event = Event.create!(
        payload: {
          "provider" => "gemini",
          "model" => "gemini-2.5-flash",
          "input_tokens" => 1200,
          "output_tokens" => 300,
          "cached_tokens" => 800,
          "cache_creation_tokens" => 50,
          "thinking_tokens" => 40
        }
      )

      assert event.cost > 0.0
      assert_in_delta (priced.total || floor), event.cost, 1e-12
    end

    test "sets cost to zero for a model the registry does not know" do
      event = Event.create!(
        payload: { "provider" => "openai", "model" => "not-a-real-model", "input_tokens" => 1000, "output_tokens" => 500 }
      )

      assert_equal 0.0, event.cost
    end
  end
end
