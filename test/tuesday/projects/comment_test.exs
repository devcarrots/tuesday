defmodule Tuesday.Projects.CommentTest do
  use Tuesday.DataCase

  alias Tuesday.Projects.Comment

  describe "create_comment" do
    test "valid input creates a new comment" do
      %{org_member: org_member, project: project} = create_project_member()
      task_id = generate(task(project_id: project.id)).id

      {:ok, comment} =
        Ash.Changeset.for_create(
          Comment,
          :create_comment,
          %{
            body: "description about a project task",
            task_id: task_id
          },
          actor: org_member
        )
        |> Ash.Changeset.apply_attributes()

      assert comment.body == "description about a project task"
      assert comment.task_id == task_id
    end

    test "missing required fields (e.g., body) fails creation" do
      changeset =
        Ash.Changeset.for_create(
          Comment,
          :create_comment,
          %{
            body: nil,
            task_id: nil
          }
        )

      assert_has_error(changeset, fn error ->
        match?(
          %{fields: [:body, :task_id], message: "Is required"},
          error
        )
      end)
    end

    test "author association is set correctly" do
      actor = %{id: generate_id()}

      comment_params = %{
        body: "description about a project task",
        task_id: generate_id()
      }

      changeset = Ash.Changeset.for_create(Comment, :create_comment, comment_params, actor: actor)

      [{[author], _relation_opts}] = changeset.relationships.author

      assert actor.id == author.id
    end

    test "tenant of a different organization cannot create a comment" do
      tenant = generate(organization()).id
      another_org = generate(organization())
      %{org_member: org_member} = create_org_member(organization: another_org)
      %{project: project} = create_project_member(org_member: org_member)
      task_id = generate(task(project_id: project.id)).id

      changeset =
        Ash.Changeset.for_create(
          Comment,
          :create_comment,
          %{
            body: "description about a project task",
            task_id: task_id,
            organization_id: another_org.id
          },
          actor: org_member,
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

  describe "update_comment" do
    test "valid input updates the comment" do
      comment = generate(comment())

      comment_params = %{
        body: "Updated comment"
      }

      changeset = Ash.Changeset.for_update(comment, :update_comment, comment_params)

      assert changeset.attributes.body == "Updated comment"
    end

    test "empty body fails update" do
      comment = generate(comment())

      comment_params = %{
        body: nil
      }

      changeset = Ash.Changeset.for_update(comment, :update_comment, comment_params)

      assert_has_error(changeset, fn error ->
        match?(%Ash.Error.Changes.Required{field: :body}, error)
      end)
    end

    test "tenant of a different organization cannot create a comment" do
      tenant = generate(organization()).id
      another_org_id = generate(organization()).id
      comment = generate(comment(organization_id: another_org_id))

      changeset =
        Ash.Changeset.for_update(
          comment,
          :update_comment,
          %{
            body: "Updated comment"
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
