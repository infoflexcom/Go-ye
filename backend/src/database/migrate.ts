import { Pool } from 'pg';
import { migrateDown, migrateUp } from './migrations.js';

async function main(): Promise<void> {
  const direction = process.argv[2] ?? 'up';
  if (direction !== 'up' && direction !== 'down') {
    throw new Error('Usage: npm run migration:up or npm run migration:down');
  }
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error('DATABASE_URL is required to run migrations');
  }

  const pool = new Pool({ connectionString });
  try {
    const client = await pool.connect();
    try {
      const result = direction === 'up' ? await migrateUp(client) : await migrateDown(client);
      console.log(JSON.stringify({ direction, result }));
    } finally {
      client.release();
    }
  } finally {
    await pool.end();
  }
}

void main();
