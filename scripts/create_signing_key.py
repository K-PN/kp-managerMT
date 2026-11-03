"""Create an RSA distribution signing key locally. Never print or overwrite the key."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def create_key(destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as output:
            result = subprocess.run(["openssl", "genrsa", "-traditional", "2048"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if not result.stdout.startswith(b"-----BEGIN RSA PRIVATE KEY-----"):
                raise ValueError("OpenSSL did not produce a PKCS#1 RSA key.")
            output.write(result.stdout)
    except BaseException:
        destination.unlink(missing_ok=True)
        raise


def main() -> int:
    destination = ROOT / ".local-signing/ios_distribution_private_key.pem"
    try:
        create_key(destination)
    except FileExistsError:
        print("A signing key already exists. Keep it; this command does not overwrite it.", file=sys.stderr)
        return 1
    except (OSError, ValueError, subprocess.CalledProcessError):
        print("Could not create the key. Install OpenSSL 3+ and retry. No key contents were printed.", file=sys.stderr)
        return 1
    print(f"Created {destination}. Copy its contents directly to Codemagic's secret CERTIFICATE_PRIVATE_KEY.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
