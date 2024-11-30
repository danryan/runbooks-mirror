# PostgreSQL Wait Event Analysis

## Introduction

This document aims to analyze key wait events in PostgreSQL that may indicate performance issues or other critical aspects of database operation.

It is not intended to be an exhaustive overview of all wait events, but rather focuses on highlighting some important ones. \
For a comprehensive description and detailed analysis of all wait events, refer to the [official PostgreSQL documentation](https://www.postgresql.org/docs/current/monitoring-stats.html#WAIT-EVENT-TABLE) and the Amazon RDS User Guide section on ["RDS for PostgreSQL wait events"](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Tuning.concepts.summary.html), which includes tables of the most commonly encountered events indicating performance problems, along with their common causes and corrective actions.

## Dashboard:

[_link to dashboard here_]

Chart: `Wait Events` (Detailed information about wait events, based on [pg_wait_sampling](https://github.com/postgrespro/pg_wait_sampling)).

## Checklist:
  - **Are there any changes in the wait events? What events are being observed?**
    - _Note: The list below is categorized by wait event types and specific wait events, that corresponding to the 'wait_event_type' and 'wait_event' columns in pg_stat_activity._
    - **Some key Wait Events (if observed):**
      - `IO`
        - Description: The server process is waiting for an I/O operation to complete. wait_event will identify the specific wait point; see [Table 28.9](https://www.postgresql.org/docs/current/monitoring-stats.html#WAIT-EVENT-IO-TABLE).
        - `DataFileRead`
          - Description: This wait event occurs when a connection waits on a backend process to read a required page from storage because the page isn't available in shared memory.
          - Actions:
            - Individual wait events are not an indicator of a problem, but if the 'DataFileRead' event occurs frequently, this may be an indicator that the shared buffer pool might be too small to accommodate workload. Perform a review of the database workload.
            - Refer to Amazon's 'IO:DataFileRead' wait event description [page](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/wait-event.iodatafileread.html).
        - `WALWrite`
          - Description: This wait event is generated when the SQL session is waiting for the WAL data to complete writing to disk so that it can release the transaction's COMMIT call.
          - Actions:
            - Individual wait events are not an indicator of a problem, but if this wait event occurs often, perform review workload and the type of updates that your workload performs and their frequency. Verify the database server is not experiencing disk I/O overload issues.
            - Refer to Amazon's 'IO:WALWrite 'wait event description [page](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/wait-event.iowalwrite.html).
      - `Lock`
        - Description: The server process is waiting for a heavyweight lock. wait_event will identify the type of lock awaited; see [Table 28.11](https://www.postgresql.org/docs/current/monitoring-stats.html#WAIT-EVENT-LOCK-TABLE).
          - Actions:
            - If you observe frequent lock-related wait events (e.q., `relation`, `transactionid`, `tuple`, [etc](https://www.postgresql.org/docs/current/monitoring-stats.html#WAIT-EVENT-LOCK-TABLE)), perform a detailed analysis heavyweight locks using runbook [_link here_]. Determine which specific objects (relation, statement) are the sources of locks and how long they hold them.
      - `LWLock`
        - `LockManager`
          - Description: This event occurs when the PostgreSQL maintains the shared lock's memory area to allocate, check, and deallocate a lock when a fast path lock isn't possible. When this wait event occurs more than normal, possibly indicating a performance problem. For more information, see [GitLab's challenge with Postgres LWLock lock_manager contention](https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/2301).
          - Actions:
            - Remove unnecessary indexes: Your database might contain unused or rarely used indexes. If so, consider deleting them.
            - Reduce number of relations per query: to fewer than 16 (to use the Fast path locking).
            - Use prepared statements or PL/PgSQL functions: See the tests [here](https://gitlab.com/postgres-ai/postgresql-consulting/tests-and-benchmarks/-/issues/41) and [here](https://gitlab.com/postgres-ai/postgresql-consulting/tests-and-benchmarks/-/issues/42) which demonstrate a reduction in the number of LWLocks and queries latency by caching the plans using prepared statements.
        - `SubtransBuffer` or `SubtransSLRU`
          - Description: Waiting for I/O on a sub-transaction SLRU buffer or access to the sub-transaction SLRU cache. This waiting event can usually be seen in highly loaded databases (thousands of TPS), and when we see this wait event, it may indicate a possible performance problem. For more information, see [PostgreSQL Subtransactions Considered Harmful](https://postgres.ai/blog/20210831-postgresql-subtransactions-considered-harmful).
          - Actions:
            - If subtransactions are used, it does not immediately mean that they need to be eliminated – it all depends on the risks of your particular case. But if you are seeing an increase in the number of expectation events related to subtransactions and this begins to correlate with the degradation of database performance, consider getting rid of the use of subtransactions.
        - `pg_stat_kcache`
          - Description: Wait events related to the 'pg_stat_kcache' extension are relatively rare. These events have been [observed](https://gitlab.com/postgres-ai/postgresql-consulting/tests-and-benchmarks/-/jobs/5865735816/artifacts/file/ARTIFACTS/2024-01-05-0425_c200/pg_wait_sampling_profile.csv) primarily during synthetic stress [tests](https://gitlab.com/postgres-ai/postgresql-consulting/tests-and-benchmarks/-/jobs/5865735814) using `pgbench` (select-only) on servers with a high number of CPUs (more than 100).
          - Actions:
            - If you notice an increase in wait events related to the 'pg_stat_kcache' extension, and this correlates with increased query latency, you are observing a performance degradation, consider the following steps:
              1. Remove the extension from the database (on the Primary server): Execute `DROP EXTENSION pg_stat_kcache;`
              2. Remove `pg_stat_kcache` from the `shared_preload_libraries` parameter in PostgreSQL configuration.
              3. Restart PostgreSQL to apply these changes. Do this one at a time, first on the Replicas and only then on the Primary.
            - Subsequently, report the issue to the project's [repository](https://github.com/powa-team/pg_stat_kcache) with a detailed description of the problem. Once a solution is found and necessary updates are made, conduct pre-testing in a load-testing environment before create the extension in the production database.

