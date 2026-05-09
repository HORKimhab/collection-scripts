#!/usr/bin/env python3
import argparse
import csv
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone


PLAYLIST_ID_RE = re.compile(r"(?:[?&]list=)?([A-Za-z0-9_-]{10,})")
EMAIL_RE = re.compile(r"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$", re.IGNORECASE)


def read_nonempty_lines(path):
    values = []
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            values.append(line)
    return values


def load_dotenv(dotenv_path):
    if not os.path.isfile(dotenv_path):
        return

    with open(dotenv_path, "r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            os.environ.setdefault(key, value)


def parse_playlist_id(value):
    if "youtube.com" in value or "youtu.be" in value:
      parsed = urllib.parse.urlparse(value)
      query_value = urllib.parse.parse_qs(parsed.query).get("list", [])
      if query_value:
          return query_value[0]
    match = PLAYLIST_ID_RE.search(value)
    if not match:
        raise ValueError(f"Could not parse playlist ID from: {value}")
    return match.group(1)


def validate_emails(emails):
    invalid = [email for email in emails if not EMAIL_RE.match(email)]
    if invalid:
        raise ValueError(f"Invalid email(s): {', '.join(invalid)}")


class YouTubeClient:
    def __init__(self, access_token=None, api_key=None):
        self.access_token = access_token
        self.api_key = api_key
        if not access_token and not api_key:
            raise ValueError("Set YOUTUBE_ACCESS_TOKEN or YOUTUBE_API_KEY in .env")

    def _request(self, endpoint, params, access_token=None, api_key=None):
        query = dict(params)
        if access_token:
            headers = {"Authorization": f"Bearer {access_token}"}
        else:
            query["key"] = api_key
            headers = {}

        url = "https://www.googleapis.com/youtube/v3/" + endpoint + "?" + urllib.parse.urlencode(query)
        request = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"HTTP {exc.code} for {endpoint}: {body}") from exc

    def _get(self, endpoint, params):
        if self.access_token:
            try:
                return self._request(endpoint, params, access_token=self.access_token)
            except RuntimeError as exc:
                if self.api_key and "HTTP 401" in str(exc):
                    return self._request(endpoint, params, api_key=self.api_key)
                raise

        return self._request(endpoint, params, api_key=self.api_key)

    def playlist_items(self, playlist_id):
        items = []
        page_token = None
        while True:
            params = {
                "part": "snippet,contentDetails",
                "playlistId": playlist_id,
                "maxResults": 50,
            }
            if page_token:
                params["pageToken"] = page_token
            payload = self._get("playlistItems", params)
            items.extend(payload.get("items", []))
            page_token = payload.get("nextPageToken")
            if not page_token:
                return items

    def videos(self, video_ids):
        items = []
        for index in range(0, len(video_ids), 50):
            chunk = video_ids[index:index + 50]
            payload = self._get(
                "videos",
                {
                    "part": "snippet,status",
                    "id": ",".join(chunk),
                    "maxResults": 50,
                },
            )
            items.extend(payload.get("items", []))
        return items


def build_report(playlists, emails, client):
    videos = []
    failures = []

    for original_value in playlists:
        playlist_id = parse_playlist_id(original_value)
        try:
            playlist_items = client.playlist_items(playlist_id)
        except Exception as exc:  # noqa: BLE001
            failures.append({
                "playlist": original_value,
                "playlistId": playlist_id,
                "error": str(exc),
            })
            continue

        seen_video_ids = []
        for item in playlist_items:
            video_id = (
                item.get("contentDetails", {}).get("videoId")
                or item.get("snippet", {}).get("resourceId", {}).get("videoId")
            )
            if video_id:
                seen_video_ids.append(video_id)

        details_by_id = {}
        if seen_video_ids:
            try:
                for video in client.videos(seen_video_ids):
                    details_by_id[video["id"]] = video
            except Exception as exc:  # noqa: BLE001
                failures.append({
                    "playlist": original_value,
                    "playlistId": playlist_id,
                    "error": str(exc),
                })
                continue

        for item in playlist_items:
            video_id = (
                item.get("contentDetails", {}).get("videoId")
                or item.get("snippet", {}).get("resourceId", {}).get("videoId")
            )
            if not video_id:
                continue

            detail = details_by_id.get(video_id, {})
            snippet = detail.get("snippet", {})
            status = detail.get("status", {})
            videos.append(
                {
                    "playlistInput": original_value,
                    "playlistId": playlist_id,
                    "videoId": video_id,
                    "title": snippet.get("title") or item.get("snippet", {}).get("title") or "",
                    "privacyStatus": status.get("privacyStatus", "unknown"),
                    "videoUrl": f"https://www.youtube.com/watch?v={video_id}",
                    "studioUrl": f"https://studio.youtube.com/video/{video_id}/edit",
                    "shareEmailsRequested": emails,
                }
            )

    private_videos = [video for video in videos if video["privacyStatus"] == "private"]
    share_targets = []
    for video in private_videos:
        for email in emails:
            share_targets.append(
                {
                    "playlistId": video["playlistId"],
                    "videoId": video["videoId"],
                    "title": video["title"],
                    "email": email,
                    "studioUrl": video["studioUrl"],
                }
            )

    return {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "playlistCount": len(playlists),
        "emailCount": len(emails),
        "videoCount": len(videos),
        "privateVideoCount": len(private_videos),
        "playlists": playlists,
        "emails": emails,
        "videos": videos,
        "shareTargets": share_targets,
        "failures": failures,
    }


def write_outputs(report, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    report_path = os.path.join(output_dir, "report.json")
    summary_path = os.path.join(output_dir, "summary.txt")
    csv_path = os.path.join(output_dir, "share-targets.csv")

    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, ensure_ascii=False)

    with open(summary_path, "w", encoding="utf-8") as handle:
        handle.write(f"Generated: {report['generatedAt']}\n")
        handle.write(f"Playlists: {report['playlistCount']}\n")
        handle.write(f"Emails: {report['emailCount']}\n")
        handle.write(f"Videos: {report['videoCount']}\n")
        handle.write(f"Private videos: {report['privateVideoCount']}\n")
        handle.write(f"Failures: {len(report['failures'])}\n\n")
        for video in report["videos"]:
            handle.write(
                f"[{video['privacyStatus']}] {video['title']} | {video['videoId']} | {video['playlistId']}\n"
            )

    with open(csv_path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["playlistId", "videoId", "title", "email", "studioUrl"],
        )
        writer.writeheader()
        writer.writerows(report["shareTargets"])

    return report_path, summary_path, csv_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--playlist-file", required=True)
    parser.add_argument("--emails-file", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    playlists = read_nonempty_lines(args.playlist_file)
    emails = read_nonempty_lines(args.emails_file)
    validate_emails(emails)

    project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    load_dotenv(os.path.join(project_dir, ".env"))

    client = YouTubeClient(
        access_token=os.environ.get("YOUTUBE_ACCESS_TOKEN", "").strip() or None,
        api_key=os.environ.get("YOUTUBE_API_KEY", "").strip() or None,
    )
    report = build_report(playlists, emails, client)
    report_path, summary_path, csv_path = write_outputs(report, args.output_dir)

    print(f"Report written: {report_path}")
    print(f"Summary written: {summary_path}")
    print(f"CSV written: {csv_path}")
    print(
        f"Processed {report['videoCount']} videos across {report['playlistCount']} playlists; "
        f"{report['privateVideoCount']} private videos require Studio sharing."
    )
    if report["failures"]:
        print(f"Encountered {len(report['failures'])} playlist failures.", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
