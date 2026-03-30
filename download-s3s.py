import boto3
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dotenv import load_dotenv

# ─── LOAD .env FILE ────────────────────────────────────────
load_dotenv(".s3.env")  # reads .env file if present

# ─── CONFIG (from .env or environment variables) ───────────
AWS_ACCESS_KEY   = os.getenv("AWS_ACCESS_KEY_ID")
AWS_SECRET_KEY   = os.getenv("AWS_SECRET_ACCESS_KEY")
AWS_REGION       = os.getenv("AWS_REGION", "us-east-1")
LOCAL_DIR        = os.getenv("LOCAL_DIR", "./downloaded_images")
S3_PREFIX        = os.getenv("S3_PREFIX", "")
MAX_WORKERS      = int(os.getenv("MAX_WORKERS", "10"))

# Multiple buckets: comma-separated in .env → BUCKET_NAMES=bucket-1,bucket-2,bucket-3
BUCKET_NAMES = [b.strip() for b in os.getenv("BUCKET_NAMES", "").split(",") if b.strip()]

IMAGE_EXTENSIONS = ('.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg', '.bmp', '.tiff', '.ico')
# ───────────────────────────────────────────────────────────


def validate_config():
    """Validate required environment variables are set."""
    missing = []
    if not AWS_ACCESS_KEY:
        missing.append("AWS_ACCESS_KEY_ID")
    if not AWS_SECRET_KEY:
        missing.append("AWS_SECRET_ACCESS_KEY")
    if not BUCKET_NAMES:
        missing.append("BUCKET_NAMES")

    if missing:
        print("❌ Missing required environment variables:")
        for var in missing:
            print(f"   - {var}")
        print("\n💡 Set them in a .env file or export them:")
        print('   export AWS_ACCESS_KEY_ID="your_key"')
        print('   export AWS_SECRET_ACCESS_KEY="your_secret"')
        print('   export BUCKET_NAMES="bucket-1,bucket-2"')
        sys.exit(1)


def print_help():
    """Print usage instructions."""
    print("""
╔══════════════════════════════════════════════════════════╗
║           S3 Multi-Bucket Image Downloader               ║
╚══════════════════════════════════════════════════════════╝

USAGE:
  python download_s3_images_multi.py [--help]

SETUP (choose one):

  1️⃣  Using a .env file (recommended):
     Create a file named .env in the same folder:

       AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
       AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
       AWS_REGION=us-east-1
       BUCKET_NAMES=my-bucket-1,my-bucket-2,my-bucket-3
       LOCAL_DIR=./downloaded_images
       S3_PREFIX=
       MAX_WORKERS=10

  2️⃣  Using export (Linux/macOS):

       export AWS_ACCESS_KEY_ID="your_access_key"
       export AWS_SECRET_ACCESS_KEY="your_secret_key"
       export AWS_REGION="us-east-1"
       export BUCKET_NAMES="my-bucket-1,my-bucket-2,my-bucket-3"
       export LOCAL_DIR="./downloaded_images"
       export S3_PREFIX=""
       export MAX_WORKERS="10"

  3️⃣  Using set (Windows CMD):

       set AWS_ACCESS_KEY_ID=your_access_key
       set AWS_SECRET_ACCESS_KEY=your_secret_key
       set AWS_REGION=us-east-1
       set BUCKET_NAMES=my-bucket-1,my-bucket-2,my-bucket-3

VARIABLES:
  AWS_ACCESS_KEY_ID      (required) Your AWS access key
  AWS_SECRET_ACCESS_KEY  (required) Your AWS secret key
  BUCKET_NAMES           (required) Comma-separated bucket names
  AWS_REGION             (optional) Default: us-east-1
  LOCAL_DIR              (optional) Default: ./downloaded_images
  S3_PREFIX              (optional) S3 folder prefix, e.g. images/
  MAX_WORKERS            (optional) Parallel threads, default: 10

OUTPUT STRUCTURE:
  downloaded_images/
  ├── my-bucket-1/
  │   └── uploads/2024/photo.jpg   ← exact S3 path preserved
  └── my-bucket-2/
      └── products/logo.png
""")


def create_s3_client():
    return boto3.client(
        's3',
        aws_access_key_id=AWS_ACCESS_KEY,
        aws_secret_access_key=AWS_SECRET_KEY,
        region_name=AWS_REGION,
    )


def list_all_images(s3_client, bucket_name):
    """List all image keys in a bucket using pagination."""
    paginator = s3_client.get_paginator('list_objects_v2')
    pages = paginator.paginate(Bucket=bucket_name, Prefix=S3_PREFIX)

    image_keys = []
    for page in pages:
        for obj in page.get('Contents', []):
            key = obj['Key']
            if key.lower().endswith(IMAGE_EXTENSIONS):
                image_keys.append(key)

    return image_keys


def download_image(s3_client, bucket_name, key):
    """Download image keeping the exact S3 folder structure and filename."""
    # e.g. s3://my-bucket/uploads/2024/june/photo.jpg
    #   -> ./downloaded_images/my-bucket/uploads/2024/june/photo.jpg
    local_path = os.path.join(LOCAL_DIR, bucket_name, key)
    os.makedirs(os.path.dirname(local_path), exist_ok=True)

    try:
        s3_client.download_file(bucket_name, key, local_path)
        return f"✅ [{bucket_name}] {key}"
    except Exception as e:
        return f"❌ [{bucket_name}] {key} → {e}"


def process_bucket(s3_client, bucket_name):
    """List and download all images from one bucket."""
    print(f"\n📂 Bucket: {bucket_name}")
    print(f"   🔍 Listing images...")

    images = list_all_images(s3_client, bucket_name)

    if not images:
        print(f"   ⚠️  No images found in '{bucket_name}'")
        return 0

    print(f"   📦 Found {len(images)} image(s). Downloading...")

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {
            executor.submit(download_image, s3_client, bucket_name, key): key
            for key in images
        }
        for i, future in enumerate(as_completed(futures), 1):
            print(f"   [{i}/{len(images)}] {future.result()}")

    return len(images)


def main():
    # Show help if requested
    if "--help" in sys.argv or "-h" in sys.argv:
        print_help()
        sys.exit(0)

    validate_config()
    os.makedirs(LOCAL_DIR, exist_ok=True)

    print("╔══════════════════════════════════════════════════════════╗")
    print("║           S3 Multi-Bucket Image Downloader               ║")
    print("╚══════════════════════════════════════════════════════════╝")
    print(f"  Region     : {AWS_REGION}")
    print(f"  Buckets    : {', '.join(BUCKET_NAMES)}")
    print(f"  Prefix     : '{S3_PREFIX}' (all files)" if not S3_PREFIX else f"  Prefix     : {S3_PREFIX}")
    print(f"  Output     : {os.path.abspath(LOCAL_DIR)}")
    print(f"  Threads    : {MAX_WORKERS}")

    print("\n🔗 Connecting to S3...")
    s3 = create_s3_client()

    total = 0
    failed_buckets = []

    for bucket in BUCKET_NAMES:
        try:
            count = process_bucket(s3, bucket)
            total += count
        except Exception as e:
            print(f"❌ Could not access bucket '{bucket}': {e}")
            failed_buckets.append(bucket)

    # ─── Summary ───────────────────────────────────────────
    print("\n" + "=" * 58)
    print(f"  ✅ Total images downloaded : {total}")
    print(f"  🪣  Buckets processed       : {len(BUCKET_NAMES) - len(failed_buckets)}/{len(BUCKET_NAMES)}")
    if failed_buckets:
        print(f"  ❌ Failed buckets          : {', '.join(failed_buckets)}")
    print(f"  📁 Saved to                : {os.path.abspath(LOCAL_DIR)}")
    print("=" * 58)


if __name__ == "__main__":
    main()