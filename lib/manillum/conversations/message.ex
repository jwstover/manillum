defmodule Manillum.Conversations.Message do
  use Ash.Resource,
    otp_app: :manillum,
    domain: Manillum.Conversations,
    extensions: [AshOban],
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  oban do
    triggers do
      trigger :respond do
        actor_persister Manillum.AiAgentActorPersister
        action :respond
        queue :chat_responses
        lock_for_update? false
        scheduler_cron false
        worker_module_name Manillum.Conversations.Message.Workers.Respond
        scheduler_module_name Manillum.Conversations.Message.Schedulers.Respond
        where expr(needs_response)
      end
    end
  end

  postgres do
    table "messages"
    repo Manillum.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :for_conversation do
      pagination keyset?: true, required?: false
      argument :conversation_id, :uuid, allow_nil?: false

      prepare build(default_sort: [inserted_at: :desc])
      filter expr(conversation_id == ^arg(:conversation_id))
    end

    create :create do
      accept [:content]

      validate match(:content, ~r/\S/) do
        message "Message cannot be empty"
      end

      argument :conversation_id, :uuid do
        public? false
      end

      change Manillum.Conversations.Message.Changes.CreateConversationIfNotProvided
      change run_oban_trigger(:respond)
    end

    update :respond do
      accept []
      require_atomic? false
      transaction? false
      change Manillum.Conversations.Message.Changes.Respond
    end

    create :upsert_response do
      upsert? true
      accept [:id, :response_to_id, :conversation_id]
      argument :complete, :boolean, default: false

      argument :content, :string,
        allow_nil?: false,
        constraints: [trim?: false, allow_empty?: true]

      argument :tool_calls, {:array, :map}
      argument :tool_results, {:array, :map}

      # if updating
      #   if complete, set the content to the provided content
      #   if streaming still, append the chunk to the existing content
      change atomic_update(
               :content,
               {:atomic,
                expr(
                  if ^arg(:complete) do
                    ^arg(:content)
                  else
                    content <> ^arg(:content)
                  end
                )}
             )

      change atomic_update(
               :tool_calls,
               {:atomic,
                expr(
                  if not is_nil(^arg(:tool_calls)) do
                    fragment(
                      "? || ?",
                      tool_calls,
                      type(
                        ^arg(:tool_calls),
                        {:array, :map}
                      )
                    )
                  else
                    tool_calls
                  end
                )}
             )

      change atomic_update(
               :tool_results,
               {:atomic,
                expr(
                  if not is_nil(^arg(:tool_results)) do
                    fragment(
                      "? || ?",
                      tool_results,
                      type(
                        ^arg(:tool_results),
                        {:array, :map}
                      )
                    )
                  else
                    tool_results
                  end
                )}
             )

      # if creating, set the content attribute to the provided content
      change set_attribute(:content, arg(:content))
      change set_attribute(:complete, arg(:complete))
      change set_attribute(:role, :assistant)
      change set_attribute(:tool_results, arg(:tool_results))
      change set_attribute(:tool_calls, arg(:tool_calls))

      # on update, only set complete to its new value
      upsert_fields [:complete]
    end
  end

  pub_sub do
    module ManillumWeb.Endpoint
    prefix "chat"

    publish :create, ["messages", :conversation_id] do
      transform fn %{data: message} ->
        %{
          content: message.content,
          id: message.id,
          role: message.role,
          complete: message.complete,
          tool_calls: message.tool_calls,
          tool_results: message.tool_results
        }
      end
    end

    publish :upsert_response, ["messages", :conversation_id] do
      transform fn %{data: message} ->
        %{
          content: message.content,
          id: message.id,
          role: message.role,
          complete: message.complete,
          tool_calls: message.tool_calls,
          tool_results: message.tool_results
        }
      end
    end
  end

  attributes do
    timestamps()
    uuid_v7_primary_key :id, writable?: true

    attribute :content, :string do
      constraints allow_empty?: true, trim?: false
      public? true
      allow_nil? false
    end

    attribute :tool_calls, {:array, :map}
    attribute :tool_results, {:array, :map}

    attribute :role, Manillum.Conversations.Message.Types.Role do
      allow_nil? false
      public? true
      default :user
    end

    attribute :complete, :boolean do
      allow_nil? false
      default true
    end
  end

  relationships do
    belongs_to :conversation, Manillum.Conversations.Conversation do
      public? true
      allow_nil? false
    end

    belongs_to :response_to, __MODULE__ do
      public? true
    end

    has_one :response, __MODULE__ do
      public? true
      destination_attribute :response_to_id
    end
  end

  calculations do
    calculate :needs_response, :boolean do
      calculation expr(role == :user and not exists(response))
    end
  end
end
