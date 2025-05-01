defmodule Tuesday.Projects.Task do
  use Ash.Resource,
    domain: Tuesday.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Tuesday.Audit.ActivityLogger, Ash.Notifier.PubSub]

  postgres do
    table "tasks"
    repo Tuesday.Repo
  end

  resource do
    description """
    `Task` captures the details of a task assigned to a specific member of the project. It's the primary
    resource around which Tuesday project app works.
    """
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    read :list_tasks do
      prepare build(sort: [:inserted_at], limit: 5)

      pagination do
        # offset? true
        keyset? true
      end
    end

    read :overdue_tasks do
      prepare build(load: [:is_overdue])

      # filter expr(due_date < today() and not is_complete )
      filter is_overdue: true
    end

    read :list_project_tasks do
      description "List all tasks within the project."

      argument :project_id, :uuid
      filter expr(project_id: ^arg(:project_id))
    end

    read :list_project_parent_tasks do
      description "List all the parent tasks within the project."

      argument :project_id, :uuid
      filter expr(project_id: ^arg(:project_id))
      filter expr(is_nil(parent_task_id))
    end

    create :create_task do
      description "Creates a new task within the project."

      # manage assignees using manage_relationship
      accept [
        :title,
        :description,
        :priority,
        :start_date,
        :due_date,
        :project_id,
        :organization_id
      ]

      validate present(:title), message: "Is required"
      validate present(:project_id), message: "Is required"
    end

    update :update_task do
      description "Updates task details"

      accept [
        :title,
        :description,
        :priority,
        :start_date,
        :due_date,
        :is_complete
      ]
    end

    update :complete_task do
      description "Marks the task as complated"

      select [:title, :is_complete]

      change set_attribute(:is_complete, true)
    end

    update :add_sub_task do
      argument :sub_task, :map, allow_nil?: false

      require_atomic? false

      change manage_relationship(:sub_task, :sub_tasks, on_no_match: :create)
    end

    update :add_parent_task do
      accept [:parent_task_id]

      # Note: should we have a validation to ensure no nested tasks are created?
    end
  end

  policies do
    policy action(:create_task) do
      authorize_if Tuesday.Checks.CanActorCreateTask
    end

    policy_group action_type(:update) do
      policy relates_to_actor_via([:project, :organization, :organization_members]) do
        authorize_if actor_attribute_equals(:role, :admin)
        authorize_if actor_attribute_equals(:role, :owner)
        authorize_if relates_to_actor_via([:project, :project_members, :organization_member])
      end
    end

    policy_group action_type(:read) do
      policy relates_to_actor_via([:project, :organization, :organization_members]) do
        authorize_if actor_attribute_equals(:role, :admin)
        authorize_if actor_attribute_equals(:role, :owner)
        authorize_if relates_to_actor_via([:project, :project_members, :organization_member])
      end
    end
  end

  pub_sub do
    module TuesdayWeb.Endpoint
    prefix "task"
    publish :create_task, [[:id, nil]]
    publish_all :update, [[:id]]
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

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string

    attribute :is_complete, :boolean do
      source :is_done
      default false
      allow_nil? false
    end

    attribute :priority, :integer do
      constraints min: 1, max: 5
      default 3
      allow_nil? false
      select_by_default? false
    end

    attribute :story_point, :integer do
      constraints min: 1, max: 21
      default 3
      allow_nil? false
      public? true
    end

    attribute :start_date, :date do
      default &Date.utc_today/0
    end

    attribute :due_date, :date do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, Tuesday.Workspace.Organization

    belongs_to :project, Tuesday.Projects.Project do
      description "The project this task belongs to."
      allow_nil? false
      public? true
    end

    many_to_many :assignees, Tuesday.Workspace.OrganizationMember do
      description "Users assigned to this project."

      through Tuesday.Projects.TaskAssignee
      source_attribute_on_join_resource :task_id
      destination_attribute_on_join_resource :assignee_id
    end

    belongs_to :parent_task, Tuesday.Projects.Task do
      description "Parent task, if this task is a sub-task."

      source_attribute :parent_task_id
      destination_attribute :id
    end

    has_many :sub_tasks, Tuesday.Projects.Task do
      description "Sub-tasks, if other tasks refers to this task."

      source_attribute :id
      destination_attribute :parent_task_id
    end

    has_many :comments, Tuesday.Projects.Comment do
      description "Comments related to this task."

      destination_attribute :task_id
    end

    has_one :latest_comment, Tuesday.Projects.Comment do
      description "Latest Comment related to this task."

      destination_attribute :task_id
    end
  end

  calculations do
    calculate :is_overdue, :boolean, expr(due_date < now()) do
      description "Indicates if the task is overdue."
    end

    calculate :progress_percentage,
              :float,
              expr(
                if sub_task_count > 0 do
                  completed_sub_tasks / sub_task_count * 100
                else
                  0.0
                end
              ) do
      description "Percentage of completed sub-tasks."
    end
  end

  aggregates do
    exists :has_sub_tasks, :sub_tasks

    count :sub_task_count, :sub_tasks do
      description "Number of sub-tasks."
    end

    count :completed_sub_tasks, :sub_tasks do
      description "Count of completed sub-tasks."

      filter expr(is_complete == true)
    end
  end

  identities do
    identity :unique_title_per_project, [:title, :project_id] do
      description "Ensures task titles are unique within a project and tenant."
    end
  end
end
