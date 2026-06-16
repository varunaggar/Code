import express from 'express';
import multer from 'multer';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT || 3000;

// Configure TARGET_API_URL from environment with a placeholder default
const TARGET_API_URL = process.env.TARGET_API_URL || 'https://httpbin.org/put';

// Configure multer for in-memory storage
const storage = multer.memoryStorage();
const upload = multer({
  storage: storage,
  limits: {
    fileSize: 10 * 1024 * 1024 // 10MB limit
  },
  fileFilter: (req, file, cb) => {
    // Accept only SVG files
    if (file.mimetype === 'image/svg+xml' || file.originalname.endsWith('.svg')) {
      cb(null, true);
    } else {
      cb(new Error('Only SVG files are allowed'));
    }
  }
});

// Serve static files from the public directory
app.use(express.static(path.join(__dirname, 'public')));

// POST endpoint to handle file upload
app.post('/upload', upload.single('svgFile'), async (req, res) => {
  try {
    // Check if file was uploaded
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No file uploaded'
      });
    }

    console.log(`Received SVG file: ${req.file.originalname} (${req.file.size} bytes)`);
    console.log(`Sending PUT request to: ${TARGET_API_URL}`);

    // Get the file content from memory buffer
    const svgContent = req.file.buffer;

    // Send PUT request to external API
    const response = await fetch(TARGET_API_URL, {
      method: 'PUT',
      headers: {
        'Content-Type': 'image/svg+xml',
        'Accept': 'application/json, text/plain, */*'
      },
      body: svgContent
    });

    console.log(`External API responded with status: ${response.status}`);

    // Parse response based on content type
    const contentType = response.headers.get('content-type') || '';
    let responseBody;

    if (contentType.includes('application/json')) {
      responseBody = await response.json();
    } else {
      responseBody = await response.text();
    }

    // Convert headers to plain object
    const headersObj = {};
    response.headers.forEach((value, key) => {
      headersObj[key] = value;
    });

    // Send response back to frontend
    res.json({
      success: response.ok,
      status: response.status,
      headers: headersObj,
      body: responseBody
    });

  } catch (error) {
    console.error('Error processing upload:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Internal server error'
    });
  }
});

// Start the server
app.listen(PORT, () => {
  console.log(`SVG Uploader server running on http://localhost:${PORT}`);
  console.log(`Target API URL: ${TARGET_API_URL}`);
  console.log(`Set TARGET_API_URL environment variable to change the destination`);
});
