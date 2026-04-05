import os
import sys
import time
import psycopg2
from psycopg2 import sql
from flask import Flask, jsonify, request

app = Flask(__name__)

# Read configuration from environment variables
DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")
APP_PORT = int(os.getenv("APP_PORT", "8080"))

# Validate required environment variables
required_env_vars = ["DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD"]
missing_vars = [var for var in required_env_vars if not os.getenv(var)]
if missing_vars:
    print(f"ERROR: Missing required environment variables: {', '.join(missing_vars)}", file=sys.stderr)
    sys.exit(1)


def get_db_connection():
    """Create and return a database connection."""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )
        return conn
    except psycopg2.Error as e:
        print(f"ERROR: Database connection failed: {e}", file=sys.stderr)
        raise


def init_db():
    """Initialize database schema if not present."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS items (
                id SERIAL PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()
        cursor.close()
        conn.close()
        print("Database initialized successfully")
    except psycopg2.Error as e:
        print(f"ERROR: Database initialization failed: {e}", file=sys.stderr)
        raise


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint with database connectivity test."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.fetchone()
        cursor.close()
        conn.close()
        return jsonify({"status": "ok", "db": "connected"}), 200
    except Exception as e:
        print(f"ERROR: Health check failed: {e}", file=sys.stderr)
        return jsonify({"status": "error", "db": "disconnected", "error": str(e)}), 500


@app.route("/items", methods=["GET"])
def get_items():
    """List all items from the database."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT id, name, created_at FROM items ORDER BY created_at DESC")
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        
        items = [{"id": row[0], "name": row[1], "created_at": str(row[2])} for row in rows]
        return jsonify({"items": items}), 200
    except Exception as e:
        print(f"ERROR: Failed to fetch items: {e}", file=sys.stderr)
        return jsonify({"error": str(e)}), 500


@app.route("/items", methods=["POST"])
def create_item():
    """Create a new item in the database."""
    try:
        data = request.get_json()
        if not data or "name" not in data:
            return jsonify({"error": "Missing 'name' field"}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO items (name) VALUES (%s) RETURNING id, name, created_at",
            (data["name"],)
        )
        result = cursor.fetchone()
        conn.commit()
        cursor.close()
        conn.close()
        
        return jsonify({
            "id": result[0],
            "name": result[1],
            "created_at": str(result[2])
        }), 201
    except Exception as e:
        print(f"ERROR: Failed to create item: {e}", file=sys.stderr)
        return jsonify({"error": str(e)}), 500


@app.route("/stress/cpu", methods=["GET"])
def stress_cpu():
    """Burn CPU for 10 seconds to trigger CPU alarm."""
    try:
        end_time = time.time() + 10
        while time.time() < end_time:
            _ = sum(i * i for i in range(100000))
        return jsonify({"status": "cpu_stress_complete"}), 200
    except Exception as e:
        print(f"ERROR: CPU stress test failed: {e}", file=sys.stderr)
        return jsonify({"error": str(e)}), 500


@app.route("/stress/memory", methods=["GET"])
def stress_memory():
    """Allocate 300 MB in-process to trigger memory alarm."""
    try:
        # Allocate ~300 MB
        large_list = [bytearray(1024 * 1024) for _ in range(300)]
        return jsonify({"status": "memory_stress_allocated"}), 200
    except Exception as e:
        print(f"ERROR: Memory stress test failed: {e}", file=sys.stderr)
        return jsonify({"error": str(e)}), 500


@app.route("/stress/slow-query", methods=["GET"])
def stress_slow_query():
    """Run a slow database query to trigger DB latency alarm."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT pg_sleep(15)")
        cursor.fetchone()
        cursor.close()
        conn.close()
        return jsonify({"status": "slow_query_complete"}), 200
    except Exception as e:
        print(f"ERROR: Slow query test failed: {e}", file=sys.stderr)
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    # Initialize database on startup
    try:
        init_db()
    except Exception:
        sys.exit(1)
    
    # Run the Flask app
    app.run(host="0.0.0.0", port=APP_PORT, debug=False)
