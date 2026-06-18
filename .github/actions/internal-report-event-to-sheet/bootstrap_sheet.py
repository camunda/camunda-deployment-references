#!/usr/bin/env python3
"""Bootstrap the CI-events reporting Google Sheet.

Creates/refreshes the structure used by the reporter:

* ``events``    - append-only log (header row). MUST stay in sync with
                  ``append_event.py``.
* ``triage``    - human-editable classification, keyed by ``run_id``.
* ``dashboard`` - readable, auto-updating overview: KPI scorecards, a grouped
                  "hotlist" (branch / workflow / type), and a 14-day trend.
* ``pivot``     - a native pivot table (Branch -> Workflow rows, Type columns,
                  event counts) for collapsible grouping.

Plus conditional formatting on ``events`` for at-a-glance severity colours.

Safe to run repeatedly. Triggered manually via the reporter workflow's
``workflow_dispatch`` entry point. Credentials come from
``GOOGLE_SHEETS_SA_KEY`` (raw or base64 JSON); the service account needs Editor
access to the spreadsheet.
"""
from __future__ import annotations

import base64
import json
import os
import sys

# Order MUST match the row built in append_event.py.
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

TRIAGE_HEADERS = [
    "run_id",
    "branch",
    "workflow",
    "type",
    "status",
    "owner",
    "root_cause",
    "linked_issue_or_pr",
    "notes",
    "updated_at",
]

# Column offsets (0-based) into the events tab, for the pivot and formatting.
COL_BRANCH = 2
COL_WORKFLOW = 3
COL_RUN_ID = 4
COL_TYPE = 6
EVENTS_COL_COUNT = len(HEADERS)

# Dashboard formulas. Written with USER_ENTERED (these are our own trusted
# formulas; untrusted event data is always written RAW by append_event.py).
SEVEN_DAYS = '">="&TEXT(NOW()-7,"yyyy-mm-dd")'
THIRTY_DAYS = '">="&TEXT(NOW()-30,"yyyy-mm-dd")'

DASHBOARD_LAYOUT = [
    ["CI Events Dashboard", "", "", "", ""],
    ["Auto-updates from the events tab. Most urgent first.", "", "", "", ""],
    ["Failures 7d", "Warnings 7d", "Stable-branch failures 7d", "Worst streak", "Last event"],
    [
        f'=COUNTIFS(events!G:G,"failure",events!A:A,{SEVEN_DAYS})',
        f'=COUNTIFS(events!G:G,"warning",events!A:A,{SEVEN_DAYS})',
        f'=COUNTIFS(events!G:G,"failure",events!C:C,"stable/*",events!A:A,{SEVEN_DAYS})',
        '=IFERROR(MAX(ARRAYFORMULA(IF(events!M2:M="",0,VALUE(events!M2:M)))),0)',
        '=IFERROR(INDEX(SORT(FILTER(events!A2:A,events!A2:A<>""),1,FALSE),1,1),"-")',
    ],
    ["", "", "", "", ""],
    ["14-day failure trend", "", "Hotlist (branch / workflow / type, last 30d)", "", ""],
    [
        (
            '=SPARKLINE(BYCOL(SEQUENCE(1,14,TODAY()-13),'
            'LAMBDA(d,COUNTIFS(events!$G:$G,"failure",'
            'events!$A:$A,">="&TEXT(d,"yyyy-mm-dd"),'
            'events!$A:$A,"<"&TEXT(d+1,"yyyy-mm-dd")))),'
            '{"charttype","column";"color","#cc0000"})'
        ),
        "",
        (
            '=QUERY(events!A2:N,"select C, D, G, count(E), max(A) '
            "where A is not null and A >= '\"&TEXT(NOW()-30,\"yyyy-mm-dd\")&\"' "
            "group by C, D, G order by count(E) desc "
            "label C 'Branch', D 'Workflow', G 'Type', "
            "count(E) '# events', max(A) 'Last seen'\",0)"
        ),
        "",
        "",
    ],
]


def _load_service_account(raw: str) -> dict:
    raw = raw.strip()
    if not raw:
        raise ValueError("GOOGLE_SHEETS_SA_KEY is empty")
    if not raw.startswith("{"):
        raw = base64.b64decode(raw).decode("utf-8")
    return json.loads(raw)


def _sheet_id(meta: dict, title: str):
    for sheet in meta.get("sheets", []):
        if sheet["properties"]["title"] == title:
            return sheet["properties"]["sheetId"]
    return None


def _ensure_tab(service, spreadsheet_id: str, meta: dict, title: str):
    """Return the sheetId of ``title``, creating the tab if needed."""
    sheet_id = _sheet_id(meta, title)
    if sheet_id is not None:
        return sheet_id
    resp = (
        service.spreadsheets()
        .batchUpdate(
            spreadsheetId=spreadsheet_id,
            body={"requests": [{"addSheet": {"properties": {"title": title}}}]},
        )
        .execute()
    )
    print(f"Created tab '{title}'.")
    return resp["replies"][0]["addSheet"]["properties"]["sheetId"]


def _write(service, spreadsheet_id: str, rng: str, values: list[list]) -> None:
    service.spreadsheets().values().update(
        spreadsheetId=spreadsheet_id,
        range=rng,
        valueInputOption="USER_ENTERED",
        body={"values": values},
    ).execute()


def _solid(red: float, green: float, blue: float) -> dict:
    return {"backgroundColor": {"red": red, "green": green, "blue": blue}}


def _cf_rule(events_id: int, index: int, formula: str, colour: dict) -> dict:
    return {
        "addConditionalFormatRule": {
            "index": index,
            "rule": {
                "ranges": [
                    {
                        "sheetId": events_id,
                        "startRowIndex": 1,
                        "startColumnIndex": 0,
                        "endColumnIndex": EVENTS_COL_COUNT,
                    }
                ],
                "booleanRule": {
                    "condition": {
                        "type": "CUSTOM_FORMULA",
                        "values": [{"userEnteredValue": formula}],
                    },
                    "format": colour,
                },
            },
        }
    }


def _apply_conditional_formatting(service, spreadsheet_id: str, events_id: int) -> None:
    # Inserted at index 0 in this order so the final priority is:
    # stable-branch failure (strongest) > failure > warning.
    requests = [
        _cf_rule(events_id, 0, '=$G2="warning"', _solid(1, 0.95, 0.70)),
        _cf_rule(events_id, 0, '=$G2="failure"', _solid(0.99, 0.87, 0.82)),
        _cf_rule(
            events_id,
            0,
            '=AND($G2="failure",REGEXMATCH($C2,"^stable/"))',
            _solid(0.96, 0.73, 0.73),
        ),
    ]
    service.spreadsheets().batchUpdate(
        spreadsheetId=spreadsheet_id, body={"requests": requests}
    ).execute()
    print("Applied conditional formatting to 'events'.")


def _build_pivot(service, spreadsheet_id: str, events_id: int, pivot_id: int) -> None:
    pivot_table = {
        "source": {
            "sheetId": events_id,
            "startRowIndex": 0,
            "startColumnIndex": 0,
            "endColumnIndex": EVENTS_COL_COUNT,
        },
        "rows": [
            {"sourceColumnOffset": COL_BRANCH, "showTotals": True, "sortOrder": "ASCENDING"},
            {"sourceColumnOffset": COL_WORKFLOW, "showTotals": True, "sortOrder": "ASCENDING"},
        ],
        "columns": [
            {"sourceColumnOffset": COL_TYPE, "showTotals": True, "sortOrder": "ASCENDING"}
        ],
        "values": [{"summarizeFunction": "COUNTA", "sourceColumnOffset": COL_RUN_ID}],
        "valueLayout": "HORIZONTAL",
    }
    service.spreadsheets().batchUpdate(
        spreadsheetId=spreadsheet_id,
        body={
            "requests": [
                {
                    "updateCells": {
                        "rows": [{"values": [{"pivotTable": pivot_table}]}],
                        "start": {"sheetId": pivot_id, "rowIndex": 0, "columnIndex": 0},
                        "fields": "pivotTable",
                    }
                }
            ]
        },
    ).execute()
    print("Built pivot table on 'pivot'.")


def main() -> int:
    spreadsheet_id = os.environ["SHEET_SPREADSHEET_ID"]
    events_tab = os.environ.get("SHEET_TAB", "events")
    sa_info = _load_service_account(os.environ.get("GOOGLE_SHEETS_SA_KEY", ""))

    from google.oauth2.service_account import Credentials
    from googleapiclient.discovery import build

    creds = Credentials.from_service_account_info(
        sa_info, scopes=["https://www.googleapis.com/auth/spreadsheets"]
    )
    service = build("sheets", "v4", credentials=creds, cache_discovery=False)

    meta = service.spreadsheets().get(spreadsheetId=spreadsheet_id).execute()

    # Core (must succeed): events + triage headers.
    events_id = _ensure_tab(service, spreadsheet_id, meta, events_tab)
    _write(service, spreadsheet_id, f"{events_tab}!A1", [HEADERS])
    print(f"Wrote {len(HEADERS)} headers to '{events_tab}'.")

    _ensure_tab(service, spreadsheet_id, meta, "triage")
    _write(service, spreadsheet_id, "triage!A1", [TRIAGE_HEADERS])
    print("Wrote triage headers.")

    # Refresh metadata so newly created tabs are visible for id lookups.
    meta = service.spreadsheets().get(spreadsheetId=spreadsheet_id).execute()

    # Dashboard (best-effort: a formatting/pivot hiccup must not lose the core).
    try:
        _ensure_tab(service, spreadsheet_id, meta, "dashboard")
        _write(service, spreadsheet_id, "dashboard!A1", DASHBOARD_LAYOUT)
        print("Wrote dashboard layout.")
    except Exception as exc:  # noqa: BLE001
        print(f"::warning::dashboard layout step failed: {exc}")

    try:
        _apply_conditional_formatting(service, spreadsheet_id, events_id)
    except Exception as exc:  # noqa: BLE001
        print(f"::warning::conditional formatting step failed: {exc}")

    try:
        meta = service.spreadsheets().get(spreadsheetId=spreadsheet_id).execute()
        pivot_id = _ensure_tab(service, spreadsheet_id, meta, "pivot")
        _build_pivot(service, spreadsheet_id, events_id, pivot_id)
    except Exception as exc:  # noqa: BLE001
        print(f"::warning::pivot step failed: {exc}")

    print("Bootstrap complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
