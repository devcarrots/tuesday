defmodule Tuesday.Workspace.OrganizationMemberTest do
  use Tuesday.DataCase

  alias Tuesday.Workspace.OrganizationMember

  describe "invite_org_member" do
    test "valid input creates a new organization member and user" do
      organization_id = generate(organization()).id

      assert {:ok, org_member} =
               Ash.Changeset.for_create(OrganizationMember, :invite_org_member, %{
                 email: "chaaru@example.com",
                 username: "chaaru",
                 role: :standard,
                 organization_id: organization_id
               })
               |> Ash.create(authorize?: false)

      assert org_member.username == "chaaru"
      assert org_member.role == :standard
      assert org_member.organization_id == organization_id
      assert org_member.user.email.string == "chaaru@example.com"
    end

    test "succeeds in relating if user already exists" do
      organization_id = generate(organization()).id
      user = generate(user(email: "chaaru@example.com"))

      assert {:ok, org_member} =
               Ash.Changeset.for_create(OrganizationMember, :invite_org_member, %{
                 email: "chaaru@example.com",
                 username: "chaaru",
                 role: :standard,
                 organization_id: organization_id
               })
               |> Ash.create(authorize?: false)

      assert org_member.user_id == user.id
    end

    test "missing required fields fails invitation" do
      organization_id = generate(organization()).id

      changeset =
        Ash.Changeset.for_create(OrganizationMember, :invite_org_member, %{
          email: nil,
          username: "chaaru",
          role: :standard,
          organization_id: organization_id
        })

      refute changeset.valid?

      assert_has_error(changeset, fn error ->
        match?(%Ash.Error.Changes.Required{field: :email}, error)
      end)
    end

    test "invalid role fails invitation" do
      organization_id = generate(organization()).id

      changeset =
        Ash.Changeset.for_create(OrganizationMember, :invite_org_member, %{
          email: "chaaru@example.com",
          username: "chaaru",
          role: :invalid_role,
          organization_id: organization_id
        })

      refute changeset.valid?

      assert_has_error(changeset, fn error ->
        match?(
          %{
            field: :role,
            message: "atom must be one of %{atom_list}, got: %{value}",
            vars: [atom_list: "owner, admin, standard", value: :invalid_role]
          },
          error
        )
      end)
    end

    test "tenant of a different organization cannot invite org member" do
      tenant = generate(organization()).id
      another_organization_id = generate(organization()).id

      changeset =
        Ash.Changeset.for_create(
          OrganizationMember,
          :invite_org_member,
          %{
            email: "chaaru@example.com",
            username: "chaaru",
            role: :standard,
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

  describe "update_org_member" do
    test "fails with empty username" do
      member = generate(organization_member(username: "chaaru"))
      changeset = Ash.Changeset.for_update(member, :update_org_member, %{username: ""})

      assert_has_error(changeset, fn error ->
        match?(%{message: "Username is required"}, error)
      end)
    end

    test "fails with invalid role" do
      member = generate(organization_member(role: :admin))
      changeset = Ash.Changeset.for_update(member, :update_org_member, %{role: :invalid_role})

      assert_has_error(changeset, fn error ->
        match?(
          %{
            field: :role,
            message: "atom must be one of %{atom_list}, got: %{value}",
            vars: [atom_list: "owner, admin, standard", value: :invalid_role]
          },
          error
        )
      end)
    end

    test "succeeds updating an organization member with valid params" do
      member = generate(organization_member(username: "devy", role: :standard))

      changeset =
        Ash.Changeset.for_update(member, :update_org_member, %{username: "chaaru", role: :admin})

      assert {:ok, member} = Ash.Changeset.apply_attributes(changeset)

      assert member.username == "chaaru"
      assert member.role == :admin
    end

    test "tenant of a different organization cannot update org member" do
      tenant = generate(organization()).id
      another_organization_id = generate(organization()).id

      member =
        generate(
          organization_member(
            username: "devy",
            role: :standard,
            organization_id: another_organization_id
          )
        )

      changeset =
        Ash.Changeset.for_update(member, :update_org_member, %{username: "chaaru", role: :admin},
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

  describe "deactivate_org_member" do
    test "succeeds updating the status of organization member to inactive" do
      member = generate(organization_member(status: :active))
      changeset = Ash.Changeset.for_update(member, :deactivate_org_member)

      assert {:ok, member} = Ash.Changeset.apply_attributes(changeset)
      assert member.status == :inactive
    end

    test "tenant of a different organization cannot deactivate org member" do
      tenant = generate(organization()).id
      another_organization_id = generate(organization()).id

      member =
        generate(
          organization_member(
            username: "devy",
            role: :standard,
            organization_id: another_organization_id
          )
        )

      changeset =
        Ash.Changeset.for_update(member, :deactivate_org_member, %{}, tenant: tenant)

      assert_has_error(changeset, fn error ->
        match?(
          %{field: :organization_id, message: "Tenant is not the same as `:organization_id`"},
          error
        )
      end)
    end
  end

  describe "activate_org_member" do
    test "successfully updates the status of organization member to active" do
      member = generate(organization_member(status: :inactive))
      changeset = Ash.Changeset.for_update(member, :activate_org_member)

      assert {:ok, member} = Ash.Changeset.apply_attributes(changeset)
      assert member.status == :active
    end
  end

  test "tenant of a different organization cannot activate org member" do
    tenant = generate(organization()).id
    another_organization_id = generate(organization()).id

    member =
      generate(
        organization_member(
          username: "devy",
          role: :standard,
          organization_id: another_organization_id
        )
      )

    changeset =
      Ash.Changeset.for_update(member, :deactivate_org_member, %{}, tenant: tenant)

    assert_has_error(changeset, fn error ->
      match?(
        %{field: :organization_id, message: "Tenant is not the same as `:organization_id`"},
        error
      )
    end)
  end
end
