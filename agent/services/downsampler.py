"""Query-time downsampling logic for the history API."""

from typing import List, Optional, Tuple


def compute_resolution(range_seconds: float, explicit_resolution: Optional[int] = None) -> int:
    """Compute the appropriate bucket size in seconds for a given time range.

    Returns the resolution in seconds.
    """
    if explicit_resolution is not None:
        return max(1, explicit_resolution)

    if range_seconds < 3600:          # < 1 hour
        return 10                     # Raw data
    elif range_seconds < 21600:       # 1-6 hours
        return 60
    elif range_seconds < 86400:       # 6-24 hours
        return 300                    # 5 minutes
    else:                             # > 24 hours
        return 900                    # 15 minutes


def build_history_query(
    metric_name: str,
    from_ts: str,
    to_ts: str,
    resolution: int,
) -> Tuple[str, dict]:
    """Build the SQL query for historical metric data with downsampling.

    Returns (sql_string, params_dict).
    """
    if resolution <= 10:
        # No downsampling — return raw data
        sql = """
            SELECT timestamp, value
            FROM metrics
            WHERE metric_name = :metric_name
              AND timestamp >= :from_ts
              AND timestamp <= :to_ts
            ORDER BY timestamp
        """
        params = {
            "metric_name": metric_name,
            "from_ts": from_ts,
            "to_ts": to_ts,
        }
    else:
        # Downsample using time buckets
        sql = """
            SELECT
                datetime(
                    (CAST(strftime('%s', timestamp) AS INTEGER) / :bucket) * :bucket,
                    'unixepoch'
                ) AS bucket_time,
                AVG(value) AS value
            FROM metrics
            WHERE metric_name = :metric_name
              AND timestamp >= :from_ts
              AND timestamp <= :to_ts
            GROUP BY bucket_time
            ORDER BY bucket_time
        """
        params = {
            "metric_name": metric_name,
            "from_ts": from_ts,
            "to_ts": to_ts,
            "bucket": resolution,
        }

    return sql, params
