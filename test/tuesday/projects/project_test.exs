defmodule Tuesday.Projects.ProjectTest do
  use Tuesday.DataCase

  alias Tuesday.Projects.Project
  require Ash.Resource.Change.Builtins

  describe "add_members" do
    test "valid input adds a member to the project" do
      %{org_member: org_member, organization: organization} = create_org_member()
      project = generate(project(organization_id: organization.id))

      changeset =
        Ash.Changeset.for_update(project, :add_members, %{
          project_members: [
            %{
              project_role: :admin,
              organization_member_id: org_member.id,
              project_id: project.id
            }
          ]
        })

      assert [{[project_member], relationship_opts}] = changeset.relationships.project_members

      assert changeset.valid?

      assert project_member.project_role == :admin
      assert project_member.organization_member_id == org_member.id
      assert project_member.project_id == project.id

      assert Keyword.get(relationship_opts, :on_no_match) == :create
    end

    test "duplicate member addition fails" do
      %{org_member: org_member} = create_org_member()

      %{project_member: project_member, project: project} =
        create_project_member(org_member: org_member)

      changeset =
        Ash.Changeset.for_update(project, :add_members, %{
          project_members: [
            %{
              project_role: project_member.project_role,
              organization_member_id: project_member.organization_member_id
            }
          ]
        })
        |> Ash.update(authorize?: false)

      assert_has_error(changeset, fn error ->
        match?(%{field: :organization_member_id, message: "Membership already exists."}, error)
      end)
    end

    test "tenant of a different organization cannot add members to the project" do
      tenant = generate(organization()).id
      %{org_member: org_member, organization: organization} = create_org_member()
      project = generate(project(organization_id: organization.id))

      changeset =
        Ash.Changeset.for_update(
          project,
          :add_members,
          %{
            project_members: [
              %{
                project_role: :admin,
                organization_member_id: org_member.id,
                project_id: project.id
              }
            ]
          },
          tenant: tenant
        )

      assert_has_error(changeset, fn error ->
        match?(
          %{field: :organization_id, message: "Tenant is not the same as `:organization_id`"},
          error
        )
      end)
    end
  end

  describe "update_member" do
    test "valid input updates the project member" do
      %{project_member: project_member, project: project} =
        create_project_member(project_role: :standard)

      %{project_members: [updated_project_member]} =
        Ash.Changeset.for_update(project, :update_member, %{
          project_member: %{
            id: project_member.id,
            project_role: :admin
          }
        })
        |> Ash.update!(authorize?: false)

      assert project_member.project_role == :standard
      assert updated_project_member.id == project_member.id
      assert updated_project_member.project_role == :admin
    end

    test "tenant cannot update project member of a different organization" do
      tenant = generate(organization()).id

      %{project_member: project_member, project: project} =
        create_project_member(project_role: :standard)

      changeset =
        Ash.Changeset.for_update(
          project,
          :update_member,
          %{
            project_member: %{
              id: project_member.id,
              project_role: :admin
            }
          },
          tenant: tenant
        )

      assert_has_error(changeset, fn error ->
        match?(
          %{field: :organization_id, message: "Tenant is not the same as `:organization_id`"},
          error
        )
      end)
    end
  end

  describe "remove_member" do
    test "valid input removes the member from the project" do
      %{project_member: project_member, project: project} =
        create_project_member(project_role: :standard)

      Ash.Changeset.for_update(project, :remove_member, %{
        project_member: %{
          id: project_member.id
        }
      })
      |> Ash.update!(authorize?: false)

      result = Ash.reload(project_member)

      assert_has_error(result, fn error ->
        match?(%Ash.Error.Query.NotFound{}, error)
      end)
    end

    test "tenant of a different organization cannot remove project member" do
      tenant = generate(organization()).id

      %{project_member: project_member, project: project} =
        create_project_member(project_role: :standard)

      changeset =
        Ash.Changeset.for_update(
          project,
          :remove_member,
          %{
            project_member: %{
              id: project_member.id,
              project_role: :admin
            }
          },
          tenant: tenant
        )

      assert_has_error(changeset, fn error ->
        match?(
          %{field: :organization_id, message: "Tenant is not the same as `:organization_id`"},
          error
        )
      end)
    end
  end

  describe "create_project" do
    test "valid input creates a new project" do
      organization_id = generate(organization()).id

      changeset =
        Ash.Changeset.for_create(Project, :create_project, %{
          name: "project",
          description: "some description",
          start_date: ~D[2025-04-10],
          end_date: ~D[2025-05-01],
          organization_id: organization_id
        })

      assert changeset.valid?
    end

    test "missing name fails creation" do
      changeset =
        Ash.Changeset.for_create(Project, :create_project, %{
          name: nil
        })

      assert_has_error(changeset, fn error ->
        match?(%{field: :name, message: "is required"}, error)
      end)
    end

    test "missing end_date fails creation" do
      changeset =
        Ash.Changeset.for_create(Project, :create_project, %{
          end_date: nil
        })

      assert_has_error(changeset, fn error ->
        match?(%{field: :end_date, message: "is required"}, error)
      end)
    end

    test "missing organization_id fails creation" do
      changeset =
        Ash.Changeset.for_create(Project, :create_project, %{
          organization_id: nil
        })

      assert_has_error(changeset, fn error ->
        match?(%{field: :organization_id, message: "is required"}, error)
      end)
    end

    test "default attributes are set correctly" do
      changeset =
        Ash.Changeset.for_create(Project, :create_project, %{
          name: "org",
          end_date: ~D[2025-05-01],
          organization_id: Ecto.UUID.generate()
        })

      assert {:ok, project} = Ash.Changeset.apply_attributes(changeset)

      assert project.start_date == Date.utc_today()
    end

    test "ignore default value for start_date when set" do
      changeset =
        Ash.Changeset.for_create(Project, :create_project, %{
          name: "org",
          start_date: ~D[2025-04-01],
          end_date: ~D[2025-05-01],
          organization_id: Ecto.UUID.generate()
        })

      assert {:ok, project} = Ash.Changeset.apply_attributes(changeset)

      assert project.start_date == ~D[2025-04-01]
    end

    test "fails with duplicate name within the the organization" do
      organization = generate(organization())
      project = generate(project(name: "project", organization_id: organization.id))

      duplicate_project_params = %{
        name: project.name,
        start_date: ~D[2025-04-10],
        end_date: ~D[2025-05-01],
        organization_id: project.organization_id
      }

      result =
        Ash.create(Project, duplicate_project_params,
          action: :create_project,
          authorize?: false
        )

      assert_has_error(result, fn error ->
        match?(
          %{message: "A project with the given name already exists in the organization"},
          error
        )
      end)
    end

    test "fails with an end date before the start date" do
      changeset =
        Ash.Changeset.for_create(Project, :create_project, %{
          start_date: ~D[2025-05-01],
          end_date: ~D[2025-04-10]
        })

      assert_has_error(changeset, fn error ->
        match?(%{message: "must be greater than start_date"}, error)
      end)
    end

    test "tenant of a different organization cannot create a project member" do
      tenant = generate(organization()).id
      another_organization_id = generate(organization()).id

      changeset =
        Ash.Changeset.for_create(
          Project,
          :create_project,
          %{
            name: "project",
            description: "some description",
            start_date: ~D[2025-04-10],
            end_date: ~D[2025-05-01],
            organization_id: another_organization_id
          },
          tenant: tenant
        )

      assert_has_error(changeset, fn error ->
        match?(
          %{field: :organization_id, message: "Tenant is not the same as `:organization_id`"},
          error
        )
      end)
    end
  end

  describe "update_project" do
    test "valid input updates the project" do
      project = generate(project())

      changeset =
        Ash.Changeset.for_update(project, :update_project, %{
          name: "project",
          description: "some description",
          start_date: ~D[2025-04-10],
          end_date: ~D[2025-05-01]
        })

      assert changeset.valid?
    end

    test "validates that the end date is not before the start date" do
      project = generate(project())

      changeset =
        Ash.Changeset.for_update(project, :update_project, %{
          name: "project",
          start_date: ~D[2025-05-01],
          end_date: ~D[2025-04-10]
        })

      assert_has_error(changeset, fn error ->
        match?(%{message: "must be greater than start_date"}, error)
      end)
    end

    test "empty required field fails to update" do
      project = generate(project())

      changeset =
        Ash.Changeset.for_update(project, :update_project, %{
          name: "",
          start_date: nil,
          end_date: nil
        })

      assert_has_error(changeset, fn error ->
        match?(%{message: "is required"}, error)
      end)
    end

    test "tenant of a different organization cannot update a project member" do
      tenant = generate(organization()).id
      another_organization_id = generate(organization()).id

      changeset =
        Ash.Changeset.for_create(
          Project,
          :create_project,
          %{
            name: "project",
            description: "some description",
            start_date: ~D[2025-04-10],
            end_date: ~D[2025-05-01],
            organization_id: another_organization_id
          },
          tenant: tenant
        )

      assert_has_error(changeset, fn error ->
        match?(
          %{field: :organization_id, message: "Tenant is not the same as `:organization_id`"},
          error
        )
      end)
    end
  end

  describe "archive_project" do
    test "updates the status of project to archived" do
      project = generate(project(status: :completed))
      changeset = Ash.Changeset.for_update(project, :archive_project)

      assert project.status == :completed
      assert changeset.valid?
      assert changeset.attributes.status == :archived
    end

    test "tenant of a different organization cannot archive project" do
      tenant = generate(organization()).id
      another_organization_id = generate(organization()).id
      project = generate(project(status: :completed, organization_id: another_organization_id))

      changeset = Ash.Changeset.for_update(project, :archive_project, %{}, tenant: tenant)

      assert_has_error(changeset, fn error ->
        match?(
          %{field: :organization_id, message: "Tenant is not the same as `:organization_id`"},
          error
        )
      end)
    end
  end

  describe "complete_project" do
    test "updates the status of project to completed" do
      project = generate(project(status: :active))
      changeset = Ash.Changeset.for_update(project, :complete_project)

      assert project.status == :active
      assert changeset.valid?
      assert changeset.attributes.status == :completed
    end

    test "tenant of a different organization cannot mark a project as complete" do
      tenant = generate(organization()).id
      another_organization_id = generate(organization()).id
      project = generate(project(status: :active, organization_id: another_organization_id))

      changeset = Ash.Changeset.for_update(project, :complete_project, %{}, tenant: tenant)

      assert_has_error(changeset, fn error ->
        match?(
          %{field: :organization_id, message: "Tenant is not the same as `:organization_id`"},
          error
        )
      end)
    end
  end

  describe "activate_project" do
    test "updates the status of project to active" do
      project = generate(project(status: :archived))
      changeset = Ash.Changeset.for_update(project, :activate_project)

      assert project.status == :archived
      assert changeset.valid?
      assert changeset.attributes.status == :active
    end

    test "tenant of a different organization cannot mark a project as active" do
      tenant = generate(organization()).id
      another_organization_id = generate(organization()).id
      project = generate(project(status: :archived, organization_id: another_organization_id))

      changeset = Ash.Changeset.for_update(project, :activate_project, %{}, tenant: tenant)

      assert_has_error(changeset, fn error ->
        match?(
          %{field: :organization_id, message: "Tenant is not the same as `:organization_id`"},
          error
        )
      end)
    end
  end
end
