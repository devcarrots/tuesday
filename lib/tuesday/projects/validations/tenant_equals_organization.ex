defmodule Tuesday.Validations.TenantEqualsOrganization do
  use Ash.Resource.Validation

  @impl true
  def init(opts) do
    {:ok, opts}
  end

  @impl true
  def validate(changeset, _opts, %{tenant: tenant}) do
    organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)

    cond do
      is_nil(organization_id) || is_nil(tenant) ->
        :ok

      tenant == organization_id ->
        :ok

      true ->
        {:error, field: :organization_id, message: "Tenant is not the same as `:organization_id`"}
    end
  end
end
