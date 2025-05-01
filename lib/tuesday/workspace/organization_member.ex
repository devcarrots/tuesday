defmodule Tuesday.Workspace.OrganizationMember do
  use Ash.Resource,
    domain: Tuesday.Workspace,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "organization_members"
    repo Tuesday.Repo
  end

  resource do
    description """
    `OrganizationMember` captures the organization specific User information. All resources that needs an
    association with the user who is currently logged in should be associated with OrganizationMember instead
    of User.

    This separates avoids leaking `Auth.User` resource details which is primarly capturing authentication related
    data of the currently logged in user from spanning into all the other unrelated domains.
    """
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    create :invite_org_member do
      description """
        Register `User` identified by the `email` as the `OrganizationMember`

        If an `User` exists for the given email, then register them as `OrganizationMember`.
        If no `User` exist for the email id, then create a new `User` with the email given and then
        proceed to registering the newly created User as the `OrganizationMember`.
      """

      argument :email, :string, allow_nil?: false

      change manage_relationship(:email, :user,
               on_match: :error,
               on_lookup: :relate,
               on_no_match: :create,
               value_is_key: :email,
               use_identities: [:unique_email]
             )

      accept [:username, :role, :organization_id]
      validate present(:user_id), message: "is required"
    end

    create :create_member do
      accept [:username, :role, :organization_id, :user_id]
    end

    update :update_org_member do
      accept [:username, :role]
    end

    update :deactivate_org_member do
      change set_attribute(:status, :inactive)
    end

    update :activate_org_member do
      change set_attribute(:status, :active)
    end
  end

  policies do
    policy action(:invite_org_member) do
      authorize_if Tuesday.Checks.CanActorInviteMember
    end

    policy action(:update_org_member) do
      authorize_if Tuesday.Checks.CanActorUpdateOrgMember
    end

    policy action(:deactivate_org_member) do
      authorize_if Tuesday.Checks.CanActorDeactivateOrgMember
    end

    policy do
      authorize_if always()
    end
  end

  validations do
    validate present(:username), message: "Username is required"
    validate {Tuesday.Validations.TenantEqualsOrganization, []}
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
    global? true
  end

  attributes do
    uuid_primary_key :id

    attribute :username, :string do
      constraints min_length: 3,
                  max_length: 20,
                  match: ~r/^[a-z_-]*$/

      allow_nil? false
      public? true
    end

    attribute :role, :atom do
      description "Role of the associated user in the current organization."
      constraints one_of: [:owner, :admin, :standard]
      default :standard
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      description "Membership status of the associated user in the current organization."
      constraints one_of: [:active, :inactive]
      default :active
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Tuesday.Auth.User do
      allow_nil? false
    end

    belongs_to :organization, Tuesday.Workspace.Organization do
      allow_nil? false
    end

    many_to_many :projects, Tuesday.Projects.Project do
      description "Projects assigned to this member."

      through Tuesday.Projects.ProjectMember
      source_attribute_on_join_resource :organization_member_id
      destination_attribute_on_join_resource :project_id
    end

    many_to_many :tasks, Tuesday.Projects.Task do
      description "Tasks assigned to this member."

      through Tuesday.Projects.TaskAssignee
      source_attribute_on_join_resource :assignee_id
      destination_attribute_on_join_resource :task_id
    end
  end

  calculations do
    calculate :task_completion_rate,
              :float,
              expr(
                if assigned_tasks > 0 do
                  completed_tasks / assigned_tasks * 100
                else
                  0.0
                end
              ) do
      description "Percentage of completed tasks out of assigned tasks."
    end

    calculate :workload_score,
              :integer,
              expr(
                count(tasks, query: [filter: expr(priority == 5)]) * 10 +
                  count(tasks, query: [filter: expr(priority == 4)]) * 8 +
                  count(tasks, query: [filter: expr(priority == 3)]) * 6 +
                  count(tasks, query: [filter: expr(priority == 2)]) * 4 +
                  count(tasks, query: [filter: expr(priority == 1)]) * 2
              ) do
      description "Weighted score based on task priorities."
    end
  end

  aggregates do
    count :assigned_tasks, :tasks do
      description "Count of tasks assigned to the user."
    end

    count :completed_tasks, :tasks do
      description "Count of completed tasks."

      filter expr(status == "completed")
    end
  end
end
