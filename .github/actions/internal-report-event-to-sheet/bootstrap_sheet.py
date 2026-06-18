#!/usr/bin/env python3
"""Bootstrap the CI-events reporting Google Sheet.

Ensures the ``events`` tab exists and (re)writes its header row. Safe to run
repeatedly. Intended to be triggered manually through the reporter workflow's
``workflow_dispatch`` entry point.

Credentials come from ``GOOGLE_SHEETS_SA_KEY`` (raw or base64 JSON); the service
account needs *Editor* access to the spreadsheet.

``HEADERS`` MUST stay in sync with the row built in ``append_event.py``.
"""
from __future__ import annotations

import base64
import json
import os
import sys

HEADERS = [
    "timestamp_utc",
    "repo",
    "branch",
    "workflow",
    "run_id",
    "run_url",
    "type",
    "category",
    "severity",
    "title",
    "commit_sha",
    "actor",
    "consecutive_failures",
    "slack_ts",
]


def _load_service_account(raw: str) -> dict:
    raw = raw.strip()
    if not raw:
        raise ValueError("GOOGLE_SHEETS_SA_KEY is empty")
    if not raw.startswith("{"):
        raw = base64.b64decode(raw).decode("utf-8")
    return json.loads(raw)


def main() -> int:
    spreadsheet_id = os.environ["SHEET_SPREADSHEET_ID"]
    tab = os.environ.get("SHEET_TAB", "events")
    sa_info = _load_service_account(os.environ.get("GOOGLE_SHEETS_SA_KEY", ""))

    from google.oauth2.service_account import Credentials
    from googleapiclient.discovery import build

    creds = Credentials.from_service_account_info(
        sa_info, scopes=["https://www.googleapis.com/auth/spreadsheets"]
    )
    service = build("sheets", "v4", credentials=creds, cache_discovery=False)

    meta = service.spreadsheets().get(spreadsheetId=spreadsheet_id).execute()
    existing = [s["properties"]["title"] for s in meta.get("sheets", [])]

    if tab not in existing:
        service.spreadsheets().batchUpdate(
            spreadsheetId=spreadsheet_id,
            body={"requests": [{"addSheet": {"properties": {"title": tab}}}]},
        ).execute()
        print(f"Created tab '{tab}'.")
    else:
        print(f"Tab '{tab}' already exists.")

    service.spreadsheets().values().update(
        spreadsheetId=spreadsheet_id,
        range=f"{tab}!A1",
        valueInputOption="RAW",
        body={"values": [HEADERS]},
    ).execute()
    print(f"Wrote {len(HEADERS)} header columns to '{tab}!A1'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
