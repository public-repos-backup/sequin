# Getting Started

In this guide, you'll boot Sequin locally and start working with your first stream.

## Install Sequin

First, you'll install the Sequin CLI and boot Sequin with Docker:

**Step 1:** Install the Sequin CLI:

```bash
brew tap/install {TODO}
```

**Step 2:** Create a new, local database for Sequin:

```bash
createdb sequin
```

> [!TIP]
> You can use an existing database with Sequin too 👇

**Step 3:** Boot Sequin with Docker using the `sequin` database you just created:

```bash
docker run sequin/sequin --env PG_DATABASE=sequin
```

In this example, we're using the defaults for Postgres (i.e. `localhost`, `5432`, `postgres/postgres`) and specifying the `sequin` database you created in the prior step.

<details>

<summary>
You can connect Sequin to any Postgres. Here are all the docker configs:
</summary>

| Flag           | Default    |
|----------------|------------|
| `PG_HOSTNAME`  | `localhost`|
| `PG_DATABASE`  | `postgres` |
| `PG_PORT`      | `5432`     |
| `PG_POOL_SIZE` |  `30`      |
| `PG_SSL`       |  `false`   |
| `PG_USERNAME`  |  `postgres`|
| `PG_PASSWORD`  |  `postgres`|
| `PG_URL`       |  When set, this is used instead of the individual connection parts. Example: `postgresql://username:password@localhost:5432/postgres`. The schema prefix still defaults to `sequin_`, but you can override by appending `schema_prefix=myprefix_`.|

</details>

Sequin is running! Now create your first stream.

## Create your stream

A stream in Sequin is a persistent, ordered sequence of messages. It's a powerful abstraction for handling real-time data flows and event-driven architectures. Streams allow you to:

- Publish messages to specific subjects within the stream
- Consume messages in the order they were published
- Store messages durably in your PostgreSQL database
- Process messages asynchronously with multiple consumers, and different consumer patterns.

Streams are ideal for building event-sourcing systems, implementing pub/sub patterns, or managing any scenario where you need to track and process a series of events over time. All using the Postgres.

**Step 1:** In a new terminal, create a new stream:

```bash
sequin stream add sequin-demo
```

You just created a new stream called `sequin-demo`.

> [!TIP]
> By default, the CLI connects to Sequin running on `http://localhost:4000`. You can override this configuration by creating a new context in the CLI:
> ```bash
> sequin context create
>```

**Step 2:** Now, inspect the stream you just created:

```bash
sequin stream info sequin-demo
```

Looks like your stream could use some messages.

## Publish a message

**Step 1:** In your terminal, add a message to your stream:

```bash
sequin stream pub sequin-demo sqn.test "Hello World!"
```

You just published a message to your `sequin-demo` stream with the subject of `sqn.test` and a data payload of `Hello World!`.

Sequin uses a hierarchical subject structure, similar to [NATS](https://docs.nats.io/nats-concepts/subjects). This allows for flexible message routing and filtering. Here's how they work:

- **Dot-separated hierarchy**: Subjects are a combination of tokens (i.e. strings) separated by dots, forming a hierarchy. For example: `orders.created`, `users.profile.updated`.
- **Consumer wildcards**: When creating a consumer, you'll be able to filter which messages you subscribe to using two types of wildcards:
  - Single-level wildcard (`*`): Matches any single token in the subject hierarchy. For example, `orders.*` would match `orders.created`, `orders.updated`, but not `orders.shipping.created`.
  - Multi-level wildcard (`>`): Matches one or more tokens at the end of a subject. For example, `users.>` would match `users.profile.updated`, `users.login`, and any other subject starting with `users.`.

**Step 2:** Check that your message in the stream by running `sequin stream info sequin-demo` again:

```bash
EXAMPLE
```

Great, the message count has incremented up.

**Step 3:** Publish a couple more messages to help you get a sense of you stream:

```bash
sequin stream pub sequin-demo sqn.test "Hello World 2!"
sequin stream pub sequin-demo sqn.test "Hello World 3!"
sequin stream pub sequin-demo sqn.foo "bar"
```

## Observe your stream

There are plenty of ways to view messages sitting in the stream.

**`stream last`**

Dump the last (i.e. head of the stream) X number messages that match a subject pattern from a stream into your terminal. For instance, `sequin stream sequin-demo last 2 sqn.test` will dump the two most recently added messages that match the subject `sqn.text`.

**`stream first`**

Similarly, `sequin stream sequin-demo first 2 sqn.test` will dump the two oldest (i.e. tail of the stream) messages that match the subject `sqn.test`.

**`stream tail`**

You can also observe your stream live, as messages get published. In a new terminal, run:

```bash
sequin stream sequin-demo tail sqn.*
```

Then in your other terminal, publish a new message:

```bash
sequin stream pub sequin-demo sqn.live "This is live"
```

Go back to your first terminal running `stream tail` and you'll see the message appear:

```bash
EXAMPLE
```

**SQL**

Of course, you can use SQL too. Connect to your `sequin` database using the SQL client of your choice and run:

```sql
select * from sequin_stream.streams
```

## Consume a message

In Sequin, a consumer is a client that subscribes to and processes messages from a stream. Consumers allow you to distribute work across multiple processes or services, ensuring that each message is processed at least once. A couple key features of Sequin consumers:

- **Durable**: Consumers maintain their position in the stream, allowing them to pick up where they left off if they disconnect and reconnect.
- **At-Least-Once delivery**: Sequin guarantees that each message will be delivered to a consumer at least once, ensuring no data is lost.
- **Acknowledgments**: Consumers are responsible for acknowledging messages once they've been successfully processed. This helps Sequin track which messages have been handled.
- **Fan out**: Multiple consumers can be added to a single stream, allowing for parallel processing and load distribution.
- **Backfilling**: When a new consumer is added, it can process all existing messages in the stream before moving on to new ones.

Now, let's walk through the process of setting up and using a consumer:

**Step 1:** Add a consumer to your stream:

```bash
sequin consumer add sequin-demo demo-consumer
```

Here, your creating a new consumer with the slug `demo-consumer` to the `sequin-demo` stream.

As with streams, you can observe the state of your consumer using the `ls` command:

```bash
sequin consumer ls sequin-demo
```

You can see that the consumer has pending messages in the stream. Now you are ready to consume messages.

**Step 2:** Fetch the next message for a consumer:

```bash
sequin consumer next sequin-demo demo-consumer --no-ack
```

The `next` command fetches the next available message for your `demo-consumer` from the `sequin-demo` stream. The `--no-ack` flag tells the consumer to not immediately `ack` the message so you can step through the message lifecycle in this guide.

Copy the `ack_id` for this message. You'll use it soon.

Now, when you inspect your consumer with the `info` command, you'll see that there is now an outstanding message:

```bash
sequin consumer info sequin-demo demo-consumer
```

You can introspect this outstanding message further:

```bash
sequin consumer messages sequin-demo demo-consumer --pending
```

This command dumps your consumer's pending (i.e. delivered but not yet ack'd or nack'd) messages to your terminal. You can see your outstanding message is checked out by the consumer - and no longer available in the stream for other consumer's to work on.

Now, instruct the consumer to `ack` the message:

```bash
sequin consumer ack sequin-demo demo-consumer [ack_id]
```

You've just consumed and ack'd your first message. When you run `consumer info` you'll now see there are now pending messages, and outstanding messages has decremented by one.

**Step 3:** Observe your consumer

You just stepped through the process of observing the state of your consumer as you fetched and ack'd a message. There are easier ways to monitor your consumer.

**`con tap`**

Logs the state of your consumer in your terminal. Run the following command to tap into your `demo-consumer`:

```bash
sequin con tap sequin-demo demo-consumer
```

Then, open another terminal and fetch another message. Skip the `--no-ack` flag this time, so your consumer both fetches and ack's the message:

```bash
sequin consumer next sequin-demo demo-consumer
```

When you return to your other terminal running `con tap` you'll see both the fetch and ack logged.

**SQL**

As with streams, consumers can be observed through your database as well:

```sql
select * from sequin_stream.consumer_messages
```

## Move to the API

The CLI is built on top of Sequin's HTTP interface. Meaning everything you've done so far is available over HTTP.

**Step 1:** generate an API token for your account:

```bash
sequin keys add [?description]
```

With an API token added to your account, you can now generate the `curl` equivalent for any CLI command by passing the `--as-curl` flag:

```bash
sequin stream info sequin-demo --as-curl
```

If you execute the `curl` command for `stream info`, the Sequin API will return the stats for your stream:

```bash
CURL EXAMPLE
```

**Step 2:** publish a message to your stream:

```bash
sequin stream pub sequin-demo sqn.test "Hello API" --as-curl

CURL EXAMPLE
```

**Step 3:** fetch a message for a consumer:

```bash
sequin consumer next sequin-demo demo-consumer --no-ack --as-curl

CURL EXAMPLE
```

**Step 4:** nack a message:

```bash
sequin consumer nack sequin-demo demo-consumer [ack_id] --as-curl

CURL EXAMPLE
```

**Step 5:** ack a message:

```bash
sequin consumer ack sequin-demo demo-consumer [ack_id] --as-curl

CURL EXAMPLE
```

> [!NOTE]
> Sequin HTTP push consumers are coming next week. In addition to HTTP pull consumer you just played with, you'll be able to create a consumer with a webhook endpoint. Sequin will then deliver messages to that endpoint.


## Connect your existing tables

So far, you've published messages to your stream using the Sequin CLI and API. You can also use Postgres tables as the source for data for a Sequin stream.

This means as records are created, updated, and deleted in your database, they are published into your Sequin stream. Consumers can subscribe to the messages they care about to process new, updated, and deleted records at-least-once.

You can connect Sequin to any Postgres database:

**Step 1:** setup logical replication on your Postgres database:

[TODO: Follow these steps]

**Step 2:** connect your Sequin stream to your Postgres replication slot:

```bash
sequin sources postgres add
```

Check the status of your new Postgres source:

```bash
sequin sources postgres ls
```

You'll see that your new database source is active and connected to your stream. You'll also see the subject pattern for messages generated from each connected table:

```bash
[database_slug].[schema].[table].[record_id]
```

**Step 3:** try it!

In a new terminal, start monitoring your stream:

```bash
sequin stream sequin-demo tail [subject]
```

Create a record in the table you just connected to your stream! Then watch a message enter your stream.