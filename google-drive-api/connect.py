import io
import mimetypes
import stat
import zipfile
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaIoBaseDownload

SCOPES = ["https://www.googleapis.com/auth/drive.readonly"]
BASE_DIR = Path(__file__).resolve().parent
TOKEN_PATH = BASE_DIR / "token.json"
CREDENTIALS_PATH = BASE_DIR / "credentials.json"
SEARCH_FILE_PATH = BASE_DIR / "search.txt"
DOWNLOADS_DIR = BASE_DIR / "downloads"
ZIP_PATH = BASE_DIR / "downloads.zip"
ENV_PATH = BASE_DIR / ".env"

EXPORT_MIME_TYPES = {
    "application/vnd.google-apps.document":
        ("application/pdf", ".pdf"),
    "application/vnd.google-apps.spreadsheet":
        ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", ".xlsx"),
    "application/vnd.google-apps.presentation":
        ("application/vnd.openxmlformats-officedocument.presentationml.presentation", ".pptx"),
    "application/vnd.google-apps.drawing":
        ("image/png", ".png"),
}


def load_client_config():
  if not CREDENTIALS_PATH.exists():
    raise FileNotFoundError(
        f"Missing {CREDENTIALS_PATH.name}. Add your OAuth client file here."
    )

  client_config = json.loads(CREDENTIALS_PATH.read_text())
  if "installed" not in client_config:
    raise ValueError(
        f"{CREDENTIALS_PATH.name} must be a Google OAuth desktop client JSON. "
        "Create a 'Desktop app' OAuth client in Google Cloud Console and "
        "download that file here."
    )

  return client_config


def ensure_private_file(path):
  mode = stat.S_IMODE(path.stat().st_mode)
  if mode & 0o077:
    raise PermissionError(
        f"{path.name} permissions are too open. Run 'chmod 600 {path.name}' "
        "so only your user can read and write it."
    )


def load_env_file():
  if not ENV_PATH.exists():
    raise FileNotFoundError(
        f"Missing {ENV_PATH.name}. Add FOLDER_ID to that file."
    )

  ensure_private_file(ENV_PATH)

  env = {}
  for raw_line in ENV_PATH.read_text().splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
      continue

    key, separator, value = line.partition("=")
    if not separator:
      continue

    key = key.strip()
    value = value.strip().strip("'").strip('"')
    env[key] = value

  return env


def load_folder_id():
  env = load_env_file()
  folder_id = env.get("FOLDER_ID", "").strip()
  if not folder_id:
    raise ValueError(
        f"Missing FOLDER_ID in {ENV_PATH.name}. Add your target Google Drive folder ID."
    )
  return folder_id


def load_credentials():
  creds = None
  if TOKEN_PATH.exists():
    try:
      creds = Credentials.from_authorized_user_file(TOKEN_PATH, SCOPES)
    except ValueError:
      creds = None

  if creds and creds.valid:
    return creds

  if creds and creds.expired and creds.refresh_token:
    creds.refresh(Request())
  else:
    client_config = load_client_config()
    flow = InstalledAppFlow.from_client_config(client_config, SCOPES)
    creds = flow.run_local_server(port=0)

  TOKEN_PATH.write_text(creds.to_json())
  return creds


def load_search_terms():
  if not SEARCH_FILE_PATH.exists():
    raise FileNotFoundError(
        f"Missing {SEARCH_FILE_PATH.name}. Add one search term per line."
    )

  terms = []
  seen = set()
  for raw_line in SEARCH_FILE_PATH.read_text().splitlines():
    term = raw_line.strip()
    if not term or term.startswith("#"):
      continue
    if term in seen:
      continue
    seen.add(term)
    terms.append(term)
  return terms


def escape_drive_query_value(value):
  return value.replace("\\", "\\\\").replace("'", "\\'")


def search_files(service, folder_id, term):
  escaped_term = escape_drive_query_value(term)
  query = (
      f"'{folder_id}' in parents and trashed = false and "
      f"(name contains '{escaped_term}' or fullText contains '{escaped_term}')"
  )
  page_token = None
  matches = []

  while True:
    response = (
        service.files()
        .list(
            q=query,
            spaces="drive",
            fields=(
                "nextPageToken,"
                "files(id, name, mimeType, modifiedTime, size)"
            ),
            pageToken=page_token,
            pageSize=100,
        )
        .execute()
    )
    matches.extend(response.get("files", []))
    page_token = response.get("nextPageToken")
    if not page_token:
      return matches


def sanitize_filename(name):
  safe = "".join(char if char not in '/\\:*?"<>|' else "_" for char in name)
  return safe.strip() or "download"


def build_output_name(file_metadata):
  original_name = sanitize_filename(file_metadata["name"])
  mime_type = file_metadata["mimeType"]

  if mime_type in EXPORT_MIME_TYPES:
    _, extension = EXPORT_MIME_TYPES[mime_type]
    base_name = Path(original_name).stem
    return f"{base_name}{extension}"

  if Path(original_name).suffix:
    return original_name

  guessed_extension = mimetypes.guess_extension(mime_type or "")
  if guessed_extension:
    return f"{original_name}{guessed_extension}"
  return original_name


def build_output_path(file_metadata):
  output_name = build_output_name(file_metadata)
  output_path = DOWNLOADS_DIR / output_name
  if not output_path.exists():
    return output_path

  stem = output_path.stem
  suffix = output_path.suffix
  counter = 2
  while True:
    candidate = DOWNLOADS_DIR / f"{stem} ({counter}){suffix}"
    if not candidate.exists():
      return candidate
    counter += 1


def download_file(service, file_metadata):
  file_id = file_metadata["id"]
  mime_type = file_metadata["mimeType"]
  output_path = build_output_path(file_metadata)

  if mime_type in EXPORT_MIME_TYPES:
    export_mime_type, _ = EXPORT_MIME_TYPES[mime_type]
    request = service.files().export_media(
        fileId=file_id,
        mimeType=export_mime_type,
    )
  else:
    request = service.files().get_media(fileId=file_id)

  buffer = io.BytesIO()
  downloader = MediaIoBaseDownload(buffer, request)

  done = False
  while not done:
    _, done = downloader.next_chunk()

  output_path.write_bytes(buffer.getvalue())
  return output_path


def write_zip_archive(paths):
  with zipfile.ZipFile(ZIP_PATH, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in paths:
      archive.write(path, arcname=path.name)


def main():
  try:
    creds = load_credentials()
    folder_id = load_folder_id()
    search_terms = load_search_terms()
    service = build("drive", "v3", credentials=creds)

    matched_files = {}
    for term in search_terms:
      results = search_files(service, folder_id, term)
      print(f"{term}: {len(results)} match(es)")
      for file_metadata in results:
        matched_files[file_metadata["id"]] = file_metadata

    if not matched_files:
      print("No matching files found.")
      return

    DOWNLOADS_DIR.mkdir(exist_ok=True)
    downloaded_paths = []

    for file_metadata in sorted(matched_files.values(), key=lambda item: item["name"].lower()):
      output_path = download_file(service, file_metadata)
      downloaded_paths.append(output_path)
      print(f"Downloaded {file_metadata['name']} -> {output_path.name}")

    write_zip_archive(downloaded_paths)
    print(f"Created {ZIP_PATH}")
  except FileNotFoundError as error:
    print(error)
  except PermissionError as error:
    print(error)
  except ValueError as error:
    print(error)
  except HttpError as error:
    print(f"An error occurred: {error}")


if __name__ == "__main__":
  main()
