"""The nightly report job (python -m app.report): counts registrations per day.

Runs against the test database. REPORTS_BUCKET is unset, so it only prints
the CSV and never calls S3.
"""

from app import report


def test_report_counts_registrations(client, capsys, monkeypatch):
    monkeypatch.delenv("REPORTS_BUCKET", raising=False)
    for name in ("alice", "bob"):
        payload = {"name": name, "email": f"{name}@example.com", "password": "secret123"}
        client.post("/api/v1/auth/register", json=payload)

    report.main()

    lines = capsys.readouterr().out.strip().splitlines()
    assert lines[0] == "date,registrations"
    assert len(lines) == 2  # both users registered today
    assert lines[1].endswith(",2")


def test_report_with_no_users(capsys, monkeypatch):
    monkeypatch.delenv("REPORTS_BUCKET", raising=False)

    report.main()

    assert capsys.readouterr().out.strip() == "date,registrations"
