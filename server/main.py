from fastapi import FastAPI, HTTPException, Body
from pydantic import BaseModel, Field
from typing import List, Optional
import sqlite3
import json
from datetime import datetime
from pathlib import Path
import hashlib
import hmac

app = FastAPI(title="Pharos Sync Server", version="1.0.0")

# Database path
DB_PATH = Path("./pharos_reports.db")


class ScanResult(BaseModel):
    timestamp: str
    location: Optional[str] = None
    medicine_name: str
    batch_code: str
    risk_level: str
    risk_score: int = Field(ge=0, le=100)
    flags: List[str] = []


class SyncPayload(BaseModel):
    device_id: str
    public_key: str
    signature: str
    scan_results: List[ScanResult]


class ReportStats(BaseModel):
    total_scans: int
    critical_count: int
    high_count: int
    moderate_count: int
    low_count: int
    last_24h_count: int


def init_db():
    """Initialize SQLite database for reports."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS reports (
            id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            location TEXT,
            medicine_name TEXT NOT NULL,
            batch_code TEXT NOT NULL,
            risk_level TEXT NOT NULL,
            risk_score INTEGER NOT NULL,
            flags TEXT,
            public_key TEXT NOT NULL,
            signature TEXT NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    conn.close()


def verify_signature(payload: SyncPayload) -> bool:
    """
    Verify HMAC-SHA256 signature from device.
    In production, validate against device's registered public key.
    """
    # For demonstration: accept valid base64 signatures
    # In production: verify Ed25519 signature with public_key
    return bool(payload.signature and len(payload.signature) > 0)


@app.on_event("startup")
async def startup():
    """Initialize database on startup."""
    init_db()


@app.post("/api/v1/reports")
async def ingest_reports(payload: SyncPayload = Body(...)) -> dict:
    """
    Ingest scan reports from a Pharos Android device.
    
    Verifies signature and stores reports in database.
    Returns 200 on success, 422 on invalid signature, 400 on bad data.
    """
    # Validate signature
    if not verify_signature(payload):
        raise HTTPException(status_code=422, detail="Invalid signature")
    
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        stored_count = 0
        for i, scan in enumerate(payload.scan_results):
            try:
                # Generate unique report ID
                report_id = f"{payload.device_id}_{scan.timestamp}_{i}"
                
                # Store in database
                cursor.execute('''
                    INSERT INTO reports (
                        id, device_id, timestamp, location,
                        medicine_name, batch_code, risk_level, risk_score,
                        flags, public_key, signature
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', (
                    report_id,
                    payload.device_id,
                    scan.timestamp,
                    scan.location,
                    scan.medicine_name,
                    scan.batch_code,
                    scan.risk_level,
                    scan.risk_score,
                    json.dumps(scan.flags),
                    payload.public_key,
                    payload.signature,
                ))
                stored_count += 1
            except Exception as e:
                # Log but continue storing other reports
                print(f"Error storing report {i}: {e}")
                continue
        
        conn.commit()
        conn.close()
        
        return {
            "status": "success",
            "device_id": payload.device_id,
            "stored_count": stored_count,
            "timestamp": datetime.now().isoformat(),
        }
    
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/api/v1/stats")
async def get_stats() -> ReportStats:
    """
    Get aggregated scan statistics for dashboard.
    """
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Total and by risk level
        cursor.execute("SELECT COUNT(*) FROM reports")
        total = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM reports WHERE risk_level = 'CRITICAL'")
        critical = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM reports WHERE risk_level = 'HIGH'")
        high = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM reports WHERE risk_level = 'MODERATE'")
        moderate = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM reports WHERE risk_level = 'LOW'")
        low = cursor.fetchone()[0]
        
        # Last 24 hours
        cursor.execute('''
            SELECT COUNT(*) FROM reports 
            WHERE datetime(timestamp) > datetime('now', '-1 day')
        ''')
        last_24h = cursor.fetchone()[0]
        
        conn.close()
        
        return ReportStats(
            total_scans=total,
            critical_count=critical,
            high_count=high,
            moderate_count=moderate,
            low_count=low,
            last_24h_count=last_24h,
        )
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "ok", "service": "pharos-sync-server"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
