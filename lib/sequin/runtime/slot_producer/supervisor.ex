defmodule Sequin.Runtime.SlotProducer.Supervisor do
  @moduledoc """
  Supervisor for the complete SlotProducer pipeline.

  This supervisor manages the three-stage GenStage pipeline:
  1. SlotProducer - Connects to PostgreSQL replication and produces messages
  2. Multiple Processor partitions - Transform replication messages into SlotProcessor.Messages
  3. ReorderBuffer - Reorders messages from partitions and delivers batches
  """
  use Supervisor

  alias Sequin.Databases.PostgresDatabase
  alias Sequin.Repo
  alias Sequin.Runtime.MessageHandler
  alias Sequin.Runtime.SlotProcessorServer
  alias Sequin.Runtime.SlotProducer
  alias Sequin.Runtime.SlotProducer.Processor
  alias Sequin.Runtime.SlotProducer.ReorderBuffer

  def child_spec(opts) do
    replication_slot = Keyword.fetch!(opts, :replication_slot)

    spec = %{
      id: via_tuple(replication_slot.id),
      start: {__MODULE__, :start_link, [opts]}
    }

    Supervisor.child_spec(spec, [])
  end

  def start_link(opts) do
    replication_slot = Keyword.fetch!(opts, :replication_slot)
    Supervisor.start_link(__MODULE__, opts, name: via_tuple(replication_slot.id))
  end

  def via_tuple(replication_slot_id) do
    {:via, :syn, {:replication, {__MODULE__, replication_slot_id}}}
  end

  @impl Supervisor
  def init(opts) do
    replication_slot =
      opts
      |> Keyword.fetch!(:replication_slot)
      |> Repo.lazy_preload([:postgres_database])

    partition_count = Processor.partition_count()

    postgres_database = Map.put(replication_slot.postgres_database, :tables, nil)
    slot_producer_opts = Keyword.get(opts, :slot_producer_opts, [])
    processor_opts = Keyword.get(opts, :processor_opts, [])
    reorder_buffer_opts = Keyword.get(opts, :reorder_buffer_opts, [])
    slot_processor_opts = Keyword.get(opts, :slot_processor_opts, [])
    {skip_slot_processor_server?, slot_processor_opts} = Keyword.pop(slot_processor_opts, :skip_start?, false)
    pipeline_id = replication_slot.id

    slot_producer_opts =
      Keyword.merge(
        [
          id: pipeline_id,
          account_id: postgres_database.account_id,
          database_id: postgres_database.id,
          slot_name: replication_slot.slot_name,
          publication_name: replication_slot.publication_name,
          pg_major_version: postgres_database.pg_major_version,
          connect_opts: PostgresDatabase.to_protocol_opts(postgres_database),
          conn: fn -> postgres_database end,
          test_pid: opts[:test_pid]
        ],
        slot_producer_opts
      )

    processor_specs =
      Enum.map(0..(partition_count - 1), fn partition_idx ->
        Supervisor.child_spec(
          {Processor,
           Keyword.merge(
             [
               id: pipeline_id,
               partition_idx: partition_idx,
               account_id: postgres_database.account_id,

               # Subscribe to SlotProducer in init - subscribe_to can be overridden for tests
               subscribe_to: [
                 {SlotProducer.via_tuple(pipeline_id), []}
               ]
             ],
             processor_opts
           )},
          id: {:processor, partition_idx}
        )
      end)

    reoder_buffer_opts =
      Keyword.merge(
        [
          id: pipeline_id,
          producer_partitions: partition_count,
          account_id: postgres_database.account_id,
          # Subscribe to all Processor partitions via subscribe_to in init
          subscribe_to:
            Enum.map(0..(partition_count - 1), fn partition_idx ->
              {Processor.via_tuple(pipeline_id, partition_idx),
               max_demand: :sequin |> Application.fetch_env!(ReorderBuffer) |> Keyword.fetch!(:max_demand),
               min_demand: :sequin |> Application.fetch_env!(ReorderBuffer) |> Keyword.fetch!(:min_demand)}
            end)
        ],
        reorder_buffer_opts
      )

    slot_processor_opts =
      Keyword.merge(
        [
          id: replication_slot.id,
          slot_name: replication_slot.slot_name,
          postgres_database: %{postgres_database | tables: []},
          replication_slot: replication_slot,
          message_handler_ctx_fn: &MessageHandler.context/1,
          message_handler_module: default_message_handler_module(),
          ipv6: replication_slot.postgres_database.ipv6,
          test_pid: opts[:test_pid]
        ],
        slot_processor_opts
      )

    slot_processor_server =
      if Application.get_env(:sequin, :env) == :test and skip_slot_processor_server? do
        []
      else
        [{SlotProcessorServer, slot_processor_opts}]
      end

    children =
      List.flatten([
        {SlotProducer, slot_producer_opts},
        processor_specs,
        {ReorderBuffer, reoder_buffer_opts},
        slot_processor_server
      ])

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc """
  Starts the complete SlotProducer pipeline for the given replication slot.

  ## Options

  - `:replication_slot` - Required. The PostgresReplicationSlot record with preloaded postgres_database
  - `:flush_batch_fn` - Required. Function called when ReorderBuffer has a complete batch ready
  - `:slot_producer_opts` - Optional. Additional options for SlotProducer
  - `:reorder_buffer_opts` - Optional. Additional options for ReorderBuffer

  ## Example

      replication_slot =
        Repo.get!(PostgresReplicationSlot, slot_id)
        |> Repo.preload(:postgres_database)

      {:ok, _pid} = SlotProducer.Supervisor.start_link(
        replication_slot: replication_slot,
        flush_batch_fn: fn batch_marker, messages ->
          # Process the batch
          :ok
        end,
        slot_producer_opts: [
          batch_flush_interval: 5000
        ]
      )
  """
  def start_pipeline(opts) do
    start_link(opts)
  end

  @doc """
  Stops the pipeline for the given replication slot.
  """
  def stop_pipeline(replication_slot_id) do
    case Process.whereis(via_tuple(replication_slot_id)) do
      nil -> :ok
      pid -> Supervisor.stop(pid)
    end
  end

  @doc """
  Returns the child processes for the given replication slot pipeline.
  """
  def which_children(replication_slot_id) do
    case Process.whereis(via_tuple(replication_slot_id)) do
      nil -> []
      pid -> Supervisor.which_children(pid)
    end
  end

  defp default_message_handler_module do
    Application.get_env(:sequin, :message_handler_module)
  end
end
