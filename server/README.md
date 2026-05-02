# Virgo DTX Server

FastAPI backend server for serving DTX drum chart files, designed for deployment on Cloudflare Workers.

## Features

- List available DTX files
- Download DTX files  
- Extract metadata from DTX files
- CORS-enabled for local development
- Cloudflare Workers compatible

## Local Development

1. Install dependencies:
```bash
cd server
uv sync
```

2. Run the server:
```bash
uv run uvicorn main:app --host 127.0.0.1 --port 8001 --reload
```

The server will start on `http://127.0.0.1:8001`

## API Endpoints

- `GET /` - Server info
- `GET /dtx/list` - List all available DTX files
- `GET /dtx/download/{filename}` - Download a specific DTX file
- `GET /dtx/metadata/{filename}` - Get metadata from a DTX file

## Cloudflare Workers Deployment

1. Install Wrangler CLI:
```bash
npm install -g wrangler
```

2. Configure wrangler.toml with your settings

3. Deploy:
```bash
wrangler deploy
```

## DTX File Format

The server parses DTX files with Shift-JIS encoding and extracts:
- Title (#TITLE)
- Artist (#ARTIST) 
- BPM (#BPM)
- Difficulty Level (#DLEVEL)

Note data parsing follows the format `#xxxYY: aabbccdd` where:
- `xxx` = measure number (000-999)
- `YY` = lane ID (hexadecimal)
- `aabbccdd` = note array with timing positions
