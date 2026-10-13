import express from 'express';
import cors from 'cors';
import morgan from 'morgan';
import path from 'path';
import { dbService } from './database';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import { encryptionService } from './encryption';
import { backupRouter } from './routes/backup';
import { config } from './config';
import { logger } from './logger';
import fs from 'fs';
import { z } from 'zod';
import { backupScheduler } from './backup-scheduler';

// Create Express server
const app = express();
const PORT = config.server.port;
const clientDir = path.resolve(__dirname, '../../../../dist');

// Security middlewares
// Apply helmet for security headers
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", "data:", "https://lovable.dev"],
      connectSrc: ["'self'"],
      fontSrc: ["'self'"],
      objectSrc: ["'none'"],
      mediaSrc: ["'self'"],
      frameSrc: ["'none'"],
      formAction: ["'self'"],
      upgradeInsecureRequests: []
    }
  },
  // Disable strict MIME checking to allow modules to load correctly
  crossOriginEmbedderPolicy: false,
  crossOriginOpenerPolicy: false,
  crossOriginResourcePolicy: false
}));

// Apply rate limiting to all requests
const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' }
});
app.use(generalLimiter);

// More strict rate limiting for authentication/sensitive operations
const strictLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 10, // limit each IP to 10 requests per windowMs
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests for sensitive operations, please try again later.' }
});

// Middleware
app.use(cors({
  origin: ['http://localhost:3000', 'http://localhost:8080'],
  credentials: true
}));
app.use(express.json({ limit: '100kb' })); // Limit payload size
app.use(morgan('dev'));

// Express handles path containment, MIME types and all Vite asset formats.
app.use(express.static(clientDir, { dotfiles: 'deny', index: false, maxAge: '1h' }));

// API Routes
app.get('/api/health', async (req, res) => {
  try {
    const dbStatus = await dbService.getDataBrokers().length > 0 ? 'ok' : 'warning';
    const encryptionStatus = await dbService.getEncryptionStatus();
    
    const health = {
      status: 'ok',
      timestamp: new Date().toISOString(),
      version: process.env.npm_package_version || '1.0.0',
      services: {
        database: {
          status: dbStatus,
          message: dbStatus === 'ok' ? 'Connected' : 'Connected but no data'
        },
        encryption: {
          status: encryptionStatus.enabled ? 'ok' : 'disabled',
          initialized: encryptionStatus.initialized
        },
        backup: {
          status: config.database.backup.enabled ? 'ok' : 'disabled',
          interval: `${config.database.backup.intervalSeconds}s`,
          retention: `${config.database.backup.retentionDays} days`,
          directory: config.storage.backupDir
        }
      },
      uptime: process.uptime(),
      memory: process.memoryUsage()
    };

    res.json(health);
  } catch (error) {
    console.error('Health check failed:', error);
    res.status(500).json({
      status: 'error',
      timestamp: new Date().toISOString(),
      error: 'Health check failed'
    });
  }
});

// Data Brokers API
app.get('/api/brokers', (req, res) => {
  try {
    const brokers = dbService.getDataBrokers();
    res.json(brokers);
  } catch (error) {
    console.error('Error getting brokers:', error);
    res.status(500).json({ error: 'Failed to get data brokers' });
  }
});

// Apply strict rate limiting to sensitive operations
app.post('/api/brokers', strictLimiter, (req, res) => {
  try {
    const broker = dbService.addDataBroker(req.body);
    res.status(201).json(broker);
  } catch (error) {
    console.error('Error adding broker:', error);
    res.status(500).json({ error: 'Failed to add data broker' });
  }
});

app.delete('/api/brokers/:id', strictLimiter, (req, res) => {
  try {
    const success = dbService.deleteDataBroker(req.params.id);
    if (success) {
      res.json({ success: true });
    } else {
      res.status(404).json({ error: 'Data broker not found' });
    }
  } catch (error) {
    console.error('Error deleting broker:', error);
    res.status(500).json({ error: 'Failed to delete data broker' });
  }
});

app.post('/api/brokers/search', async (req, res) => {
  try {
    const { email } = req.body;
    if (!z.string().email().safeParse(email).success) {
      return res.status(400).json({ error: 'Email is required' });
    }
    
    const brokers = await dbService.findDataBrokersForEmail(email);
    res.json(brokers);
  } catch (error) {
    console.error('Error searching brokers:', error);
    res.status(500).json({ error: 'Failed to search data brokers' });
  }
});

const requestSchema = z.object({
  brokerName: z.string().trim().min(1).max(200),
  status: z.enum(['pending', 'sent', 'responded', 'completed']),
  userEmail: z.string().email().max(320),
  responseContent: z.string().max(50000).optional(),
  metadata: z.string().max(50000).optional(),
}).strict();

// Requests API
app.get('/api/requests', async (req, res) => {
  try {
    const requests = await dbService.getRequests();
    res.json(requests);
  } catch (error) {
    console.error('Error getting requests:', error);
    res.status(500).json({ error: 'Failed to get requests' });
  }
});

app.get('/api/requests/:id', async (req, res) => {
  try {
    const request = await dbService.getRequestById(req.params.id);
    if (request) {
      res.json(request);
    } else {
      res.status(404).json({ error: 'Request not found' });
    }
  } catch (error) {
    console.error('Error getting request:', error);
    res.status(500).json({ error: 'Failed to get request' });
  }
});

app.post('/api/requests', strictLimiter, async (req, res) => {
  try {
    const parsed = requestSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Invalid request data' });
    const request = await dbService.createRequest(parsed.data);
    res.status(201).json(request);
  } catch (error) {
    console.error('Error creating request:', error);
    res.status(500).json({ error: 'Failed to create request' });
  }
});

app.put('/api/requests/:id', strictLimiter, async (req, res) => {
  try {
    const parsed = requestSchema.partial().safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'Invalid request updates' });
    const request = await dbService.updateRequest(req.params.id, parsed.data);
    if (request) {
      res.json(request);
    } else {
      res.status(404).json({ error: 'Request not found' });
    }
  } catch (error) {
    console.error('Error updating request:', error);
    res.status(500).json({ error: 'Failed to update request' });
  }
});

app.delete('/api/requests/:id', strictLimiter, (req, res) => {
  try {
    const success = dbService.deleteRequest(req.params.id);
    if (success) {
      res.json({ success: true });
    } else {
      res.status(404).json({ error: 'Request not found' });
    }
  } catch (error) {
    console.error('Error deleting request:', error);
    res.status(500).json({ error: 'Failed to delete request' });
  }
});

// Add Encryption API Routes
app.get('/api/encryption/status', (req, res) => {
  try {
    const status = dbService.getEncryptionStatus();
    res.json(status);
  } catch (error) {
    console.error('Error getting encryption status:', error);
    res.status(500).json({ error: 'Failed to get encryption status' });
  }
});

app.post('/api/encryption/enable', strictLimiter, async (req, res) => {
  try {
    const { enable } = req.body;
    if (typeof enable !== 'boolean') {
      return res.status(400).json({ error: 'Enable parameter must be a boolean' });
    }
    
    const success = await dbService.enableEncryption(enable);
    if (success) {
      res.json({ success: true, enabled: enable });
    } else {
      res.status(500).json({ error: 'Failed to change encryption status' });
    }
  } catch (error) {
    console.error('Error updating encryption status:', error);
    res.status(500).json({ error: 'Failed to update encryption status' });
  }
});

app.get('/api/encryption/export-key', strictLimiter, async (req, res) => {
  try {
    const key = await dbService.exportEncryptionKey();
    if (key) {
      res.json({ key });
    } else {
      res.status(404).json({ error: 'No encryption key found' });
    }
  } catch (error) {
    console.error('Error exporting encryption key:', error);
    res.status(500).json({ error: 'Failed to export encryption key' });
  }
});

app.post('/api/encryption/import-key', strictLimiter, async (req, res) => {
  try {
    const { key } = req.body;
    if (!key || typeof key !== 'string') {
      return res.status(400).json({ error: 'Valid key is required' });
    }
    
    const success = await dbService.importEncryptionKey(key);
    if (success) {
      res.json({ success: true });
    } else {
      res.status(500).json({ error: 'Failed to import encryption key' });
    }
  } catch (error) {
    console.error('Error importing encryption key:', error);
    res.status(500).json({ error: 'Failed to import encryption key' });
  }
});

// Apply strict rate limiting to sensitive operations
app.use('/api/backups', strictLimiter, backupRouter);

// Add data deletion endpoint
app.post('/api/settings/delete-all-data', strictLimiter, async (req, res) => {
  try {
    // Clear rows through the open connection so later writes remain persistent.
    dbService.deleteAllData();
    for (const file of await fs.promises.readdir(config.storage.backupDir).catch((error: NodeJS.ErrnoException) => { if (error.code === 'ENOENT') return []; throw error; })) {
      if (/^[a-zA-Z0-9._-]+\.db$/.test(file)) await fs.promises.unlink(path.join(config.storage.backupDir, file));
    }
    await encryptionService.reset();

    res.json({ success: true, message: 'All data has been deleted' });
  } catch (error) {
    logger.error('Error deleting all data:', error);
    res.status(500).json({ error: 'Failed to delete all data' });
  }
});

// Add this immediately before the last route


// Catch-all route to serve the React app
app.get('*', (req, res) => {
  // Don't serve the index for API routes or asset requests that fail
  if (req.url.startsWith('/api/') || req.url.startsWith('/assets/')) {
    return res.status(404).json({ error: 'Not found' });
  }
  
  // For all other routes, serve the index.html for client-side routing
  res.sendFile(path.join(clientDir, 'index.html'));
});

// Start configured backups and stop timers when shutting down.

process.on('SIGTERM', () => { backupScheduler.stop(); process.exit(0); });

// Start server
app.listen(PORT, process.env.HOST || '127.0.0.1', () => {
  console.log(`Server running on port ${PORT}`);
}); 