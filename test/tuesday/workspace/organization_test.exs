defmodule Tuesday.Workspace.OrganizationTest do
  use Tuesday.DataCase

  alias Tuesday.Workspace.Organization

  describe "create_org_with_owner" do
    test "valid input creates an organization with an owner" do
      organization =
        Ash.Changeset.for_create(Organization, :create_org_with_owner, %{
          name: "devCarrots",
          plan_type: :premium,
          member: %{email: "chaaru@example.com", username: "chaaru", role: :owner}
        })
        |> Ash.create!(authorize?: false)

      assert %{name: "devCarrots", plan_type: :premium, organization_members: [member]} =
               organization

      assert member.role == :owner
      assert member.user.email.string == "chaaru@example.com"
      assert member.username == "chaaru"
    end

    test "missing name fails creation" do
      changeset =
        Ash.Changeset.for_create(Organization, :create_org_with_owner, %{
          name: nil,
          member: nil
        })

      refute changeset.valid?

      assert_has_error(changeset, fn error ->
        match?(%{field: :name, message: "Name is required"}, error)
        match?(%Ash.Error.Changes.Required{field: :member}, error)
      end)
    end

    test "invalid plan type fails creation" do
      changeset =
        Ash.Changeset.for_create(Organization, :create_org_with_owner, %{
          name: "devCarrots",
          plan_type: :invalid_plan
        })

      refute changeset.valid?

      assert_has_error(changeset, fn error ->
        match?(
          %{
            field: :plan_type,
            message: "atom must be one of %{atom_list}, got: %{value}",
            vars: [atom_list: "free, premium, enterprise", value: :invalid_plan]
          },
          error
        )
      end)
    end

    test "default attributes are set correctly" do
      changeset =
        Ash.Changeset.for_create(Organization, :create_org_with_owner, %{
          name: "devCarrots",
          member: %{email: "chaaru@example.com", username: "chaaru", role: :owner}
        })

      assert {:ok, organization} = Ash.Changeset.apply_attributes(changeset)
      assert organization.can_standard_member_create_project
      assert organization.plan_type == :free
    end

    test "slug attribute is set correctly from name given" do
      changeset =
        Ash.Changeset.for_create(Organization, :create_org_with_owner, %{
          name: "dev Carrots",
          member: %{email: "chaaru@example.com", username: "chaaru", role: :owner}
        })

      assert {:ok, %{slug: "dev-carrots"}} = Ash.Changeset.apply_attributes(changeset)
    end
  end

  describe "update_org" do
    test "fails with empty name" do
      organization = generate(organization(name: "devCarrots"))
      changeset = Ash.Changeset.for_update(organization, :update_org, %{name: ""})

      assert_has_error(changeset, fn error ->
        match?(%{message: "Name is required"}, error)
      end)
    end

    test "fails with a duplicate name" do
      _organization1 = generate(organization(name: "devCarrots"))
      organization2 = generate(organization(name: "noobCarrots"))

      assert {:error, error} =
               Ash.Changeset.for_update(organization2, :update_org, %{name: "devCarrots"})
               |> Ash.update(authorize?: false)

      assert [%{field: :name, message: "An organization with the given name already exists"}] =
               error.errors
    end

    test "succesfully updates the org with valid params" do
      organization =
        generate(organization(name: "noobCarrots", can_standard_member_create_project: true))

      changeset =
        Ash.Changeset.for_update(organization, :update_org, %{
          name: "devCarrots",
          can_standard_member_create_project: false
        })

      assert {:ok, organization} = Ash.Changeset.apply_attributes(changeset)
      assert organization.name == "devCarrots"
      refute organization.can_standard_member_create_project
    end
  end

  describe "change_org_plan" do
    test "fails with an invalid plan type" do
      organization = generate(organization(plan_type: :free))

      changeset =
        Ash.Changeset.for_update(organization, :change_org_plan, %{plan_type: :invalid_plan})

      assert_has_error(changeset, fn error ->
        match?(
          %{
            field: :plan_type,
            message: "atom must be one of %{atom_list}, got: %{value}",
            vars: [atom_list: "free, premium, enterprise", value: :invalid_plan]
          },
          error
        )
      end)
    end

    test "successfully updates the organization with the given plan type" do
      organization = generate(organization(plan_type: :free))

      changeset =
        Ash.Changeset.for_update(organization, :change_org_plan, %{plan_type: :enterprise})

      assert {:ok, organization} = Ash.Changeset.apply_attributes(changeset)
      assert organization.plan_type == :enterprise
    end
  end
end
