import random
import sqlite3
import string
from datetime import datetime, timezone
from pathlib import Path

DB_PATH = Path(__file__).parent.parent / "data" / "records.db"

DEPARTMENTS = [
    "Engineering", "Sales", "Marketing", "Finance", "HR",
    "Operations", "Legal", "Support", "Product", "Design",
]

SCHEMA = """
CREATE TABLE IF NOT EXISTS records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    age INTEGER NOT NULL,
    salary REAL NOT NULL,
    department TEXT NOT NULL,
    is_active INTEGER NOT NULL,
    score REAL NOT NULL,
    notes TEXT NOT NULL,
    created_at TEXT NOT NULL
);
"""


def _random_string(rng: random.Random, length: int) -> str:
    return "".join(rng.choices(string.ascii_lowercase, k=length))


def _random_name(rng: random.Random) -> str:
    first = _random_string(rng, rng.randint(4, 8)).capitalize()
    last = _random_string(rng, rng.randint(5, 10)).capitalize()
    return f"{first} {last}"


def _random_email(rng: random.Random, name: str) -> str:
    parts = name.lower().split()
    domain = _random_string(rng, 6)
    return f"{parts[0]}.{parts[1]}@{domain}.com"


def _random_notes(rng: random.Random) -> str:
    words = [_random_string(rng, rng.randint(3, 10)) for _ in range(rng.randint(5, 20))]
    return " ".join(words)


def _random_datetime(rng: random.Random) -> str:
    year = rng.randint(2020, 2025)
    month = rng.randint(1, 12)
    day = rng.randint(1, 28)
    hour = rng.randint(0, 23)
    minute = rng.randint(0, 59)
    second = rng.randint(0, 59)
    dt = datetime(year, month, day, hour, minute, second, tzinfo=timezone.utc)
    return dt.isoformat()


def seed_db(n: int, db_path: Path | None = None) -> Path:
    """Generate n synthetic rows using n as the random seed."""
    path = db_path or DB_PATH
    path.parent.mkdir(parents=True, exist_ok=True)

    if path.exists():
        path.unlink()

    conn = sqlite3.connect(str(path))
    conn.execute(SCHEMA)

    rng = random.Random(n)
    batch = []
    for _ in range(n):
        name = _random_name(rng)
        row = (
            name,
            _random_email(rng, name),
            rng.randint(18, 70),
            round(rng.uniform(30000, 200000), 2),
            rng.choice(DEPARTMENTS),
            rng.randint(0, 1),
            round(rng.uniform(0, 100), 4),
            _random_notes(rng),
            _random_datetime(rng),
        )
        batch.append(row)

        if len(batch) >= 5000:
            conn.executemany(
                "INSERT INTO records (name, email, age, salary, department, is_active, score, notes, created_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                batch,
            )
            batch.clear()

    if batch:
        conn.executemany(
            "INSERT INTO records (name, email, age, salary, department, is_active, score, notes, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            batch,
        )

    conn.commit()
    conn.close()
    return path


def get_connection(db_path: Path | None = None) -> sqlite3.Connection:
    path = db_path or DB_PATH
    conn = sqlite3.connect(str(path))
    conn.row_factory = sqlite3.Row
    return conn


def count_records(db_path: Path | None = None) -> int:
    conn = get_connection(db_path)
    result = conn.execute("SELECT COUNT(*) FROM records").fetchone()[0]
    conn.close()
    return result


def fetch_records(offset: int, limit: int, db_path: Path | None = None) -> list[dict]:
    conn = get_connection(db_path)
    rows = conn.execute(
        "SELECT * FROM records ORDER BY id LIMIT ? OFFSET ?", (limit, offset)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


if __name__ == "__main__":
    n = 100_000
    path = seed_db(n)
    count = count_records()
    print(f"Seeded {count} records into {path}")
