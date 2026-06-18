#!/usr/bin/env python3
"""Append a single CI event row to the reporting Google Sheet.

The service-account credentials are provided via the ``GOOGLE_SHEETS_SA_KEY``
environment variable (raw JSON or base64-encoded JSON). The service account
must have *Editor* access to the target spreadsheet.

The script is best-effort by default: any failure is emitted as a GitHub
Actions ``::warning::`` and the process exits 0 so that event reporting can
never break the pipeline it observes. Set ``SHEET_STRICT=true`` to fail hard.

Column order is kept in sync with ``bootstrap_sheet.py`` (the ``events`` tab
header row).
"""
from __future__ import annotations

import base64
import datetime
import json
import os
import sys


def _warn(message: str) -> None:
    # Escape GitHub workflow-command metacharacters so a stray %, CR or LF in an
    # exception message cannot break log parsing or inject a workflow command.
    safe = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::warning title=report-event-to-sheet::{safe}")


def _load_service_account(raw: str) -> dict:
    raw = raw.strip()
    if not raw:
        raise ValueError("GOOGLE_SHEETS_SA_KEY is empty")
    # Accept either raw JSON or base64-encoded JSON.
    if not raw.startswith("{"):
        raw = base64.b64decode(raw).decode("utf-8")
    return json.loads(raw)


def _build_row() -> list[str]:
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    # Order MUST match bootstrap_sheet.HEADERS.
    return [
        now,
        os.environ.get("EVENT_REPO", ""),
        os.environ.get("EVENT_BRANCH", ""),
        os.environ.get("EVENT_WORKFLOW", ""),
        os.environ.get("EVENT_RUN_ID", ""),
        os.environ.get("EVENT_RUN_URL", ""),
        os.environ.get("EVENT_TYPE", ""),
        os.environ.get("EVENT_CATEGORY", ""),
        os.environ.get("EVENT_SEVERITY", ""),
        os.environ.get("EVENT_TITLE", ""),
        os.environ.get("EVENT_COMMIT", ""),
        os.environ.get("EVENT_ACTOR", ""),
        os.environ.get("EVENT_CONSECUTIVE_FAILURES", ""),
        os.environ.get("EVENT_SLACK_TS", ""),
    ]


def main() -> int:
    strict = os.environ.get("SHEET_STRICT", "false").lower() == "true"
    try:
        spreadsheet_id = os.environ["SHEET_SPREADSHEET_ID"]
        tab = os.environ.get("SHEET_TAB", "events")
        sa_info = _load_service_account(os.environ.get("GOOGLE_SHEETS_SA_KEY", ""))

        from google.oauth2.service_account import Credentials
        from googleapiclient.discovery import build

        creds = Credentials.from_service_account_info(
            sa_info, scopes=["https://www.googleapis.com/auth/spreadsheets"]
        )
        service = build("sheets", "v4", credentials=creds, cache_discovery=False)

        row = _build_row()
        service.spreadsheets().values().append(
            spreadsheetId=spreadsheet_id,
            range=f"{tab}!A1",
            # RAW (never USER_ENTERED): event fields such as branch name, run title
            # or actor are attacker-influenceable, and USER_ENTERED would evaluate a
            # leading =/+/-/@ as a formula (spreadsheet formula injection).
            valueInputOption="RAW",
            insertDataOption="INSERT_ROWS",
            body={"values": [row]},
        ).execute()
        print(f"Appended {row[6] or 'event'} for '{row[3]}' [{row[2]}] to '{tab}'.")
        return 0
    except Exception as exc:  # noqa: BLE001 - best-effort reporter, never block CI
        _warn(f"failed to append event: {exc}")
        return 1 if strict else 0


if __name__ == "__main__":
    sys.exit(main())
