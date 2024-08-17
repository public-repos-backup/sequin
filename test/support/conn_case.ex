defmodule SequinWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use SequinWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Sequin.Factory.AccountsFactory

  using opts do
    quote do
      use Sequin.DataCase, unquote(opts)
      use SequinWeb, :verified_routes

      import Phoenix.ConnTest
      import Plug.Conn
      import SequinWeb.ConnCase
      # The default endpoint for testing
      @endpoint SequinWeb.Endpoint

      # Import conveniences for testing with connections
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def authenticated_conn(%{conn: conn}) do
    # TODO: Right now, FetchUser just uses this - in future, we'll need to add to conn here
    account = AccountsFactory.insert_account!()
    conn = Plug.Conn.assign(conn, :account_id, account.id)
    {:ok, conn: conn, account: account}
  end
end