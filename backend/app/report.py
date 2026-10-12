"""Nightly report job: how many people registered on each day, as a CSV.

What it does:
  1. Reads the users table and counts registrations per day.
  2. Prints the CSV, so it also shows up in the logs (CloudWatch in AWS).
  3. If the REPORTS_BUCKET environment variable is set, uploads the CSV
     to s3://<REPORTS_BUCKET>/reports/<today's date>.csv.

Example output:
  date,registrations
  2026-10-12,3

How it runs:
  - In AWS, every night: EventBridge Scheduler starts a Step Functions
    state machine, which runs this backend image as an ECS task with the
    command `python -m app.report`.
  - Locally: `python -m app.report` (prints only, since REPORTS_BUCKET
    isn't set).

It reuses the app's own database settings (DB_* environment variables)
and the User model, so there is no separate config. S3 access comes from
the ECS task's IAM role; no AWS keys are used.
"""

import csv
import io
import os
from datetime import date

from sqlalchemy import Date, cast, func, select

from app.db.session import SessionLocal
from app.models.user import User


def main() -> None:
    day = cast(User.created_at, Date)
    with SessionLocal() as db:
        rows = db.execute(select(day, func.count()).group_by(day).order_by(day)).all()

    out = io.StringIO()
    writer = csv.writer(out)
    writer.writerow(["date", "registrations"])
    writer.writerows(rows)
    print(out.getvalue())

    bucket = os.environ.get("REPORTS_BUCKET")
    if bucket:
        import boto3

        key = f"reports/{date.today()}.csv"
        boto3.client("s3").put_object(Bucket=bucket, Key=key, Body=out.getvalue())
        print(f"Uploaded s3://{bucket}/{key}")


if __name__ == "__main__":
    main()
