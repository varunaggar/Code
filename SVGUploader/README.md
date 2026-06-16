# SVG Uploader

A simple web application that allows users to upload SVG files and send them to an external API via PUT request.

## Features

- **File Upload**: Web interface for selecting and uploading SVG files
- **API Integration**: Sends uploaded SVG content to a configurable external API via HTTP PUT
- **Response Display**: Shows the external API's response in a formatted, readable way
- **Error Handling**: Gracefully handles errors and displays clear error messages

## Architecture

- **Backend**: Node.js with Express server
- **Frontend**: Vanilla HTML, CSS, and JavaScript
- **File Handling**: Uses Multer for in-memory file upload processing
- **HTTP Client**: Uses built-in Fetch API for making PUT requests

## Requirements

- Node.js 18+ (for built-in fetch support)
- npm or yarn package manager

## Installation

1. Navigate to the SVGUploader directory:
   ```bash
   cd SVGUploader
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

## Configuration

The application sends uploaded SVG files to an external API. Configure the target API URL using the `TARGET_API_URL` environment variable.

### Setting the API URL

**On Linux/macOS:**
```bash
export TARGET_API_URL=https://your-api-endpoint.com/svg
```

**On Windows (Command Prompt):**
```cmd
set TARGET_API_URL=https://your-api-endpoint.com/svg
```

**On Windows (PowerShell):**
```powershell
$env:TARGET_API_URL="https://your-api-endpoint.com/svg"
```

### Default Behavior

If `TARGET_API_URL` is not set, the application defaults to `https://httpbin.org/put` for testing purposes. This is a public HTTP testing service that echoes back the request details.

## Usage

1. Start the server:
   ```bash
   npm start
   ```

2. Open your browser and navigate to:
   ```
   http://localhost:3000
   ```

3. Use the web interface to:
   - Click the file input to select an SVG file
   - Click "Upload and Send" button
   - View the API response displayed on the page

## API Endpoint Details

### Backend Endpoint

**POST /upload**
- Accepts: multipart/form-data with a file field named `svgFile`
- File Type: SVG files only (validated by extension and MIME type)
- Max File Size: 10MB

### External API Request

The backend sends a PUT request with:
- **Method**: PUT
- **Content-Type**: image/svg+xml
- **Accept**: application/json, text/plain, */*
- **Body**: Raw SVG file content

### Response Format

The backend returns JSON with the following structure:
```json
{
  "success": true,
  "status": 200,
  "headers": {
    "content-type": "application/json",
    ...
  },
  "body": {
    // Parsed response body (JSON or text)
  }
}
```

## Development

For development with auto-reload (Node 18.11+):
```bash
npm run dev
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TARGET_API_URL` | External API endpoint URL | `https://httpbin.org/put` |
| `PORT` | Server port | `3000` |

## Testing

To test the application:

1. Start the server with the default test URL (httpbin.org):
   ```bash
   npm start
   ```

2. Create a simple test SVG file:
   ```bash
   echo '<svg xmlns="http://www.w3.org/2000/svg"><circle cx="50" cy="50" r="40"/></svg>' > test.svg
   ```

3. Open http://localhost:3000 and upload the test.svg file

4. You should see a response showing that the SVG was successfully received by the API

## Error Handling

The application handles various error scenarios:

- **No file selected**: Returns 400 Bad Request
- **Invalid file type**: Returns error message (only SVG files accepted)
- **File too large**: Returns error for files over 10MB
- **API request failure**: Returns 500 with error details
- **Network errors**: Displays error message in the UI

## Security Considerations

- File type validation ensures only SVG files are processed
- File size limit prevents abuse (10MB max)
- In-memory storage avoids filesystem clutter
- No persistent storage of uploaded files

## License

MIT
