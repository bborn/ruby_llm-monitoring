require "test_helper"

module RubyLLM::Monitoring
  class EventSubscriberTest < ActiveSupport::TestCase
    test "creates event when chat is completed" do
      VCR.use_cassette "event_subscriber_test_creates_event_when_chat_is_completed" do
        chat = RubyLLM.chat provider: "ollama", model: "gemma3"

        before_count = Event.count
        chat.ask "what's 1 + 1?"
        assert_operator Event.count, :>, before_count

        assert Event.exists?(name: "chat.ruby_llm")
      end
    end

    test "creates event from notification event" do
      notification_event = ActiveSupport::Notifications::Event.new(
        "chat.ruby_llm",
        Time.current,
        Time.current + 1.second,
        "transaction-123",
        { provider: "ollama", model: "gemma3", input_tokens: 100, output_tokens: 50 }
      )

      assert_difference "Event.count", 1 do
        EventSubscriber.new.call(notification_event)
      end

      event = Event.last
      assert_equal "chat.ruby_llm", event.name
      assert_equal "transaction-123", event.transaction_id
      assert_equal "ollama", event.payload["provider"]
    end

    test "extracts exception from payload" do
      notification_event = ActiveSupport::Notifications::Event.new(
        "chat.ruby_llm",
        Time.current,
        Time.current + 1.second,
        "transaction-456",
        { provider: "ollama", model: "gemma3", exception: [ "StandardError", "Something went wrong" ] }
      )

      assert_difference "Event.count", 1 do
        EventSubscriber.new.call(notification_event)
      end

      event = Event.last
      assert_equal "StandardError", event.exception_class
      assert_equal "Something went wrong", event.exception_message
    end

    test "handles payload with chat messages containing attachments" do
      VCR.use_cassette "event_subscriber_test_cleans_event_payload_when_chat_is_completed" do
        RubyLLM::Chat.new(model: "gemini-3-pro-image-preview").ask("Remove the purse from the model.", with: [ "https://app-cdn.osello.com/u/image_asset/oimg_1sEDBYq08L/upload/4d80ce71943f8ae131bf64605ad01f5e" ])

        event = Event.find_by!(name: "chat.ruby_llm")
        assert event.payload["chat"].blank?
        assert event.payload["input_messages"].blank?
        assert event.payload["messages_after"].blank?
      end
    end
    test "flattens RubyLLM 2.0 tokens and cost into the payload" do
      tokens = RubyLLM::Tokens.new(input: 1200, output: 300, cache_read: 800, cache_write: 50, thinking: 40)
      cost = RubyLLM::Cost.from_h({ input: 0.001, output: 0.002, total: 0.003 }, tokens: tokens)
      notification_event = ActiveSupport::Notifications::Event.new(
        "chat.ruby_llm",
        Time.current,
        Time.current + 1.second,
        "transaction-789",
        { provider: "gemini", model: "gemini-2.5-flash", tokens: tokens, cost: cost }
      )

      EventSubscriber.new.call(notification_event)

      event = Event.last
      assert_equal 1200, event.payload["input_tokens"]
      assert_equal 300, event.payload["output_tokens"]
      assert_equal 800, event.payload["cached_tokens"]
      assert_equal 50, event.payload["cache_creation_tokens"]
      assert_equal 40, event.payload["thinking_tokens"]
      assert_nil event.payload["tokens"]
      assert_in_delta 0.003, event.payload["cost"], 1e-12
      assert_in_delta 0.003, event.cost, 1e-12
    end

    test "keeps flat token counts an emitter reported itself" do
      notification_event = ActiveSupport::Notifications::Event.new(
        "chat.ruby_llm",
        Time.current,
        Time.current + 1.second,
        "transaction-790",
        { provider: "gemini", model: "gemini-2.5-flash", input_tokens: 10, output_tokens: 5, tokens: RubyLLM::Tokens.new }
      )

      EventSubscriber.new.call(notification_event)

      assert_equal 10, Event.last.payload["input_tokens"]
      assert_equal 5, Event.last.payload["output_tokens"]
    end

    test "does not store ignored events" do
      notification_event = ActiveSupport::Notifications::Event.new(
        "usage.ruby_llm",
        Time.current,
        Time.current + 1.second,
        "transaction-791",
        { provider: "gemini", model: "gemini-2.5-flash", tokens: RubyLLM::Tokens.new(input: 1, output: 1) }
      )

      assert_no_difference "Event.count" do
        EventSubscriber.new.call(notification_event)
      end
    end

    test "filters tool results out of the stored payload" do
      notification_event = ActiveSupport::Notifications::Event.new(
        "tool_call.ruby_llm",
        Time.current,
        Time.current + 1.second,
        "transaction-792",
        { provider: "gemini", model: "gemini-2.5-flash", tool_name: "weather", result: "sunny", result_content: "sunny" }
      )

      EventSubscriber.new.call(notification_event)

      payload = Event.last.payload
      assert_equal "weather", payload["tool_name"]
      assert_nil payload["result"]
      assert_nil payload["result_content"]
    end
  end
end
