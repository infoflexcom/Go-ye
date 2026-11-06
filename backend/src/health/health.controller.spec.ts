import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { DatabaseHealthService } from './database-health.service.js';
import { HealthController } from './health.controller.js';

describe('HealthController', () => {
  const database = {
    check: vi.fn<DatabaseHealthService['check']>(),
  };
  const controller = new HealthController(database as DatabaseHealthService);

  beforeEach(() => {
    database.check.mockReset();
  });

  it('returns the expected hello response', () => {
    expect(controller.hello()).toEqual({
      message: 'Go-Ye API is ready.',
      service: 'go-ye-api',
    });
  });

  it('includes the database check in its health response', async () => {
    database.check.mockResolvedValue('connected');

    await expect(controller.health()).resolves.toEqual({
      status: 'ok',
      database: 'connected',
    });
  });
});
