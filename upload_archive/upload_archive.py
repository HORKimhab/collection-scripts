import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from dotenv import load_dotenv
except ImportError:  # pragma: no cover - optional dependency at runtime
    load_dotenv = None


BASE_DIR = Path(__file__).resolve().parent


def load_env() -> None:
    """Load optional env files without overriding exported shell variables."""
    if load_dotenv is None:
        return
    load_dotenv(BASE_DIR / ".archive.env", override=False)
    load_dotenv(BASE_DIR.parent / ".env", override=False)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Upload a file to Archive.org with optional OpenSSL encryption."
    )
    parser.add_argument("--identifier", required=True, help="Archive.org item identifier.")
    parser.add_argument("--file", required=True, help="Local file path to upload.")
    parser.add_argument(
        "--remote-name",
        help="Remote filename inside the Archive.org item. Defaults to the local filename.",
    )
    parser.add_argument("--title", help="Metadata title for the item.")
    parser.add_argument("--description", help="Metadata description for the item.")
    parser.add_argument(
        "--collection",
        action="append",
        default=[],
        help="Collection metadata. Repeat the flag to add multiple collections.",
    )
    parser.add_argument(
        "--mediatype",
        help="Metadata mediatype, for example: data, texts, movies, audio.",
    )
    parser.add_argument(
        "--metadata",
        action="append",
        default=[],
        help="Extra metadata in key=value format. Repeat as needed.",
    )
    password_group = parser.add_mutually_exclusive_group()
    password_group.add_argument(
        "--password",
        help="Password used to encrypt the file before upload. Avoid shell history when possible.",
    )
    password_group.add_argument(
        "--password-env",
        help="Read the encryption password from this environment variable name.",
    )
    parser.add_argument(
        "--keep-encrypted-file",
        action="store_true",
        help="Keep the encrypted file on disk instead of deleting the temporary copy.",
    )
    parser.add_argument(
        "--encrypted-output",
        help="When set, write the encrypted file to this path instead of a temporary file.",
    )
    parser.add_argument(
        "--openssl-bin",
        default="openssl",
        help="OpenSSL executable to use. Defaults to 'openssl'.",
    )
    parser.add_argument(
        "--openssl-iter",
        type=int,
        default=200000,
        help="PBKDF2 iteration count for OpenSSL encryption. Defaults to 200000.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would happen without encrypting or uploading.",
    )
    return parser


def fail(message: str, exit_code: int = 1) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(exit_code)


def parse_metadata(metadata_args):
    metadata = {}
    for raw in metadata_args:
        if "=" not in raw:
            fail(f"Invalid --metadata value '{raw}'. Expected key=value.")
        key, value = raw.split("=", 1)
        key = key.strip()
        if not key:
            fail(f"Invalid --metadata value '{raw}'. Key cannot be empty.")
        metadata[key] = value.strip()
    return metadata


def collect_metadata(args):
    metadata = parse_metadata(args.metadata)

    if args.title:
        metadata["title"] = args.title
    elif os.getenv("ARCHIVE_METADATA_TITLE"):
        metadata["title"] = os.getenv("ARCHIVE_METADATA_TITLE", "")

    if args.description:
        metadata["description"] = args.description
    elif os.getenv("ARCHIVE_METADATA_DESCRIPTION"):
        metadata["description"] = os.getenv("ARCHIVE_METADATA_DESCRIPTION", "")

    collections = list(args.collection)
    default_collection = os.getenv("ARCHIVE_COLLECTION", "").strip()
    if not collections and default_collection:
        collections.append(default_collection)
    if collections:
        metadata["collection"] = collections if len(collections) > 1 else collections[0]

    mediatype = args.mediatype or os.getenv("ARCHIVE_MEDIATYPE", "").strip()
    if mediatype:
        metadata["mediatype"] = mediatype

    return metadata


def resolve_password(args):
    if args.password is not None:
        return args.password
    if args.password_env:
        value = os.getenv(args.password_env)
        if value is None:
            fail(f"Environment variable '{args.password_env}' is not set.")
        return value
    return None


def ensure_file_exists(path_str: str) -> Path:
    path = Path(path_str).expanduser().resolve()
    if not path.is_file():
        fail(f"File not found: {path}")
    return path


def ensure_archive_credentials():
    access_key = os.getenv("IAS3_ACCESS_KEY")
    secret_key = os.getenv("IAS3_SECRET_KEY")
    if not access_key or not secret_key:
        fail(
            "Missing IAS3 credentials. Set IAS3_ACCESS_KEY and IAS3_SECRET_KEY, "
            "for example in upload_archive/.archive.env."
        )
    return access_key, secret_key


def encrypt_file_with_openssl(source: Path, password: str, args) -> tuple[Path, bool]:
    if shutil.which(args.openssl_bin) is None:
        fail(f"OpenSSL binary '{args.openssl_bin}' was not found in PATH.")

    if args.encrypted_output:
        output_path = Path(args.encrypted_output).expanduser().resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        cleanup_required = False
    else:
        temp_dir = Path(tempfile.mkdtemp(prefix="archive-upload-"))
        output_path = temp_dir / f"{source.name}.enc"
        cleanup_required = not args.keep_encrypted_file

    env = os.environ.copy()
    env["ARCHIVE_UPLOAD_PASSWORD"] = password
    cmd = [
        args.openssl_bin,
        "enc",
        "-aes-256-cbc",
        "-pbkdf2",
        "-iter",
        str(args.openssl_iter),
        "-salt",
        "-in",
        str(source),
        "-out",
        str(output_path),
        "-pass",
        "env:ARCHIVE_UPLOAD_PASSWORD",
    ]

    try:
        subprocess.run(cmd, check=True, env=env, capture_output=True, text=True)
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        fail(f"OpenSSL encryption failed: {stderr or exc}")

    return output_path, cleanup_required


def summarize_result(result) -> bool:
    if isinstance(result, bool):
        return result
    if result is None:
        return True
    try:
        values = list(result)
    except TypeError:
        return True

    success = True
    for value in values:
        status_code = getattr(value, "status_code", None)
        url = getattr(value, "url", None)
        if status_code is not None:
            print(f"  Response: {status_code} {url or ''}".rstrip())
            if int(status_code) >= 400:
                success = False
    return success


def stage_remote_name(upload_path: Path, remote_name: str) -> tuple[Path, Path | None]:
    if upload_path.name == remote_name:
        return upload_path, None

    temp_dir = Path(tempfile.mkdtemp(prefix="archive-remote-name-"))
    staged_path = temp_dir / remote_name
    shutil.copy2(upload_path, staged_path)
    return staged_path, temp_dir


def upload_file(identifier: str, upload_path: Path, metadata, access_key: str, secret_key: str):
    try:
        from internetarchive import get_item
    except ImportError:
        fail(
            "Missing dependency 'internetarchive'. Install it with "
            "`python3 -m pip install -r upload_archive/requirements.txt`."
        )

    item = get_item(identifier)
    return item.upload(
        str(upload_path),
        metadata=metadata or None,
        access_key=access_key,
        secret_key=secret_key,
        verbose=True,
    )


def cleanup_encrypted_file(encrypted_path: Path) -> None:
    parent = encrypted_path.parent
    if parent.name.startswith("archive-upload-"):
        shutil.rmtree(parent, ignore_errors=True)
    else:
        encrypted_path.unlink(missing_ok=True)


def cleanup_temp_dir(temp_dir: Path | None) -> None:
    if temp_dir is not None:
        shutil.rmtree(temp_dir, ignore_errors=True)


def main() -> None:
    load_env()
    parser = build_parser()
    args = parser.parse_args()

    local_file = ensure_file_exists(args.file)
    password = resolve_password(args)
    metadata = collect_metadata(args)
    remote_name = args.remote_name or local_file.name

    print(f"Identifier : {args.identifier}")
    print(f"Local file : {local_file}")
    print(f"Remote name: {remote_name}")
    print(f"Encrypt    : {'yes' if password else 'no'}")
    if metadata:
        print(f"Metadata   : {metadata}")

    if args.dry_run:
        print("Dry run only. No encryption or upload was performed.")
        return

    access_key, secret_key = ensure_archive_credentials()

    upload_path = local_file
    encrypted_cleanup_required = False
    if password:
        upload_path, encrypted_cleanup_required = encrypt_file_with_openssl(local_file, password, args)
        if args.remote_name is None:
            remote_name = upload_path.name
        print(f"Encrypted  : {upload_path}")

    staged_upload_path, remote_name_temp_dir = stage_remote_name(upload_path, remote_name)
    if staged_upload_path != upload_path:
        print(f"Staged file: {staged_upload_path}")

    try:
        result = upload_file(
            identifier=args.identifier,
            upload_path=staged_upload_path,
            metadata=metadata,
            access_key=access_key,
            secret_key=secret_key,
        )
        success = summarize_result(result)
    finally:
        cleanup_temp_dir(remote_name_temp_dir)
        if password and encrypted_cleanup_required:
            cleanup_encrypted_file(upload_path)

    if not success:
        fail("Upload finished with one or more non-success responses.")

    print(f"Item URL   : https://archive.org/details/{args.identifier}")


if __name__ == "__main__":
    main()
