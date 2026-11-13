#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================================
# DAILY IT NEWS AND SERVICE MONITOR
# Monitors Microsoft 365, Outlook, cloud, SaaS, security
# and IT infrastructure.
# Output: Windows Desktop/dailynews/
# ==========================================================

python3 <<'PYTHON'

import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from html import escape
import re

# ==========================================================
# CONFIGURATION
# ==========================================================

HOURS_BACK = 48
MAX_ITEMS = 100
TIMEOUT = 20

OUTPUT_DIR = Path("/mnt/c/Users/ArtanV/Desktop/dailynews")

FEEDS = [
    # Microsoft and cloud service status
    ("Microsoft 365 / Outlook", "status",
     "https://status.cloud.microsoft/api/feed/mac"),
    ("Azure", "status",
     "https://rssfeed.azure.status.microsoft/en-us/status/feed/"),
    ("AWS", "status",
     "https://status.aws.amazon.com/rss/all.rss"),
    ("Google Cloud", "status",
     "https://status.cloud.google.com/en/feed.atom"),
    ("Cloudflare", "status",
     "https://www.cloudflarestatus.com/history.atom"),
    ("GitHub", "status",
     "https://www.githubstatus.com/history.rss"),
    ("OpenAI", "status",
     "https://status.openai.com/feed.rss"),
    ("Atlassian", "status",
     "https://status.atlassian.com/history.rss"),
    ("Slack", "status",
     "https://status.slack.com/feed/rss"),
    ("Zoom", "status",
     "https://status.zoom.us/history.rss"),

    # Cybersecurity and IT news
    ("BleepingComputer", "news",
     "https://www.bleepingcomputer.com/feed/"),
    ("The Hacker News", "news",
     "https://feeds.feedburner.com/TheHackersNews"),
    ("Krebs on Security", "news",
     "https://krebsonsecurity.com/feed/"),
    ("CISA Advisories", "security",
     "https://www.cisa.gov/cybersecurity-advisories/all.xml"),
    ("SANS Internet Storm Center", "security",
     "https://isc.sans.edu/rssfeed_full.xml"),
    ("The Register Security", "news",
     "https://www.theregister.com/security/headlines.atom"),
    ("Ars Technica", "news",
     "https://feeds.arstechnica.com/arstechnica/index"),
]

NOW = datetime.now(timezone.utc)
CUTOFF = NOW - timedelta(hours=HOURS_BACK)

# ==========================================================
# SEVERITY CLASSIFICATION
# ==========================================================

HIGH_WORDS = [
    "outage",
    "service disruption",
    "degraded",
    "vulnerability",
    "exploit",
    "breach",
    "malware",
    "phishing",
    "compromised",
    "authentication failure",
    "security incident",
    "denial of service",
    "ddos",
    "ransomware",
    "data breach",
]

MEDIUM_WORDS = [
    "incident",
    "interruption",
    "latency",
    "performance",
    "patch",
    "update",
    "maintenance",
    "advisory",
    "security",
]

def classify_severity(title, summary, kind):
    text = (title + " " + summary).lower()

    if kind == "status" and "scheduled" in text:
        if "no operational impact" in text:
            return "INFO"
        if "maintenance" in text:
            return "MEDIUM"

    if any(phrase in text for phrase in [
        "global outage", "widespread outage", "complete outage",
        "critical outage", "mass exploitation",
    ]):
        return "CRITICAL"

    if kind in ("news", "security") and any(phrase in text for phrase in [
        "actively exploited", "actively exploiting", "active exploitation",
        "under active exploitation", "exploited in the wild",
        "zero-day exploited", "zero day exploited", "critical vulnerability",
    ]):
        return "CRITICAL"

    if kind == "status" and any(phrase in text for phrase in [
        "major outage", "service outage", "service disruption",
        "service unavailable", "authentication failure", "denial of service",
    ]):
        return "HIGH"

    if any(word in text for word in HIGH_WORDS):
        return "HIGH"

    if any(word in text for word in MEDIUM_WORDS):
        return "MEDIUM"

    return "INFO"


# ==========================================================
# CATEGORY CLASSIFICATION
# ==========================================================

def classify_category(title, summary, source):
    text = (title + " " + summary + " " + source).lower()

    if any(x in text for x in [
        "microsoft 365", "office 365", "outlook",
        "exchange", "sharepoint", "teams"
    ]):
        return "Microsoft 365 / Outlook"

    if any(x in text for x in [
        "azure", "aws", "amazon web services",
        "google cloud", "cloudflare", "cloud platform"
    ]):
        return "Cloud"

    if any(x in text for x in [
        "ransomware", "malware", "phishing",
        "vulnerability", "cve-", "exploit",
        "cybersecurity", "data breach", "hacker"
    ]):
        return "Cybersecurity"

    if any(x in text for x in [
        "network", "server", "datacenter",
        "data center", "storage", "database",
        "infrastructure", "linux", "windows"
    ]):
        return "Infrastructure"

    if any(x in text for x in [
        "github", "slack", "zoom", "atlassian",
        "openai", "saas", "software"
    ]):
        return "SaaS / Applications"

    return "General IT"


# ==========================================================
# DATE AND TEXT HELPERS
# ==========================================================

def parse_date(value):
    if not value:
        return None

    try:
        dt = parsedate_to_datetime(value)

        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)

        return dt.astimezone(timezone.utc)

    except Exception:
        pass

    try:
        dt = datetime.fromisoformat(
            value.replace("Z", "+00:00")
        )

        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)

        return dt.astimezone(timezone.utc)

    except Exception:
        return None


def clean_text(value):
    value = re.sub(r"<[^>]+>", " ", value or "")
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def get_child_text(element, names):
    for child in element.iter():

        tag = child.tag.split("}")[-1].lower()

        if tag in names:

            if tag == "link":
                href = child.attrib.get("href")

                if href:
                    return href

            if child.text:
                return child.text.strip()

    return ""


# ==========================================================
# RSS AND ATOM FEED READER
# ==========================================================

def fetch_feed(source, kind, url):

    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "DailyITMonitor/1.0"
        }
    )

    with urllib.request.urlopen(
        request,
        timeout=TIMEOUT
    ) as response:

        data = response.read()

    root = ET.fromstring(data)

    results = []

    for element in root.iter():

        tag = element.tag.split("}")[-1].lower()

        if tag not in ("item", "entry"):
            continue

        title = get_child_text(
            element,
            {"title"}
        )

        link = get_child_text(
            element,
            {"link", "guid"}
        )

        summary = get_child_text(
            element,
            {"description", "summary", "content", "encoded"}
        )

        date_text = get_child_text(
            element,
            {"pubdate", "published", "updated", "date", "created"}
        )

        dt = parse_date(date_text)

        if not title:
            continue

        if dt is None or dt < CUTOFF or dt > NOW:
            continue

        title = clean_text(title)
        summary = clean_text(summary)

        results.append({
            "source": source,
            "kind": kind,
            "title": title,
            "summary": summary[:900],
            "date": dt,
            "link": link,
            "severity": classify_severity(
                title, summary, kind
            ),
            "category": classify_category(
                title, summary, source
            ),
        })

    return results


# ==========================================================
# COLLECT FEED INFORMATION
# ==========================================================

print()
print("=" * 65)
print("          DAILY IT NEWS AND SERVICE MONITOR")
print("=" * 65)

print("Started:", NOW.astimezone().strftime(
    "%Y-%m-%d %H:%M %Z"
))

print()

all_items = []
failed_sources = []

for source, kind, url in FEEDS:

    print("Checking:", source)

    try:

        found = fetch_feed(
            source,
            kind,
            url
        )

        all_items.extend(found)

        print("  Found", len(found), "recent items")

    except Exception as error:

        failed_sources.append(source)

        print("  WARNING:", str(error)[:180])


# ==========================================================
# REMOVE DUPLICATES
# ==========================================================

unique = {}

for item in all_items:

    key = re.sub(
        r"\W+",
        "",
        item["title"].lower()
    )

    if key not in unique:
        unique[key] = item

items = list(unique.values())


# ==========================================================
# SORT BY PRIORITY AND DATE
# ==========================================================

priority = {
    "CRITICAL": 0,
    "HIGH": 1,
    "MEDIUM": 2,
    "INFO": 3,
}

items.sort(
    key=lambda x: (
        priority[x["severity"]],
        -x["date"].timestamp()
    )
)

items = items[:MAX_ITEMS]


# ==========================================================
# SUMMARY STATISTICS
# ==========================================================

counts = {
    level: sum(
        1 for item in items
        if item["severity"] == level
    )
    for level in priority
}

categories = {}

for item in items:

    category = item["category"]

    categories[category] = (
        categories.get(category, 0) + 1
    )


# ==========================================================
# MARKDOWN REPORT
# ==========================================================

today = NOW.astimezone().strftime(
    "%Y-%m-%d %H:%M %Z"
)

md = [
    "# Daily IT News and Service Monitoring",
    "",
    f"**Generated:** {today}",
    f"**Reporting period:** Last {HOURS_BACK} hours",
    "",
    "## Executive Summary",
    "",
    f"- Total items: **{len(items)}**",
    f"- Critical: **{counts['CRITICAL']}**",
    f"- High: **{counts['HIGH']}**",
    f"- Medium: **{counts['MEDIUM']}**",
    f"- Informational: **{counts['INFO']}**",
    "",
    "## Category Overview",
    "",
]

for category, count in sorted(
    categories.items(),
    key=lambda x: (-x[1], x[0])
):

    md.append(f"- {category}: {count}")

md += [
    "",
    "## Incidents and News",
    "",
]

html_items = {level: [] for level in priority}

for item in items:

    date = item["date"].astimezone().strftime(
        "%Y-%m-%d %H:%M %Z"
    )

    md += [
        f"### [{item['severity']}] {item['title']}",
        "",
        f"- **Source:** {item['source']}",
        f"- **Category:** {item['category']}",
        f"- **Date:** {date}",
    ]

    if item["link"]:
        md.append(f"- **Link:** {item['link']}")

    if item["summary"]:
        md += [
            "",
            item["summary"]
        ]

    md.append("")

    link_html = ""

    if item["link"].startswith("https://"):

        link_html = (
            '<p><a href="' +
            escape(item["link"], quote=True) +
            '" target="_blank" rel="noopener">'
            'Open source</a></p>'
        )

        html_items[item["severity"]].append(f"""
        <article class="story">
            <div class="story-meta">
                <span class="category">{escape(item['category'])}</span>
                <span>{escape(item['source'])}</span>
                <time>{escape(date)}</time>
            </div>
            <h3>{escape(item['title'])}</h3>
            <p>{escape(item['summary']) if item['summary'] else 'No summary was provided by the source.'}</p>
            {link_html}
        </article>
        """)

severity_labels = {
        "CRITICAL": "Critical",
        "HIGH": "High",
        "MEDIUM": "Medium",
        "INFO": "Informational",
}

severity_sections = []

for level, label in severity_labels.items():
        story_content = "".join(html_items[level])

        if not story_content:
                story_content = '<p class="empty-state">No items at this level in the reporting period.</p>'

        severity_sections.append(f"""
        <section class="severity-section {level.lower()}" id="{level.lower()}" aria-labelledby="heading-{level.lower()}">
            <div class="section-heading">
                <div>
                    <p class="section-kicker">{level}</p>
                    <h2 id="heading-{level.lower()}">{label}</h2>
                </div>
                <span class="section-count">{counts[level]} {"item" if counts[level] == 1 else "items"}</span>
            </div>
            <div class="stories">{story_content}</div>
        </section>
        """)


if not items:

    md += [
        "No recent items were retrieved.",
        "",
        "Check feed connectivity and source URLs.",
    ]


if failed_sources:

    md += [
        "",
        "## Sources That Could Not Be Reached",
        "",
    ]

    for source in failed_sources:
        md.append(f"- {source}")


# ==========================================================
# HTML REPORT
# ==========================================================

source_count = len({item["source"] for item in items})
priority_items = sorted(
    items,
    key=lambda x: (priority[x["severity"]], -x["date"].timestamp())
)[:5]

top_alerts_html = []
for item in priority_items:
    date = item["date"].astimezone().strftime("%Y-%m-%d %H:%M %Z")
    summary = item["summary"] or "No summary was provided by the source."
    top_alerts_html.append(f"""
        <article class=\"priority-card\" data-severity=\"{escape(item['severity'])}\" data-category=\"{escape(item['category'])}\">
            <div class=\"priority-card-header\">
                <span class=\"severity-badge severity-{escape(item['severity']).lower()}\">{escape(item['severity'])}</span>
                <span class=\"category-tag\">{escape(item['category'])}</span>
            </div>
            <h3>{escape(item['title'])}</h3>
            <p>{escape(summary[:220])}</p>
            <div class=\"priority-card-meta\">
                <span>{escape(item['source'])}</span>
                <time>{escape(date)}</time>
            </div>
        </article>
    """)

news_cards_html = []
for item in items:
    date = item["date"].astimezone().strftime("%Y-%m-%d %H:%M %Z")
    summary = item["summary"] or "No summary was provided by the source."
    severity_label = severity_labels.get(item["severity"], item["severity"].title())
    detail_link = ""
    if item["link"] and item["link"].startswith("https://"):
        detail_link = f'<a href="{escape(item["link"], quote=True)}" target="_blank" rel="noopener">Open source</a>'

    news_cards_html.append(f"""
        <article class=\"news-card\" data-severity=\"{escape(item['severity'])}\" data-category=\"{escape(item['category'])}\" data-title=\"{escape(item['title'])}\" data-source=\"{escape(item['source'])}\" data-date=\"{item['date'].isoformat()}\">
            <div class=\"news-card-header\">
                <span class=\"severity-badge severity-{escape(item['severity']).lower()}\">{escape(severity_label)}</span>
                <span class=\"category-tag\">{escape(item['category'])}</span>
            </div>
            <h3>{escape(item['title'])}</h3>
            <div class=\"news-card-meta\">
                <span>{escape(item['source'])}</span>
                <time>{escape(date)}</time>
            </div>
            <p class=\"news-summary\">{escape(summary[:260])}</p>
            <div class=\"news-card-actions\">
                <button type=\"button\" class=\"toggle-details\" aria-expanded=\"false\">Show details</button>
                {detail_link if detail_link else '<span class=\"muted-link\">Source link unavailable</span>'}
            </div>
            <div class=\"news-details\" hidden>
                <p>{escape(summary)}</p>
            </div>
        </article>
    """)

intel_rows_html = []
for item in sorted(items, key=lambda x: (priority[x["severity"]], -x["date"].timestamp()))[:12]:
    date = item["date"].astimezone().strftime("%Y-%m-%d %H:%M %Z")
    link_html = "—"
    if item["link"] and item["link"].startswith("https://"):
        link_html = f'<a href="{escape(item["link"], quote=True)}" target="_blank" rel="noopener">Open</a>'
    intel_rows_html.append(f"""
        <tr>
            <td>{escape(item['severity'])}</td>
            <td>{escape(item['title'])}</td>
            <td>{escape(item['source'])}</td>
            <td>{escape(item['category'])}</td>
            <td>{escape(date)}</td>
            <td>{link_html}</td>
        </tr>
    """)

source_list_html = []
source_map = {}
for item in items:
    source_map.setdefault(item["source"], item["link"])

for source, source_link in sorted(source_map.items(), key=lambda x: x[0].lower()):
    source_category = next((item["category"] for item in items if item["source"] == source), "General IT")
    source_anchor = "—"
    if source_link and source_link.startswith("https://"):
        source_anchor = f'<a href="{escape(source_link, quote=True)}" target="_blank" rel="noopener">{escape(source_link)}</a>'
    source_list_html.append(f"""
        <li class=\"source-item\">
            <div>
                <strong>{escape(source)}</strong>
                <span>{escape(source_category)}</span>
            </div>
            {source_anchor}
        </li>
    """)

severity_options_html = "".join(
    f'<option value="{level}">{label}</option>'
    for level, label in severity_labels.items()
)
category_options_html = "".join(
    f'<option value="{escape(category)}">{escape(category)}</option>'
    for category in sorted(categories.keys())
)

html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>Cybersecurity Intelligence Brief</title>
<style>
:root {{
    --bg: #f3f6fb;
    --bg-alt: #eaf1f7;
    --surface: #ffffff;
    --surface-strong: #f7f9fc;
    --surface-soft: #edf3f8;
    --line: #d9e3ee;
    --line-strong: #c2cfde;
    --text: #122033;
    --muted: #5d6f82;
    --blue: #1d5bbf;
    --blue-strong: #114097;
    --navy: #0b1d38;
    --critical: #c63b3b;
    --high: #d86d2c;
    --medium: #c69a1b;
    --info: #1f6baa;
    --shadow: 0 14px 32px rgba(11, 29, 56, 0.08);
    --radius: 18px;
}}
body[data-theme="dark"] {{
    --bg: #071521;
    --bg-alt: #0c1d2b;
    --surface: #102335;
    --surface-strong: #0d1d2d;
    --surface-soft: #132a3b;
    --line: #1d3448;
    --line-strong: #2b455d;
    --text: #edf5ff;
    --muted: #9eb3c8;
    --blue: #66a3ff;
    --blue-strong: #8cc0ff;
    --navy: #0c1d2d;
    --shadow: 0 16px 36px rgba(0, 0, 0, 0.35);
}}
* {{ box-sizing: border-box; }}
html {{ scroll-behavior: smooth; }}
body {{
    margin: 0;
    background: linear-gradient(180deg, var(--bg-alt) 0%, var(--bg) 200px);
    color: var(--text);
    font-family: Inter, "Segoe UI", sans-serif;
    line-height: 1.55;
}}
a {{ color: var(--blue); text-decoration: none; }}
a:hover {{ color: var(--blue-strong); }}
button, input, select {{ font: inherit; }}
img {{ max-width: 100%; }}
[hidden] {{ display: none !important; }}
.topbar {{
    position: sticky;
    top: 0;
    z-index: 20;
    backdrop-filter: blur(12px);
    background: rgba(11, 29, 56, 0.86);
    border-bottom: 1px solid rgba(255,255,255,0.08);
    box-shadow: 0 10px 20px rgba(8, 16, 24, 0.12);
}}
.topbar-inner {{
    max-width: 1320px;
    margin: 0 auto;
    padding: 0 22px;
    min-height: 72px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 20px;
}}
.brand-lockup {{
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
}}
.brand-mark {{
    width: 36px;
    height: 36px;
    border-radius: 10px;
    background: linear-gradient(135deg, #2a6de6 0%, #73b8ff 100%);
    position: relative;
    box-shadow: inset 0 0 0 1px rgba(255,255,255,0.18);
}}
.brand-mark::before {{
    content: "";
    position: absolute;
    inset: 9px;
    border-radius: 8px;
    border: 2px solid rgba(255,255,255,0.8);
    border-left-width: 4px;
    transform: rotate(45deg);
}}
.brand-copy {{
    display: flex;
    flex-direction: column;
    min-width: 0;
}}
.brand-copy strong {{
    color: #eef6ff;
    font-size: 0.9rem;
    letter-spacing: 0.14em;
    text-transform: uppercase;
}}
.brand-copy span {{
    color: rgba(225, 236, 248, 0.75);
    font-size: 0.7rem;
}}
.nav-links {{
    display: flex;
    align-items: center;
    gap: 18px;
    flex-wrap: wrap;
}}
.nav-links a {{
    color: rgba(236, 244, 252, 0.82);
    font-size: 0.8rem;
    letter-spacing: 0.04em;
    text-transform: uppercase;
}}
.nav-actions {{ display: flex; align-items: center; gap: 12px; }}
.theme-toggle {{
    border: 1px solid rgba(255,255,255,0.14);
    background: rgba(255,255,255,0.06);
    color: #eef6ff;
    border-radius: 999px;
    padding: 8px 14px;
    cursor: pointer;
}}
.page-shell {{
    max-width: 1320px;
    margin: 0 auto;
    padding: 30px 22px 42px;
}}
.report-hero {{
    background: linear-gradient(180deg, var(--surface) 0%, rgba(255,255,255,0.92) 100%);
    border: 1px solid var(--line);
    border-radius: var(--radius);
    box-shadow: var(--shadow);
    padding: 28px clamp(20px, 2vw, 32px);
}}
body[data-theme="dark"] .report-hero {{
    background: linear-gradient(180deg, rgba(13, 29, 45, 0.96) 0%, rgba(16, 35, 53, 0.96) 100%);
}}
.hero-topline {{
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 20px;
    flex-wrap: wrap;
    margin-bottom: 18px;
}}
.overline {{
    margin: 0;
    color: var(--blue);
    text-transform: uppercase;
    letter-spacing: 0.13em;
    font-size: 0.72rem;
    font-weight: 800;
}}
.hero-grid {{
    display: grid;
    grid-template-columns: minmax(0, 1.5fr) minmax(260px, 0.8fr);
    gap: 26px;
    align-items: center;
}}
.hero-copy h1 {{
    margin: 6px 0 12px;
    font-size: clamp(2rem, 3vw, 3.1rem);
    line-height: 1.08;
    letter-spacing: -0.05em;
}}
.hero-copy p {{
    margin: 0;
    color: var(--muted);
    max-width: 720px;
    font-size: 1.02rem;
}}
.hero-metrics {{
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 12px;
}}
.metric-pill {{
    background: var(--surface-soft);
    border: 1px solid var(--line);
    border-radius: 14px;
    padding: 14px 16px;
}}
.metric-pill span {{
    display: block;
    font-size: 0.75rem;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.08em;
}}
.metric-pill strong {{
    display: block;
    margin-top: 6px;
    font-size: 1.3rem;
    letter-spacing: -0.03em;
}}
.summary-grid {{
    display: grid;
    grid-template-columns: repeat(5, minmax(0, 1fr));
    gap: 14px;
    margin-top: 28px;
}}
.stat-card {{
    background: var(--surface);
    border: 1px solid var(--line);
    border-top: 4px solid var(--blue);
    border-radius: 16px;
    box-shadow: var(--shadow);
    padding: 18px 18px 14px;
    min-height: 116px;
}}
.stat-card.critical {{ border-top-color: var(--critical); }}
.stat-card.high {{ border-top-color: var(--high); }}
.stat-card.medium {{ border-top-color: var(--medium); }}
.stat-card.info {{ border-top-color: var(--info); }}
.stat-card .label {{
    display: block;
    color: var(--muted);
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
}}
.stat-card .value {{
    display: block;
    margin-top: 10px;
    font-size: clamp(2rem, 2vw, 2.4rem);
    line-height: 1;
    letter-spacing: -0.06em;
}}
.panel {{
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: var(--radius);
    box-shadow: var(--shadow);
    margin-top: 24px;
    padding: 22px;
}}
.intel-layout {{
    display: grid;
    grid-template-columns: minmax(0, 1.3fr) minmax(260px, 0.7fr);
    gap: 24px;
}}
.panel h2 {{
    margin: 0 0 14px;
    font-size: clamp(1.2rem, 2vw, 1.8rem);
    letter-spacing: -0.04em;
}}
.priority-list {{
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 14px;
}}
.priority-card {{
    background: var(--surface-strong);
    border: 1px solid var(--line);
    border-left: 4px solid var(--blue);
    border-radius: 14px;
    padding: 16px 16px 14px;
}}
.priority-card h3 {{
    margin: 14px 0 8px;
    font-size: 1.02rem;
    line-height: 1.4;
}}
.priority-card p {{
    margin: 0;
    color: var(--muted);
    font-size: 0.92rem;
}}
.priority-card-meta {{
    display: flex;
    justify-content: space-between;
    gap: 8px;
    margin-top: 12px;
    color: var(--muted);
    font-size: 0.73rem;
}}
.priority-card-header, .news-card-header {{
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    flex-wrap: wrap;
}}
.severity-badge, .category-tag {{
    display: inline-flex;
    align-items: center;
    border-radius: 999px;
    padding: 5px 9px;
    font-size: 0.68rem;
    font-weight: 800;
    letter-spacing: 0.06em;
    text-transform: uppercase;
}}
.severity-badge {{
    color: #fff;
    background: var(--blue);
}}
.severity-critical {{ background: var(--critical); }}
.severity-high {{ background: var(--high); }}
.severity-medium {{ background: var(--medium); }}
.severity-info {{ background: var(--info); }}
.category-tag {{
    background: var(--surface-soft);
    color: var(--text);
    border: 1px solid var(--line);
    letter-spacing: 0.04em;
    text-transform: none;
}}
.overview-stack {{
    display: grid;
    gap: 14px;
}}
.category-list {{
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
}}
.category-pill {{
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 7px 10px;
    border-radius: 999px;
    background: var(--surface-soft);
    border: 1px solid var(--line);
    color: var(--muted);
    font-size: 0.74rem;
    font-weight: 600;
}}
.category-pill strong {{ color: var(--text); }}
.feed-status {{
    display: grid;
    gap: 8px;
    color: var(--muted);
    font-size: 0.92rem;
}}
.feed-status strong {{ color: var(--text); }}
.controls {{
    display: flex;
    flex-wrap: wrap;
    gap: 14px;
    align-items: end;
}}
.field {{
    display: grid;
    gap: 6px;
    min-width: 170px;
    flex: 1;
}}
.field label {{
    color: var(--muted);
    font-size: 0.74rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.08em;
}}
.field input, .field select {{
    width: 100%;
    border: 1px solid var(--line-strong);
    border-radius: 12px;
    padding: 10px 12px;
    background: var(--surface-strong);
    color: var(--text);
}}
.feed-header {{
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    flex-wrap: wrap;
    margin-bottom: 16px;
}}
.feed-header span {{
    color: var(--muted);
    font-size: 0.82rem;
    font-weight: 600;
}}
.news-grid {{
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 16px;
}}
.news-card {{
    background: var(--surface-strong);
    border: 1px solid var(--line);
    border-left: 4px solid var(--blue);
    border-radius: 16px;
    padding: 18px;
    min-width: 0;
}}
.news-card[data-severity="CRITICAL"] {{ border-left-color: var(--critical); }}
.news-card[data-severity="HIGH"] {{ border-left-color: var(--high); }}
.news-card[data-severity="MEDIUM"] {{ border-left-color: var(--medium); }}
.news-card[data-severity="INFO"] {{ border-left-color: var(--info); }}
.news-card h3 {{
    margin: 14px 0 8px;
    font-size: 1.08rem;
    line-height: 1.42;
}}
.news-card-meta {{
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    color: var(--muted);
    font-size: 0.77rem;
    justify-content: space-between;
}}
.news-summary {{
    margin: 12px 0 0;
    color: var(--muted);
    font-size: 0.92rem;
}}
.news-card-actions {{
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin-top: 14px;
    padding-top: 12px;
    border-top: 1px solid var(--line);
}}
.toggle-details {{
    border: 1px solid var(--line-strong);
    background: transparent;
    color: var(--text);
    padding: 7px 12px;
    border-radius: 999px;
    cursor: pointer;
}}
.muted-link {{
    color: var(--muted);
    font-size: 0.76rem;
    font-weight: 600;
}}
.news-details {{
    margin-top: 12px;
    padding-top: 12px;
    border-top: 1px solid var(--line);
    color: var(--muted);
    font-size: 0.88rem;
}}
.table-wrap {{
    overflow-x: auto;
    border: 1px solid var(--line);
    border-radius: 12px;
}}
.table-wrap table {{
    width: 100%;
    border-collapse: collapse;
    min-width: 760px;
}}
.table-wrap th, .table-wrap td {{
    padding: 14px 16px;
    border-bottom: 1px solid var(--line);
    text-align: left;
    vertical-align: top;
}}
.table-wrap th {{
    background: var(--surface-soft);
    color: var(--muted);
    font-size: 0.72rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
}}
.table-wrap td {{
    color: var(--text);
    font-size: 0.93rem;
}}
.table-wrap tr:last-child td {{ border-bottom: none; }}
.source-list {{
    list-style: none;
    padding: 0;
    margin: 0;
    display: grid;
    gap: 10px;
}}
.source-item {{
    display: flex;
    justify-content: space-between;
    gap: 16px;
    align-items: center;
    background: var(--surface-strong);
    border: 1px solid var(--line);
    border-radius: 12px;
    padding: 14px 16px;
}}
.source-item div {{
    display: grid;
    gap: 4px;
}}
.source-item span {{
    color: var(--muted);
    font-size: 0.76rem;
    text-transform: uppercase;
    letter-spacing: 0.06em;
}}
.source-item a {{
    color: var(--blue);
    overflow-wrap: anywhere;
    font-size: 0.82rem;
}}
.footer-note {{
    max-width: 1320px;
    margin: 0 auto;
    padding: 0 22px 28px;
    color: var(--muted);
    font-size: 0.75rem;
}}
@media (max-width: 980px) {{
    .hero-grid, .intel-layout {{ grid-template-columns: 1fr; }}
    .summary-grid {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
    .news-grid, .priority-list {{ grid-template-columns: 1fr; }}
}}
@media (max-width: 640px) {{
    .topbar-inner {{ flex-wrap: wrap; padding-top: 10px; padding-bottom: 10px; }}
    .nav-links {{ width: 100%; justify-content: space-between; }}
    .summary-grid {{ grid-template-columns: 1fr; }}
    .controls {{ display: grid; }}
    .source-item {{ flex-direction: column; align-items: flex-start; }}
}}
</style>
</head>
<body data-theme="light">
<header class="topbar">
    <div class="topbar-inner">
        <div class="brand-lockup" aria-label="Cybersecurity intelligence brand">
            <div class="brand-mark" aria-hidden="true"></div>
            <div class="brand-copy">
                <strong>Cybersecurity Intelligence</strong>
                <span>Operations dashboard</span>
            </div>
        </div>
        <nav class="nav-links" aria-label="Primary navigation">
            <a href="#summary">Summary</a>
            <a href="#intelligence">Threat overview</a>
            <a href="#feed">News feed</a>
            <a href="#sources">Sources</a>
        </nav>
        <div class="nav-actions">
            <button type="button" class="theme-toggle" data-theme-toggle aria-label="Toggle color theme">Dark mode</button>
        </div>
    </div>
</header>
<main class="page-shell">
    <section class="report-hero" id="summary">
        <div class="hero-topline">
            <p class="overline">Security operations brief</p>
            <span class="category-tag">Reporting period: Last {HOURS_BACK} hours</span>
        </div>
        <div class="hero-grid">
            <div class="hero-copy">
                <h1>Cybersecurity Intelligence Brief</h1>
                <p>Action-oriented monitoring of critical security developments, operational incidents, advisories, and trusted industry reporting across configured feeds.</p>
            </div>
            <div class="hero-metrics">
                <div class="metric-pill">
                    <span>Generated</span>
                    <strong>{escape(today)}</strong>
                </div>
                <div class="metric-pill">
                    <span>Last updated</span>
                    <strong>{escape(today)}</strong>
                </div>
                <div class="metric-pill">
                    <span>Sources</span>
                    <strong>{len(FEEDS)}</strong>
                </div>
                <div class="metric-pill">
                    <span>Active in report</span>
                    <strong>{source_count}</strong>
                </div>
            </div>
        </div>
        <div class="summary-grid" aria-label="Executive summary metrics">
            <div class="stat-card total">
                <span class="label">Total stories</span>
                <strong class="value">{len(items)}</strong>
            </div>
            <div class="stat-card critical">
                <span class="label">Critical</span>
                <strong class="value">{counts['CRITICAL']}</strong>
            </div>
            <div class="stat-card high">
                <span class="label">High</span>
                <strong class="value">{counts['HIGH']}</strong>
            </div>
            <div class="stat-card medium">
                <span class="label">Medium</span>
                <strong class="value">{counts['MEDIUM']}</strong>
            </div>
            <div class="stat-card info">
                <span class="label">Informational</span>
                <strong class="value">{counts['INFO']}</strong>
            </div>
        </div>
    </section>

    <section class="panel" id="intelligence">
        <div class="intel-layout">
            <div>
                <p class="overline">Threat overview</p>
                <h2>Priority developments</h2>
                <div class="priority-list">
                    {''.join(top_alerts_html) if top_alerts_html else '<article class="priority-card"><h3>No prioritised items</h3><p>No recent intelligence matches the configured reporting period.</p></article>'}
                </div>
            </div>
            <div class="overview-stack">
                <div>
                    <p class="overline">Coverage</p>
                    <h2>By category</h2>
                    <div class="category-list">
                        {''.join(f'<span class="category-pill">{escape(k)} <strong>{v}</strong></span>' for k, v in sorted(categories.items(), key=lambda x: (-x[1], x[0]))) if categories else '<span class="category-pill">No categories available</span>'}
                    </div>
                </div>
                <div>
                    <p class="overline">Source health</p>
                    <div class="feed-status">
                        <strong>{len(FEEDS) - len(failed_sources)} of {len(FEEDS)} feeds responded</strong>
                        <span>{'Unavailable: ' + ', '.join(escape(x) for x in failed_sources) if failed_sources else 'No feed errors reported.'}</span>
                    </div>
                </div>
            </div>
        </div>
    </section>

    <section class="panel">
        <div class="controls" aria-label="Filters and sorting controls">
            <div class="field" style="flex: 2 1 300px;">
                <label for="searchInput">Search</label>
                <input id="searchInput" type="search" placeholder="Search headlines, sources, categories..." />
            </div>
            <div class="field">
                <label for="severityFilter">Severity</label>
                <select id="severityFilter">
                    <option value="">All severities</option>
                    {severity_options_html}
                </select>
            </div>
            <div class="field">
                <label for="categoryFilter">Category</label>
                <select id="categoryFilter">
                    <option value="">All categories</option>
                    {category_options_html}
                </select>
            </div>
            <div class="field">
                <label for="sortSelect">Sort</label>
                <select id="sortSelect">
                    <option value="date-desc">Newest first</option>
                    <option value="severity">Severity order</option>
                </select>
            </div>
        </div>
    </section>

    <section class="panel" id="feed">
        <div class="feed-header">
            <div>
                <p class="overline">Security feed</p>
                <h2>Collective news and advisories</h2>
            </div>
            <span id="resultCount">{len(items)} items shown</span>
        </div>
        <div class="news-grid" id="newsGrid">
            {''.join(news_cards_html) if news_cards_html else '<article class="news-card"><h3>No items available</h3><p>There are no recent stories in the current reporting window.</p></article>'}
        </div>
    </section>

    <section class="panel">
        <p class="overline">Vulnerability and advisory intelligence</p>
        <h2>Priority intelligence table</h2>
        <div class="table-wrap">
            <table aria-label="Priority intelligence table">
                <thead>
                    <tr>
                        <th>Severity</th>
                        <th>Title</th>
                        <th>Source</th>
                        <th>Category</th>
                        <th>Published</th>
                        <th>Reference</th>
                    </tr>
                </thead>
                <tbody>
                    {''.join(intel_rows_html) if intel_rows_html else '<tr><td colspan="6">No intelligence entries in the current reporting window.</td></tr>'}
                </tbody>
            </table>
        </div>
    </section>

    <section class="panel" id="sources">
        <p class="overline">Source references</p>
        <h2>Original source directory</h2>
        <ul class="source-list">
            {''.join(source_list_html) if source_list_html else '<li class="source-item"><div><strong>No sources</strong><span>Unavailable</span></div><span>No source links were captured in the current window.</span></li>'}
        </ul>
    </section>
</main>
<footer class="footer-note">
    Items are sourced from the configured vendor feeds, advisories, and trusted security publications. This dashboard is for operational awareness and should be paired with direct source review for any critical incident or active exploitation claim.
</footer>
<script>
(() => {{
    const body = document.body;
    const toggleButton = document.querySelector('[data-theme-toggle]');
    const preferredTheme = localStorage.getItem('theme') || (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');

    const applyTheme = (theme) => {{
        body.setAttribute('data-theme', theme);
        toggleButton.textContent = theme === 'dark' ? 'Light mode' : 'Dark mode';
    }};

    applyTheme(preferredTheme);
    toggleButton.addEventListener('click', () => {{
        const nextTheme = body.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
        localStorage.setItem('theme', nextTheme);
        applyTheme(nextTheme);
    }});

    const cards = Array.from(document.querySelectorAll('.news-card'));
    const searchInput = document.getElementById('searchInput');
    const severityFilter = document.getElementById('severityFilter');
    const categoryFilter = document.getElementById('categoryFilter');
    const sortSelect = document.getElementById('sortSelect');
    const resultCount = document.getElementById('resultCount');
    const newsGrid = document.getElementById('newsGrid');

    const applyFilters = () => {{
        const term = searchInput.value.trim().toLowerCase();
        const severity = severityFilter.value;
        const category = categoryFilter.value;
        const sortMode = sortSelect.value;

        const visibleCards = cards.filter((card) => {{
            const text = [
                card.dataset.title || '',
                card.dataset.source || '',
                card.dataset.category || '',
                card.textContent || ''
            ].join(' ').toLowerCase();

            const matchesSearch = term === '' || text.includes(term);
            const matchesSeverity = !severity || card.dataset.severity === severity;
            const matchesCategory = !category || card.dataset.category === category;
            return matchesSearch && matchesSeverity && matchesCategory;
        }});

        let orderedCards = [...visibleCards];
        if (sortMode === 'severity') {{
            const severityOrder = {{ CRITICAL: 0, HIGH: 1, MEDIUM: 2, INFO: 3 }};
            orderedCards.sort((a, b) => {{
                const severityDelta = (severityOrder[a.dataset.severity] ?? 99) - (severityOrder[b.dataset.severity] ?? 99);
                if (severityDelta !== 0) return severityDelta;
                return Date.parse(b.dataset.date) - Date.parse(a.dataset.date);
            }});
        }} else {{
            orderedCards.sort((a, b) => Date.parse(b.dataset.date) - Date.parse(a.dataset.date));
        }}

        cards.forEach((card) => {{
            const isVisible = visibleCards.includes(card);
            card.hidden = !isVisible;
        }});

        orderedCards.forEach((card) => newsGrid.appendChild(card));
        resultCount.textContent = `${{visibleCards.length}} item${{visibleCards.length === 1 ? '' : 's'}} shown`;
    }};

    searchInput.addEventListener('input', applyFilters);
    severityFilter.addEventListener('change', applyFilters);
    categoryFilter.addEventListener('change', applyFilters);
    sortSelect.addEventListener('change', applyFilters);

    document.querySelectorAll('.toggle-details').forEach((button) => {{
        button.addEventListener('click', () => {{
            const card = button.closest('.news-card');
            const details = card.querySelector('.news-details');
            const expanded = button.getAttribute('aria-expanded') === 'true';
            button.setAttribute('aria-expanded', String(!expanded));
            details.hidden = expanded;
            button.textContent = expanded ? 'Show details' : 'Hide details';
        }});
    }});

    applyFilters();
}})();
</script>
</body>
</html>
"""


# ==========================================================
# SAVE REPORTS TO WINDOWS DESKTOP
# ==========================================================

print()
print("Saving reports...")

OUTPUT_DIR.mkdir(
    parents=True,
    exist_ok=True
)

markdown_file = OUTPUT_DIR / "dailynews.md"
html_file = OUTPUT_DIR / "dailynews.html"

markdown_file.write_text(
    "\n".join(md),
    encoding="utf-8"
)

html_file.write_text(
    html,
    encoding="utf-8"
)


# ==========================================================
# FINAL TERMINAL SUMMARY
# ==========================================================

print()
print("=" * 65)
print("                 REPORT COMPLETE")
print("=" * 65)

print()
print("Total items:    ", len(items))
print("Critical:       ", counts["CRITICAL"])
print("High:           ", counts["HIGH"])
print("Medium:         ", counts["MEDIUM"])
print("Informational:  ", counts["INFO"])

print()
print("OUTPUT DIRECTORY:")
print(OUTPUT_DIR)

print()
print("MARKDOWN REPORT:")
print(markdown_file)

print()
print("HTML REPORT:")
print(html_file)

if failed_sources:

    print()
    print("FEEDS WITH ERRORS:")

    for source in failed_sources:
        print(" -", source)

print()
print("Finished successfully.")
print("=" * 65)

PYTHON

