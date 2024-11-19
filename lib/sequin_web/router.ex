defmodule SequinWeb.Router do
  use SequinWeb, :router

  import SequinWeb.UserAuth

  alias SequinWeb.Plugs.AssignCurrentPath
  alias SequinWeb.Plugs.VerifyApiToken

  @self_hosted Application.compile_env!(:sequin, :self_hosted)

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {SequinWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(AssignCurrentPath)
    plug(:fetch_current_user)
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug VerifyApiToken
  end

  ## Authentication routes

  scope "/", SequinWeb do
    pipe_through [:browser]

    get "/auth/github", UserSessionController, :start_oauth
    get "/auth/github/callback", UserSessionController, :callback

    live_session :home do
      live "/", HomeLive, :index

      if @self_hosted do
        live "/migration-oct-2024", MigrationOct2024Live, :index
      end
    end
  end

  scope "/", SequinWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{SequinWeb.UserAuth, :redirect_if_user_is_authenticated}, {SequinWeb.LiveHooks, :global}],
      layout: {SequinWeb.Layouts, :app_no_sidenav} do
      live "/register", UserRegistrationLive, :new
      live "/login", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit

      if @self_hosted do
        live "/setup", SetupLive, :index
      end
    end

    post "/login", UserSessionController, :create
  end

  scope "/", SequinWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{SequinWeb.UserAuth, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", SequinWeb do
    pipe_through [:browser]

    delete "/logout", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{SequinWeb.UserAuth, :mount_current_user}],
      layout: {SequinWeb.Layouts, :app_no_sidenav} do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end

  scope "/", SequinWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :default, on_mount: [{SequinWeb.UserAuth, :ensure_authenticated}, {SequinWeb.LiveHooks, :global}] do
      live "/consumer-groups", ConsumerGroupsLive.Index, :list
      live "/consumer-groups/new", ConsumerGroupsLive.Index, :new
      live "/consumer-groups/:id", ConsumerGroupsLive.Show, :show
      live "/consumer-groups/:id/messages", ConsumerGroupsLive.Show, :messages
      live "/consumer-groups/:id/edit", ConsumerGroupsLive.Show, :edit

      live "/sinks", SinkConsumersLive.Index, :list
      live "/sinks/new", SinkConsumersLive.Index, :new
      live "/sinks/:type/:id", SinkConsumersLive.Show, :show
      live "/sinks/:type/:id/messages", SinkConsumersLive.Show, :messages
      live "/sinks/:type/:id/edit", SinkConsumersLive.Show, :edit

      live "/databases", DatabasesLive.Index, :index
      live "/databases/new", DatabasesLive.Form, :new
      live "/databases/:id", DatabasesLive.Show, :show
      live "/databases/:id/edit", DatabasesLive.Form, :edit
      live "/databases/:id/messages", DatabasesLive.Show, :messages

      live "/http-endpoints", HttpEndpointsLive.Index, :index
      live "/http-endpoints/new", HttpEndpointsLive.Form, :new
      live "/http-endpoints/:id", HttpEndpointsLive.Show, :show
      live "/http-endpoints/:id/edit", HttpEndpointsLive.Form, :edit

      live "/change-capture-pipelines", WalPipelinesLive.Index, :index
      live "/change-capture-pipelines/new", WalPipelinesLive.Form, :new
      live "/change-capture-pipelines/:id", WalPipelinesLive.Show, :show
      live "/change-capture-pipelines/:id/edit", WalPipelinesLive.Form, :edit

      live "/streams", SequencesLive.Index, :index
      live "/streams/new", SequencesLive.Index, :new
      # live "/streams/:id", SequencesLive.Show, :show
      # live "/streams/:id/edit", SequencesLive.Form, :edit

      live "/logout", UserLogoutLive, :index

      get "/easter-egg", EasterEggController, :home

      live "/outbox", OutboxLive, :index

      live "/settings/accounts", Settings.AccountSettingsLive, :index

      live "/accept-invite/:token", AcceptInviteLive, :index
    end

    get "/admin/impersonate/:secret", UserSessionController, :impersonate
    get "/admin/unimpersonate", UserSessionController, :unimpersonate
  end

  scope "/health", SequinWeb do
    get "/", HealthCheckController, :check
  end

  scope "/api", SequinWeb do
    pipe_through(:api)

    resources("/streams/:stream_id_or_name/consumers", ConsumerController,
      except: [:new, :edit],
      param: "id_or_name"
    )

    resources("/databases", DatabaseController, except: [:new, :edit], param: "id_or_name")
    resources("/api_keys", ApiKeyController, only: [:index, :create, :delete])

    resources("/postgres_replications", PostgresReplicationController, except: [:new, :edit])
    resources("/local_tunnels", LocalTunnelController, only: [:index])

    post("/databases/:id_or_name/test_connection", DatabaseController, :test_connection)
    post("/databases/:id_or_name/setup_replication", DatabaseController, :setup_replication)
    get("/databases/:id_or_name/schemas", DatabaseController, :list_schemas)
    get("/databases/:id_or_name/schemas/:schema/tables", DatabaseController, :list_tables)
    post("/databases/test_connection", DatabaseController, :test_connection_params)
    post("/http_pull_consumers/:id_or_name/receive", PullController, :receive)
    get("/http_pull_consumers/:id_or_name/receive", PullController, :receive)
    post("/http_pull_consumers/:id_or_name/ack", PullController, :ack)
    post("/http_pull_consumers/:id_or_name/nack", PullController, :nack)

    post("/config/apply", YamlController, :apply)
    post("/config/plan", YamlController, :plan)
    get("/config/export", YamlController, :export)
  end

  # Other scopes may use custom stacks.
  # scope "/api", SequinWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:sequin, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: SequinWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end

    scope "/push-webhook" do
      post "/ack", SequinWeb.PushWebhookController, :ack
      post "/maybe-ack", SequinWeb.PushWebhookController, :maybe_ack
      post "/nack", SequinWeb.PushWebhookController, :nack
      post "/timeout", SequinWeb.PushWebhookController, :timeout
    end
  end
end
