from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pathlib import Path
from typing import Dict, Any

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

def parse_dtx_line(line: str, key: str) -> str:
    """
    Robust parser for DTX metadata lines.
    Handles various formats like "#KEY: value", "#KEY value", "#KEYvalue"
    """
    line = line.strip()
    if not line.startswith(f'#{key}'):
        return None
    
    # Remove the key prefix
    value_part = line[len(f'#{key}'):].strip()
    
    # Handle colon separator
    if value_part.startswith(':'):
        return value_part[1:].strip()
    
    # Handle direct value (no colon)
    return value_part

def parse_set_def(set_def_path: Path) -> Dict[str, Any]:
    """Parse SET.def file to get song title and difficulty mappings"""
    content = None
    # Try multiple encodings in order
    encodings_to_try = ['utf-16', 'shift-jis', 'utf-8']
    
    for encoding in encodings_to_try:
        try:
            with open(set_def_path, 'r', encoding=encoding) as file:
                content = file.read()
                break
        except UnicodeDecodeError:
            continue
    
    if content is None:
        # Final fallback with error handling
        with open(set_def_path, 'r', encoding='utf-8', errors='ignore') as file:
            content = file.read()
    
    song_info = {
        'title': None,
        'difficulties': {}
    }
    
    for line in content.split('\n'):
        line = line.strip()
        
        # Parse title using robust parser
        title = parse_dtx_line(line, 'TITLE')
        if title is not None:
            song_info['title'] = title
        elif line.startswith('#L') and 'LABEL' in line:
            # Parse difficulty labels: #L1LABEL BASIC
            level_num = line[2]  # Get the number after L
            label = line.split('LABEL')[1].strip()
            song_info['difficulties'][level_num] = {'label': label}
        elif line.startswith('#L') and 'FILE' in line:
            # Parse difficulty files: #L1FILE bas.dtx
            level_num = line[2]  # Get the number after L
            filename = line.split('FILE')[1].strip()
            if level_num in song_info['difficulties']:
                song_info['difficulties'][level_num]['file'] = filename
            else:
                song_info['difficulties'][level_num] = {'file': filename}
    
    return song_info

def parse_dtx_metadata(dtx_path: Path) -> Dict[str, Any]:
    """Parse individual DTX file for metadata"""
    try:
        with open(dtx_path, 'r', encoding='shift-jis') as file:
            content = file.read()
    except UnicodeDecodeError:
        with open(dtx_path, 'r', encoding='utf-8', errors='ignore') as file:
            content = file.read()
    
    metadata = {}
    
    for line in content.split('\n'):
        line = line.strip()
        
        # Parse title
        title = parse_dtx_line(line, 'TITLE')
        if title is not None:
            metadata['title'] = title
            continue
            
        # Parse artist
        artist = parse_dtx_line(line, 'ARTIST')
        if artist is not None:
            metadata['artist'] = artist
            continue
            
        # Parse BPM
        bpm_str = parse_dtx_line(line, 'BPM')
        if bpm_str is not None:
            try:
                metadata['bpm'] = float(bpm_str)
            except ValueError:
                metadata['bpm'] = None
            continue
            
        # Parse difficulty level
        dlevel_str = parse_dtx_line(line, 'DLEVEL')
        if dlevel_str is not None:
            try:
                metadata['level'] = int(dlevel_str)
            except ValueError:
                metadata['level'] = None
            continue
    
    return metadata

def parse_song_folder(song_dir: Path) -> Dict[str, Any]:
    """Parse a song folder with SET.def and multiple DTX files"""
    set_def_path = song_dir / "SET.def"
    if not set_def_path.exists():
        return None
    
    set_info = parse_set_def(set_def_path)
    
    # Map difficulty labels to standard names
    difficulty_mapping = {
        'BASIC': 'easy',
        'ADVANCED': 'medium', 
        'EXTREME': 'hard',
        'MASTER': 'expert',
        'REAL': 'expert'
    }
    
    song_data = {
        'song_id': song_dir.name,
        'title': set_info['title'] or song_dir.name.replace('_', ' ').title(),
        'artist': None,
        'bpm': None,
        'charts': []
    }
    
    # Process each difficulty
    for level_num, diff_info in set_info['difficulties'].items():
        if 'file' in diff_info and 'label' in diff_info:
            dtx_path = song_dir / diff_info['file']
            if dtx_path.exists():
                dtx_metadata = parse_dtx_metadata(dtx_path)
                
                # Use DTX metadata to fill in song info if not already set
                if not song_data['artist'] and dtx_metadata.get('artist'):
                    song_data['artist'] = dtx_metadata['artist']
                if not song_data['bpm'] and dtx_metadata.get('bpm'):
                    song_data['bpm'] = dtx_metadata['bpm']
                
                # Map difficulty label to standard name
                difficulty_label = diff_info['label'].upper()
                difficulty_name = difficulty_mapping.get(difficulty_label, difficulty_label.lower())
                
                song_data['charts'].append({
                    'difficulty': difficulty_name,
                    'difficulty_label': diff_info['label'],
                    'level': dtx_metadata.get('level', 50),
                    'filename': diff_info['file'],
                    'size': dtx_path.stat().st_size
                })
    
    return song_data

@app.get("/")
async def root():
    return {"message": "Virgo DTX Server", "version": "1.0.0"}

@app.get("/dtx/list")
async def list_dtx_files():
    """List all available DTX songs with their difficulties"""
    try:
        if not DTX_FILES_DIR.exists():
            return {"songs": []}
        
        songs = []
        
        # Process song folders (directories with SET.def)
        for song_dir in DTX_FILES_DIR.iterdir():
            if song_dir.is_dir():
                set_def_path = song_dir / "SET.def"
                if set_def_path.exists():
                    song_info = parse_song_folder(song_dir)
                    if song_info:
                        songs.append(song_info)
        
        # Also process individual DTX files for backward compatibility
        dtx_files = []
        for file_path in DTX_FILES_DIR.glob("*.dtx"):
            dtx_files.append({
                "filename": file_path.name,
                "size": file_path.stat().st_size
            })
        
        return {"songs": songs, "individual_files": dtx_files}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error listing DTX songs: {str(e)}") from e

@app.get("/dtx/download/{filename}")
async def download_dtx_file(filename: str):
    """Download a specific DTX file (backward compatibility)"""
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

@app.get("/dtx/download/{song_id}/{chart_filename}")
async def download_chart_file(song_id: str, chart_filename: str):
    """Download a specific chart file or BGM file from a song folder"""
    if not (chart_filename.endswith('.dtx') or chart_filename.endswith('.ogg') or chart_filename.endswith('.mp3')):
        raise HTTPException(status_code=400, detail="Invalid file type. Only .dtx, .ogg, and .mp3 files are allowed")
    
    song_dir = DTX_FILES_DIR / song_id
    if not song_dir.exists() or not song_dir.is_dir():
        raise HTTPException(status_code=404, detail="Song not found")
    
    file_path = song_dir / chart_filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Chart file not found")
    
    return FileResponse(
        path=str(file_path),
        filename=f"{song_id}_{chart_filename}",
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
        
        # Parse basic metadata using robust parser
        for line in content.split('\n'):
            line = line.strip()
            
            # Parse title
            title = parse_dtx_line(line, 'TITLE')
            if title is not None:
                metadata['title'] = title
                continue
                
            # Parse artist
            artist = parse_dtx_line(line, 'ARTIST')
            if artist is not None:
                metadata['artist'] = artist
                continue
                
            # Parse BPM
            bpm_str = parse_dtx_line(line, 'BPM')
            if bpm_str is not None:
                try:
                    metadata['bpm'] = float(bpm_str)
                except ValueError:
                    metadata['bpm'] = None
                continue
                
            # Parse difficulty level
            dlevel_str = parse_dtx_line(line, 'DLEVEL')
            if dlevel_str is not None:
                try:
                    metadata['level'] = int(dlevel_str)
                except ValueError:
                    metadata['level'] = None
                continue
        
        return {
            "filename": filename,
            "metadata": metadata
        }
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error reading DTX file: {str(e)}") from e

# Cloudflare Workers compatibility
def on_fetch(request, env):
    """Handler for Cloudflare Workers"""
    
    
    # This is the entry point for Cloudflare Workers
    # The actual implementation would use an ASGI adapter
    pass

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)