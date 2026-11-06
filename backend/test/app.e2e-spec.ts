import type { INestApplication } from '@nestjs/common';
import type { Server } from 'node:http';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AppModule } from '../src/app.module.js';

describe('system endpoints (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api/v1');
    await app.init();
  });

  afterAll(async () => {
    await app?.close();
  });

  it('returns the hello response without a database dependency', async () => {
    const response = await request(app.getHttpServer() as Server)
      .get('/api/v1/hello')
      .expect(200);

    expect(response.body).toEqual({
      message: 'Go-Ye API is ready.',
      service: 'go-ye-api',
    });
  });
});
