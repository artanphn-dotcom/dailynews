# Cybersecurity Intelligence Dashboard

A lightweight, automated monitoring dashboard for tracking cyber threats, vendor advisories, cloud service incidents, and security news from trusted public feeds.

This project pulls recent updates from status pages and security news sources, classifies each item by severity and category, removes duplicates, and produces both a readable Markdown report and a modern HTML dashboard suitable for quick operational review.

## What this project does

The script continuously collects information from a curated set of feeds including:

- Microsoft 365 / Outlook status
- Azure, AWS, Google Cloud, Cloudflare, GitHub, OpenAI, Atlassian, Slack, and Zoom service status pages
- Security news and advisories from BleepingComputer, The Hacker News, Krebs on Security, CISA, SANS Internet Storm Center, The Register, and Ars Technica

It then:

- filters items to the last 48 hours
- removes duplicate headlines
- assigns a severity level (`CRITICAL`, `HIGH`, `MEDIUM`, `INFO`)
- categorizes content such as Cybersecurity, Cloud, SaaS / Applications, Infrastructure, and Microsoft 365 / Outlook
- summarizes counts for the executive report
- writes a Markdown brief and a polished HTML dashboard

## Why this exists

Security and IT operations teams often need a fast, easy-to-scan view of:

- active incidents
- high-priority vulnerabilities or advisories
- major cloud or SaaS outages
- vendor security announcements
- newly surfaced attack or exploit activity

This project consolidates those signals into a single, browser-friendly daily intelligence brief without requiring a backend service or external database.

## Project output

The script generates the following files in the project directory:

- `dailynews.sh` — the main data collection and reporting script
- `dailynews.md` — a plain-text Markdown summary for quick reading or documentation
- `dailynews.html` — a standalone HTML dashboard built for modern browser viewing

## Dashboard features

The generated HTML report includes:

- executive KPI cards
- threat and vulnerability summary panels
- severity-based sections
- searchable and filterable content
- responsive layout for desktop and mobile devices
- dark/light theme support
- direct links to original source articles
- a professional enterprise-style SOC dashboard design

## How it works

The workflow is intentionally simple:

1. Read RSS/Atom feeds from configured sources.
2. Parse recent entries and normalize metadata.
3. Remove duplicates and sort by urgency.
4. Classify severity and category using keyword-based analysis.
5. Generate a Markdown summary report.
6. Generate a standalone HTML dashboard for presentation.

The collection logic is preserved to keep the tool useful as a practical monitoring workflow. The HTML layer focuses on presentation, readability, and usability.

## Requirements

- Bash
- Python 3
- Internet access to fetch the configured public feeds

## Usage

Run the script from the project directory:

```bash
bash ./dailynews.sh
```

This will regenerate both the Markdown and HTML outputs based on the latest available data.

## Files in this repo

```text
.
├── README.md
├── dailynews.sh
├── dailynews.md
├── dailynews.html
```

## GitHub Pages

Because the HTML output is a static file, it can be published on GitHub Pages or hosted as a standalone report on any static hosting platform.

For GitHub Pages, you can either:

- publish the project root directly as a static site, or
- copy `dailynews.html` into a `docs/` folder and configure Pages to serve that folder

Example:

```bash
mkdir docs
cp dailynews.html docs/index.html
```

Then configure GitHub Pages to serve the `docs` folder.

## Example use cases

- daily executive cyber monitoring
- IT operations incident watch-list
- vendor and cloud service status dashboard
- quick review of high-severity advisories and public security news

## Notes

- The script intentionally focuses on public and operationally relevant sources.
- It does not require a backend or database.
- Original source links remain available in the generated output.
- The data is refreshed each time the script is run.

## License

This project is provided as-is for operational monitoring and internal use. If you plan to publish or extend it publicly, ensure that any downstream licensing or source-attribution requirements for external feeds are respected.

## Contributing

This project is intentionally lightweight and easy to extend. If you want to add more feeds, change categories, improve severity logic, or enhance the dashboard design, you can do so without altering the overall structure of the project.
