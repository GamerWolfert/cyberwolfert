// Database-verbinding (PostgreSQL). Config via config.env (kopie van .env.example).
// Gebruik: const pool = require('./db');
require('dotenv').config({ path: require('path').join(__dirname, '..', 'config.env') });
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.PGHOST || '127.0.0.1',
  port: Number(process.env.PGPORT || 5432),
  user: process.env.PGUSER || 'wolfert',
  password: process.env.PGPASSWORD || '',
  database: process.env.PGDATABASE || 'cyberwolfert_db',
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

pool.on('error', (err) => console.error('[pg] pool error', err.message));

async function query(text, params) {
  return pool.query(text, params);
}

module.exports = { pool, query };
