CREATE INDEX idx_apalis_jobs_status_type_recent
    ON jobs (
        status,
        job_type,
        done_at DESC,
        run_at DESC
    );

CREATE INDEX idx_apalis_jobs_status_recent
    ON jobs (
        status,
        done_at DESC,
        run_at DESC
    );
