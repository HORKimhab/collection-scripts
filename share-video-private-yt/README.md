# share-video-private-yt

This folder contains two flows:

- `report`: uses the official YouTube Data API to read playlists, expand videos, and prepare a share plan.
- `share`: uses browser automation in YouTube Studio to add missing email viewers to private videos.

The official API can list playlists and videos, but it cannot grant private-video access to specific email addresses. The browser automation flow covers that gap.

## Files

- `playlists.txt`: one YouTube playlist URL or playlist ID per line
- `emails.txt`: one email address per line
- `.env`: runtime configuration
- `share-private-yt.sh`: Bash entrypoint

## Setup

1. Copy the examples:

```bash
cd share-video-private-yt
cp .env.example .env
cp playlists.txt.example playlists.txt
cp emails.txt.example emails.txt
```

2. Fill `.env`.

Recommended auth for the report flow:

- `YOUTUBE_ACCESS_TOKEN`: OAuth access token with YouTube read scope
- Optional fallback for public playlists only: `YOUTUBE_API_KEY`

Recommended auth for the share flow:

- Browser login to YouTube Studio in a persistent Playwright profile

3. Install browser automation dependencies when you want to run the `share` flow:

```bash
npm install
npx playwright install chromium
```

## Usage

Generate a report only:

```bash
bash share-private-yt.sh report
```

Generate a report and then open Studio automation:

```bash
bash share-private-yt.sh share
```

Install local Node dependencies:

```bash
bash share-private-yt.sh install-automation
```

## Output

Generated files are written under `output/<timestamp>/`:

- `report.json`: full machine-readable report
- `summary.txt`: human-readable summary
- `share-targets.csv`: private videos x missing emails

## Notes

- The report flow can determine `privacyStatus` only when the token has access to those videos.
- The `share` flow is launched from Bash, but the actual Studio browser automation is handled by Playwright. Pure Bash is suitable for the API/report flow, not for reliable web UI automation.
- The Studio UI changes over time. The automation script uses resilient selectors where possible, but some accounts may need small selector updates later.
- YouTube private sharing is limited by YouTube product rules, including viewer-count limits.
