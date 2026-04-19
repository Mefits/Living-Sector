defmodule Simulator.EventsTest do
  use ExUnit.Case, async: true

  alias Simulator.Events

  describe "subscribe/1 and broadcast/3" do
    test "subscriber receives broadcasted events" do
      Events.subscribe("test:topic")

      Events.broadcast("test:topic", :test_event, %{value: 42})

      assert_receive {:test_event, %{value: 42}}
    end

    test "subscriber does not receive events from other topics" do
      Events.subscribe("test:topic_a")

      Events.broadcast("test:topic_b", :other_event, %{})

      refute_receive {:other_event, _}
    end

    test "multiple subscribers receive the same event" do
      parent = self()

      Events.subscribe("test:multi")

      task =
        Task.async(fn ->
          Events.subscribe("test:multi")
          send(parent, :subscribed)

          receive do
            {:multi_event, payload} -> payload
          end
        end)

      # Wait for the task to subscribe
      assert_receive :subscribed

      Events.broadcast("test:multi", :multi_event, %{data: "hello"})

      assert_receive {:multi_event, %{data: "hello"}}
      assert Task.await(task) == %{data: "hello"}
    end
  end

  describe "unsubscribe/1" do
    test "unsubscribed process stops receiving events" do
      Events.subscribe("test:unsub")
      Events.unsubscribe("test:unsub")

      Events.broadcast("test:unsub", :gone, %{})

      refute_receive {:gone, _}
    end
  end
end
