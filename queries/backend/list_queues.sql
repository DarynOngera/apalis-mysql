WITH stats AS (
    SELECT
        job_type,
        SUM(IF(status = 'Running', 1, 0)) AS running_jobs,
        SUM(IF(status = 'Pending', 1, 0)) AS pending_jobs,
        SUM(IF(status = 'Failed', 1, 0)) AS failed_jobs,
        SUM(IF(status = 'Done', 1, 0)) AS done_jobs,
        SUM(IF(status = 'Killed', 1, 0)) AS killed_jobs,
        SUM(IF(status IN ('Pending', 'Queued', 'Running'), 1, 0)) AS active_jobs,
        SUM(IF(status = 'Running' AND run_at < UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 HOUR)), 1, NULL)) AS stale_running_jobs,
        SUM(IF(run_at >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 HOUR)), 1, NULL)) AS jobs_past_hour,
        SUM(IF(DATE(FROM_UNIXTIME(run_at)) = DATE(NOW()), 1, NULL)) AS jobs_today,
        SUM(IF(DATE(FROM_UNIXTIME(run_at)) = DATE(NOW()) AND status = 'Killed', 1, NULL)) AS killed_jobs_today,
        SUM(IF(run_at >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 7 DAY)), 1, NULL)) AS jobs_past_7_days,
        ROUND(
            AVG(
                IF(
                    status IN ('Done', 'Failed', 'Killed') AND done_at IS NOT NULL,
                    (done_at - run_at) / 60.0,
                    NULL
                )
            ),
            2
        ) AS avg_job_duration_mins,
        MAX(IF(status = 'Running', (UNIX_TIMESTAMP(NOW()) - run_at) / 60.0, 0)) AS longest_running_job_mins,
        COUNT(*) AS total_jobs,
        MAX(run_at) AS most_recent_job
    FROM
        jobs
    GROUP BY
        job_type
),
lockers AS (
    SELECT
        job_type,
        JSON_ARRAYAGG(lock_by) AS workers
    FROM
        jobs
    WHERE
        lock_by IS NOT NULL
    GROUP BY
        job_type
),
activity AS (
    SELECT
        job_type,
        JSON_ARRAYAGG(daily_count) AS activity
    FROM (
        SELECT
            job_type,
            DATE(FROM_UNIXTIME(run_at)) AS run_date,
            COUNT(*) AS daily_count
        FROM
            jobs
        WHERE
            run_at >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 7 DAY))
        GROUP BY
            job_type,
            DATE(FROM_UNIXTIME(run_at))
        ORDER BY
            job_type,
            DATE(FROM_UNIXTIME(run_at))
    ) daily
    GROUP BY
        job_type
),
queue_stats AS (
    SELECT
        job_type,
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'title',
                statistic,
                'stat_type',
                type,
                'value',
                value,
                'priority',
                priority
            )
        ) as stats
    FROM (
        SELECT
            s.job_type,
            1 AS priority,
            'Number' AS type,
            'RUNNING_JOBS' AS statistic,
            CAST(s.running_jobs AS CHAR) AS value
        FROM
            stats s
        UNION ALL
        SELECT
            s.job_type,
            1,
            'Number',
            'PENDING_JOBS',
            CAST(s.pending_jobs AS CHAR)
        FROM
            stats s
        UNION ALL
        SELECT
            s.job_type,
            1,
            'Number',
            'FAILED_JOBS',
            CAST(s.failed_jobs AS CHAR)
        FROM
            stats s
        UNION ALL
        SELECT
            s.job_type,
            2,
            'Number',
            'ACTIVE_JOBS',
            CAST(s.active_jobs AS CHAR)
        FROM
            stats s
        UNION ALL
        SELECT
            s.job_type,
            2,
            'Number',
            'STALE_RUNNING_JOBS',
            CAST(s.stale_running_jobs AS CHAR)
        FROM
            stats s
        WHERE
            s.stale_running_jobs IS NOT NULL
        UNION ALL
        SELECT
            s.job_type,
            2,
            'Percentage',
            'KILL_RATE',
            CAST(ROUND(100.0 * s.killed_jobs / NULLIF(s.total_jobs, 0), 2) AS CHAR)
        FROM
            stats s
        UNION ALL
        SELECT
            s.job_type,
            3,
            'Number',
            'JOBS_PAST_HOUR',
            CAST(s.jobs_past_hour AS CHAR)
        FROM
            stats s
        WHERE
            s.jobs_past_hour IS NOT NULL
        UNION ALL
        SELECT
            s.job_type,
            3,
            'Number',
            'JOBS_TODAY',
            CAST(s.jobs_today AS CHAR)
        FROM
            stats s
        WHERE
            s.jobs_today IS NOT NULL
        UNION ALL
        SELECT
            s.job_type,
            3,
            'Number',
            'KILLED_JOBS_TODAY',
            CAST(COALESCE(s.killed_jobs_today, 0) AS CHAR)
        FROM
            stats s
        WHERE
            s.jobs_today IS NOT NULL
        UNION ALL
        SELECT
            s.job_type,
            3,
            'Decimal',
            'AVG_JOBS_PER_MINUTE_PAST_HOUR',
            CAST(ROUND(s.jobs_past_hour / 60.0, 2) AS CHAR)
        FROM
            stats s
        WHERE
            s.jobs_past_hour IS NOT NULL
        UNION ALL
        SELECT
            s.job_type,
            4,
            'Number',
            'TOTAL_JOBS',
            CAST(s.total_jobs AS CHAR)
        FROM
            stats s
        UNION ALL
        SELECT
            s.job_type,
            4,
            'Number',
            'DONE_JOBS',
            CAST(s.done_jobs AS CHAR)
        FROM
            stats s
        UNION ALL
        SELECT
            s.job_type,
            4,
            'Number',
            'KILLED_JOBS',
            CAST(s.killed_jobs AS CHAR)
        FROM
            stats s
        UNION ALL
        SELECT
            s.job_type,
            4,
            'Percentage',
            'SUCCESS_RATE',
            CAST(ROUND(100.0 * s.done_jobs / NULLIF(s.total_jobs, 0), 2) AS CHAR)
        FROM
            stats s
        UNION ALL
        SELECT
            s.job_type,
            5,
            'Decimal',
            'AVG_JOB_DURATION_MINS',
            CAST(s.avg_job_duration_mins AS CHAR)
        FROM
            stats s
        WHERE
            s.avg_job_duration_mins IS NOT NULL
        UNION ALL
        SELECT
            s.job_type,
            5,
            'Decimal',
            'LONGEST_RUNNING_JOB_MINS',
            CAST(ROUND(s.longest_running_job_mins, 2) AS CHAR)
        FROM
            stats s
        UNION ALL
        SELECT
            s.job_type,
            6,
            'Number',
            'JOBS_PAST_7_DAYS',
            CAST(s.jobs_past_7_days AS CHAR)
        FROM
            stats s
        WHERE
            s.jobs_past_7_days IS NOT NULL
        UNION ALL
        SELECT
            s.job_type,
            8,
            'Timestamp',
            'MOST_RECENT_JOB',
            CAST(s.most_recent_job AS CHAR)
        FROM
            stats s
    ) t
    GROUP BY
        job_type
),
all_job_types AS (
    SELECT
        worker_type AS job_type
    FROM
        workers
    UNION
    SELECT
        job_type
    FROM
        stats
)
SELECT
    jt.job_type as name,
    COALESCE(qs.stats, JSON_ARRAY()) as stats,
    COALESCE(lk.workers, JSON_ARRAY()) as workers,
    COALESCE(a.activity, JSON_ARRAY()) as activity
FROM
    all_job_types jt
    LEFT JOIN queue_stats qs ON jt.job_type = qs.job_type
    LEFT JOIN lockers lk ON jt.job_type = lk.job_type
    LEFT JOIN activity a ON jt.job_type = a.job_type
ORDER BY
    name;
