defmodule ManillumWeb.ManillumComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ManillumWeb.ManillumComponents

  describe "format_event_date/1 and /3" do
    test "year-only renders the bare year" do
      assert format_event_date(%{year: 1066}) == "1066"
      assert format_event_date(1066, nil, nil) == "1066"
    end

    test "month adds the month name before the year" do
      assert format_event_date(%{year: 1066, month: 10}) == "October 1066"
      assert format_event_date(1066, 10, nil) == "October 1066"
    end

    test "day adds the day in front of the month name" do
      assert format_event_date(%{year: 1066, month: 10, day: 14}) == "14 October 1066"
      assert format_event_date(1066, 10, 14) == "14 October 1066"
    end

    test "BC years render with a BC suffix and a positive magnitude" do
      assert format_event_date(%{year: -753}) == "753 BC"
      assert format_event_date(%{year: -44, month: 3, day: 15}) == "15 March 44 BC"
      assert format_event_date(%{year: -44, month: 3}) == "March 44 BC"
    end

    test "all twelve month names are spelled correctly" do
      for {m, name} <- [
            {1, "January"},
            {2, "February"},
            {3, "March"},
            {4, "April"},
            {5, "May"},
            {6, "June"},
            {7, "July"},
            {8, "August"},
            {9, "September"},
            {10, "October"},
            {11, "November"},
            {12, "December"}
          ] do
        assert format_event_date(2000, m, nil) == "#{name} 2000"
      end
    end
  end

  describe "era_band/1 with events" do
    test "renders nothing extra when events is empty" do
      html = render_component(&era_band/1, %{events: []})
      refute html =~ "era_band__event"
    end

    test "renders one mark per event with the right tooltip text" do
      events = [
        %{
          id: "1",
          year: 1066,
          month: 10,
          day: 14,
          title: "Battle of Hastings",
          summary: "William defeats Harold."
        },
        %{
          id: "2",
          year: -44,
          month: 3,
          day: 15,
          title: "Assassination of Caesar"
        },
        %{id: "3", year: 1969, title: "Apollo 11"}
      ]

      html = render_component(&era_band/1, %{events: events})

      # Three marks
      marks = Regex.scan(~r/class="era_band__event"/, html)
      assert length(marks) == 3

      # Header splits year + AD/BC + era; subtitle carries day+month
      assert html =~ ~s(<span class="era_band__event-year">1066</span>)
      assert html =~ "AD · MIDDLE AGES"
      assert html =~ "14 October"
      assert html =~ "Battle of Hastings"
      assert html =~ "William defeats Harold."

      assert html =~ ~s(<span class="era_band__event-year">44</span>)
      assert html =~ "BC · CLASSICAL"
      assert html =~ "15 March"
      assert html =~ "Assassination of Caesar"

      assert html =~ ~s(<span class="era_band__event-year">1969</span>)
      assert html =~ "Apollo 11"

      # Click target navigates to the source message via fragment id
      # (only present when the event has a :message_id; these don't, so absent)
      refute html =~ "href=\"#message-"
    end

    test "renders an anchor href when a mention has message_id" do
      events = [
        %{
          id: "1",
          year: 1066,
          title: "Battle of Hastings",
          message_id: "msg-abc-123"
        }
      ]

      html = render_component(&era_band/1, %{events: events})

      assert html =~ ~s(href="#message-msg-abc-123")
    end

    test "anchors the tooltip to the band edge for marks near the boundary" do
      # 'Now' era ends at the current year — pick a year far in the future
      # for right-edge anchoring; for left-edge, use the very oldest era.
      events = [
        %{id: "left", year: -3000, title: "Beginning"},
        %{id: "right", year: 2026, title: "Today"}
      ]

      html = render_component(&era_band/1, %{events: events})

      assert html =~ "era_band__event-tooltip--left"
      assert html =~ "era_band__event-tooltip--right"
    end

    test "skips events without a year (defensive — malformed payloads)" do
      events = [
        %{id: "good", year: 1066, title: "Hastings"},
        %{id: "missing-year", title: "Floating"}
      ]

      html = render_component(&era_band/1, %{events: events})

      marks = Regex.scan(~r/class="era_band__event"/, html)
      assert length(marks) == 1
      assert html =~ "Hastings"
      refute html =~ "Floating"
    end
  end
end
