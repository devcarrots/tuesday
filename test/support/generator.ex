defmodule Tuesday.Generator do
  use Ash.Generator

  alias Tuesday.Auth.User
  alias Tuesday.Workspace.{Organization, OrganizationMember}
  alias Tuesday.Projects.{Project, ProjectMember, Task, TaskAssignee, Comment}

  def user(opts \\ []) do
    user_template = %User{
      email: email()
    }

    seed_generator(user_template, overrides: opts)
  end

  def create_organization_with_member(opts \\ []) do
    member_opts = Keyword.get(opts, :organization_member, [])

    member_user_id =
      member_opts[:user_id] ||
        once(:default_member_user_id, fn ->
          generate(user()).id
        end)

    member_opts = Keyword.merge(member_opts, role: "owner", user_id: member_user_id)

    %{
      organization: generate(organization(opts)),
      organization_member: generate(organization_member(member_opts))
    }
  end

  @spec organization(any()) :: StreamData.t(any())
  def organization(opts \\ []) do
    organization_template = %Organization{
      name: sequence(:organization_name, &"Gen-Organization #{&1}"),
      plan_type: StreamData.member_of([:free, :premium, :enterprise]),
      can_standard_member_create_project: StreamData.boolean()
    }

    seed_generator(organization_template, overrides: opts)
  end

  def organization_member(opts \\ []) do
    organization_id =
      opts[:organization_id] ||
        once(:default_organization_id, fn ->
          generate(organization()).id
        end)

    user_id =
      opts[:user_id] ||
        once(:default_user_id, fn ->
          generate(user()).id
        end)

    organization_member_template = %OrganizationMember{
      username: username(),
      user_id: user_id,
      organization_id: organization_id,
      role: StreamData.member_of([:owner, :admin, :standard]),
      status: StreamData.member_of([:active, :inactive])
    }

    seed_generator(organization_member_template, overrides: opts)
  end

  def project(opts \\ []) do
    organization_id =
      opts[:organization_id] ||
        once(:default_organization_id, fn ->
          generate(organization()).id
        end)

    start_date = random_date()
    end_date = Date.add(start_date, Enum.random(31..45))

    project_template = %Project{
      name: sequence(:project_name, &"Gen-Project #{&1}"),
      description: StreamData.string(:alphanumeric, min_length: 100, max_length: 200),
      start_date: start_date,
      end_date: end_date,
      status: StreamData.member_of([:archived, :active, :completed]),
      organization_id: organization_id
    }

    seed_generator(project_template, overrides: opts)
  end

  def project_member(opts \\ []) do
    project_id =
      opts[:project_id] ||
        once(:default_project_id, fn ->
          generate(project()).id
        end)

    organization_member_id =
      opts[:organization_member_id] ||
        once(:default_organization_member_id, fn ->
          generate(organization_member()).id
        end)

    project_member_template = %ProjectMember{
      organization_member_id: organization_member_id,
      project_id: project_id
    }

    seed_generator(project_member_template, overrides: opts)
  end

  def task(opts \\ []) do
    project_id =
      opts[:project_id] ||
        once(:default_project_id, fn ->
          generate(project()).id
        end)

    organization_id = opts[:organization_id]

    start_date = random_date()
    end_date = Date.add(start_date, Enum.random(31..45))

    task_template = %Task{
      title: sequence(:task_title, &"Gen-Task #{&1}"),
      description: StreamData.string(:alphanumeric, min_length: 100, max_length: 200),
      is_complete: StreamData.boolean(),
      priority: Enum.random(1..5),
      story_point: Enum.random([1, 3, 5, 8, 13, 21]),
      start_date: start_date,
      due_date: end_date,
      project_id: project_id,
      organization_id: organization_id
    }

    seed_generator(task_template, overrides: opts)
  end

  def child_task(opts \\ []) do
    project_id =
      opts[:project_id] ||
        once(:default_project_id, fn ->
          generate(project()).id
        end)

    parent_task_id =
      opts[:parent_task_id] ||
        once(:default_parent_task_id, fn ->
          generate(project()).id
        end)

    start_date = opts[:start_date] || random_date()
    end_date = Date.add(start_date, Enum.random(1..30))

    child_task_template = %Task{
      title: sequence(:task_title, &"Gen-Child task #{&1}"),
      description: StreamData.string(:alphanumeric, min_length: 100, max_length: 200),
      is_complete: StreamData.boolean(),
      priority: Enum.random(1..5),
      start_date: start_date,
      due_date: end_date,
      project_id: project_id,
      parent_task_id: parent_task_id
    }

    seed_generator(child_task_template, override: true)
  end

  def task_assignee(opts \\ []) do
    task_id =
      opts[:task_id] ||
        once(:default_task_id, fn ->
          generate(task()).id
        end)

    assignee_id =
      opts[:assignee_id] ||
        once(:default_assignee_id, fn ->
          generate(organization_member()).id
        end)

    task_assignee_template = %TaskAssignee{
      assignee_id: assignee_id,
      task_id: task_id
    }

    seed_generator(task_assignee_template, overrides: opts)
  end

  def comment(opts \\ []) do
    author_id =
      opts[:author_id] ||
        once(:default_author_id, fn ->
          generate(organization_member()).id
        end)

    task_id =
      opts[:task_id] ||
        once(:default_task_id, fn ->
          generate(task()).id
        end)

    organization_id = opts[:organization_id]

    comment_template = %Comment{
      body: StreamData.string(:alphanumeric, min_length: 100, max_length: 200),
      task_id: task_id,
      author_id: author_id,
      organization_id: organization_id
    }

    seed_generator(comment_template, overrides: opts)
  end

  @valid_org_member_opts [:user, :organization, :role, :status, :username]
  def create_org_member(opts \\ []) do
    case validate_options(opts, @valid_org_member_opts) do
      {:ok, opts} ->
        user = opts[:user] || generate(user())

        organization = opts[:organization] || generate(organization())

        user_org_opts = [
          user_id: user.id,
          organization_id: organization.id
        ]

        member_opts = Keyword.merge(user_org_opts, opts)

        %{
          user: user,
          organization: organization,
          org_member: generate(organization_member(member_opts))
        }

      error ->
        error
    end
  end

  @valid_project_member_opts [:org_member, :project, :project_role]
  def create_project_member(opts \\ []) do
    case validate_options(opts, @valid_project_member_opts) do
      {:ok, opts} ->
        org_member =
          opts[:org_member] || generate(organization_member())

        project =
          opts[:project] || generate(project(organization_id: org_member.organization_id))

        project_member_opts = [
          organization_member_id: org_member.id,
          project_id: project.id,
          organization_id: project.organization_id
        ]

        member_opts = Keyword.merge(project_member_opts, opts)

        %{
          org_member: org_member,
          project: project,
          project_member: generate(project_member(member_opts))
        }

      error ->
        error
    end
  end

  def validate_options(opts, valid_keys) when is_list(opts) and is_list(valid_keys) do
    keys = Keyword.keys(opts)

    if Enum.all?(keys, &(&1 in valid_keys)) do
      {:ok, opts}
    else
      {:error, {:invalid_keys, keys -- valid_keys}}
    end
  end

  defp username,
    do: StreamData.string(Enum.concat([?a..?z, [?_, ?-]]), min_length: 5, max_length: 10)

  defp email,
    do: StreamData.bind(username(), fn name -> StreamData.constant("#{name}@example.com") end)

  # # Helper function to generate random dates
  defp random_date do
    Date.utc_today()
    |> Date.add(-Enum.random(0..30))
  end
end
