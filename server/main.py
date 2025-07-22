from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
import os
from pathlib import Path
from typing import List, Dict, Any

app = FastAPI(title="Virgo DTX Server", version="1.0.0")

# Configure CORS for local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# DTX files directory
DTX_FILES_DIR = Path(__file__).parent / "dtx_files"

@app.get("/")
async def root():
    return {"message": "Virgo DTX Server", "version": "1.0.0"}

@app.get("/dtx/list")
async def list_dtx_files():
    """List all available DTX files"""
    try:
        if not DTX_FILES_DIR.exists():
            return {"files": []}
        
        dtx_files = []
        for file_path in DTX_FILES_DIR.glob("*.dtx"):
            dtx_files.append({
                "filename": file_path.name,
                "size": file_path.stat().st_size
            })
        
        return {"files": dtx_files}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error listing DTX files: {str(e)}")

@app.get("/dtx/download/{filename}")
async def download_dtx_file(filename: str):
    """Download a specific DTX file"""
    if not filename.endswith('.dtx'):
        raise HTTPException(status_code=400, detail="Invalid file type. Only .dtx files are allowed")
    
    file_path = DTX_FILES_DIR / filename
    
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="DTX file not found")
    
    return FileResponse(
        path=str(file_path),
        filename=filename,
        media_type='application/octet-stream'
    )

@app.get("/dtx/metadata/{filename}")
async def get_dtx_metadata(filename: str):
    """Get metadata from a DTX file without downloading the full file"""
    if not filename.endswith('.dtx'):
        raise HTTPException(status_code=400, detail="Invalid file type. Only .dtx files are allowed")
    
    file_path = DTX_FILES_DIR / filename
    
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="DTX file not found")
    
    try:
        # Read file with Shift-JIS encoding
        with open(file_path, 'r', encoding='shift-jis') as file:
            content = file.read()
        
        metadata = {}
        
        # Parse basic metadata
        for line in content.split('\n'):
            line = line.strip()
            if line.startswith('#TITLE:'):
                metadata['title'] = line[7:].strip()
            elif line.startswith('#ARTIST:'):
                metadata['artist'] = line[8:].strip()
            elif line.startswith('#BPM:'):
                try:
                    metadata['bpm'] = float(line[5:].strip())
                except ValueError:
                    metadata['bpm'] = None
            elif line.startswith('#DLEVEL:'):
                try:
                    metadata['level'] = int(line[8:].strip())
                except ValueError:
                    metadata['level'] = None
        
        return {
            "filename": filename,
            "metadata": metadata
        }
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error reading DTX file: {str(e)}")

# Cloudflare Workers compatibility
def on_fetch(request, env):
    """Handler for Cloudflare Workers"""
    import asyncio
    from fastapi.middleware.wsgi import WSGIMiddleware
    
    # This is the entry point for Cloudflare Workers
    # The actual implementation would use an ASGI adapter
    pass

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)