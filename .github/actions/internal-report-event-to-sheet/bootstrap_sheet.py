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

def _dashboard_layout(tab: str) -> list[list]:
    """Build the dashboard formulas bound to the configured events ``tab``.

    Written with USER_ENTERED (our own trusted formulas; untrusted event data is
    always written RAW by append_event.py). The tab is single-quoted so custom
    SHEET_TAB names containing spaces still resolve.
    """
    q = f"'{tab}'"
    # Timestamps are stored as text (RAW, for injection safety), so date filters
    # use string comparison (ISO sorts chronologically) via SUMPRODUCT/QUERY
    # rather than COUNTIFS, whose >=date criterion never matches text cells.
    seven = 'TEXT(NOW()-7,"yyyy-mm-dd")'
    return [
        ["CI Events Dashboard", "", "", "", ""],
        ["Auto-updates from the events tab. Most urgent first.", "", "", "", ""],
        ["Failures 7d", "Warnings 7d", "Stable-branch failures 7d", "Worst streak", "Last event"],
        [
            f'=SUMPRODUCT(({q}!$G$2:$G="failure")*({q}!$A$2:$A>={seven}))',
            f'=SUMPRODUCT(({q}!$G$2:$G="warning")*({q}!$A$2:$A>={seven}))',
            f'=SUMPRODUCT(({q}!$G$2:$G="failure")*(LEFT({q}!$C$2:$C,7)="stable/")*({q}!$A$2:$A>={seven}))',
            f'=IFERROR(MAX(ARRAYFORMULA(IF({q}!M2:M="",0,VALUE({q}!M2:M)))),0)',
            f'=IFERROR(INDEX(SORT(FILTER({q}!A2:A,{q}!A2:A<>""),1,FALSE),1,1),"-")',
        ],
        ["", "", "", "", ""],
        ["14-day failure trend", "", "Hotlist (branch / workflow / type, last 30d)", "", ""],
        [
            (
                f'=SPARKLINE(BYCOL(SEQUENCE(1,14,TODAY()-13),'
                f'LAMBDA(d,SUMPRODUCT(({q}!$G$2:$G="failure")*'
                f'({q}!$A$2:$A>=TEXT(d,"yyyy-mm-dd"))*'
                f'({q}!$A$2:$A<TEXT(d+1,"yyyy-mm-dd"))))),'
                '{"charttype","column";"color","#cc0000"})'
            ),
            "",
            (
                f'=QUERY({q}!A2:N,"select C, D, G, count(E), max(A) '
                "where A is not null and A >= '\"&TEXT(NOW()-30,\"yyyy-mm-dd\")&\"' "
                "group by C, D, G order by count(E) desc "
                "label C 'Branch', D 'Workflow', G 'Type', "
                "count(E) '# events', max(A) 'Last seen'\",0)"
            ),
            "",
            "",
        ],
    ]


def _warn(message: str) -> None:
    # Escape workflow-command metacharacters so a stray %, CR or LF in an
    # exception message cannot break log parsing or inject a workflow command.
    safe = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::warning title=bootstrap-sheet::{safe}")


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
    # Idempotent: drop any existing rules on the events sheet first so repeated
    # bootstraps don't accumulate duplicate conditional-format rules.
    meta = (
        service.spreadsheets()
        .get(
            spreadsheetId=spreadsheet_id,
            fields="sheets(properties.sheetId,conditionalFormats)",
        )
        .execute()
    )
    existing = 0
    for sheet in meta.get("sheets", []):
        if sheet["properties"]["sheetId"] == events_id:
            existing = len(sheet.get("conditionalFormats", []) or [])
            break

    requests = [
        {"deleteConditionalFormatRule": {"sheetId": events_id, "index": 0}}
        for _ in range(existing)
    ]
    # Added at index 0 in this order so the final priority is:
    # stable-branch failure (strongest) > failure > warning.
    requests += [
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
    print(f"Applied conditional formatting to 'events' (replaced {existing} rule(s)).")


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


def _fmt(sheet_id, r0, r1, c0, c1, bold=False, italic=False, font_size=None, bg=None, fg=None):
    text_format = {"bold": bold, "italic": italic}
    if font_size is not None:
        text_format["fontSize"] = font_size
    if fg is not None:
        text_format["foregroundColor"] = fg
    cell_format = {"textFormat": text_format}
    if bg is not None:
        cell_format["backgroundColor"] = bg
    return {
        "repeatCell": {
            "range": {
                "sheetId": sheet_id,
                "startRowIndex": r0,
                "endRowIndex": r1,
                "startColumnIndex": c0,
                "endColumnIndex": c1,
            },
            "cell": {"userEnteredFormat": cell_format},
            "fields": "userEnteredFormat(textFormat,backgroundColor)",
        }
    }


def _freeze(sheet_id, rows):
    return {
        "updateSheetProperties": {
            "properties": {"sheetId": sheet_id, "gridProperties": {"frozenRowCount": rows}},
            "fields": "gridProperties.frozenRowCount",
        }
    }


def _col_width(sheet_id, col, px):
    return {
        "updateDimensionProperties": {
            "range": {
                "sheetId": sheet_id,
                "dimension": "COLUMNS",
                "startIndex": col,
                "endIndex": col + 1,
            },
            "properties": {"pixelSize": px},
            "fields": "pixelSize",
        }
    }


def _apply_display_formatting(service, spreadsheet_id, events_id, triage_id, dashboard_id):
    header_bg = {"red": 0.85, "green": 0.87, "blue": 0.91}
    grey = {"red": 0.42, "green": 0.42, "blue": 0.42}
    triage_status = ["new", "investigating", "fixed", "ignored", "flaky"]
    requests = [
        # Freeze header rows.
        _freeze(events_id, 1),
        _freeze(triage_id, 1),
        _freeze(dashboard_id, 2),
        # Bold, shaded header rows.
        _fmt(events_id, 0, 1, 0, EVENTS_COL_COUNT, bold=True, bg=header_bg),
        _fmt(triage_id, 0, 1, 0, len(TRIAGE_HEADERS), bold=True, bg=header_bg),
        # Dashboard title / subtitle / KPI emphasis.
        _fmt(dashboard_id, 0, 1, 0, 1, bold=True, font_size=14),
        _fmt(dashboard_id, 1, 2, 0, 1, italic=True, fg=grey),
        _fmt(dashboard_id, 2, 3, 0, 5, bold=True),
        _fmt(dashboard_id, 3, 4, 0, 5, bold=True, font_size=12),
        # Readable column widths on events.
        _col_width(events_id, COL_BRANCH, 110),
        _col_width(events_id, COL_WORKFLOW, 300),
        _col_width(events_id, 9, 320),
        # Triage status dropdown.
        {
            "setDataValidation": {
                "range": {
                    "sheetId": triage_id,
                    "startRowIndex": 1,
                    "startColumnIndex": 4,
                    "endColumnIndex": 5,
                },
                "rule": {
                    "condition": {
                        "type": "ONE_OF_LIST",
                        "values": [{"userEnteredValue": v} for v in triage_status],
                    },
                    "showCustomUi": True,
                    "strict": False,
                },
            }
        },
    ]
    service.spreadsheets().batchUpdate(
        spreadsheetId=spreadsheet_id, body={"requests": requests}
    ).execute()
    print("Applied display formatting (freezes, headers, KPI emphasis, widths, dropdown).")


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

    # Opt-in reset: wipe data rows (keep the header). Used to clear seeded
    # preview/sample rows. Never enabled on the routine reporter path.
    if os.environ.get("SHEET_RESET", "false").lower() == "true":
        service.spreadsheets().values().clear(
            spreadsheetId=spreadsheet_id, range=f"{events_tab}!A2:N"
        ).execute()
        print(f"Reset: cleared data rows in '{events_tab}'.")

    _ensure_tab(service, spreadsheet_id, meta, "triage")
    _write(service, spreadsheet_id, "triage!A1", [TRIAGE_HEADERS])
    print("Wrote triage headers.")

    # Refresh metadata so newly created tabs are visible for id lookups.
    meta = service.spreadsheets().get(spreadsheetId=spreadsheet_id).execute()

    # Dashboard (best-effort: a formatting/pivot hiccup must not lose the core).
    try:
        _ensure_tab(service, spreadsheet_id, meta, "dashboard")
        _write(service, spreadsheet_id, "dashboard!A1", _dashboard_layout(events_tab))
        print("Wrote dashboard layout.")
    except Exception as exc:  # noqa: BLE001
        _warn(f"dashboard layout step failed: {exc}")

    try:
        _apply_conditional_formatting(service, spreadsheet_id, events_id)
    except Exception as exc:  # noqa: BLE001
        _warn(f"conditional formatting step failed: {exc}")

    try:
        meta = service.spreadsheets().get(spreadsheetId=spreadsheet_id).execute()
        pivot_id = _ensure_tab(service, spreadsheet_id, meta, "pivot")
        _build_pivot(service, spreadsheet_id, events_id, pivot_id)
    except Exception as exc:  # noqa: BLE001
        _warn(f"pivot step failed: {exc}")

    try:
        meta = service.spreadsheets().get(spreadsheetId=spreadsheet_id).execute()
        triage_id = _sheet_id(meta, "triage")
        dashboard_id = _sheet_id(meta, "dashboard")
        if triage_id is not None and dashboard_id is not None:
            _apply_display_formatting(
                service, spreadsheet_id, events_id, triage_id, dashboard_id
            )
    except Exception as exc:  # noqa: BLE001
        _warn(f"display formatting step failed: {exc}")

    print("Bootstrap complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
