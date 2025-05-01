defmodule Tuesday.Projects.TaskTest do
  use Tuesday.DataCase

  alias Tuesday.Projects.Task

  describe "create_task" do
    test "valid input creates a new task" do
      changeset =
        Ash.Changeset.for_create(Task, :create_task, %{
          title: "Some Task",
          description: "some description",
          priority: 3,
          start_date: ~D[2025-04-10],
          due_date: ~D[2025-05-11],
          project_id: generate_id()
        })

      assert changeset.valid?
    end

    test "missing required fields (e.g., title) fails creation" do
      changeset =
        Ash.Changeset.for_create(Task, :create_task, %{
          title: nil,
          description: nil,
          priority: nil,
          start_date: nil,
          due_date: nil,
          project_id: nil
        })

      assert_has_error(changeset, fn error ->
        match?(%{field: :title, message: "Is required"}, error)
      end)
    end

    test "default attributes are set correctly" do
      changeset =
        Ash.Changeset.for_create(Task, :create_task, %{
          title: "Some Task",
          description: "some description",
          priority: 3,
          due_date: ~D[2025-05-11],
          project_id: generate_id()
        })

      assert {:ok, task} = Ash.Changeset.apply_attributes(changeset)

      assert task.start_date == Date.utc_today()
      refute task.is_complete
    end

    test "ignore default value for start_date when set" do
      changeset =
        Ash.Changeset.for_create(Task, :create_task, %{
          title: "Some Task",
          description: "some description",
          priority: 3,
          start_date: ~D[2025-05-01],
          due_date: ~D[2025-05-11],
          project_id: generate_id()
        })

      assert {:ok, task} = Ash.Changeset.apply_attributes(changeset)

      assert task.start_date == ~D[2025-05-01]
    end

    test "tenant of a different cannot create task " do
      tenant = generate(organization()).id
      another_org = generate(organization())

      changeset =
        Ash.Changeset.for_create(
          Task,
          :create_task,
          %{
            title: "Some Task",
            description: "some description",
            priority: 3,
            start_date: ~D[2025-05-01],
            due_date: ~D[2025-05-11],
            # doubt: should this be changed to project_id?
            project_id: generate_id(),
            organization_id: another_org.id
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

  describe "update_task" do
    test "valid input updates the task" do
      task = generate(task())

      task_params = %{
        title: "New Task",
        description: "change description",
        priority: 1
      }

      changeset = Ash.Changeset.for_update(task, :update_task, task_params)

      assert changeset.valid?
    end

    test "empty title fails update" do
      task = generate(task())

      task_params = %{
        title: nil
      }

      changeset = Ash.Changeset.for_update(task, :update_task, task_params)

      refute changeset.valid?
    end

    test "tenant of a different organization cannot update task" do
      tenant = generate(organization()).id
      another_org = generate(organization())
      task = generate(task(organization_id: another_org.id))

      changeset =
        Ash.Changeset.for_update(
          task,
          :update_task,
          %{
            title: "New Task",
            description: "change description",
            priority: 1
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

  describe "add_sub_task" do
    test "valid input adds a sub-task" do
      task = generate(task())

      changeset =
        Ash.Changeset.for_update(task, :add_sub_task, %{
          sub_task: %{
            title: "Some Task",
            description: "some description",
            priority: 3,
            due_date: ~D[2025-05-11],
            parent_task_id: task.id,
            project_id: generate_id()
          }
        })

      assert changeset.valid?
    end

    test "missing required sub-task fields fails creation" do
      task = generate(task())

      changeset =
        Ash.Changeset.for_update(task, :add_sub_task, %{
          sub_task: nil
        })

      refute changeset.valid?
    end

    test "tenant of a different organization cannot add sub task" do
      tenant = generate(organization()).id
      another_org = generate(organization())
      task = generate(task(organization_id: another_org.id))

      changeset =
        Ash.Changeset.for_update(
          task,
          :add_sub_task,
          %{
            sub_task: %{
              title: "Some Task",
              description: "some description",
              priority: 3,
              due_date: ~D[2025-05-11],
              parent_task_id: task.id,
              project_id: generate_id()
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

    test "sub-task inherits project context" do
      # Placeholder: Validate that the sub-task’s project_id matches the parent task’s project_id.
      # Verify the sub-task is persisted with the correct project association.
    end
  end

  describe "add_parent_task" do
    test "valid input assigns a parent task" do
      project = generate(project(name: "Project 1"))
      parent_task_id = generate(task(project_id: project.id)).id
      task = generate(task())

      task_params = %{
        parent_task_id: parent_task_id
      }

      changeset = Ash.Changeset.for_update(task, :add_parent_task, task_params)

      assert changeset.valid?
    end

    test "tenant of a different organization cannot add sub task" do
      tenant = generate(organization()).id
      another_org = generate(organization())
      project = generate(project(name: "Project 1"))
      parent_task_id = generate(task(project_id: project.id)).id
      task = generate(task(organization_id: another_org.id))

      changeset =
        Ash.Changeset.for_update(
          task,
          :add_parent_task,
          %{
            parent_task_id: parent_task_id
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
end
