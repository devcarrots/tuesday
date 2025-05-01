defmodule Tuesday.Projects.Comment do
  require Ash.Query

  use Ash.Resource,
    domain: Tuesday.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "comments"
    repo Tuesday.Repo
  end

  resource do
    description """
    `Comment` stores the discussion from various members of the organization in a `Task` record.
    """
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    read :list_filtered_comments_preprations do
      argument :filter_for_actor, :boolean, default: false

      prepare Tuesday.Projects.Preparations.FilterCommentsForActor
    end

    read :list_filtered_comments_before_callback do
      argument :filter_level, :atom,
        default: :organization,
        constraints: [one_of: [:project, :organization]]

      prepare before_action(fn query, context ->
                filter_level = Ash.Query.get_argument(query, :filter_level)
                do_filter_comments(query, context.actor, filter_level)
              end)
    end

    create :create_comment do
      description "Creates a new comment."

      accept [:body, :task_id, :organization_id]

      change relate_actor(:author)

      change before_action(fn changeset, _context ->
               text = Ash.Changeset.get_attribute(changeset, :body)
               transformed_text = transform_emoji(text)
               Ash.Changeset.change_attribute(changeset, :body, transformed_text)
             end)

      validate present([:body, :task_id]), message: "Is required"
    end

    update :update_comment do
      description "Updates the comment content."

      accept [:body]
    end
  end

  policies do
    policy action(:create_comment) do
      authorize_if Tuesday.Checks.CanActorCreateComment
    end

    policy action(:update_comment) do
      authorize_if relates_to_actor_via(:author)
      forbid_if always()
    end

    policy_group relates_to_actor_via([:task, :project, :project_members, :organization_member]) do
      policy do
        authorize_if always()
      end
    end
  end

  validations do
    validate {Tuesday.Validations.TenantEqualsOrganization, []}
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
    global? true
  end

  attributes do
    uuid_primary_key :id
    attribute :body, :string, allow_nil?: false

    attribute :author_id, :uuid do
      source :organization_member_id
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, Tuesday.Workspace.Organization

    belongs_to :author, Tuesday.Workspace.OrganizationMember do
      description "The OrganizationMember who posted this comment."

      define_attribute? false
      source_attribute :author_id
      allow_nil? false
    end

    belongs_to :task, Tuesday.Projects.Task do
      description "The Task this comment is attached to."
      allow_nil? false
    end
  end

  calculations do
    calculate :time_since_posted,
              :integer,
              expr(
                fragment(
                  "FLOOR(EXTRACT(EPOCH FROM (timezone('UTC', now()) - ?)) / 60)",
                  inserted_at
                )
              ) do
      description "Time elapsed since the comment was posted, in minutes."
    end
  end

  defp do_filter_comments(query, %{organization_id: actor_org_id}, :organization)
       when not is_nil(actor_org_id) do
    org_filter_expr = [
      task: [
        project: [
          organization_id: actor_org_id
        ]
      ]
    ]

    Ash.Query.filter(query, ^org_filter_expr)
  end

  defp do_filter_comments(query, %{id: actor_id}, :project) when not is_nil(actor_id) do
    project_filter_expr = [
      task: [
        project: [
          project_members: [
            organization_member: [id: actor_id]
          ]
        ]
      ]
    ]

    Ash.Query.filter(query, ^project_filter_expr)
  end

  defp do_filter_comments(query, _, _),
    do: Ash.Query.add_error(query, "Invalid actor. Requires actor to be given to the action.")

  defp transform_emoji(text) do
    text
    |> String.replace(":heart:", "**emoji**")
    |> String.replace(":smile:", "**emoji**")

    # Add more emoji mappings as needed
  end
end
