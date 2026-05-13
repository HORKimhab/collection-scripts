# Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
deactivate # exit .venv
```

Create `credentials.json` in this folder, then add one search term per line to `search.txt`.
Create `.env` in this folder with `FOLDER_ID=your_google_drive_folder_id`.
Secure the file so only your user can read it:

```bash
chmod 600 .env
```

`credentials.json` must be the JSON downloaded from a Google OAuth client of type `Desktop app`.
Do not use an OAuth Playground export or a `web` client JSON here.

During login, Google will redirect back to a temporary `http://localhost:<port>/` URL.
That is expected for installed apps because `connect.py` starts a short-lived local callback server to receive the authorization code.

## Run

```bash
python connect.py
```

The script will:

- read search terms from `search.txt`
- read `FOLDER_ID` from `.env`
- search inside that Drive folder
- download every matched file into `downloads/`
- create `downloads.zip`

Google Docs files are exported as PDF, Sheets as XLSX, Slides as PPTX, and Drawings as PNG.

## More

- https://youtu.be/1y0-IfRW114?si=A8iy5T-d5iBfwNBE
- https://developers.google.com/oauthplayground/
