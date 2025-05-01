defmodule Tuesday.Projects.Project do
  use Ash.Resource,
    domain: Tuesday.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub, Tuesday.Audit.ActivityLogger]

  alias Tuesday.Workspace.OrganizationMember

  postgres do
    table "projects"
    repo Tuesday.Repo
  end

  resource do
    description """
    Project represents a collection of various tasks related to a common goal. An organization
    can create multiple Project records with each having its own set of Task records.

    Projects are not shared across organizations. They are visible only to the members of the same organization.
    """
  end

  actions do
    defaults [:read, :destroy, create: :*]

    read :list_projects

    read :read_with_history do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))

      prepare after_action(fn
                _query, [record], context ->
                  Tuesday.ProjectViewHistory.view_project(context.actor.id, record.id)
                  {:ok, [record]}

                _query, records, _context ->
                  {:ok, records}
              end)
    end

    create :create_with_audit do
      accept [:name, :organization_id]

      change after_action(fn changeset, result, context ->
               require Logger
               Logger.info("Actor: #{context.actor.id} created project: #{result.id}")

               {:ok, result}
             end)
    end

    read :high_story_point_projects do
      argument :sp_threshold, :integer

      prepare build(load: [:total_story_points])

      filter expr(total_story_points > arg(:sp_threshold))
    end

    create :create_project do
      description "Creates a new project."

      accept [:name, :description, :start_date, :end_date, :organization_id]

      validate present(:name), message: "is required"
      validate present(:end_date), message: "is required"
      validate present(:organization_id), message: "is required"
    end

    update :update_project do
      description "Updates project details."

      require_atomic? false

      accept [:name, :description, :status, :start_date, :end_date]
      validate present(:name), message: "is required"
      validate present(:start_date), message: "is required"
      validate present(:end_date), message: "is required"
      # validate present(:organization_id), message: "is required"
    end

    update :update do
      primary? true
      accept [:*]
      require_atomic? false
    end

    update :archive_project do
      description "Marks the project as archived"
      require_atomic? false

      change set_attribute(:status, :archived)
    end

    update :complete_project do
      description "Marks the project as complated"
      require_atomic? false

      change set_attribute(:status, :completed)
    end

    update :activate_project do
      description "Marks the project as active"
      require_atomic? false

      change set_attribute(:status, :active)
    end

    update :add_members do
      description "Add an OrganizationMember to Project"
      require_atomic? false

      argument :project_members, {:array, :map}, allow_nil?: false

      change fn changeset, ctx ->
        project_id = Ash.Changeset.get_data(changeset, :id)
        organization_id = Ash.Changeset.get_data(changeset, :organization_id)
        project_members = Ash.Changeset.get_argument(changeset, :project_members)

        # updated_members = Enum.map(project_members, &Map.put(&1, :project_id, project_id))
        updated_members =
          Enum.map(
            project_members,
            &Map.merge(&1, %{project_id: project_id, organization_id: organization_id})
          )

        Ash.Changeset.set_argument(changeset, :project_members, updated_members)
      end

      change manage_relationship(:project_members, :project_members, type: :create)
    end

    update :update_member do
      description "Update the member details at project level"
      require_atomic? false

      argument :project_member, :map, allow_nil?: false

      change manage_relationship(:project_member, :project_members,
               on_match: :update,
               on_no_match: :error
             )
    end

    update :remove_member do
      description "Remove the member from the project"
      require_atomic? false

      argument :project_member, :map, allow_nil?: false

      change manage_relationship(:project_member, :project_members,
               on_match: {:destroy, :destroy},
               on_no_match: :error
             )
    end
  end

  policies do
    # bypass relates_to_actor_via([:organization, :organization_members]) do
    #   authorize_if actor_attribute_equals(:role, :owner)
    #   authorize_if actor_attribute_equals(:role, :admin)
    # end

    # policy_group relates_to_actor_via([:project_members, :organization_member]) do
    #   policy action_type(:update) do
    #     authorize_unless {Tuesday.Checks.IsProjectMemberRole, role: :standard}
    #   end

    #   policy action_type(:read) do
    #     authorize_if always()
    #   end
    # end

    policy_group relates_to_actor_via([:organization, :organization_members]) do
      policy action_type(:update) do
        authorize_if actor_attribute_equals(:role, :owner)
        authorize_if actor_attribute_equals(:role, :admin)
        forbid_unless relates_to_actor_via([:project_members, :organization_member])
        authorize_unless {Tuesday.Checks.IsProjectMemberRole, role: :standard}
      end

      policy action_type(:read) do
        authorize_if actor_attribute_equals(:role, :owner)
        authorize_if actor_attribute_equals(:role, :admin)
        authorize_if relates_to_actor_via([:project_members, :organization_member])
      end
    end

    policy action(:create_project) do
      authorize_if Tuesday.Checks.ActorCreateProject
    end

    policy action(:add_members) do
      authorize_if matches(
                     "the organization id of actor, member, and project are all same and actor isn't an org member",
                     fn
                       nil, _ctx ->
                         false

                       actor, ctx ->
                         Enum.all?(ctx.changeset.arguments.project_members, fn project_member ->
                           project_id = project_member.project_id
                           organization_member_id = project_member.organization_member_id

                           with {:ok, project} <- Ash.get(__MODULE__, project_id, actor: actor),
                                {:ok, member} <-
                                  Ash.get(OrganizationMember, organization_member_id,
                                    actor: actor
                                  ) do
                             actor.role != :standard

                             actor.organization_id == member.organization_id &&
                               member.organization_id == project.organization_id
                           else
                             err ->
                               false
                           end
                         end)
                     end
                   )
    end
  end

  validations do
    validate {Tuesday.Validations.TenantEqualsOrganization, []}
  end

  validations do
    validate fn changeset, _context ->
               start_date = Ash.Changeset.get_attribute(changeset, :start_date)
               end_date = Ash.Changeset.get_attribute(changeset, :end_date)

               if :gt == Date.compare(end_date, start_date) do
                 :ok
               else
                 {:error, field: :end_date, message: "must be greater than start_date"}
               end
             end,
             where: present([:start_date, :end_date])
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
    global? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string

    attribute :start_date, :date do
      allow_nil? false
      default &Date.utc_today/0
    end

    attribute :end_date, :date

    attribute :status, :atom do
      constraints one_of: [:archived, :active, :completed]
      default :active
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, Tuesday.Workspace.Organization do
      description "The organization this project belongs to."
      allow_nil? false
      public? true
    end

    has_many :tasks, Tuesday.Projects.Task do
      description "Tasks within this project"

      destination_attribute :project_id
    end

    has_many :project_members, Tuesday.Projects.ProjectMember do
      description "OrganizationMembers assigned to this project."

      destination_attribute :project_id
    end
  end

  calculations do
    calculate :completion_percentage,
              :float,
              expr(count(tasks, query: [filter: [is_complete: true]]) / count(tasks) * 100) do
      description "Percentage of completed tasks."
    end

    calculate :days_until_deadline,
              :integer,
              expr(fragment("EXTRACT(DAY FROM age(end_date, current_timestamp))")) do
      description "Days remaining until the project end date."
    end
  end

  aggregates do
    max :max_story_point, :tasks, :story_point

    min :min_story_point, :tasks, :story_point

    sum :total_story_points, :tasks, :story_point

    first :task_name, :tasks, :title do
      sort [:inserted_at, :asc]
    end
  end

  identities do
    identity :unique_name_per_organization, [:name, :organization_id] do
      description "Ensures project names are unique."
      message "A project with the given name already exists in the organization"
    end
  end
end
